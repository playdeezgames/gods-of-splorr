package gods

import "core:math/rand"

Sex :: enum u8 {
	Male,
	Female,
}

SEX_NAMES := [Sex]string {
	.Male   = "male",
	.Female = "female",
}

Person :: struct {
	x, y:            int,
	sex:             Sex,
	melanin:         f32, // 0 (lightest) to 1 (darkest); sets how dark the sprite is
	next_move_hours: f64, // game clock time of the next step
}

// Everyone is a shade of brown: melanin runs from light tan (0) to deep brown (1).
SKIN_LIGHTEST :: [3]f32{0.96, 0.78, 0.60}
SKIN_DARKEST :: [3]f32{0.42, 0.24, 0.12}

skin_color :: proc(melanin: f32) -> [3]f32 {
	m := clamp(melanin, 0, 1)
	return SKIN_LIGHTEST + (SKIN_DARKEST - SKIN_LIGHTEST) * m
}

// Average of two draws, so most people land mid-range with the extremes rarer.
random_melanin :: proc() -> f32 {
	return (rand.float32() + rand.float32()) / 2
}

// Average game time between steps; each wait is 0.5x to 1.5x this.
PERSON_STEP_HOURS :: 10.0 / 60.0

// People only walk on grass.
walkable :: proc(t: Terrain) -> bool {
	return t == .Grass
}

person_at :: proc(g: ^Game, x, y: int) -> int {
	for p, i in g.people {
		if p.x == x && p.y == y {return i}
	}
	return -1
}

can_enter :: proc(g: ^Game, x, y: int) -> bool {
	return in_bounds(g, x, y) && walkable(terrain_at(g, x, y)) && person_at(g, x, y) < 0
}

next_step_time :: proc(from: f64) -> f64 {
	return from + PERSON_STEP_HOURS * (0.5 + rand.float64())
}

// Put a person on a random free grass cell. Returns false if there is none.
spawn_person :: proc(g: ^Game, sex: Sex) -> bool {
	for _ in 0 ..< 10000 {
		x, y := rand.int_max(g.size), rand.int_max(g.size)
		if can_enter(g, x, y) {
			append(&g.people, Person{x = x, y = y, sex = sex, melanin = random_melanin(), next_move_hours = next_step_time(g.clock.hours)})
			return true
		}
	}
	return false
}

DIRS := [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

update_people :: proc(g: ^Game) {
	for &p in g.people {
		for g.clock.hours >= p.next_move_hours {
			d := DIRS[rand.int_max(len(DIRS))]
			if can_enter(g, p.x + d.x, p.y + d.y) {
				p.x += d.x
				p.y += d.y
			}
			p.next_move_hours = next_step_time(p.next_move_hours)
		}
	}
}
