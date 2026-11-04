package gods

import "core:fmt"
import "core:math/rand"
import "core:strings"

// Things people drop sit on the ground where they fell. Stone keeps; everything else rots.
Ground_Item :: struct {
	x, y:          int,
	item:          Item,
	dropped_hours: f64, // game clock time it hit the ground
	loaded:        Item, // what a cooking stick on the ground has on it
	pack:          [BASKET_SLOTS]Item, // what a basket on the ground still holds; it keeps while the basket does
}

// Game hours for a dropped item to lose all its freshness and rot away; 0 means it never does.
// Food goes fastest, then fiber, then twine, then sticks.
FOOD_SPOIL_HOURS :: 24.0
FIBER_SPOIL_HOURS :: 72.0
TWINE_SPOIL_HOURS :: 240.0
STICK_SPOIL_HOURS :: 720.0
SPOIL_HOURS := [Item]f64 {
	.None  = 0,
	.Food  = FOOD_SPOIL_HOURS,
	.Stone = 0,
	.Fiber = FIBER_SPOIL_HOURS,
	.Stick = STICK_SPOIL_HOURS,
	.Twine = TWINE_SPOIL_HOURS,
	.Sharp_Stone = 0, // keeps like stone
	.Short_Stick = STICK_SPOIL_HOURS,
	.Spear = 0, // keeps like stone
	.Snake_Corpse = FOOD_SPOIL_HOURS,
	.Snake_Meat = FOOD_SPOIL_HOURS,
	.Snake_Skin = TWINE_SPOIL_HOURS,
	.Reed = TWINE_SPOIL_HOURS,
	.Basket = STICK_SPOIL_HOURS,
	.Bow = 0, // keeps like the other tools
	.Stake = 0,
	.Fire_Drill = 0,
	.Net = 0,
	.Fish = FOOD_SPOIL_HOURS,
	.Fish_Filet = FOOD_SPOIL_HOURS,
	.Cooking_Stick = 0,
	.Cooked_Snake_Meat = FOOD_SPOIL_HOURS,
	.Cooked_Fish_Filet = FOOD_SPOIL_HOURS,
	.Rope = TWINE_SPOIL_HOURS,
	.Belt = 0, // worn, never dropped
	.Rabbit_Corpse = FOOD_SPOIL_HOURS,
	.Rabbit_Meat = FOOD_SPOIL_HOURS,
	.Cooked_Rabbit_Meat = FOOD_SPOIL_HOURS,
	.Fur = STICK_SPOIL_HOURS,
	.Fur_Coat = 0, // keeps
	.Drying = 0, // dries before it could rot
	.Dried_Berries = 0,
	.Dried_Meat = 0,
	.Drying_Rack = 0, // keeps like the tools
	.Fire_Pit = 0,
}
DROP_CHANCE :: 0.02 // chance per action that a person carrying something simply sets it down

// 1 when just dropped, 0 when it rots away.
ground_freshness :: proc(g: ^Game, it: Ground_Item) -> f32 {
	hours := SPOIL_HOURS[it.item]
	if hours <= 0 {return 1}
	return clamp(1 - f32((g.clock.hours - it.dropped_hours) / hours), 0, 1)
}

// Things lying on the person's cell or any of the eight around it are within arm's reach, so a crowded
// stockpile (where its centre is occupied) still works.
in_reach :: proc(x1, y1, x2, y2: int) -> bool {
	return max(abs(x1 - x2), abs(y1 - y2)) <= 1
}

// Put whatever is in hand `hand` on the ground at the person's feet. A dropped basket keeps its food.
drop_item :: proc(g: ^Game, p: ^Person, hand: int) -> bool {
	if hand < 0 || hand >= carry_slots(p^) || p.hands[hand] == .None {return false}
	append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = p.hands[hand], dropped_hours = g.clock.hours, pack = p.packs[hand], loaded = p.loaded[hand]})
	p.hands[hand], p.loaded[hand], p.packs[hand] = .None, .None, {}
	return true
}

