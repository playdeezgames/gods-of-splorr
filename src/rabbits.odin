package gods

import "core:math/rand"

// Rabbits graze the grass's fiber (and can strip it to dirt), starve without it, bolt from people who come close, and breed in warm weather. A hunter with a
// spear kills them for a corpse that a sharp stone skins into meat and, if the cut is clean, fur. Fur
// sewn with twine makes a coat, the tribe's only defence against the deep winter.
Rabbit :: struct {
	x, y:            int,
	dodge:           f32, // 0 to 100, set against the hunter's ranged skill like a snake's
	fullness:        f32, // hours of grazing left in it; at 0 it starves
	next_move_hours: f64,
}

RABBIT_STEP_HOURS :: PERSON_STEP_HOURS
RABBITS_PER_1024_CELLS :: 8 // how many a world starts with, per 32x32 of it
RABBIT_MAX_PER_1024_CELLS :: 24 // breeding stops at this many
RABBIT_FEAR :: 3 // a rabbit bolts from a person this close (distance along both axes)
RABBIT_BOLT_CHANCE :: 0.6 // and the rest of the time it freezes, which is when a hunter closes in
RABBIT_WANDER_CHANCE :: 0.3 // a rabbit with nobody near hops somewhere this often
RABBIT_BREED_PER_HOUR :: 1.0 / 120.0 // each rabbit has a kit about every 5 days in warm weather
RABBIT_BREED_ABOVE_C :: 8.0 // by the season (the daily mean), not the hour
RABBIT_ARRIVE_HOURS :: 48.0 // with almost none left, a rabbit wanders in from elsewhere this often
RABBIT_FEW :: 2
RABBIT_FULL_HOURS :: 48.0 // a full rabbit lasts two days without grazing
RABBIT_HUNGRY_HOURS :: 24.0 // under this it looks for grass, and is too hungry to breed
RABBIT_BITE :: 0.25 // fiber eaten in one nibble...
RABBIT_BITE_HOURS :: 12.0 // ...and how long it keeps the rabbit going

rabbit_at :: proc(g: ^Game, x, y: int) -> int {
	for r, i in g.rabbits {
		if r.x == x && r.y == y {return i}
	}
	return -1
}

rabbit_cap :: proc(g: ^Game, per_1024: int) -> int {
	return max(1, per_1024 * g.width * g.height / 1024)
}

// Put a rabbit on (x, y) if it is free grass.
spawn_rabbit :: proc(g: ^Game, x, y: int) -> bool {
	if !can_enter(g, x, y) || terrain_at(g, x, y) != .Grass {return false}
	append(&g.rabbits, Rabbit{x = x, y = y, dodge = random_skill(), fullness = RABBIT_FULL_HOURS, next_move_hours = g.clock.hours + RABBIT_STEP_HOURS})
	return true
}

// Put a rabbit on a random free grass cell.
spawn_rabbit_anywhere :: proc(g: ^Game) -> bool {
	for _ in 0 ..< 1000 {
		if spawn_rabbit(g, rand.int_max(g.width), rand.int_max(g.height)) {return true}
	}
	return false
}

populate_rabbits :: proc(g: ^Game) {
	for _ in 0 ..< rabbit_cap(g, RABBITS_PER_1024_CELLS) {spawn_rabbit_anywhere(g)}
	g.next_rabbit_hours = g.clock.hours + RABBIT_ARRIVE_HOURS
}

// The nearest person within RABBIT_FEAR, or -1.
rabbit_threat :: proc(g: ^Game, r: Rabbit) -> int {
	best, best_dist := -1, RABBIT_FEAR + 1
	for p, i in g.people {
		if dist := max(abs(p.x - r.x), abs(p.y - r.y)); dist < best_dist {best, best_dist = i, dist}
	}
	return best
}

