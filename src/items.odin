package gods

import "core:fmt"
import "core:math/rand"
import "core:strings"

// Things people drop sit on the ground where they fell. Stone keeps; everything else rots.
Ground_Item :: struct {
	x, y:          int,
	item:          Item,
	dropped_hours: f64, // game clock time it hit the ground
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
	.Knife = 0, // keeps like stone
	.Spear = 0, // keeps like stone
	.Snake_Corpse = FOOD_SPOIL_HOURS,
	.Snake_Meat = FOOD_SPOIL_HOURS,
	.Snake_Skin = TWINE_SPOIL_HOURS,
	.Reed = TWINE_SPOIL_HOURS,
	.Basket = STICK_SPOIL_HOURS,
}
DROP_CHANCE :: 0.02 // chance per action that a person carrying something simply sets it down

// 1 when just dropped, 0 when it rots away.
ground_freshness :: proc(g: ^Game, it: Ground_Item) -> f32 {
	hours := SPOIL_HOURS[it.item]
	if hours <= 0 {return 1}
	return clamp(1 - f32((g.clock.hours - it.dropped_hours) / hours), 0, 1)
}

// Put whatever is in hand `hand` on the ground at the person's feet.
drop_item :: proc(g: ^Game, p: ^Person, hand: int) -> bool {
	if hand < 0 || hand >= carry_slots(p^) || p.hands[hand] == .None {return false}
	append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = p.hands[hand], dropped_hours = g.clock.hours})
	p.hands[hand] = .None
	spill_unsupported(g, p)
	return true
}

// Without a basket in hand, whatever was riding in its places falls to the ground at the person's feet.
spill_unsupported :: proc(g: ^Game, p: ^Person) {
	if has_basket(p^) {return}
	for i in p.hand_count ..< MAX_SLOTS {
		if p.hands[i] == .None {continue}
		append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = p.hands[i], dropped_hours = g.clock.hours})
		p.hands[i] = .None
	}
}

// Remove dropped things that have had time to rot away.
update_ground_items :: proc(g: ^Game) {
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
	p.craft_levels[item] += 1
	return true
}

// "twine 5, knife 2" for what a person has made, or "" if they have made nothing.
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
	.Knife = "knife",
	.Spear = "spear",
	.Snake_Corpse = "snake corpse",
	.Snake_Meat = "snake meat",
	.Snake_Skin = "snake skin",
	.Reed = "reed",
	.Basket = "basket",
}

// Twist two plant fibers held in hand into one twine, which takes one hand and frees the other.
craft_twine :: proc(p: ^Person) -> bool {
	first, second := -1, -1
	for h in 0 ..< carry_slots(p^) {
		if p.hands[h] != .Fiber {continue}
		if first < 0 {first = h} else {second = h; break}
	}
	if second < 0 {return false}
	if !craft_roll(p, .Twine) { // a botched twist wastes a fiber
		p.hands[second] = .None
		return true
	}
	p.hands[first] = .Twine
	p.hands[second] = .None
	return true
}

// Knock two stones together: one stays a stone and the other becomes a sharp stone. If the
// attempt fails the would-be sharp stone is lost, leaving just the one stone.
craft_sharp_stone :: proc(p: ^Person) -> bool {
	first, second := -1, -1
	for h in 0 ..< carry_slots(p^) {
		if p.hands[h] != .Stone {continue}
		if first < 0 {first = h} else {second = h; break}
	}
	if second < 0 {return false}
	p.hands[second] = .Sharp_Stone if craft_roll(p, .Sharp_Stone) else .None
	return true
}

// Cut a stick with a sharp stone: the sharp stone is kept and the stick becomes two short sticks.
// That is three things for two hands, so whatever does not fit in a free hand lands on the ground
// at the person's feet. If the attempt fails the stick is lost and the sharp stone kept.
craft_short_sticks :: proc(g: ^Game, p: ^Person) -> bool {
	sharp, stick := -1, -1
	for h in 0 ..< carry_slots(p^) {
		if p.hands[h] == .Sharp_Stone && sharp < 0 {sharp = h}
		if p.hands[h] == .Stick && stick < 0 {stick = h}
	}
	if sharp < 0 || stick < 0 {return false}
	if !craft_roll(p, .Short_Stick) {
		p.hands[stick] = .None
		return true
	}
	p.hands[stick] = .Short_Stick
	if hand := free_hand(p^); hand >= 0 {
		p.hands[hand] = .Short_Stick
	} else {
		append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = .Short_Stick, dropped_hours = g.clock.hours})
	}
	return true
}

