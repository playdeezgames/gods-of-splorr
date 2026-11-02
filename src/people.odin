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
	Stone,
	Fiber,
	Stick,
	Twine,
	Sharp_Stone,
	Short_Stick,
	Knife,
	Spear,
	Snake_Corpse,
	Snake_Meat,
	Snake_Skin,
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
	sleep_hours:     f32, // hours of sleep needed per day, 4 to 12
	energy:          f32, // drains while awake; at 0 the person falls asleep until it is full
	asleep:          bool,
	foraging:        f32, // skill 0 to 100: chance of success when gathering food, fiber, sticks, stone
	crafting:        f32, // skill 0 to 100: chance of success when crafting
	ranged:          f32, // skill 0 to 100: aim with a spear, set against a snake's dodge
	hand_count:      int, // how many hands, so how many items can be carried; one item per hand
	hands:           [MAX_HANDS]Item,
	wear:            [MAX_HANDS]int, // uses a held tool has been through; reset when a new one is made into that hand
	age_years:       f32, // grows with game time; the calendar decides how long a year is
	lifespan_years:  f32, // dies of old age on reaching this; 0 means never
	poison_hours:    f32, // hours of poison left; health drains while it lasts
	next_move_hours: f64, // game clock time of the next step
}

MAX_HEALTH :: 100.0
MAX_SATIETY :: 100.0
MAX_STOMACH :: 100.0
MAX_ENERGY :: 100.0

MAX_SKILL :: 100.0
SKILL_MIN_SUCCESS :: 0.25 // an unskilled person still succeeds this often; a master always does

// Everyone starts as an adult and lives to a lifespan of their own: most near 65, a few much shorter
// or longer (a triangular spread like the sleep need).
START_AGE_MIN :: 16.0
START_AGE_MAX :: 40.0
LIFESPAN_MIN :: 50.0
LIFESPAN_MAX :: 80.0

random_lifespan :: proc() -> f32 {
	return LIFESPAN_MIN + (rand.float32() + rand.float32()) / 2 * (LIFESPAN_MAX - LIFESPAN_MIN)
}

// Age a person by dt game hours; true once they have reached their lifespan.
step_age :: proc(p: ^Person, dt, hours_per_year: f32) -> bool {
	p.age_years += dt / hours_per_year
	return p.lifespan_years > 0 && p.age_years >= p.lifespan_years
}

// Skills spread 0..100 around 50 (triangular), like the sleep need.
random_skill :: proc() -> f32 {
	return (rand.float32() + rand.float32()) / 2 * MAX_SKILL
}

// Roll against a skill: chance of success runs from 25% at skill 0 to 100% at skill 100.
skill_succeeds :: proc(skill: f32) -> bool {
	chance := SKILL_MIN_SUCCESS + (1 - SKILL_MIN_SUCCESS) * clamp(skill, 0, MAX_SKILL) / MAX_SKILL
	return rand.float32() < chance
}

// Each person needs a certain amount of sleep per 24-hour day, from 4 to 12 hours and 8 on
// average. They stay awake for the rest of the day: energy drains over (24 - need) awake
// hours, which puts them to sleep, and a full night of `sleep_hours` wakes them.
MIN_SLEEP_HOURS :: 4.0
DEFAULT_SLEEP_HOURS :: 8.0
MAX_SLEEP_HOURS :: 12.0

// Triangular spread over 4..12 centred on 8: most people are near average, extremes are rare.
random_sleep_hours :: proc() -> f32 {
	return DEFAULT_SLEEP_HOURS + (rand.float32() + rand.float32() - 1) * (MAX_SLEEP_HOURS - DEFAULT_SLEEP_HOURS)
}

energy_drain_per_hour :: proc(p: Person) -> f32 {
	return MAX_ENERGY / (HOURS_PER_DAY - clamp(p.sleep_hours, MIN_SLEEP_HOURS, MAX_SLEEP_HOURS))
}

energy_recover_per_hour :: proc(p: Person) -> f32 {
	return MAX_ENERGY / clamp(p.sleep_hours, MIN_SLEEP_HOURS, MAX_SLEEP_HOURS)
}

// Per game hour. With these, a full stomach digests in 20 hours, an empty one
// loses satiety over about 2.8 days, and starving takes health down over about 4 days.
DIGEST_PER_HOUR :: 5.0 // stomach lost, and satiety gained, while stomach > 0
HUNGER_PER_HOUR :: 1.5 // satiety lost while stomach == 0
STARVE_PER_HOUR :: 1.0 // health lost while satiety == 0

FOOD_STOMACH :: 20.0 // stomach gained from eating one food item
EAT_BELOW_STOMACH :: 25.0 // a person with food in hand eats once their stomach drops under this

START_STOMACH :: 30.0
START_SATIETY :: 50.0

Corpse :: struct {
	x, y:       int,
	sex:        Sex,
	melanin:    f32,
	died_hours: f64,
	skeleton:   bool, // once the flesh has rotted away only bones are left
	bones_hours: f64, // game clock time it became a skeleton
}

// A corpse rots to a skeleton after this many game hours; the skeleton then lasts much longer
// before it rots away too.
CORPSE_ROT_HOURS :: 120.0 // 5 days
SKELETON_ROT_HOURS :: 1200.0 // 50 days

// 0 when fresh, 1 when this stage (corpse or skeleton) has run its course.
corpse_rot_fraction :: proc(g: ^Game, c: Corpse) -> f32 {
	if c.skeleton {return clamp(f32((g.clock.hours - c.bones_hours) / SKELETON_ROT_HOURS), 0, 1)}
	return clamp(f32((g.clock.hours - c.died_hours) / CORPSE_ROT_HOURS), 0, 1)
}