update_rabbits :: proc(g: ^Game) {
	warm := mean_temperature_c(g.clock, g.cfg) > RABBIT_BREED_ABOVE_C
	cap := rabbit_cap(g, RABBIT_MAX_PER_1024_CELLS)
	for i := 0; i < len(g.rabbits); i += 1 { // kits are appended as we go, and move from their next turn
		for g.clock.hours >= g.rabbits[i].next_move_hours {
			r := &g.rabbits[i]
			step := RABBIT_STEP_HOURS * (0.5 + rand.float64())
			r.next_move_hours += step
			r.fullness -= f32(step)
			if r.fullness <= 0 {break} // starved; cleared away below
			rx, ry := r.x, r.y
			if warm && r.fullness > RABBIT_HUNGRY_HOURS && len(g.rabbits) < cap && rand.float64() < RABBIT_BREED_PER_HOUR * step {
				d := DIRS[rand.int_max(len(DIRS))]
				spawn_rabbit(g, rx + d.x, ry + d.y)
				r = &g.rabbits[i] // the append may have moved the array
			}
			if t := rabbit_threat(g, r^); t >= 0 {
				if rand.float32() < RABBIT_BOLT_CHANCE {hop_away(g, r, g.people[t].x, g.people[t].y)}
			} else if graze(g, r) {
			} else if r.fullness < RABBIT_HUNGRY_HOURS && hop_to_grass(g, r) {
			} else if rand.float32() < RABBIT_WANDER_CHANCE {
				d := DIRS[rand.int_max(len(DIRS))]
				if can_enter(g, r.x + d.x, r.y + d.y) {r.x += d.x; r.y += d.y}
			}
		}
	}
	for i := len(g.rabbits) - 1; i >= 0; i -= 1 { // the starved leave a corpse, which a hunter may still use
		r := g.rabbits[i]
		if r.fullness > 0 {continue}
		append(&g.ground_items, Ground_Item{x = r.x, y = r.y, item = .Rabbit_Corpse, dropped_hours = g.clock.hours})
		unordered_remove(&g.rabbits, i)
	}
	if len(g.rabbits) < RABBIT_FEW && g.clock.hours >= g.next_rabbit_hours {
		g.next_rabbit_hours = g.clock.hours + RABBIT_ARRIVE_HOURS
		spawn_rabbit_anywhere(g)
	}
}

// Nibble the fiber of the grass underfoot, if there is room for it.
graze :: proc(g: ^Game, r: ^Rabbit) -> bool {
	if r.fullness > RABBIT_FULL_HOURS - RABBIT_BITE_HOURS {return false}
	taken := take_fiber(g, r.x, r.y, RABBIT_BITE)
	if taken <= 0 {return false}
	r.fullness = min(r.fullness + RABBIT_BITE_HOURS * taken / RABBIT_BITE, RABBIT_FULL_HOURS)
	return true
}

// Hop to the neighbouring cell with the most fiber, if any has some.
hop_to_grass :: proc(g: ^Game, r: ^Rabbit) -> bool {
	best: f32 = 0
	bx, by := 0, 0
	for d in DIRS {
		if !can_enter(g, r.x + d.x, r.y + d.y) {continue}
		if f, ok := fiber_at(g, r.x + d.x, r.y + d.y); ok && f > best {best, bx, by = f, d.x, d.y}
	}
	if best <= 0 {return false}
	r.x += bx
	r.y += by
	return true
}

// Hop to the neighbouring cell farthest from (fx, fy), if any is farther than here.
hop_away :: proc(g: ^Game, r: ^Rabbit, fx, fy: int) {
	sq :: proc(n: int) -> int {return n * n}
	best := sq(r.x - fx) + sq(r.y - fy)
	bx, by := r.x, r.y
	start := rand.int_max(len(DIRS))
	for k in 0 ..< len(DIRS) {
		d := DIRS[(start + k) % len(DIRS)]
		nx, ny := r.x + d.x, r.y + d.y
		if !can_enter(g, nx, ny) {continue}
		if dist := sq(nx - fx) + sq(ny - fy); dist > best {best, bx, by = dist, nx, ny}
	}
	r.x, r.y = bx, by
}

HUNT_RABBIT_RANGE :: 12 // a hunter goes after a rabbit this close

