package gods

import "core:math"

// Dopamine is a person's mood chemical. Making something feels good, most of all the first time,
// and less and less as they make more things; it bleeds away by itself. People who feel flat crave
// the feeling, which sends them after things to make.
MAX_DOPAMINE :: 100.0
START_DOPAMINE :: 50.0
DOPAMINE_HALF_LIFE_HOURS :: 12.0
CRAVING_BELOW :: 35.0
SEEK_MIN_SATIETY :: 60.0 // a hungry person is not out looking for things to make; they look for food

CRAFT_REWARD :: 10.0 // before the multipliers below
FIRST_CRAFT_MULT :: 4.0 // the first time a person ever makes a particular item
HABITUATION_PER_CRAFT :: 0.02 // each success at anything dulls every later reward by this much

Mood :: enum {
	Despondent,
	Gloomy,
	Content,
	Cheerful,
	Elated,
}

MOOD_NAMES := [Mood]string {
	.Despondent = "Despondent",
	.Gloomy     = "Gloomy",
	.Content    = "Content",
	.Cheerful   = "Cheerful",
	.Elated     = "Elated",
}

mood_of :: proc(dopamine: f32) -> Mood {
	switch {
	case dopamine < 15: return .Despondent
	case dopamine < CRAVING_BELOW: return .Gloomy
	case dopamine < 65: return .Content
	case dopamine < 85: return .Cheerful
	}
	return .Elated
}

craving :: proc(p: Person) -> bool {
	return p.dopamine < CRAVING_BELOW
}

// Every success at any item, added up.
total_crafts :: proc(p: Person) -> int {
	n := 0
	for item in Item {n += p.craft_levels[item]}
	return n
}

// Every success at anything: items made, fish caught, meals cooked.
total_successes :: proc(p: Person) -> int {
	return total_crafts(p) + p.fish_level + p.cook_level
}

// What a success at something would feel like right now, given how many times the person has already
// managed it: a big hit for a first, a shrinking one for repeats, and everything duller the more the
// person has already achieved in all.
shaped_reward :: proc(p: Person, level: int) -> f32 {
	novelty := f32(FIRST_CRAFT_MULT) if level == 0 else 1 / f32(1 + level)
	return CRAFT_REWARD * novelty / (1 + HABITUATION_PER_CRAFT * f32(total_successes(p)))
}

craft_reward :: proc(p: Person, item: Item) -> f32 {
	return shaped_reward(p, p.craft_levels[item])
}

// Catching a fish and cooking a meal are goals too: they stand in the list as .Fish and
// .Cooked_Fish_Filet and feel like a success at fishing or cooking.
goal_reward :: proc(p: Person, item: Item) -> f32 {
	#partial switch item {
	case .Fish: return shaped_reward(p, p.fish_level)
	case .Cooked_Fish_Filet: return shaped_reward(p, p.cook_level)
	}
	return craft_reward(p, item)
}

// Pay out the reward for a success. Call it before the item's level goes up.
reward_dopamine :: proc(p: ^Person, item: Item) {
	reward_activity(p, p.craft_levels[item])
}

// The same for a success at fishing or cooking, whose experience is not kept per item.
reward_activity :: proc(p: ^Person, level: int) {
	p.dopamine = min(p.dopamine + shaped_reward(p^, level), MAX_DOPAMINE)
}

// Dopamine bleeds off exponentially: half is gone after the half-life.
step_dopamine :: proc(p: ^Person, dt: f32) {
	p.dopamine *= math.pow(f32(0.5), dt / DOPAMINE_HALF_LIFE_HOURS)
}

// Things people can set their hearts on, in the order that breaks ties between equally new ones.
CRAFTABLE := [?]Item{.Twine, .Sharp_Stone, .Short_Stick, .Spear, .Basket, .Bow, .Stake, .Fire_Drill, .Fire_Pit, .Net, .Cooking_Stick, .Belt, .Fish, .Cooked_Fish_Filet}

try_craft :: proc(g: ^Game, p: ^Person, item: Item) -> bool {
	#partial switch item {
	case .Twine: return craft_twine(g, p)
	case .Sharp_Stone: return craft_sharp_stone(g, p)
	case .Short_Stick: return craft_short_sticks(g, p)
	case .Spear: return craft_spear(g, p)
	case .Basket: return craft_basket(g, p)
	case .Rope: return craft_rope(g, p)
	case .Belt: return craft_belt(g, p)
	case .Bow: return craft_bow(g, p)
	case .Stake: return craft_stake(g, p)
	case .Fire_Drill: return craft_fire_drill(g, p)
	case .Fire_Pit: return build_fire_pit(g, p)
	case .Net: return craft_net(g, p)
	case .Cooking_Stick: return craft_cooking_stick(g, p)
	case .Fur_Coat: return craft_coat(g, p)
	case .Drying_Rack: return craft_drying_rack(g, p)
	}
	return false
}