// Pick up one of an item lying at the person's feet, if a hand is free.
pick_up :: proc(g: ^Game, p: ^Person, item: Item) -> bool {
	hand := free_hand(p^)
	if hand < 0 {return false}
	for it, i in g.ground_items {
		if !in_reach(it.x, it.y, p.x, p.y) || it.item != item {continue}
		p.hands[hand], p.wear[hand], p.loaded[hand], p.packs[hand] = item, 0, it.loaded, it.pack
		unordered_remove(&g.ground_items, i)
		return true
	}
	return false
}

// The nearest spot where an item lies on the ground.
nearest_ground :: proc(g: ^Game, p: Person, item: Item) -> (x, y: int, ok: bool) {
	best := max(int)
	for it in g.ground_items {
		if it.item != item {continue}
		if d := abs(it.x - p.x) + abs(it.y - p.y); d < best {best, x, y, ok = d, it.x, it.y, true}
	}
	return
}

// Pick up a basket lying at the person's feet, food and all, if they have none and a place is free.
take_basket :: proc(g: ^Game, p: ^Person) -> bool {
	hand := free_hand(p^)
	if hand < 0 || has_basket(p^) {return false}
	for it, i in g.ground_items {
		if !in_reach(it.x, it.y, p.x, p.y) || it.item != .Basket {continue}
		p.hands[hand], p.wear[hand], p.loaded[hand], p.packs[hand] = .Basket, 0, .None, it.pack
		unordered_remove(&g.ground_items, i)
		return true
	}
	return false
}

// Is there something to eat in this ground item: fresh food, or food in a basket?
edible_on_ground :: proc(g: ^Game, it: Ground_Item) -> bool {
	if it.item == .Food {return ground_freshness(g, it) > 0}
	if it.item == .Cooking_Stick {return is_cooked(it.loaded)}
	if is_dried(it.item) {return true} // but only from the store; see store_open
	if it.item != .Basket {return false}
	for x in it.pack {
		if x == .Food {return true}
	}
	return false
}

// Remove dropped things that have had time to rot away.
update_ground_items :: proc(g: ^Game) {
	update_drying(g)
	for i := len(g.ground_items) - 1; i >= 0; i -= 1 {
		it := g.ground_items[i]
		if SPOIL_HOURS[it.item] > 0 && ground_freshness(g, it) <= 0 {unordered_remove(&g.ground_items, i)}
	}
}

// Take one stone from the stone field the person is standing on, if a hand is free.
gather_stone_here :: proc(g: ^Game, p: ^Person) -> bool {
	hand := free_hand(p^)
	if hand < 0 {return false}
	if left, ok := stone_at(g, p.x, p.y); !ok || left <= 0 {return false}
	if !skill_succeeds(p.foraging) {return true} // fumbled it; nothing taken
	take_stone(g, p.x, p.y, 1)
	p.hands[hand] = .Stone
	return true
}

// Crafting an item well takes practice: the check for an item adds the person's level at that item
// (one point per success so far) to their crafting skill, and every success raises that level by one.
craft_roll :: proc(p: ^Person, item: Item) -> bool {
	if !skill_succeeds(p.crafting + f32(p.craft_levels[item])) {return false}
	craft_credit(p, item)
	return true
}

// A success with no roll behind it, such as building a firepit.
craft_credit :: proc(p: ^Person, item: Item) {
	reward_dopamine(p, item) // before the level goes up: the reward depends on how new this is
	p.craft_levels[item] += 1
}

// "twine 5, spear 2" for what a person has made, or "" if they have made nothing.
describe_craft_levels :: proc(p: Person) -> string {
	s := ""
	for item in Item {
		if p.craft_levels[item] > 0 {
			s = fmt.tprintf("%s%s%s %d", s, ", " if len(s) > 0 else "", ITEM_NAMES[item], p.craft_levels[item])
		}
	}
	return s
}

