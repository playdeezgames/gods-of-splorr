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
	Spear,
	Snake_Corpse,
	Snake_Meat,
	Snake_Skin,
	Reed,
	Basket,
	Bow,
	Stake,
	Fire_Drill,
	Net,
	Fish,
	Fish_Filet,
	Cooking_Stick,
	Cooked_Snake_Meat, // only ever on a cooking stick
	Cooked_Fish_Filet,
	Rope, // two twine
	Belt, // two rope; worn rather than held, and adds BELT_SLOTS places to carry things
	Rabbit_Corpse,
	Rabbit_Meat,
	Cooked_Rabbit_Meat,
	Fur, // skinned from a rabbit
	Fur_Coat, // fur sewn with twine; worn rather than held, and keeps the cold off
	Drying, // food set out on the ground to dry, with what it is in Ground_Item.loaded; see preserve.odin
	Dried_Berries, // keep for ever
	Dried_Meat,
	Drying_Rack, // sticks lashed into a frame that food is hung on to dry
	Fire_Pit, // never held or dropped: it is built on the ground, and is here so people can be credited with making one
}

DEFAULT_HANDS :: 2
MAX_HANDS :: 4
BELT_SLOTS :: 4 // extra places to carry things while a belt is worn
BASKET_SLOTS :: 3 // places inside a basket, which itself takes one place
MAX_SLOTS :: MAX_HANDS + BELT_SLOTS

Person :: struct {
	id:              int, // never reused within a world; 0 means no one
	doing:           Activity, // what they did on their last turn
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
	craft_levels:    [Item]int, // successes at crafting each item; each adds a point to the next check for that item
	ranged:          f32,
	fishing:         f32, // skill 0 to 100, with fish_level added to the check as crafting levels are
	cooking:         f32, // skill 0 to 100, with cook_level added to the check
	fish_level:      int, // fish caught so far
	cook_level:      int, // meals cooked so far
 // skill 0 to 100: aim with a spear, set against a snake's dodge
	role:            Role, // specialty in the tribe; see roles.odin
	hand_count:      int, // how many hands; one item per hand, and a worn belt adds BELT_SLOTS more places
	belt:            bool, // wearing a belt
	coat:            bool, // wearing a fur coat; see rabbits.odin
	hands:           [MAX_SLOTS]Item, // the first hand_count are hands; the rest hang from the belt, usable only while one is worn
	packs:           [MAX_SLOTS][BASKET_SLOTS]Item, // what is inside the basket in that place, if one is held there; it keeps
	loaded:          [MAX_SLOTS]Item, // what is on the cooking stick in that place, if one is held there
	wear:            [MAX_SLOTS]int, // uses a held tool has been through; reset when a new one is made into that hand
	dopamine:        f32, // 0 to MAX_DOPAMINE: mood; crafting raises it, time bleeds it off; see mood.odin
	site_x, site_y:  int, // where a firepit's pile of materials is being gathered
	has_site:        bool,
	age_years:       f32, // grows with game time; the calendar decides how long a year is
	lifespan_years:  f32, // dies of old age on reaching this; 0 means never
	poison_hours:    f32, // hours of poison left; health drains while it lasts
	chill, heat:     f32, // 0 to MAX_THERMAL: build up in cold or hot weather; see thermal.odin
	hypothermia:     f32, // 0 to MAX_THERMAL: while above 0, health drains and rest needs rise
	heat_stress:     f32, // likewise for heat
	harm:            [Death_Cause]f32, // health lost to each cause so far; the biggest one is blamed at death
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
	return MAX_ENERGY / (HOURS_PER_DAY - clamp(p.sleep_hours, MIN_SLEEP_HOURS, MAX_SLEEP_HOURS)) * (1 + affliction(p))
}

energy_recover_per_hour :: proc(p: Person) -> f32 {
	return MAX_ENERGY / clamp(p.sleep_hours, MIN_SLEEP_HOURS, MAX_SLEEP_HOURS) / (1 + affliction(p))
}

// Per game hour. With these, a full stomach digests in 20 hours, an empty one
// loses satiety over about 2.8 days, and starving takes health down over about 4 days.
DIGEST_PER_HOUR :: 5.0 // stomach lost, and satiety gained, while stomach > 0
HUNGER_PER_HOUR :: 1.5 // satiety lost while stomach == 0
STARVE_PER_HOUR :: 1.0 // health lost while satiety == 0

FOOD_STOMACH :: 20.0 // stomach gained from eating one food item
EAT_BELOW_SATIETY :: 85.0 // a person with a nearly full belly of satiety does not eat: it would only be wasted
EAT_BELOW_STOMACH :: 25.0 // a person with food in hand eats once their stomach drops under this