// The craftable items ordered by how good making them would feel, best first.
by_reward :: proc(p: Person) -> [len(CRAFTABLE)]Item {
	order := CRAFTABLE
	for i in 1 ..< len(order) { // stable insertion sort: ties keep their listed order
		for j := i; j > 0 && goal_reward(p, order[j]) > goal_reward(p, order[j - 1]); j -= 1 {
			order[j], order[j - 1] = order[j - 1], order[j]
		}
	}
	return order
}

// How many of an item a person has to hand: held, or lying at their feet.
have_count :: proc(g: ^Game, p: Person, item: Item) -> int {
	n := 0
	for h in 0 ..< carry_slots(p) {
		if p.hands[h] == item {n += 1}
	}
	n += packed_count(p, item)
	for it in g.ground_items {
		if in_reach(it.x, it.y, p.x, p.y) && it.item == item {n += 1}
	}
	return n
}

// What goes into making an item, with how many of each.
Need :: struct {
	item:  Item,
	count: int,
}

recipe_needs :: proc(item: Item) -> []Need {
	@(static) twine := [?]Need{{.Fiber, 2}}
	@(static) sharp := [?]Need{{.Stone, 2}}
	@(static) short := [?]Need{{.Sharp_Stone, 1}, {.Stick, 1}}
	@(static) spear := [?]Need{{.Sharp_Stone, 1}, {.Stick, 1}, {.Twine, 1}}
	@(static) basket := [?]Need{{.Reed, BASKET_REEDS}}
	@(static) rope := [?]Need{{.Twine, 2}}
	@(static) belt := [?]Need{{.Rope, 2}}
	@(static) bow := [?]Need{{.Stick, 1}, {.Twine, 1}}
	@(static) stake := [?]Need{{.Sharp_Stone, 1}, {.Short_Stick, 1}}
	@(static) drill := [?]Need{{.Bow, 1}, {.Stake, 1}}
	@(static) net := [?]Need{{.Twine, NET_TWINE}}
	@(static) cooking_stick := [?]Need{{.Sharp_Stone, 1}, {.Stick, 1}}
	@(static) coat := [?]Need{{.Fur, COAT_FUR}, {.Twine, 1}}
	@(static) rack := [?]Need{{.Stick, RACK_STICKS}}
	#partial switch item {
	case .Twine: return twine[:]
	case .Sharp_Stone: return sharp[:]
	case .Short_Stick: return short[:]
	case .Spear: return spear[:]
	case .Basket: return basket[:]
	case .Rope: return rope[:]
	case .Belt: return belt[:]
	case .Bow: return bow[:]
	case .Stake: return stake[:]
	case .Fire_Drill: return drill[:]
	case .Net: return net[:]
	case .Cooking_Stick: return cooking_stick[:]
	case .Fur_Coat: return coat[:]
	case .Drying_Rack: return rack[:]
	}
	return nil
}

// What a person should do next on the way to making an item, working back through whatever they
// must make first: either craft something now (the item itself, or an ingredient of it), or go and
// get a raw material (fiber, stone, stick or reed). Reeds need a sharp stone to cut.
Step :: struct {
	craft: Item, // make this now, or .None
	raw:   Item, // fetch this raw material, or .None
}

next_step :: proc(g: ^Game, p: Person, item: Item, depth := 0) -> Step {
	if depth > 4 {return {}}
	for need in recipe_needs(item) {
		if have_count(g, p, need.item) >= need.count {continue}
		#partial switch need.item {
		case .Fiber, .Stone, .Stick:
			return {raw = need.item}
		case .Reed:
			if !holds(p, .Sharp_Stone) {return next_step(g, p, .Sharp_Stone, depth + 1)}
			return {raw = .Reed}
		}
		return next_step(g, p, need.item, depth + 1)
	}
	return {craft = item}
}

