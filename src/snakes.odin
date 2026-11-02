package gods

import "core:math/rand"

// A poisonous snake hunts the nearest person it can sense and bites; the poison drains health over time.
Snake :: struct {
	x, y:            int,
	dodge:           f32, // 0 to 100: how well it avoids a thrown or thrust spear
	born_hours:      f64,
	next_move_hours: f64,
}

SNAKE_LIFE_HOURS :: 72.0 // a summoned snake slithers off after this long
SNAKE_STEP_HOURS :: PERSON_STEP_HOURS
SNAKE_SENSE :: 6 // how far (in cells, by distance along both axes) it notices people
SNAKE_BITE_CHANCE :: 0.6
SNAKE_BITE_COOLDOWN_HOURS :: 1.0

POISON_PER_HOUR :: 5.0
POISON_HOURS_PER_BITE :: 10.0 // one bite costs 50 health if left to run
MAX_POISON_HOURS :: 30.0

snake_at :: proc(g: ^Game, x, y: int) -> int {
	for s, i in g.snakes {
		if s.x == x && s.y == y {return i}
	}
	return -1
}

// Put a snake on (x, y) if a person could stand there.
spawn_snake :: proc(g: ^Game, x, y: int) -> bool {
	if !can_enter(g, x, y) {return false}
	append(&g.snakes, Snake{x = x, y = y, dodge = random_skill(), born_hours = g.clock.hours, next_move_hours = g.clock.hours + SNAKE_STEP_HOURS})
	return true
}

PERSON_FEAR :: 3 // people run from a snake this close (distance along both axes)

// Step away from the nearest snake if one is close. A person with nowhere better to go stands
// still, so this is true whenever a snake is near and the person should not do anything else.
flee_snake :: proc(g: ^Game, p: ^Person) -> bool {
	if holds(p^, .Spear) {return false} // the armed stand their ground; see hunt_snake
	nearest, nearest_dist := -1, PERSON_FEAR + 1
	for s, i in g.snakes {
		if dist := max(abs(s.x - p.x), abs(s.y - p.y)); dist < nearest_dist {nearest, nearest_dist = i, dist}
	}
	if nearest < 0 {return false}
	s := g.snakes[nearest]
	sq :: proc(n: int) -> int {return n * n}
	best_dist := sq(p.x - s.x) + sq(p.y - s.y) // only moves that get farther away count
	bx, by := p.x, p.y
	start := rand.int_max(len(DIRS))
	for k in 0 ..< len(DIRS) {
		d := DIRS[(start + k) % len(DIRS)]
		nx, ny := p.x + d.x, p.y + d.y
		if !can_enter(g, nx, ny) {continue}
		if dist := sq(nx - s.x) + sq(ny - s.y); dist > best_dist {best_dist, bx, by = dist, nx, ny}
	}
	p.x, p.y = bx, by
	return true
}

poison_person :: proc(p: ^Person) {
	p.poison_hours = min(p.poison_hours + POISON_HOURS_PER_BITE, MAX_POISON_HOURS)
}

// Index of a person on a cell next to (x, y), or -1.
adjacent_person :: proc(g: ^Game, x, y: int) -> int {
	for d in DIRS {
		if i := person_at(g, x + d.x, y + d.y); i >= 0 {return i}
	}
	return -1
}

// Index of the nearest person within sensing range, or -1.
nearest_person :: proc(g: ^Game, s: Snake) -> int {
	best, best_dist := -1, SNAKE_SENSE + 1
	for p, i in g.people {
		dist := max(abs(p.x - s.x), abs(p.y - s.y))
		if dist < best_dist {best, best_dist = i, dist}
	}
	return best
}

update_snakes :: proc(g: ^Game) {
	for &s in g.snakes {
		for g.clock.hours >= s.next_move_hours {
			s.next_move_hours += SNAKE_STEP_HOURS * (0.5 + rand.float64())
			if i := adjacent_person(g, s.x, s.y); i >= 0 {
				if rand.float32() < SNAKE_BITE_CHANCE {
					poison_person(&g.people[i])
					g.people[i].asleep = false // a bite wakes a sleeper
					s.next_move_hours += SNAKE_BITE_COOLDOWN_HOURS
				}
				continue
			}
			dx, dy := 0, 0
			if i := nearest_person(g, s); i >= 0 { // close in along the longer gap first
				p := g.people[i]
				ex, ey := p.x - s.x, p.y - s.y
				if abs(ex) >= abs(ey) {dx, dy = sign_of(ex), 0} else {dx, dy = 0, sign_of(ey)}
				if !can_enter(g, s.x + dx, s.y + dy) { // blocked: try the other axis
					dx, dy = int(sign_of(ex)) if dx == 0 else 0, int(sign_of(ey)) if dy == 0 else 0
				}
			} else {
				d := DIRS[rand.int_max(len(DIRS))]
				dx, dy = d.x, d.y
			}
			if (dx != 0 || dy != 0) && can_enter(g, s.x + dx, s.y + dy) {
				s.x += dx
				s.y += dy
			}
		}
	}
	for i := len(g.snakes) - 1; i >= 0; i -= 1 {
		if g.clock.hours - g.snakes[i].born_hours >= SNAKE_LIFE_HOURS {unordered_remove(&g.snakes, i)}
	}
}