// Corpses become skeletons, and skeletons crumble away.
update_corpses :: proc(g: ^Game) {
	for i := len(g.corpses) - 1; i >= 0; i -= 1 {
		c := &g.corpses[i]
		if !c.skeleton && g.clock.hours - c.died_hours >= CORPSE_ROT_HOURS {
			c.skeleton = true
			c.bones_hours = c.died_hours + CORPSE_ROT_HOURS
		}
		if c.skeleton && g.clock.hours - c.bones_hours >= SKELETON_ROT_HOURS {
			ordered_remove(&g.corpses, i)
		}
	}
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

// People walk on grass, stone fields and dirt.
walkable :: proc(t: Terrain) -> bool {
	return t == .Grass || t == .Stone_Field || t == .Dirt
}

person_at :: proc(g: ^Game, x, y: int) -> int {
	for p, i in g.people {
		if p.x == x && p.y == y {return i}
	}
	return -1
}

can_enter :: proc(g: ^Game, x, y: int) -> bool {
	return in_bounds(g, x, y) && walkable(terrain_at(g, x, y)) && person_at(g, x, y) < 0 && snake_at(g, x, y) < 0
}

next_step_time :: proc(from: f64) -> f64 {
	return from + PERSON_STEP_HOURS * (0.5 + rand.float64())
}

// Put a person on a random free grass cell. Returns false if there is none.
spawn_person :: proc(g: ^Game, sex: Sex) -> bool {
	for _ in 0 ..< 10000 {
		x, y := rand.int_max(g.width), rand.int_max(g.height)
		if can_enter(g, x, y) {
			append(&g.people, Person{x = x, y = y, sex = sex, melanin = random_melanin(), health = MAX_HEALTH, satiety = START_SATIETY, stomach = START_STOMACH, energy = MAX_ENERGY, sleep_hours = random_sleep_hours(), foraging = random_skill(), crafting = random_skill(), ranged = random_skill(), age_years = START_AGE_MIN + rand.float32() * (START_AGE_MAX - START_AGE_MIN), lifespan_years = random_lifespan(), hand_count = DEFAULT_HANDS, next_move_hours = next_step_time(g.clock.hours)})
			return true
		}
	}
	return false
}

DIRS := [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

update_people :: proc(g: ^Game) {
	for &p in g.people {
		for g.clock.hours >= p.next_move_hours {
			if p.asleep { // sleepers do nothing
				p.next_move_hours = next_step_time(p.next_move_hours)
				continue
			}
			if !hunt_snake(g, &p) && !flee_snake(g, &p) && !eat_when_hungry(&p) && !eat_from_ground(g, &p) && !skin_snake(g, &p) && !craft_twine(&p) && !craft_sharp_stone(&p) && !craft_spear(g, &p) && !craft_short_sticks(g, &p) && !craft_knife(g, &p) && !gather_adjacent(g, &p) && !gather_stick_adjacent(g, &p) && !gather_stone_here(g, &p) && !gather_fiber_here(g, &p) && !drop_something(g, &p) {
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
	step_energy(p, dt)
	if p.poison_hours > 0 { // poison runs its course whatever else is going on
		t := min(dt, p.poison_hours)
		p.health = max(p.health - POISON_PER_HOUR * t, 0)
		p.poison_hours -= t
	}
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

// Awake people lose energy and fall asleep at 0; sleepers regain it and wake when full.
// Like the nutrition chain, a step that crosses a boundary hands its leftover time on.
step_energy :: proc(p: ^Person, dt: f32) {
	left := dt
	for left > 0 {
		if p.asleep {
			t := min(left, (MAX_ENERGY - p.energy) / energy_recover_per_hour(p^))
			p.energy = min(p.energy + energy_recover_per_hour(p^) * t, MAX_ENERGY)
			left -= t
			if left <= 0 {break}
			p.energy = MAX_ENERGY
			p.asleep = false
		} else {
			t := min(left, p.energy / energy_drain_per_hour(p^))
			p.energy = max(p.energy - energy_drain_per_hour(p^) * t, 0)
			left -= t
			if left <= 0 {break}
			p.energy = 0
			p.asleep = true
		}
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
		died_of_age := step_age(p, elapsed, f32(hours_per_year(g.cfg)))
		if p.health <= 0 || died_of_age {kill_person(g, i)}
	}
}

// Remove person i from the living and leave a corpse where they stood.
kill_person :: proc(g: ^Game, i: int) {
	p := g.people[i]
	append(&g.corpses, Corpse{x = p.x, y = p.y, sex = p.sex, melanin = p.melanin, died_hours = g.clock.hours})
	ordered_remove(&g.people, i)
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
	if !skill_succeeds(p.foraging) {return true} // fumbled it; nothing taken
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

// Eat one food item from a hand: it empties the hand and fills the stomach (capped).
eat_food :: proc(p: ^Person) -> bool {
	if p.stomach >= MAX_STOMACH {return false}
	for i in 0 ..< p.hand_count {
		if p.hands[i] == .Food {
			p.hands[i] = .None
			p.stomach = min(p.stomach + FOOD_STOMACH, MAX_STOMACH)
			return true
		}
	}
	return false
}

eat_when_hungry :: proc(p: ^Person) -> bool {
	return p.stomach < EAT_BELOW_STOMACH && eat_food(p)
}