ITEM_NAMES := [Item]string {
	.None = "nothing",
	.Food = "food",
	.Stone = "stone",
	.Fiber = "fiber",
	.Stick = "stick",
	.Twine = "twine",
	.Sharp_Stone = "sharp stone",
	.Short_Stick = "short stick",
	.Spear = "spear",
	.Snake_Corpse = "snake corpse",
	.Snake_Meat = "snake meat",
	.Snake_Skin = "snake skin",
	.Reed = "reed",
	.Basket = "basket",
	.Bow = "bow",
	.Stake = "stake",
	.Fire_Drill = "fire drill",
	.Net = "net",
	.Fish = "fish",
	.Fish_Filet = "fish filet",
	.Cooking_Stick = "cooking stick",
	.Cooked_Snake_Meat = "cooked snake meat",
	.Cooked_Fish_Filet = "cooked fish filet",
	.Rope = "rope",
	.Belt = "belt",
	.Rabbit_Corpse = "rabbit corpse",
	.Rabbit_Meat = "rabbit meat",
	.Cooked_Rabbit_Meat = "cooked rabbit meat",
	.Fur = "fur",
	.Fur_Coat = "fur coat",
	.Drying = "food drying",
	.Dried_Berries = "dried berries",
	.Dried_Meat = "dried meat",
	.Drying_Rack = "drying rack",
	.Fire_Pit = "fire pit",
}

// Twist two plant fibers, held or lying at the person's feet, into one twine. A botched twist wastes
// a fiber.
craft_twine :: proc(g: ^Game, p: ^Person) -> bool {
	if have_count(g, p^, .Fiber) < 2 {return false}
	if !craft_roll(p, .Twine) {
		spend(g, p, .Fiber, 1)
		return true
	}
	spend(g, p, .Fiber, 2)
	give_or_drop(g, p, .Twine)
	return true
}

// Knock two stones together, held or lying at the person's feet: one stays a stone and the other becomes
// a sharp stone. If the attempt fails the would-be sharp stone is lost, leaving just the one stone.
craft_sharp_stone :: proc(g: ^Game, p: ^Person) -> bool {
	if have_count(g, p^, .Stone) < 2 {return false}
	spend(g, p, .Stone, 1)
	if craft_roll(p, .Sharp_Stone) {give_or_drop(g, p, .Sharp_Stone)}
	return true
}

// Cut a stick, held or lying at the person's feet, with a sharp stone in hand: the sharp stone is kept
// and the stick becomes two short sticks. That is three things for two hands, so whatever does not fit
// in a free hand lands on the ground at the person's feet. If the attempt fails the stick is lost and
// the sharp stone kept.
craft_short_sticks :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Sharp_Stone) || have_count(g, p^, .Stick) < 1 {return false}
	spend(g, p, .Stick, 1)
	if !craft_roll(p, .Short_Stick) {return true}
	give_or_drop(g, p, .Short_Stick)
	give_or_drop(g, p, .Short_Stick)
	return true
}

// Recipes that bind three ingredients together. A person has only two hands, so ingredients may be
// in hand or lying on the ground at their feet (a cut short stick often is). Success uses all three
// up and makes the result; failure wastes just the last ingredient, the twine.
SPEAR_INGREDIENTS :: [3]Item{.Sharp_Stone, .Stick, .Twine} // a sharp stone bound to a long stick

// One spear each is plenty.
craft_spear :: proc(g: ^Game, p: ^Person) -> bool {
	if holds(p^, .Spear) {return false}
	ingredients := SPEAR_INGREDIENTS
	return craft_recipe(g, p, ingredients[:], .Spear)
}

// Five reeds woven together make a basket. A person carries only one, and a clumsy weave ruins a reed.
BASKET_REEDS :: 5

