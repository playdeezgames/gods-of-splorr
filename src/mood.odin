package gods

import "core:math"

// Dopamine is a person's mood chemical. Making something feels good, most of all the first time,
// and less and less as they make more things; it bleeds away by itself. People who feel flat crave
// the feeling, which sends them after things to make.
MAX_DOPAMINE :: 100.0
START_DOPAMINE :: 50.0
DOPAMINE_HALF_LIFE_HOURS :: 12.0
CRAVING_BELOW :: 35.0
SEEK_MIN_SATIETY :: 60.0 // a hungry person is not out looking for things to make

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

// What making this item would feel like right now: a big hit for a first, a shrinking one for
// repeats of the same item, and everything duller the more the person has already made.
craft_reward :: proc(p: Person, item: Item) -> f32 {
	novelty := f32(FIRST_CRAFT_MULT) if p.craft_levels[item] == 0 else 1 / f32(1 + p.craft_levels[item])
	return CRAFT_REWARD * novelty / (1 + HABITUATION_PER_CRAFT * f32(total_crafts(p)))
}

// Pay out the reward for a success. Call it before the item's level goes up.
reward_dopamine :: proc(p: ^Person, item: Item) {
	p.dopamine = min(p.dopamine + craft_reward(p^, item), MAX_DOPAMINE)
}

// Dopamine bleeds off exponentially: half is gone after the half-life.
step_dopamine :: proc(p: ^Person, dt: f32) {
	p.dopamine *= math.pow(f32(0.5), dt / DOPAMINE_HALF_LIFE_HOURS)
}

CRAFTABLE := [?]Item{.Twine, .Sharp_Stone, .Short_Stick, .Knife, .Spear, .Basket, .Bow, .Stake, .Fire_Drill, .Fire_Pit}

try_craft :: proc(g: ^Game, p: ^Person, item: Item) -> bool {
	#partial switch item {
	case .Twine: return craft_twine(p)
	case .Sharp_Stone: return craft_sharp_stone(p)
	case .Short_Stick: return craft_short_sticks(g, p)
	case .Knife: return craft_knife(g, p)
	case .Spear: return craft_spear(g, p)
	case .Basket: return craft_basket(g, p)
	case .Bow: return craft_bow(g, p)
	case .Stake: return craft_stake(g, p)
	case .Fire_Drill: return craft_fire_drill(g, p)
	case .Fire_Pit: return build_fire_pit(g, p)
	}
	return false
}

// The craftable items ordered by how good making them would feel, best first.
by_reward :: proc(p: Person) -> [len(CRAFTABLE)]Item {
	order := CRAFTABLE
	for i in 1 ..< len(order) { // stable insertion sort: ties keep their listed order
		for j := i; j > 0 && craft_reward(p, order[j]) > craft_reward(p, order[j - 1]); j -= 1 {
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
	for it in g.ground_items {
		if it.x == p.x && it.y == p.y && it.item == item {n += 1}
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
	@(static) knife := [?]Need{{.Sharp_Stone, 1}, {.Short_Stick, 1}, {.Twine, 1}}
	@(static) spear := [?]Need{{.Sharp_Stone, 1}, {.Stick, 1}, {.Twine, 1}}
	@(static) basket := [?]Need{{.Reed, BASKET_REEDS}}
	@(static) bow := [?]Need{{.Stick, 1}, {.Twine, 1}}
	@(static) stake := [?]Need{{.Knife, 1}, {.Short_Stick, 1}}
	@(static) drill := [?]Need{{.Bow, 1}, {.Stake, 1}}
	#partial switch item {
	case .Twine: return twine[:]
	case .Sharp_Stone: return sharp[:]
	case .Short_Stick: return short[:]
	case .Knife: return knife[:]
	case .Spear: return spear[:]
	case .Basket: return basket[:]
	case .Bow: return bow[:]
	case .Stake: return stake[:]
	case .Fire_Drill: return drill[:]
	}
	return nil
}

// What a person should do next on the way to making an item, working back through whatever they
// must make first: either craft something now (the item itself, or an ingredient of it), or go and
// get a raw material (fiber, stone, stick or reed). Reeds need a knife to cut.
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
			if !holds(p, .Knife) {return next_step(g, p, .Knife, depth + 1)}
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
		if holds(p^, goal) && (goal == .Spear || goal == .Basket || goal == .Knife || goal == .Bow || goal == .Stake || goal == .Fire_Drill) {continue} // one is plenty
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
