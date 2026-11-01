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

Item :: enum u8 {
	None,
	Food,
}

DEFAULT_HANDS :: 2
MAX_HANDS :: 4

Person :: struct {
	x, y:            int,
	sex:             Sex,
	melanin:         f32, // 0 (lightest) to 1 (darkest); sets how dark the sprite is
	health:          f32, // 0 means dead
	satiety:         f32, // drains when the stomach is empty; at 0 health drains
	stomach:         f32, // food waiting to be digested into satiety
	hand_count:      int, // how many hands, so how many items can be carried; one item per hand
	hands:           [MAX_HANDS]Item,
	next_move_hours: f64, // game clock time of the next step
}

MAX_HEALTH :: 100.0
MAX_SATIETY :: 100.0
MAX_STOMACH :: 100.0

// Per game hour. With these, a full stomach digests in 20 hours, an empty one
// loses satiety over about 2.8 days, and starving takes health down over about 4 days.
DIGEST_PER_HOUR :: 5.0 // stomach lost, and satiety gained, while stomach > 0
HUNGER_PER_HOUR :: 1.5 // satiety lost while stomach == 0
STARVE_PER_HOUR :: 1.0 // health lost while satiety == 0

START_STOMACH :: 30.0
START_SATIETY :: 50.0

Corpse :: struct {
	x, y:       int,
	sex:        Sex,
	melanin:    f32,
	died_hours: f64,
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
		x, y := rand.int_max(g.width), rand.int_max(g.height)
		if can_enter(g, x, y) {
			append(&g.people, Person{x = x, y = y, sex = sex, melanin = random_melanin(), health = MAX_HEALTH, satiety = START_SATIETY, stomach = START_STOMACH, hand_count = DEFAULT_HANDS, next_move_hours = next_step_time(g.clock.hours)})
			return true
		}
	}
	return false
}

DIRS := [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

update_people :: proc(g: ^Game) {
	for &p in g.people {
		for g.clock.hours >= p.next_move_hours {
			if !gather_adjacent(g, &p) {
				d := DIRS[rand.int_max(len(DIRS))]
				if can_enter(g, p.x + d.x, p.y + d.y) {
					p.x += d.x
					p.y += d.y
				}
			}
			p.next_move_hours = next_step_time(p.next_move_hours)
		}
	}
}

// Advance one person's body by dt game hours. Stomach feeds satiety, an empty stomach
// drains satiety, and empty satiety drains health. Each stage hands any leftover time
// to the next, so a step that crosses a boundary is exact at any speed.
step_vitals :: proc(p: ^Person, dt: f32) {
	left := dt
	if p.stomach > 0 {
		t := min(left, p.stomach / DIGEST_PER_HOUR)
		digested := min(DIGEST_PER_HOUR * t, p.stomach)
		p.stomach -= digested
		p.satiety = min(p.satiety + digested, MAX_SATIETY)
		left -= t
		if left > 0 {p.stomach = 0} // ran dry before the step ended
	}
	if left > 0 && p.stomach == 0 {
		t := min(left, p.satiety / HUNGER_PER_HOUR)
		p.satiety = max(p.satiety - HUNGER_PER_HOUR * t, 0)
		left -= t
		if left > 0 {p.satiety = 0}
	}
	if left > 0 && p.satiety == 0 {
		p.health = max(p.health - STARVE_PER_HOUR * left, 0)
	}
}

// Step everyone's vitals by the game time since the last call; the dead become corpses.
update_vitals :: proc(g: ^Game) {
	elapsed := f32(g.clock.hours - g.vitals_updated_hours)
	g.vitals_updated_hours = g.clock.hours
	if elapsed <= 0 {return}
	for i := len(g.people) - 1; i >= 0; i -= 1 {
		p := &g.people[i]
		step_vitals(p, elapsed)
		if p.health <= 0 {
			append(&g.corpses, Corpse{x = p.x, y = p.y, sex = p.sex, melanin = p.melanin, died_hours = g.clock.hours})
			ordered_remove(&g.people, i)
		}
	}
}

corpse_at :: proc(g: ^Game, x, y: int) -> int {
	for c, i in g.corpses {
		if c.x == x && c.y == y {return i}
	}
	return -1
}

free_hand :: proc(p: Person) -> int {
	for i in 0 ..< p.hand_count {
		if p.hands[i] == .None {return i}
	}
	return -1
}

held_count :: proc(p: Person) -> int {
	n := 0
	for i in 0 ..< p.hand_count {
		if p.hands[i] != .None {n += 1}
	}
	return n
}

// Pick one food item from the bush at (bx, by): the person must be orthogonally next
// to it, the bush must hold at least one whole food, and a hand must be free.
gather_food :: proc(g: ^Game, p: ^Person, bx, by: int) -> bool {
	if abs(p.x - bx) + abs(p.y - by) != 1 {return false}
	if !in_bounds(g, bx, by) || terrain_at(g, bx, by) != .Bush {return false}
	hand := free_hand(p^)
	if hand < 0 {return false}
	bush := &g.bushes[by * g.width + bx]
	if bush.food < 1 {return false}
	bush.food -= 1
	p.hands[hand] = .Food
	return true
}

// Gather from the first neighbouring bush that has food, if there is a free hand.
gather_adjacent :: proc(g: ^Game, p: ^Person) -> bool {
	for d in DIRS {
		if gather_food(g, p, p.x + d.x, p.y + d.y) {return true}
	}
	return false
}