craft_basket :: proc(g: ^Game, p: ^Person) -> bool {
	if holds(p^, .Basket) || !p.belt {return false} // it takes a place, so only a belt makes room for one
	ingredients: [BASKET_REEDS]Item
	for &item in ingredients {item = .Reed}
	return craft_recipe(g, p, ingredients[:], .Basket)
}

// Two twine twisted together make a rope; a clumsy twist ruins one twine.
craft_rope :: proc(g: ^Game, p: ^Person) -> bool {
	ingredients := [?]Item{.Twine, .Twine}
	return craft_recipe(g, p, ingredients[:], .Rope)
}

// Two ropes make a belt, which is worn at once and gives BELT_SLOTS more places to carry things.
// One is plenty; a clumsy knot ruins one rope.
craft_belt :: proc(g: ^Game, p: ^Person) -> bool {
	if p.belt {return false}
	ingredients := [?]Item{.Rope, .Rope}
	return craft_recipe(g, p, ingredients[:], .Belt)
}

MAX_INGREDIENTS :: 16

craft_recipe :: proc(g: ^Game, p: ^Person, ingredients: []Item, result: Item, fail_loss := 1) -> bool {
	n := len(ingredients)
	hand_of: [MAX_INGREDIENTS]int = -1 // where each ingredient was found: a hand index...
	ground_of: [MAX_INGREDIENTS]int = -1 // ...or an index into ground_items
	used_hand: [MAX_SLOTS]bool
	for item, k in ingredients {
		for h in 0 ..< carry_slots(p^) {
			if p.hands[h] == item && !used_hand[h] {
				hand_of[k], used_hand[h] = h, true
				break
			}
		}
		if hand_of[k] >= 0 {continue}
		for it, i in g.ground_items {
			if !in_reach(it.x, it.y, p.x, p.y) || it.item != item {continue}
			taken := false
			for other in ground_of[:n] {taken ||= other == i}
			if !taken {
				ground_of[k] = i
				break
			}
		}
		if ground_of[k] < 0 {return false}
	}
	// Work out what is spent: everything on success, only the last ingredient on failure (or nothing).
	success := craft_roll(p, result)
	first := 0 if success else n - fail_loss // a failed try spends the last few ingredients (or none)
	remove_ground: [MAX_INGREDIENTS]int = -1
	for k in first ..< n {
		if hand_of[k] >= 0 {p.hands[hand_of[k]] = .None}
		remove_ground[k] = ground_of[k]
	}
	for i := len(g.ground_items) - 1; i >= 0; i -= 1 { // highest index first keeps the others valid
		for r in remove_ground[:n] {
			if r == i {
				unordered_remove(&g.ground_items, i)
				break
			}
		}
	}
	if !success {return true}
	give_or_drop(g, p, result)
	return true
}

// Tools wear out: each use (a spear thrust, a cut with a sharp stone) wears one point, and a tool with no
// durability left breaks and is gone. Anything that is not a tool never wears.
SPEAR_DURABILITY :: 8
SHARP_STONE_DURABILITY :: 12 // a sharp stone is the cutting tool: it skins, fillets, whittles and cuts reeds
FIRE_DRILL_DURABILITY :: 6

durability_of :: proc(item: Item) -> int {
	#partial switch item {
	case .Spear: return SPEAR_DURABILITY
	case .Sharp_Stone: return SHARP_STONE_DURABILITY
	case .Net: return NET_DURABILITY
	case .Fire_Drill: return FIRE_DRILL_DURABILITY
	}
	return 0
}

// Uses left in the first held tool of this kind, and whether one is held at all.
uses_left :: proc(p: Person, item: Item) -> (int, bool) {
	for h in 0 ..< carry_slots(p) {
		if p.hands[h] == item {return durability_of(item) - p.wear[h], true}
	}
	return 0, false
}

// Wear the first held tool of this kind by one use. Returns true if that broke it.
wear_tool :: proc(p: ^Person, item: Item) -> bool {
	for h in 0 ..< carry_slots(p^) {
		if p.hands[h] != item {continue}
		p.wear[h] += 1
		if p.wear[h] < durability_of(item) {return false}
		p.hands[h], p.wear[h] = .None, 0
		return true
	}
	return false
}