// Nearest cell where a raw material can be had (trees and ponds are stood beside, not on).
nearest_source :: proc(g: ^Game, p: Person, raw: Item) -> (x, y: int, ok: bool) {
	best := max(int)
	for t, i in g.cells {
		cx, cy := i % g.width, i / g.width
		have: bool
		#partial switch raw {
		case .Fiber: have = t == .Grass && g.fiber[i] >= 1
		case .Stone: have = t == .Stone_Field && g.stone[i] >= 1
		case .Stick: have = t == .Tree && g.sticks[i] >= 1
		case .Reed: have = t == .Pond && g.reeds[i] >= 1
		}
		if !have {continue}
		if d := abs(cx - p.x) + abs(cy - p.y); d < best {best, x, y, ok = d, cx, cy, true}
	}
	return
}

// Take a raw material from where the person is standing or beside, if it can be had here.
gather_raw :: proc(g: ^Game, p: ^Person, raw: Item) -> bool {
	#partial switch raw {
	case .Fiber: return gather_fiber_here(g, p)
	case .Stone: return gather_stone_here(g, p)
	case .Stick: return gather_stick_adjacent(g, p)
	case .Reed: return gather_reed_adjacent(g, p)
	}
	return false
}

// A person who is fed but craving has a goal: the thing they would most enjoy making (a new item
// beats a familiar one). They gather and craft only what that needs, and walk to wherever the raw
// materials are, rather than doing whatever is closest to hand.
pursue_goal :: proc(g: ^Game, p: ^Person) -> bool {
	if !craving(p^) || p.satiety < SEEK_MIN_SATIETY {return false}
	for goal in by_reward(p^) {
		if holds(p^, goal) && (goal == .Spear || goal == .Basket || goal == .Bow || goal == .Stake || goal == .Fire_Drill || goal == .Net || goal == .Cooking_Stick || goal == .Belt) {continue} // one is plenty
	
		if goal == .Fish {
			if pursue_fishing(g, p) {return true}
			continue
		}
		if goal == .Cooked_Fish_Filet {
			if pursue_cooking(g, p) {return true}
			continue
		}
		if goal == .Fire_Pit { // a firepit is built from a pile at a site rather than from what is in hand
			if pursue_pit(g, p) {return true}
			continue
		}
		step := next_step(g, p^, goal)
		if step.craft != .None {return try_craft(g, p, step.craft)}
		if step.raw == .None {continue}
		if free_hand(p^) < 0 {return false} // nowhere to put it
		if gather_raw(g, p, step.raw) {return true}
		tx, ty, found := nearest_source(g, p^, step.raw)
		if !found {continue}
		return step_toward(g, p, tx, ty)
	}
	return false
}

// Sixteen things will not fit in anyone's hands, so a person building a firepit picks a site beside
// open ground, hauls stone and sticks there trip by trip into a pile at their feet, and builds once
// the pile is big enough.
pursue_pit :: proc(g: ^Game, p: ^Person) -> bool {
	if !p.has_site {
		if _, _, ok := pit_spot(g, p.x, p.y); !ok {return false} // not a good place to start a pile
		p.site_x, p.site_y, p.has_site = p.x, p.y, true
	}
	pile :: proc(g: ^Game, x, y: int, item: Item) -> int {
		n := 0
		for it in g.ground_items {
			if it.x == x && it.y == y && it.item == item {n += 1}
		}
		return n
	}
	held :: proc(p: Person, item: Item) -> int {
		n := 0
		for h in 0 ..< carry_slots(p) {
			if p.hands[h] == item {n += 1}
		}
		return n
	}
	stones := pile(g, p.site_x, p.site_y, .Stone) + held(p^, .Stone)
	sticks := pile(g, p.site_x, p.site_y, .Stick) + held(p^, .Stick)
	short_stone, short_stick := FIRE_PIT_STONES - stones, FIRE_PIT_STICKS - sticks
	at_site := p.x == p.site_x && p.y == p.site_y
	carrying := held(p^, .Stone) + held(p^, .Stick) > 0
	if at_site {
		if short_stone <= 0 && short_stick <= 0 {
			if build_fire_pit(g, p) {
				p.has_site = false
				return true
			}
			if carrying {return unload(g, p)} // some of it is still in hand: put it on the pile first
			p.has_site = false // the spot is no good any more
			return false
		}
		if carrying {return unload(g, p)}
	}
	if short_stone > 0 || short_stick > 0 { // still short: fetch more, unless both hands are busy
		if free_hand(p^) >= 0 {
			raw := Item.Stone if short_stone >= short_stick else Item.Stick
			if gather_raw(g, p, raw) {return true}
			if tx, ty, found := nearest_source(g, p^, raw); found {return step_toward(g, p, tx, ty)}
			return false
		}
	}
	if !at_site && (carrying || short_stone <= 0 && short_stick <= 0) {return step_toward(g, p, p.site_x, p.site_y)}
	return false
}