sign_of :: proc(n: int) -> int {
	if n < 0 {return -1}
	if n > 0 {return 1}
	return 0
}

HUNT_RANGE :: 5 // a person with a spear goes after a snake this close
HIT_SPREAD :: 0.45 // chance of a hit moves this far either side of even as ranged and dodge pull apart
MIN_HIT_CHANCE :: 0.05
MAX_HIT_CHANCE :: 0.95

// Even odds when the hunter's ranged skill matches the snake's dodge; skill 100 against dodge 0 is
// a near-certain hit and the reverse a near-certain miss.
hit_chance :: proc(ranged, dodge: f32) -> f32 {
	return clamp(0.5 + HIT_SPREAD * (ranged - dodge) / MAX_SKILL, MIN_HIT_CHANCE, MAX_HIT_CHANCE)
}
SKIN_RANGE :: 6 // a person with a knife walks to a snake corpse this close

// Take a step toward (tx, ty), along the longer gap first, trying the other axis if blocked.
step_toward :: proc(g: ^Game, p: ^Person, tx, ty: int) -> bool {
	ex, ey := tx - p.x, ty - p.y
	dx, dy := 0, 0
	if abs(ex) >= abs(ey) {dx = sign_of(ex)} else {dy = sign_of(ey)}
	if !can_enter(g, p.x + dx, p.y + dy) {
		dx, dy = sign_of(ex) if dx == 0 else 0, sign_of(ey) if dy == 0 else 0
	}
	if (dx == 0 && dy == 0) || !can_enter(g, p.x + dx, p.y + dy) {return false}
	p.x += dx
	p.y += dy
	return true
}

// A person holding a spear closes in on the nearest snake and, once next to it, tries to kill it.
// The kill leaves a snake corpse where the snake was.
hunt_snake :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Spear) {return false}
	nearest, nearest_dist := -1, HUNT_RANGE + 1
	for s, i in g.snakes {
		if dist := max(abs(s.x - p.x), abs(s.y - p.y)); dist < nearest_dist {nearest, nearest_dist = i, dist}
	}
	if nearest < 0 {return false}
	s := g.snakes[nearest]
	if abs(s.x - p.x) + abs(s.y - p.y) == 1 {
		if rand.float32() < hit_chance(p.ranged, s.dodge) {kill_snake(g, nearest)}
		wear_tool(p, .Spear) // every thrust wears the spear, hit or miss
		return true
	}
	return step_toward(g, p, s.x, s.y)
}

kill_snake :: proc(g: ^Game, i: int) {
	s := g.snakes[i]
	append(&g.ground_items, Ground_Item{x = s.x, y = s.y, item = .Snake_Corpse, dropped_hours = g.clock.hours})
	unordered_remove(&g.snakes, i)
}

// A person holding a knife walks to a snake corpse and skins it: the corpse becomes snake meat
// and, if the cutting goes well, snake skin, both left on the ground.
skin_snake :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Knife) {return false}
	nearest, nearest_dist := -1, SKIN_RANGE + 1
	for it, i in g.ground_items {
		if it.item != .Snake_Corpse {continue}
		if dist := max(abs(it.x - p.x), abs(it.y - p.y)); dist < nearest_dist {nearest, nearest_dist = i, dist}
	}
	if nearest < 0 {return false}
	corpse := g.ground_items[nearest]
	if corpse.x != p.x || corpse.y != p.y {return step_toward(g, p, corpse.x, corpse.y)}
	unordered_remove(&g.ground_items, nearest)
	append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = .Snake_Meat, dropped_hours = g.clock.hours})
	if skill_succeeds(p.crafting) { // a clumsy cut ruins the skin
		append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = .Snake_Skin, dropped_hours = g.clock.hours})
	}
	wear_tool(p, .Knife)
	return true
}