// A bow is a stick strung with twine. A failed attempt wastes the twine.
craft_bow :: proc(g: ^Game, p: ^Person) -> bool {
	ingredients := [?]Item{.Stick, .Twine}
	return craft_recipe(g, p, ingredients[:], .Bow)
}

// Whittle a short stick to a point with a sharp stone. The stone survives (wearing a little) and a failed
// attempt wastes the short stick.
craft_stake :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Sharp_Stone) {return false}
	if !spend(g, p, .Short_Stick, 1) {return false}
	wear_tool(p, .Sharp_Stone)
	if craft_roll(p, .Stake) {give_or_drop(g, p, .Stake)}
	return true
}

// A bow and a stake make a fire drill. A failed attempt wastes nothing.
craft_fire_drill :: proc(g: ^Game, p: ^Person) -> bool {
	ingredients := [?]Item{.Bow, .Stake}
	return craft_recipe(g, p, ingredients[:], .Fire_Drill, fail_loss = 0)
}

// Use up `count` of an item, from hands first and then the ground at the person's feet. Nothing is
// spent unless all of them are there.
spend :: proc(g: ^Game, p: ^Person, item: Item, count: int) -> bool {
	if have_count(g, p^, item) < count {return false}
	left := count
	for h in 0 ..< carry_slots(p^) {
		if left > 0 && p.hands[h] == item {p.hands[h] = .None; left -= 1}
	}
	for left > 0 && unpack(p, item) {left -= 1}
	for i := len(g.ground_items) - 1; i >= 0 && left > 0; i -= 1 {
		it := g.ground_items[i]
		if in_reach(it.x, it.y, p.x, p.y) && it.item == item {unordered_remove(&g.ground_items, i); left -= 1}
	}
	return true
}

// Put a thing in a free hand, or on the ground at the person's feet if both hands are full.
give_or_drop :: proc(g: ^Game, p: ^Person, item: Item) {
	if item == .Belt { // worn at once
		p.belt = true
		return
	}
	if item == .Fur_Coat && !p.coat { // put on at once by one who has none
		p.coat = true
		return
	}
	if stow(p, item) {return} // food goes into a basket first
	if hand := free_hand(p^); hand >= 0 {
		p.hands[hand], p.wear[hand], p.loaded[hand] = item, 0, .None
	} else {
		append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = item, dropped_hours = g.clock.hours})
	}
}

holds :: proc(p: Person, item: Item) -> bool {
	if item == .Belt {return p.belt}
	for h in 0 ..< carry_slots(p) {
		if p.hands[h] == item {return true}
	}
	return false
}

// Take one stick from the tree at (tx, ty): the person must be orthogonally next to it, the
// tree must hold a whole stick, and a hand must be free.
gather_stick :: proc(g: ^Game, p: ^Person, tx, ty: int) -> bool {
	if abs(p.x - tx) + abs(p.y - ty) != 1 {return false}
	if _, ok := sticks_at(g, tx, ty); !ok {return false}
	hand := free_hand(p^)
	if hand < 0 {return false}
	i := ty * g.width + tx
	if g.sticks[i] < 1 {return false}
	if !skill_succeeds(p.foraging) {return true} // fumbled it; nothing taken
	g.sticks[i] -= 1
	p.hands[hand] = .Stick
	return true
}

gather_stick_adjacent :: proc(g: ^Game, p: ^Person) -> bool {
	for d in DIRS {
		if gather_stick(g, p, p.x + d.x, p.y + d.y) {return true}
	}
	return false
}