// Put one held stone or stick on the pile at the person's feet.
unload :: proc(g: ^Game, p: ^Person) -> bool {
	for h in 0 ..< carry_slots(p^) {
		if p.hands[h] == .Stone || p.hands[h] == .Stick {return drop_item(g, p, h)}
	}
	return false
}

// The nearest cell for which match is true.
nearest_match :: proc(g: ^Game, p: Person, match: proc(g: ^Game, x, y: int) -> bool) -> (x, y: int, ok: bool) {
	best := max(int)
	for i in 0 ..< len(g.cells) {
		cx, cy := i % g.width, i / g.width
		if !match(g, cx, cy) {continue}
		if d := abs(cx - p.x) + abs(cy - p.y); d < best {best, x, y, ok = d, cx, cy, true}
	}
	return
}

// Take the next step toward making something: craft it now, or go and get a raw material.
pursue_step :: proc(g: ^Game, p: ^Person, step: Step) -> bool {
	if step.craft != .None {return try_craft(g, p, step.craft)}
	if step.raw == .None {return false}
	if free_hand(p^) < 0 {return false}
	if gather_raw(g, p, step.raw) {return true}
	if tx, ty, found := nearest_source(g, p^, step.raw); found {return step_toward(g, p, tx, ty)}
	return false
}

// Get a net (making one if need be), then go to a pond with fish in it and fish.
pursue_fishing :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Net) {return pursue_step(g, p, next_step(g, p^, .Net))}
	if fish_adjacent(g, p) {return true}
	if tx, ty, found := nearest_match(g, p^, pond_with_fish); found {return step_toward(g, p, tx, ty)}
	return false
}

// Cook a meal: get a cooking stick, put meat on it (catching and cutting a fish if there is none),
// make sure a fire is burning, and hold the stick to it.
pursue_cooking :: proc(g: ^Game, p: ^Person) -> bool {
	if _, _, has_pit := nearest_match(g, p^, is_fire_pit); !has_pit {return false} // nowhere to cook
	if stick_where(p^, is_cooked) >= 0 {return false} // a meal is ready: eating comes first
	if stick_where(p^, is_raw_meat) >= 0 { // meat on the stick: take it to a lit fire
		if cook_on_fire(g, p) {return true}
		if tx, ty, lit := nearest_match(g, p^, lit_pit); lit {return step_toward(g, p, tx, ty)}
		return pursue_lighting(g, p)
	}
	if !holds(p^, .Cooking_Stick) {return pursue_step(g, p, next_step(g, p^, .Cooking_Stick))}
	if load_stick(g, p) {return true}
	if have_count(g, p^, .Fish) > 0 { // cut the fish into filets
		if holds(p^, .Sharp_Stone) {return fillet_fish(g, p)}
		return pursue_step(g, p, next_step(g, p^, .Sharp_Stone))
	}
	return pursue_fishing(g, p)
}

is_fire_pit :: proc(g: ^Game, x, y: int) -> bool {
	return terrain_at(g, x, y) == .Fire_Pit
}

// Light a pit that has fuel, making a fire drill first if need be.
pursue_lighting :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Fire_Drill) {
		if gx, gy, found := nearest_ground(g, p^, .Fire_Drill); found { // someone left a drill lying about: take it
			if gx == p.x && gy == p.y && pick_up(g, p, .Fire_Drill) {return true}
			if free_hand(p^) >= 0 {return step_toward(g, p, gx, gy)}
		}
		return pursue_step(g, p, next_step(g, p^, .Fire_Drill))
	}
	if light_fire(g, p) {return true}
	if tx, ty, found := nearest_match(g, p^, unlit_pit_with_fuel); found {return step_toward(g, p, tx, ty)}
	// every pit is out of fuel: put a stick on one to bring it back
	tx, ty, found := nearest_match(g, p^, pit_has_room)
	if !found {return false}
	if !holds(p^, .Stick) {return pursue_step(g, p, Step{raw = .Stick})}
	if add_stick(g, p, tx, ty) {return true}
	return step_toward(g, p, tx, ty)
}

// A fire comes before everything but food: the first person alive builds a pit, then lights it whenever
// the weather is cool enough for the warmth to matter. Others carry on; the fire is for the whole tribe.
FIRE_LIGHT_BELOW_C :: 16.0