START_STOMACH :: 30.0
START_SATIETY :: 50.0

Death_Cause :: enum u8 {
	Starvation,
	Poison,
	Cold,
	Heat,
	Old_Age,
	Smitten, // struck down by the god
}

DEATH_CAUSE_NAMES := [Death_Cause]string {
	.Starvation = "starvation",
	.Poison = "snake poison",
	.Cold = "hypothermia",
	.Heat = "heat stress",
	.Old_Age = "old age",
	.Smitten = "smiting",
}

Corpse :: struct {
	cause:      Death_Cause,
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
	return in_bounds(g, x, y) && walkable(terrain_at(g, x, y)) && person_at(g, x, y) < 0 && snake_at(g, x, y) < 0 && rabbit_at(g, x, y) < 0
}

next_step_time :: proc(from: f64) -> f64 {
	return from + PERSON_STEP_HOURS * (0.5 + rand.float64())
}

// Put a person on a random free grass cell. Returns false if there is none.
spawn_person :: proc(g: ^Game, sex: Sex) -> bool {
	for _ in 0 ..< 10000 {
		x, y := rand.int_max(g.width), rand.int_max(g.height)
		if can_enter(g, x, y) {
			g.next_person_id += 1
			append(&g.people, Person{id = g.next_person_id, x = x, y = y, sex = sex, melanin = random_melanin(), health = MAX_HEALTH, satiety = START_SATIETY, stomach = START_STOMACH, energy = MAX_ENERGY, sleep_hours = random_sleep_hours(), foraging = random_skill(), crafting = random_skill(), ranged = random_skill(), fishing = random_skill(), cooking = random_skill(), dopamine = START_DOPAMINE, age_years = START_AGE_MIN + rand.float32() * (START_AGE_MAX - START_AGE_MIN), lifespan_years = random_lifespan(), hand_count = DEFAULT_HANDS, next_move_hours = next_step_time(g.clock.hours)})
			return true
		}
	}
	return false
}

