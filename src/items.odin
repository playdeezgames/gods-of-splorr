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
	if hand < 0 || hand >= p.hand_count || p.hands[hand] == .None {return false}
	append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = p.hands[hand], dropped_hours = g.clock.hours})
	p.hands[hand] = .None
	return true
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

// Twist two plant fibers held in hand into one twine, which takes one hand and frees the other.
craft_twine :: proc(p: ^Person) -> bool {
	first, second := -1, -1
	for h in 0 ..< p.hand_count {
		if p.hands[h] != .Fiber {continue}
		if first < 0 {first = h} else {second = h; break}
	}
	if second < 0 {return false}
	if !skill_succeeds(p.crafting) { // a botched twist wastes a fiber
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
	for h in 0 ..< p.hand_count {
		if p.hands[h] != .Stone {continue}
		if first < 0 {first = h} else {second = h; break}
	}
	if second < 0 {return false}
	p.hands[second] = .Sharp_Stone if skill_succeeds(p.crafting) else .None
	return true
}

// Cut a stick with a sharp stone: the sharp stone is kept and the stick becomes two short sticks.
// That is three things for two hands, so whatever does not fit in a free hand lands on the ground
// at the person's feet. If the attempt fails the stick is lost and the sharp stone kept.
craft_short_sticks :: proc(g: ^Game, p: ^Person) -> bool {
	sharp, stick := -1, -1
	for h in 0 ..< p.hand_count {
		if p.hands[h] == .Sharp_Stone && sharp < 0 {sharp = h}
		if p.hands[h] == .Stick && stick < 0 {stick = h}
	}
	if sharp < 0 || stick < 0 {return false}
	if !skill_succeeds(p.crafting) {
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

// A knife is a sharp stone bound to a short stick handle with twine. A person has only two hands,
// so ingredients may be in hand or lying on the ground at their feet (a cut short stick often is).
// Success uses all three up and makes a knife; failure wastes just the twine.
KNIFE_INGREDIENTS :: [3]Item{.Sharp_Stone, .Short_Stick, .Twine}

craft_knife :: proc(g: ^Game, p: ^Person) -> bool {
	hand_of: [3]int = -1 // where each ingredient was found: a hand index...
	ground_of: [3]int = -1 // ...or an index into ground_items
	used_hand: [MAX_HANDS]bool
	for item, n in KNIFE_INGREDIENTS {
		for h in 0 ..< p.hand_count {
			if p.hands[h] == item && !used_hand[h] {
				hand_of[n], used_hand[h] = h, true
				break
			}
		}
		if hand_of[n] >= 0 {continue}
		for it, i in g.ground_items {
			if it.x != p.x || it.y != p.y || it.item != item {continue}
			taken := false
			for other in ground_of {taken ||= other == i}
			if !taken {
				ground_of[n] = i
				break
			}
		}
		if ground_of[n] < 0 {return false}
	}
	// Work out what is spent: everything on success, only the twine (the last ingredient) on failure.
	success := skill_succeeds(p.crafting)
	first := 0 if success else 2
	remove_ground: [3]int = -1
	for n in first ..< 3 {
		if hand_of[n] >= 0 {p.hands[hand_of[n]] = .None}
		remove_ground[n] = ground_of[n]
	}
	for i := len(g.ground_items) - 1; i >= 0; i -= 1 { // highest index first keeps the others valid
		for r in remove_ground {
			if r == i {
				unordered_remove(&g.ground_items, i)
				break
			}
		}
	}
	if !success {return true}
	if hand := free_hand(p^); hand >= 0 {
		p.hands[hand] = .Knife
	} else {
		append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = .Knife, dropped_hours = g.clock.hours})
	}
	return true
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
		for h in 0 ..< p.hand_count {
			if p.hands[h] != .Food && p.hands[h] != .None {return drop_item(g, p, h)}
		}
	}
	if held_count(p^) > 0 && rand.float32() < DROP_CHANCE {
		for h in 0 ..< p.hand_count {
			if p.hands[h] != .None {return drop_item(g, p, h)}
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
	if counts[.Twine] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d twine", sep(&b), counts[.Twine])}
	if counts[.Food] > 0 && room(&b) {fmt.sbprintf(&b, "%s%d food (%.0f%% fresh)", sep(&b), counts[.Food], 100 * fresh / f32(counts[.Food]))}
	return strings.to_string(b)
}
