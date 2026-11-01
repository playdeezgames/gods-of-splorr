package gods

import "core:fmt"
import "core:math/rand"
import "core:strings"

// Things people drop sit on the ground where they fell. Stone keeps; food spoils.
Ground_Item :: struct {
	x, y:          int,
	item:          Item,
	dropped_hours: f64, // game clock time it hit the ground
}

FOOD_SPOIL_HOURS :: 24.0 // dropped food loses freshness steadily and rots away after this long
DROP_CHANCE :: 0.02 // chance per action that a person carrying something simply sets it down

// 1 when just dropped, 0 when it rots away.
ground_food_freshness :: proc(g: ^Game, it: Ground_Item) -> f32 {
	return clamp(1 - f32((g.clock.hours - it.dropped_hours) / FOOD_SPOIL_HOURS), 0, 1)
}

// Put whatever is in hand `hand` on the ground at the person's feet.
drop_item :: proc(g: ^Game, p: ^Person, hand: int) -> bool {
	if hand < 0 || hand >= p.hand_count || p.hands[hand] == .None {return false}
	append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = p.hands[hand], dropped_hours = g.clock.hours})
	p.hands[hand] = .None
	return true
}

// Remove dropped food that has had time to rot away.
update_ground_items :: proc(g: ^Game) {
	for i := len(g.ground_items) - 1; i >= 0; i -= 1 {
		it := g.ground_items[i]
		if it.item == .Food && ground_food_freshness(g, it) <= 0 {unordered_remove(&g.ground_items, i)}
	}
}

// Take one stone from the stone field the person is standing on, if a hand is free.
gather_stone_here :: proc(g: ^Game, p: ^Person) -> bool {
	hand := free_hand(p^)
	if hand < 0 {return false}
	if take_stone(g, p.x, p.y, 1) < 1 {return false}
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
	p.hands[first] = .Twine
	p.hands[second] = .None
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
	if take_fiber(g, p.x, p.y) <= 0 {return false}
	p.hands[hand] = .Fiber
	return true
}

// Hungry people eat food lying on their own cell; spoiled food fills the stomach less.
eat_from_ground :: proc(g: ^Game, p: ^Person) -> bool {
	if p.stomach >= EAT_BELOW_STOMACH {return false}
	for it, i in g.ground_items {
		if it.x != p.x || it.y != p.y || it.item != .Food {continue}
		p.stomach = min(p.stomach + FOOD_STOMACH * ground_food_freshness(g, it), MAX_STOMACH)
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
		if it.item == .Food {fresh += ground_food_freshness(g, it)}
	}
	b := strings.builder_from_bytes(buf)
	sep :: proc(b: ^strings.Builder) -> string {return ", " if strings.builder_len(b^) > 0 else ""}
	if counts[.Stone] > 0 {fmt.sbprintf(&b, "%s%d stone", sep(&b), counts[.Stone])}
	if counts[.Fiber] > 0 {fmt.sbprintf(&b, "%s%d fiber", sep(&b), counts[.Fiber])}
	if counts[.Stick] > 0 {fmt.sbprintf(&b, "%s%d stick", sep(&b), counts[.Stick])}
	if counts[.Twine] > 0 {fmt.sbprintf(&b, "%s%d twine", sep(&b), counts[.Twine])}
	if counts[.Food] > 0 {fmt.sbprintf(&b, "%s%d food (%.0f%% fresh)", sep(&b), counts[.Food], 100 * fresh / f32(counts[.Food]))}
	return strings.to_string(b)
}