DIRS := [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

// What a person is up to, for the status panel and for following someone around.
Activity :: enum {
	Idle,
	Sleeping,
	Hunting_Snake,
	Fleeing_Snake,
	Eating,
	Skinning_Snake,
	Cooking,
	Tending_Fire,
	Cutting_Fish,
	Skewering_Meat,
	Fishing,
	Looking_For_Food,
	Working_On_A_Goal,
	Building_A_Fire,
	Crafting,
	Picking_Berries,
	Gathering,
	Setting_Something_Down,
	Wandering,
	Warming_Up,
	Hunting_Rabbit,
	Skinning_Rabbit,
	Putting_On_A_Coat,
	Storing_Food,
}

ACTIVITY_NAMES := [Activity]string {
	.Idle = "Nothing yet",
	.Sleeping = "Sleeping",
	.Hunting_Snake = "Hunting a snake",
	.Fleeing_Snake = "Running from a snake",
	.Eating = "Eating",
	.Skinning_Snake = "Skinning a snake",
	.Cooking = "Cooking a meal",
	.Tending_Fire = "Tending a fire",
	.Cutting_Fish = "Cutting up a fish",
	.Skewering_Meat = "Putting meat on a stick",
	.Fishing = "Fishing",
	.Looking_For_Food = "Looking for food",
	.Working_On_A_Goal = "Working toward something",
	.Building_A_Fire = "Building a fire",
	.Crafting = "Crafting",
	.Picking_Berries = "Picking berries",
	.Gathering = "Gathering materials",
	.Setting_Something_Down = "Setting something down",
	.Wandering = "Wandering",
	.Warming_Up = "Warming up at the fire",
	.Hunting_Rabbit = "Hunting rabbits",
	.Skinning_Rabbit = "Skinning a rabbit",
	.Putting_On_A_Coat = "Putting on a coat",
	.Storing_Food = "Laying in food for the winter",
}

ROLE_DOING := [Role]Activity {
	.Generalist = .Wandering,
	.Forager    = .Gathering,
	.Toolmaker  = .Crafting,
	.Fisher     = .Fishing,
	.Firekeeper = .Tending_Fire,
	.Hunter     = .Hunting_Rabbit,
}

update_people :: proc(g: ^Game) {
	for &p in g.people {
		for g.clock.hours >= p.next_move_hours {
			take_turn(g, &p)
			p.next_move_hours = next_step_time(p.next_move_hours)
		}
	}
}

// One step of a person's life: the first thing that applies is what they do, in this order.
take_turn :: proc(g: ^Game, p: ^Person) {
	if p.asleep { // sleepers do nothing
		p.doing = .Sleeping
		return
	}
	switch {
	case hunt_snake(g, p): p.doing = .Hunting_Snake
	case flee_snake(g, p): p.doing = .Fleeing_Snake
	case avoid_fire_heat(g, p): p.doing = .Wandering
	case eat_when_hungry(p), eat_cooked(p), eat_from_ground(g, p): p.doing = .Eating
	case put_on_coat(g, p): p.doing = .Putting_On_A_Coat
	case skin_snake(g, p): p.doing = .Skinning_Snake
	case cook_on_fire(g, p): p.doing = .Cooking
	case feed_fire(g, p): p.doing = .Tending_Fire
	case fillet_fish(g, p): p.doing = .Cutting_Fish
	case load_stick(g, p): p.doing = .Skewering_Meat
	case fish_adjacent(g, p): p.doing = .Fishing
	case pursue_food(g, p): p.doing = .Looking_For_Food
	case seek_warmth(g, p): p.doing = .Warming_Up
	case pursue_role(g, p): p.doing = ROLE_DOING[p.role]
	case p.role != .Generalist && store_short(g) && gather_for_store(g, p): p.doing = .Storing_Food // idle hands lay in for the winter
	case p.role == .Generalist && pursue_fire(g, p): p.doing = .Building_A_Fire
	case p.role == .Generalist && pursue_goal(g, p): p.doing = .Working_On_A_Goal
	case p.role == .Generalist && (craft_twine(g, p) || craft_sharp_stone(g, p) || craft_spear(g, p) || craft_basket(g, p) || craft_short_sticks(g, p)): p.doing = .Crafting
	case take_basket(g, p), stow_held(p): p.doing = .Gathering
	case gather_adjacent(g, p): p.doing = .Picking_Berries
	case p.role == .Generalist && (gather_stick_adjacent(g, p) || gather_reed_adjacent(g, p) || gather_stone_here(g, p) || gather_fiber_here(g, p)): p.doing = .Gathering
	case drop_something(g, p): p.doing = .Setting_Something_Down
	case:
		p.doing = .Wandering
		d := DIRS[rand.int_max(len(DIRS))]
		if can_enter(g, p.x + d.x, p.y + d.y) {
			p.x += d.x
			p.y += d.y
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
		p.harm[.Poison] += POISON_PER_HOUR * t
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
		p.harm[.Starvation] += STARVE_PER_HOUR * left
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
		spoil_carried(p, elapsed)
		step_thermal(p, temperature_c(g.clock, g.cfg), fire_warmth_c(g, p.x, p.y), elapsed)
		died_of_age := step_age(p, elapsed, f32(hours_per_year(g.cfg)))
		step_dopamine(p, elapsed)
		if p.health <= 0 || died_of_age {kill_person(g, i, death_cause(p^, died_of_age))}
	}
}

// Food carried in the open rots over time, as it does on the ground; food in a basket keeps.
spoil_carried :: proc(p: ^Person, dt: f32) {
	for h in 0 ..< carry_slots(p^) {
		if !stowable(p.hands[h]) {continue}
		if rand.float32() < dt / f32(SPOIL_HOURS[p.hands[h]]) {p.hands[h] = .None}
	}
}

// Remove person i from the living and leave a corpse where they stood.
// What killed someone: old age if their years ran out, otherwise whatever took the most health from them.
death_cause :: proc(p: Person, aged: bool) -> Death_Cause {
	if aged && p.health > 0 {return .Old_Age}
	worst := Death_Cause.Starvation
	for c in Death_Cause {
		if p.harm[c] > p.harm[worst] {worst = c}
	}
	return worst
}

kill_person :: proc(g: ^Game, i: int, cause: Death_Cause = .Smitten) {
	p := g.people[i]
	g.deaths[cause] += 1
	if p.coat { // the coat stays behind for someone else
		append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = .Fur_Coat, dropped_hours = g.clock.hours})
	}
	append(&g.corpses, Corpse{cause = cause, x = p.x, y = p.y, sex = p.sex, melanin = p.melanin, died_hours = g.clock.hours})
	ordered_remove(&g.people, i)
	assign_roles(g)
}

corpse_at :: proc(g: ^Game, x, y: int) -> int {
	for c, i in g.corpses {
		if c.x == x && c.y == y {return i}
	}
	return -1
}

// A belt is worn, not held, and adds places to carry things.
carry_slots :: proc(p: Person) -> int {
	return p.hand_count + (BELT_SLOTS if p.belt else 0)
}

// A basket takes one place and has places of its own inside it.
has_basket :: proc(p: Person) -> bool {
	for h in 0 ..< carry_slots(p) {
		if p.hands[h] == .Basket {return true}
	}
	return false
}