// With a sharp stone in hand, cut one reed from the pond at (px, py): the person must be orthogonally
// next to it and the pond must hold a whole reed. The reed goes in a free place, or onto the ground
// at the person's feet. Each cut wears the stone.
gather_reed :: proc(g: ^Game, p: ^Person, px, py: int) -> bool {
	if !holds(p^, .Sharp_Stone) {return false}
	if abs(p.x - px) + abs(p.y - py) != 1 {return false}
	if left, ok := reeds_at(g, px, py); !ok || left < 1 {return false}
	if !skill_succeeds(p.foraging) {return true} // fumbled it; nothing cut
	g.reeds[py * g.width + px] -= 1
	give_or_drop(g, p, .Reed)
	wear_tool(p, .Sharp_Stone)
	return true
}

gather_reed_adjacent :: proc(g: ^Game, p: ^Person) -> bool {
	for d in DIRS {
		if gather_reed(g, p, p.x + d.x, p.y + d.y) {return true}
	}
	return false
}

// Take one unit of plant fiber from the grass the person stands on, if a hand is free.
gather_fiber_here :: proc(g: ^Game, p: ^Person) -> bool {
	hand := free_hand(p^)
	if hand < 0 {return false}
	if left, ok := fiber_at(g, p.x, p.y); !ok || left <= 0 {return false}
	if !skill_succeeds(p.foraging) {return true} // fumbled it; nothing taken
	take_fiber(g, p.x, p.y)
	p.hands[hand] = .Fiber
	return true
}

// Hungry people eat food lying on their own cell; spoiled food fills the stomach less.
eat_from_ground :: proc(g: ^Game, p: ^Person) -> bool {
	if p.stomach >= EAT_BELOW_STOMACH || p.satiety >= EAT_BELOW_SATIETY {return false}
	store: Maybe(bool) // worked out only if there is dried food to hand
	for it, i in g.ground_items {
		if !in_reach(it.x, it.y, p.x, p.y) {continue}
		if is_dried(it.item) {
			if store == nil {store = store_open(g, p^)}
			if !store.? {continue}
			p.stomach = min(p.stomach + dried_stomach(it.item), MAX_STOMACH)
			unordered_remove(&g.ground_items, i)
			return true
		}
		if it.item == .Basket { // food in a basket on the ground has not spoiled
			for k in 0 ..< BASKET_SLOTS {
				if g.ground_items[i].pack[k] == .Food {
					g.ground_items[i].pack[k] = .None
					p.stomach = min(p.stomach + FOOD_STOMACH, MAX_STOMACH)
					return true
				}
			}
			continue
		}
		if it.item == .Cooking_Stick && is_cooked(it.loaded) { // a meal left out on its stick
			g.ground_items[i].loaded = .None
			p.stomach = min(p.stomach + COOKED_STOMACH, MAX_STOMACH)
			return true
		}
		if it.item != .Food {continue}
		p.stomach = min(p.stomach + FOOD_STOMACH * ground_freshness(g, it), MAX_STOMACH)
		unordered_remove(&g.ground_items, i)
		return true
	}
	return false
}

next_to_food_bush :: proc(g: ^Game, p: Person) -> bool {
	for d in DIRS {
		if b, ok := bush_at(g, p.x + d.x, p.y + d.y); ok && b.food >= 1 {return true}
	}
	return false
}

// People set things down now and then. With full hands beside a bush that has berries they
// drop something that is not food to make room for food; otherwise there is a small chance they drop something.
drop_something :: proc(g: ^Game, p: ^Person) -> bool {
	if free_hand(p^) < 0 && next_to_food_bush(g, p^) {
		for h in 0 ..< carry_slots(p^) {
			if p.hands[h] != .Food && p.hands[h] != .None && p.hands[h] != .Basket {return drop_item(g, p, h)}
		}
	}
	if held_count(p^) > 0 && rand.float32() < DROP_CHANCE {
		for h in 0 ..< carry_slots(p^) {
			if p.hands[h] != .None && p.hands[h] != .Basket && !for_the_larder(p.hands[h]) {return drop_item(g, p, h)}
		}
	}
	return false
}