fire_builder :: proc(g: ^Game, p: Person) -> bool {
	return len(g.people) > 0 && g.people[0].id == p.id
}

pursue_fire :: proc(g: ^Game, p: ^Person) -> bool {
	if !fire_builder(g, p^) {return false}
	if _, _, has_pit := nearest_match(g, p^, is_fire_pit); !has_pit {return pursue_pit(g, p)}
	if _, _, lit := nearest_match(g, p^, lit_pit); lit {return false}
	if !holds(p^, .Fire_Drill) {return pursue_lighting(g, p)} // get the drill in good time, light the fire when it is cool
	if temperature_c(g.clock, g.cfg) >= FIRE_LIGHT_BELOW_C {return false}
	return pursue_lighting(g, p)
}

// Hungry: satiety has slipped under the seeking line and there is nothing waiting in the stomach.
PREPARE_BELOW_SATIETY :: 90.0 // with no berries to be had, people set about fish and fire this early

hungry :: proc(p: Person) -> bool {
	return p.satiety < SEEK_MIN_SATIETY && p.stomach < EAT_BELOW_STOMACH
}

bush_with_food :: proc(g: ^Game, x, y: int) -> bool {
	b, ok := bush_at(g, x, y)
	return ok && b.food >= 1
}

// Put down something that is not worth keeping while hungry, to make a hand free for berries.
make_room_for_food :: proc(g: ^Game, p: ^Person) -> bool {
	for h in 0 ..< carry_slots(p^) {
		#partial switch p.hands[h] {
		case .None, .Food, .Basket, .Net, .Cooking_Stick, .Fire_Drill: continue
		}
		return drop_item(g, p, h)
	}
	for h in 0 ..< carry_slots(p^) { // all tools: set one down rather than starve; it can be fetched again
		if p.hands[h] != .None && p.hands[h] != .Food && p.hands[h] != .Basket {return drop_item(g, p, h)}
	}
	return false
}

// Winter is coming, or here: from the end of summer on, or whenever the day's average is under this,
// the berries have stopped growing and the stores will not last. This goes by the season and the daily
// average, not the temperature of the moment, which swings far more between noon and night.
PREPARE_MEAN_C :: 12.0

winter_coming :: proc(g: ^Game) -> bool {
	return cooling_season(g.clock, g.cfg) || mean_temperature_c(g.clock, g.cfg) < PREPARE_MEAN_C
}

// A hungry person goes after food before anything else: berries on a bush or fresh on the ground,
// whichever is nearest; failing those, a meal of fish cooked at a fire, building the fire if need be.
// From the end of summer, or with no berries left anywhere, even a fed person works at the fire and the fish,
// since that is the only food that will last the winter.
pursue_food :: proc(g: ^Game, p: ^Person) -> bool {
	peckish := p.satiety < PREPARE_BELOW_SATIETY && p.stomach < EAT_BELOW_STOMACH
	if p.role != .Generalist && !hungry(p^) {return false} // a specialist's job covers the preparing
	soon := winter_coming(g)
	if !hungry(p^) && !peckish && !soon {return false}
	if gather_adjacent(g, p) {return true}
	bx, by, on_bush := nearest_match(g, p^, bush_with_food)
	gx, gy: int
	on_ground: bool
	best := max(int)
	open := store_season(g, p^) && (!on_bush || abs(bx - p.x) + abs(by - p.y) > STORE_BUSH_RANGE) // see store_open
	for it in g.ground_items {
		if !edible_on_ground(g, it) || (is_dried(it.item) && !open) {continue}
		if d := abs(it.x - p.x) + abs(it.y - p.y); d < best {best, gx, gy, on_ground = d, it.x, it.y, true}
	}
	if on_bush && on_ground && best < abs(bx - p.x) + abs(by - p.y) {on_bush = false}
	preparing := soon || !(on_bush || on_ground)
	if !hungry(p^) && !preparing {return false}
	if hungry(p^) || !preparing {
		if on_bush {
			if free_hand(p^) < 0 {return make_room_for_food(g, p)} // setting it down is the turn, or the job would fill the hand again
			return step_toward(g, p, bx, by)
		}
		if on_ground {return step_toward(g, p, gx, gy)}
	}
	if _, _, has_pit := nearest_match(g, p^, is_fire_pit); has_pit {return pursue_cooking(g, p)}
	return pursue_pit(g, p)
}
