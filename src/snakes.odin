package gods

import "core:math/rand"

// A poisonous snake hunts the nearest person it can sense and bites; the poison drains health over time.
Snake :: struct {
	x, y:            int,
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
	append(&g.snakes, Snake{x = x, y = y, born_hours = g.clock.hours, next_move_hours = g.clock.hours + SNAKE_STEP_HOURS})
	return true
}

PERSON_FEAR :: 3 // people run from a snake this close (distance along both axes)

// Step away from the nearest snake if one is close. A person with nowhere better to go stands
// still, so this is true whenever a snake is near and the person should not do anything else.
flee_snake :: proc(g: ^Game, p: ^Person) -> bool {
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
					s.next_move_hours += SNAKE_BITE_COOLDOWN_HOURS
				}
				continue
			}
			dx, dy := 0, 0
			if i := nearest_person(g, s); i >= 0 { // close in along the longer gap first
				p := g.people[i]
				ex, ey := p.x - s.x, p.y - s.y
				if abs(ex) >= abs(ey) {dx, dy = int(sign_of(ex)), 0} else {dx, dy = 0, int(sign_of(ey))}
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