// Only food goes in a basket, where it does not spoil.
stowable :: proc(item: Item) -> bool {
	#partial switch item {
	case .Food, .Fish, .Fish_Filet, .Snake_Meat, .Rabbit_Meat: return true
	}
	return false
}

// The place of a basket with room, and the free spot inside it.
basket_room :: proc(p: Person) -> (slot, spot: int, ok: bool) {
	for h in 0 ..< carry_slots(p) {
		if p.hands[h] != .Basket {continue}
		for k in 0 ..< BASKET_SLOTS {
			if p.packs[h][k] == .None {return h, k, true}
		}
	}
	return
}

// Put a food item into a basket with room. False if there is none.
stow :: proc(p: ^Person, item: Item) -> bool {
	if !stowable(item) {return false}
	slot, spot, ok := basket_room(p^)
	if ok {p.packs[slot][spot] = item}
	return ok
}

packed_count :: proc(p: Person, item: Item) -> int {
	n := 0
	for h in 0 ..< carry_slots(p) {
		if p.hands[h] != .Basket {continue}
		for k in 0 ..< BASKET_SLOTS {
			if p.packs[h][k] == item {n += 1}
		}
	}
	return n
}

// Take one of an item out of a basket.
unpack :: proc(p: ^Person, item: Item) -> bool {
	for h in 0 ..< carry_slots(p^) {
		if p.hands[h] != .Basket {continue}
		for k in 0 ..< BASKET_SLOTS {
			if p.packs[h][k] == item {p.packs[h][k] = .None; return true}
		}
	}
	return false
}

// Move food held in the open into a basket that has room, where it keeps.
stow_held :: proc(p: ^Person) -> bool {
	for h in 0 ..< carry_slots(p^) {
		if stowable(p.hands[h]) && stow(p, p.hands[h]) {
			p.hands[h] = .None
			return true
		}
	}
	return false
}

free_hand :: proc(p: Person) -> int {
	for i in 0 ..< carry_slots(p) {
		if p.hands[i] == .None {return i}
	}
	return -1
}

held_count :: proc(p: Person) -> int {
	n := 0
	for i in 0 ..< carry_slots(p) {
		if p.hands[i] != .None {n += 1}
	}
	return n
}

// Pick one food item from the bush at (bx, by): the person must be orthogonally next
// to it, the bush must hold at least one whole food, and a hand must be free.
gather_food :: proc(g: ^Game, p: ^Person, bx, by: int) -> bool {
	if abs(p.x - bx) + abs(p.y - by) != 1 {return false}
	if !in_bounds(g, bx, by) || terrain_at(g, bx, by) != .Bush {return false}
	_, _, packable := basket_room(p^)
	hand := free_hand(p^)
	if hand < 0 && !packable {return false}
	bush := &g.bushes[by * g.width + bx]
	if bush.food < 1 {return false}
	if !skill_succeeds(p.foraging) { // fumbled it: nothing taken, and the bush is hurt
		damage_bush(g, bx, by)
		return true
	}
	bush.food -= 1
	give_or_drop(g, p, .Food)
	return true
}

// Gather from the first neighbouring bush that has food, if there is a free hand.
gather_adjacent :: proc(g: ^Game, p: ^Person) -> bool {
	if _, _, packable := basket_room(p^); holds(p^, .Food) && !hungry(p^) && !packable {return false} // one berry in hand is a snack; more would only clog the hands
	for d in DIRS {
		if gather_food(g, p, p.x + d.x, p.y + d.y) {return true}
	}
	return false
}

// Eat one food item from a hand: it empties the hand and fills the stomach (capped).
eat_food :: proc(p: ^Person) -> bool {
	if p.stomach >= MAX_STOMACH {return false}
	if unpack(p, .Food) {
		p.stomach = min(p.stomach + FOOD_STOMACH, MAX_STOMACH)
		return true
	}
	for i in 0 ..< carry_slots(p^) {
		if p.hands[i] == .Food {
			p.hands[i] = .None
			p.stomach = min(p.stomach + FOOD_STOMACH, MAX_STOMACH)
			return true
		}
	}
	for i in 0 ..< carry_slots(p^) {
		if is_dried(p.hands[i]) {
			p.stomach = min(p.stomach + dried_stomach(p.hands[i]), MAX_STOMACH)
			p.hands[i] = .None
			return true
		}
	}
	return false
}

eat_when_hungry :: proc(p: ^Person) -> bool {
	return p.stomach < EAT_BELOW_STOMACH && p.satiety < EAT_BELOW_SATIETY && eat_food(p)
}