// Recipes that bind three ingredients together. A person has only two hands, so ingredients may be
// in hand or lying on the ground at their feet (a cut short stick often is). Success uses all three
// up and makes the result; failure wastes just the last ingredient, the twine.
KNIFE_INGREDIENTS :: [3]Item{.Sharp_Stone, .Short_Stick, .Twine} // a sharp stone bound to a short stick handle
SPEAR_INGREDIENTS :: [3]Item{.Sharp_Stone, .Stick, .Twine} // a sharp stone bound to a long stick

craft_knife :: proc(g: ^Game, p: ^Person) -> bool {
	ingredients := KNIFE_INGREDIENTS
	return craft_recipe(g, p, ingredients[:], .Knife)
}

// One spear each is plenty.
craft_spear :: proc(g: ^Game, p: ^Person) -> bool {
	if holds(p^, .Spear) {return false}
	ingredients := SPEAR_INGREDIENTS
	return craft_recipe(g, p, ingredients[:], .Spear)
}

// Five reeds woven together make a basket. A person carries only one, and a clumsy weave ruins a reed.
BASKET_REEDS :: 5

craft_basket :: proc(g: ^Game, p: ^Person) -> bool {
	if holds(p^, .Basket) {return false}
	ingredients: [BASKET_REEDS]Item
	for &item in ingredients {item = .Reed}
	return craft_recipe(g, p, ingredients[:], .Basket)
}

MAX_INGREDIENTS :: 8

craft_recipe :: proc(g: ^Game, p: ^Person, ingredients: []Item, result: Item) -> bool {
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
			if it.x != p.x || it.y != p.y || it.item != item {continue}
			taken := false
			for other in ground_of[:n] {taken ||= other == i}
			if !taken {
				ground_of[k] = i
				break
			}
		}
		if ground_of[k] < 0 {return false}
	}
	// Work out what is spent: everything on success, only the last ingredient on failure.
	success := craft_roll(p, result)
	first := 0 if success else n - 1
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
	spill_unsupported(g, p)
	if !success {return true}
	give_or_drop(g, p, result)
	return true
}

// Tools wear out: each use (a spear thrust, a knife cut) wears one point, and a tool with no
// durability left breaks and is gone. Anything that is not a tool never wears.
SPEAR_DURABILITY :: 8
KNIFE_DURABILITY :: 12

durability_of :: proc(item: Item) -> int {
	#partial switch item {
	case .Spear: return SPEAR_DURABILITY
	case .Knife: return KNIFE_DURABILITY
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

// Put a thing in a free hand, or on the ground at the person's feet if both hands are full.
give_or_drop :: proc(g: ^Game, p: ^Person, item: Item) {
	if hand := free_hand(p^); hand >= 0 {
		p.hands[hand], p.wear[hand] = item, 0
	} else {
		append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = item, dropped_hours = g.clock.hours})
	}
}

holds :: proc(p: Person, item: Item) -> bool {
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

// With a knife in hand, cut one reed from the pond at (px, py): the person must be orthogonally
// next to it and the pond must hold a whole reed. The reed goes in a free place, or onto the ground
// at the person's feet. Each cut wears the knife.
gather_reed :: proc(g: ^Game, p: ^Person, px, py: int) -> bool {
	if !holds(p^, .Knife) {return false}
	if abs(p.x - px) + abs(p.y - py) != 1 {return false}
	if left, ok := reeds_at(g, px, py); !ok || left < 1 {return false}
	if !skill_succeeds(p.foraging) {return true} // fumbled it; nothing cut
	g.reeds[py * g.width + px] -= 1
	give_or_drop(g, p, .Reed)
	wear_tool(p, .Knife)
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
	if p.stomach >= EAT_BELOW_STOMACH {return false}
	for it, i in g.ground_items {
		if it.x != p.x || it.y != p.y || it.item != .Food {continue}
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
			if p.hands[h] != .None && p.hands[h] != .Basket {return drop_item(g, p, h)}
		}
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
	if counts[.Knife] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d knife", sep(&b), counts[.Knife])}
	if counts[.Spear] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d spear", sep(&b), counts[.Spear])}
	if counts[.Snake_Corpse] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d snake corpse", sep(&b), counts[.Snake_Corpse])}
	if counts[.Snake_Meat] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d snake meat", sep(&b), counts[.Snake_Meat])}
	if counts[.Reed] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d reed", sep(&b), counts[.Reed])}
	if counts[.Basket] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d basket", sep(&b), counts[.Basket])}
	if counts[.Snake_Skin] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d snake skin", sep(&b), counts[.Snake_Skin])}
	if counts[.Twine] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d twine", sep(&b), counts[.Twine])}
	if counts[.Food] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d food (%.0f%% fresh)", sep(&b), counts[.Food], 100 * fresh / f32(counts[.Food]))}
	return strings.to_string(b)
}