// A person holding a spear closes in on the nearest rabbit and, once beside it, thrusts. A kill leaves
// a rabbit corpse where it was.
hunt_rabbit :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Spear) {return false}
	nearest, nearest_dist := -1, HUNT_RABBIT_RANGE + 1
	for r, i in g.rabbits {
		if dist := max(abs(r.x - p.x), abs(r.y - p.y)); dist < nearest_dist {nearest, nearest_dist = i, dist}
	}
	if nearest < 0 {return false}
	r := g.rabbits[nearest]
	if abs(r.x - p.x) + abs(r.y - p.y) == 1 {
		if rand.float32() < hit_chance(p.ranged, r.dodge) {
			append(&g.ground_items, Ground_Item{x = r.x, y = r.y, item = .Rabbit_Corpse, dropped_hours = g.clock.hours})
			unordered_remove(&g.rabbits, nearest)
		}
		wear_tool(p, .Spear)
		return true
	}
	return step_toward(g, p, r.x, r.y)
}

// With a sharp stone in hand, skin a rabbit corpse within reach: the corpse becomes rabbit meat and, if
// the cut is clean, fur, both left on the cell where the corpse lay. The stone wears.
skin_rabbit :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Sharp_Stone) {return false}
	x, y: int
	found := false
	for i := len(g.ground_items) - 1; i >= 0; i -= 1 {
		it := g.ground_items[i]
		if it.item != .Rabbit_Corpse || !in_reach(it.x, it.y, p.x, p.y) {continue}
		x, y, found = it.x, it.y, true
		unordered_remove(&g.ground_items, i)
		break
	}
	if !found {
		for h in 0 ..< carry_slots(p^) { // or one carried in
			if p.hands[h] == .Rabbit_Corpse {p.hands[h] = .None; x, y, found = p.x, p.y, true; break}
		}
	}
	if !found {return false}
	append(&g.ground_items, Ground_Item{x = x, y = y, item = .Rabbit_Meat, dropped_hours = g.clock.hours})
	if skill_succeeds(p.crafting) { // a clumsy cut ruins the fur
		append(&g.ground_items, Ground_Item{x = x, y = y, item = .Fur, dropped_hours = g.clock.hours})
	}
	wear_tool(p, .Sharp_Stone)
	return true
}

// Fur sewn together with twine makes a coat. A clumsy seam wastes the twine.
COAT_FUR :: 3
COAT_WARMTH_C :: 15.0 // degrees a coat takes off the cold (it does nothing for heat: it is opened up)

craft_coat :: proc(g: ^Game, p: ^Person) -> bool {
	ingredients: [COAT_FUR + 1]Item
	for &item in ingredients {item = .Fur}
	ingredients[COAT_FUR] = .Twine
	return craft_recipe(g, p, ingredients[:], .Fur_Coat)
}

// A person without a coat puts on one they hold or that lies within reach, and as the year cools goes
// to fetch one lying anywhere.
put_on_coat :: proc(g: ^Game, p: ^Person) -> bool {
	if p.coat {return false}
	for h in 0 ..< carry_slots(p^) {
		if p.hands[h] == .Fur_Coat {
			p.hands[h], p.coat = .None, true
			return true
		}
	}
	for it, i in g.ground_items {
		if it.item == .Fur_Coat && in_reach(it.x, it.y, p.x, p.y) {
			unordered_remove(&g.ground_items, i)
			p.coat = true
			return true
		}
	}
	if !cooling_season(g.clock, g.cfg) && temperature_c(g.clock, g.cfg) >= COLD_BELOW_C {return false}
	x, y, found := nearest_ground(g, p^, .Fur_Coat)
	if !found {return false}
	return step_toward(g, p, x, y)
}

// Whoever in the tribe has one of an item, or where one lies anywhere.
tribe_has :: proc(g: ^Game, item: Item) -> int {
	n := 0
	for p in g.people {
		for h in 0 ..< carry_slots(p) {
			if p.hands[h] == item {n += 1}
		}
	}
	for it in g.ground_items {
		if it.item == item {n += 1}
	}
	return n
}

// People still without a coat, less the coats lying about or carried for them.
coats_wanted :: proc(g: ^Game) -> int {
	n := 0
	for p in g.people {
		if !p.coat {n += 1}
	}
	return n - tribe_has(g, .Fur_Coat)
}