// Tools and catch for getting a meal: people do not idly set these down.
for_the_larder :: proc(item: Item) -> bool {
	#partial switch item {
	case .Net, .Cooking_Stick, .Fire_Drill, .Fish, .Fish_Filet, .Snake_Meat, .Rabbit_Corpse, .Rabbit_Meat, .Fur, .Fur_Coat: return true
	}
	return false
}

// "2 stone, 1 fiber, 3 stick, 1 twine, 1 food (80% fresh)" for the things on a cell, or "" if there is nothing.
describe_ground_items :: proc(g: ^Game, x, y: int, buf: []byte) -> string {
	counts: [Item]int
	fresh: f32
	for it in g.ground_items {
		if it.x != x || it.y != y {continue}
		counts[it.item] += 1
		if it.item == .Food {fresh += ground_freshness(g, it)}
	}
	b := strings.builder_from_bytes(buf)
	sep :: proc(b: ^strings.Builder) -> string {return ", " if strings.builder_len(b^) > 0 else ""}
	room :: proc(b: ^strings.Builder) -> bool {return strings.builder_cap(b^) - strings.builder_len(b^) >= 48} // never grow past the caller's buffer
	if counts[.Stone] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d stone", sep(&b), counts[.Stone])}
	if counts[.Fiber] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d fiber", sep(&b), counts[.Fiber])}
	if counts[.Stick] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d stick", sep(&b), counts[.Stick])}
	if counts[.Sharp_Stone] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d sharp stone", sep(&b), counts[.Sharp_Stone])}
	if counts[.Short_Stick] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d short stick", sep(&b), counts[.Short_Stick])}
	if counts[.Spear] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d spear", sep(&b), counts[.Spear])}
	if counts[.Snake_Corpse] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d snake corpse", sep(&b), counts[.Snake_Corpse])}
	if counts[.Snake_Meat] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d snake meat", sep(&b), counts[.Snake_Meat])}
	if counts[.Bow] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d bow", sep(&b), counts[.Bow])}
	if counts[.Stake] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d stake", sep(&b), counts[.Stake])}
	if counts[.Fire_Drill] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d fire drill", sep(&b), counts[.Fire_Drill])}
	if counts[.Net] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d net", sep(&b), counts[.Net])}
	if counts[.Fish] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d fish", sep(&b), counts[.Fish])}
	if counts[.Fish_Filet] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d fish filet", sep(&b), counts[.Fish_Filet])}
	if counts[.Cooking_Stick] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d cooking stick", sep(&b), counts[.Cooking_Stick])}
	if counts[.Rabbit_Corpse] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d rabbit corpse", sep(&b), counts[.Rabbit_Corpse])}
	if counts[.Rabbit_Meat] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d rabbit meat", sep(&b), counts[.Rabbit_Meat])}
	if counts[.Fur] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d fur", sep(&b), counts[.Fur])}
	if counts[.Fur_Coat] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d fur coat", sep(&b), counts[.Fur_Coat])}
	if counts[.Drying] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d drying", sep(&b), counts[.Drying])}
	if counts[.Dried_Berries] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d dried berries", sep(&b), counts[.Dried_Berries])}
	if counts[.Dried_Meat] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d dried meat", sep(&b), counts[.Dried_Meat])}
	if counts[.Drying_Rack] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d drying rack", sep(&b), counts[.Drying_Rack])}
	if counts[.Reed] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d reed", sep(&b), counts[.Reed])}
	if counts[.Rope] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d rope", sep(&b), counts[.Rope])}
	if counts[.Basket] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d basket", sep(&b), counts[.Basket])}
	if counts[.Snake_Skin] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d snake skin", sep(&b), counts[.Snake_Skin])}
	if counts[.Twine] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d twine", sep(&b), counts[.Twine])}
	if counts[.Food] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d food (%.0f%% fresh)", sep(&b), counts[.Food], 100 * fresh / f32(counts[.Food]))}
	return strings.to_string(b)
}
