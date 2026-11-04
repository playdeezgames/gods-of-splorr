#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(test)
people_start_on_grass_with_both_sexes :: proc(t: ^testing.T) {
	rand.reset(3)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect_value(t, len(g.people), START_PEOPLE)
	testing.expect_value(t, g.people[0].sex, Sex.Male)
	testing.expect_value(t, g.people[1].sex, Sex.Female)
	for p in g.people {
		testing.expect(t, walkable(terrain_at(&g, p.x, p.y)), "on open ground")
	}
	testing.expect(t, g.people[0].x != g.people[1].x || g.people[0].y != g.people[1].y, "distinct cells")
}

@(test)
people_only_ever_walk_on_open_ground :: proc(t: ^testing.T) {
	rand.reset(11)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	start: [START_PEOPLE][2]int
	for p, i in g.people {start[i] = {p.x, p.y}}
	moved := false
	for _ in 0 ..< 5000 {
		g.clock.hours += 0.1
		update_people(&g)
		for p in g.people {
			testing.expect(t, in_bounds(&g, p.x, p.y), "in bounds")
			testing.expect(t, walkable(terrain_at(&g, p.x, p.y)), "on open ground")
		}
		testing.expect(t, g.people[0].x != g.people[1].x || g.people[0].y != g.people[1].y, "never share a cell")
	}
	for p, i in g.people {
		if p.x != start[i].x || p.y != start[i].y {moved = true}
	}
	testing.expect(t, moved, "people wander")
}

@(test)
only_open_ground_is_walkable :: proc(t: ^testing.T) {
	for terrain in Terrain {
		testing.expect_value(t, walkable(terrain), terrain == .Grass || terrain == .Stone_Field || terrain == .Dirt)
	}
}

@(test)
cannot_walk_into_blocked_cells :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.cells[0] = .Tree
	testing.expect(t, !can_enter(&g, 0, 0), "tree blocks")
	g.cells[1] = .Grass
	g.people[0].x, g.people[0].y = 1, 0
	testing.expect(t, !can_enter(&g, 1, 0), "occupied blocks")
	testing.expect(t, !can_enter(&g, -1, 0), "edge blocks")
}

luminance :: proc(c: [3]f32) -> f32 {
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
}

@(test)
more_melanin_is_darker_and_always_brown :: proc(t: ^testing.T) {
	prev := luminance(skin_color(0))
	for i in 1 ..= 10 {
		c := skin_color(f32(i) / 10)
		testing.expect(t, luminance(c) < prev, "darker with more melanin")
		testing.expect(t, c.r > c.g && c.g > c.b, "always a shade of brown")
		prev = luminance(c)
	}
	testing.expect_value(t, skin_color(-5), skin_color(0))
	testing.expect_value(t, skin_color(5), skin_color(1))
}

@(test)
people_get_melanin_in_range_with_variety :: proc(t: ^testing.T) {
	rand.reset(5)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	lo, hi: f32 = 1, 0
	for _ in 0 ..< 200 {
		m := random_melanin()
		testing.expect(t, m >= 0 && m <= 1, "in range")
		lo, hi = min(lo, m), max(hi, m)
	}
	testing.expect(t, lo < 0.2 && hi > 0.8, "both light and dark occur")
	for p in g.people {
		testing.expect(t, p.melanin >= 0 && p.melanin <= 1, "person melanin in range")
	}
}

fresh :: proc(stomach, satiety, health: f32) -> Person {
	return Person{stomach = stomach, satiety = satiety, health = health}
}

@(test)
digesting_moves_stomach_into_satiety :: proc(t: ^testing.T) {
	p := fresh(30, 50, 100)
	step_vitals(&p, 2) // 5/hour for 2 hours
	testing.expect_value(t, p.stomach, f32(20))
	testing.expect_value(t, p.satiety, f32(60))
	testing.expect_value(t, p.health, f32(100))
}

@(test)
empty_stomach_drains_satiety_then_health :: proc(t: ^testing.T) {
	p := fresh(0, 10, 100)
	step_vitals(&p, 2)
	testing.expect(t, abs(p.satiety - 7) < 1e-4, "1.5/hour")
	testing.expect_value(t, p.health, f32(100))
	p = fresh(0, 0, 100)
	step_vitals(&p, 10)
	testing.expect_value(t, p.satiety, f32(0))
	testing.expect(t, abs(p.health - 90) < 1e-4, "1/hour once satiety is 0")
}

@(test)
one_big_step_crosses_every_boundary_exactly :: proc(t: ^testing.T) {
	// 10 stomach lasts 2h (satiety 0 -> 10), 10 satiety lasts 6.67h, then 5h of starving
	p := fresh(10, 0, 100)
	step_vitals(&p, 2 + 10.0 / HUNGER_PER_HOUR + 5)
	testing.expect_value(t, p.stomach, f32(0))
	testing.expect_value(t, p.satiety, f32(0))
	testing.expect(t, abs(p.health - 95) < 1e-3, "5 hours of starvation")
	// same total time in tiny steps agrees
	q := fresh(10, 0, 100)
	for _ in 0 ..< 1000 {
		step_vitals(&q, (2 + 10.0 / HUNGER_PER_HOUR + 5) / 1000)
	}
	testing.expect(t, abs(q.health - p.health) < 0.05, "step size does not matter")
}

@(test)
satiety_and_stats_stay_in_bounds :: proc(t: ^testing.T) {
	p := fresh(100, 95, 100)
	step_vitals(&p, 20)
	testing.expect_value(t, p.satiety, f32(MAX_SATIETY))
	testing.expect_value(t, p.stomach, f32(0))
	p = fresh(0, 0, 1)
	step_vitals(&p, 100)
	testing.expect_value(t, p.health, f32(0))
}

@(test)
starved_person_becomes_a_corpse :: proc(t: ^testing.T) {
	rand.reset(9)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.people[0].stomach, g.people[0].satiety, g.people[0].health = 0, 0, 1
	x, y, mel := g.people[0].x, g.people[0].y, g.people[0].melanin
	g.clock.hours += 2
	update_vitals(&g)
	testing.expect_value(t, len(g.people), START_PEOPLE - 1)
	testing.expect_value(t, len(g.corpses), 1)
	testing.expect_value(t, g.people[0].sex, Sex.Female)
	c := g.corpses[0]
	testing.expect(t, c.x == x && c.y == y && c.melanin == mel && c.sex == .Male, "corpse stays where they fell")
	testing.expect(t, corpse_at(&g, x, y) == 0, "findable")
}

// A world with a bush at (5,5) and the first person standing at (4,5).
gather_setup :: proc(g: ^Game, food: f32) {
	for i in 0 ..< len(g.cells) {
		g.cells[i] = .Grass
	}
	g.cells[5 * g.width + 5] = .Bush
	g.bushes[5 * g.width + 5] = Bush{food = food, max_food = 20}
	g.people[0].x, g.people[0].y = 4, 5
	g.people[0].hands = {}
	g.people[0].foraging = MAX_SKILL
	g.people[0].role = .Generalist
}

@(test)
gathering_takes_from_bush_into_a_hand :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 3)
	p := &g.people[0]
	testing.expect_value(t, p.hand_count, 2)
	testing.expect(t, gather_food(&g, p, 5, 5), "first gather")
	testing.expect_value(t, g.bushes[5 * g.width + 5].food, f32(2))
	testing.expect_value(t, p.hands[0], Item.Food)
	testing.expect(t, gather_food(&g, p, 5, 5), "second gather")
	testing.expect_value(t, held_count(p^), 2)
	testing.expect(t, !gather_food(&g, p, 5, 5), "hands are full")
	testing.expect_value(t, g.bushes[5 * g.width + 5].food, f32(1))
}

@(test)
gathering_needs_adjacency_and_a_whole_food :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 3)
	p := &g.people[0]
	p.x = 3 // two cells away
	testing.expect(t, !gather_food(&g, p, 5, 5), "too far")
	p.x, p.y = 4, 4 // diagonal
	testing.expect(t, !gather_food(&g, p, 5, 5), "diagonal is not adjacent")
	p.x, p.y = 4, 5
	g.bushes[5 * g.width + 5].food = 0.9
	testing.expect(t, !gather_food(&g, p, 5, 5), "less than one food")
	testing.expect_value(t, held_count(p^), 0)
	testing.expect(t, !gather_food(&g, p, 4, 5), "not a bush")
}

@(test)
hand_count_limits_what_can_be_carried :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 10)
	p := &g.people[0]
	p.hand_count = 3
	for _ in 0 ..< 5 {
		gather_food(&g, p, 5, 5)
	}
	testing.expect_value(t, held_count(p^), 3)
	testing.expect_value(t, g.bushes[5 * g.width + 5].food, f32(7))
}

@(test)
people_next_to_bushes_gather_on_their_own :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 10)
	g.people[0].next_move_hours = g.clock.hours
	g.people[1].next_move_hours = g.clock.hours + 1000
	g.clock.hours += 0.01
	update_people(&g)
	testing.expect_value(t, held_count(g.people[0]), 1)
	testing.expect_value(t, g.people[0].x, 4) // gathering used the action, so no step
}

@(test)
eating_empties_a_hand_and_fills_the_stomach :: proc(t: ^testing.T) {
	p := Person{stomach = 10, hand_count = 2}
	testing.expect(t, !eat_food(&p), "nothing to eat")
	p.hands[1] = .Food
	testing.expect(t, eat_food(&p), "eats")
	testing.expect_value(t, p.stomach, f32(10 + FOOD_STOMACH))
	testing.expect_value(t, p.hands[1], Item.None)
	testing.expect_value(t, held_count(p), 0)
}

@(test)
eating_is_capped_and_refused_when_full :: proc(t: ^testing.T) {
	p := Person{stomach = 90, hand_count = 2}
	p.hands[0] = .Food
	testing.expect(t, eat_food(&p), "eats")
	testing.expect_value(t, p.stomach, f32(MAX_STOMACH))
	p.hands[0] = .Food
	testing.expect(t, !eat_food(&p), "full stomach refuses")
	testing.expect_value(t, p.hands[0], Item.Food)
}

@(test)
hungry_people_eat_on_their_own_before_gathering :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 10)
	p := &g.people[0]
	p.hands[0] = .Food
	p.stomach = 5
	p.next_move_hours = g.clock.hours
	g.people[1].next_move_hours = g.clock.hours + 1000
	g.clock.hours += 0.01
	update_people(&g)
	testing.expect_value(t, p.stomach, f32(5 + FOOD_STOMACH))
	testing.expect_value(t, held_count(p^), 0)
	testing.expect_value(t, g.bushes[5 * g.width + 5].food, f32(10)) // ate instead of gathering
}

@(test)
well_fed_people_keep_their_food :: proc(t: ^testing.T) {
	rand.reset(1) // a stray 2% chance to set something down would otherwise make this flaky
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 10)
	p := &g.people[0]
	p.hands[0] = .Food
	p.foraging = MAX_SKILL // never fumbles
	p.stomach = 60
	p.next_move_hours = g.clock.hours
	g.people[1].next_move_hours = g.clock.hours + 1000
	g.clock.hours += 0.01
	update_people(&g)
	testing.expect_value(t, p.stomach, f32(60))
	testing.expect_value(t, held_count(p^), 2) // kept it and gathered a second
}

@(test)
a_forager_can_stay_alive_indefinitely :: proc(t: ^testing.T) {
	rand.reset(21)
	g: Game
	game_init_rect(&g, DEFAULT_ZOOM, DEFAULT_ZOOM)
	defer game_destroy(&g)
	g.cfg.latitude = 15 // a mild climate: this test is about food, not cold
	// plenty of bushes so the walker keeps finding food
	for i in 0 ..< len(g.cells) {
		g.cells[i] = .Grass if i % 3 != 0 else .Bush
		if g.cells[i] == .Bush {g.bushes[i] = Bush{food = 20, max_food = 20}}
	}
	for i := len(g.people) - 1; i >= 0; i -= 1 {
		if g.cells[g.people[i].y * g.width + g.people[i].x] != .Grass {ordered_remove(&g.people, i)}
	}
	for _ in 0 ..< 3000 { // ~ 20 game days at 10 minute ticks
		g.clock.hours += 0.1
		update_people(&g)
		update_bushes(&g)
		update_vitals(&g)
	}
	testing.expect_value(t, len(g.corpses), 0)
}

@(test)
energy_drains_awake_and_sleep_follows :: proc(t: ^testing.T) {
	p := Person{energy = MAX_ENERGY, sleep_hours = DEFAULT_SLEEP_HOURS}
	step_energy(&p, 8)
	testing.expect(t, abs(p.energy - 50) < 1e-3, "half gone after 8 awake hours")
	testing.expect(t, !p.asleep, "still awake")
	step_energy(&p, 8)
	testing.expect_value(t, p.energy, f32(0))
	step_energy(&p, 0.001)
	testing.expect(t, p.asleep, "asleep at zero energy")
}

@(test)
sleeping_recovers_and_wakes_when_full :: proc(t: ^testing.T) {
	p := Person{energy = 0, asleep = true, sleep_hours = DEFAULT_SLEEP_HOURS}
	step_energy(&p, 4)
	testing.expect(t, abs(p.energy - 50) < 1e-3 && p.asleep, "half rested")
	step_energy(&p, 4)
	testing.expect_value(t, p.energy, f32(MAX_ENERGY))
	step_energy(&p, 1)
	testing.expect(t, !p.asleep, "awake once full")
	testing.expect(t, p.energy < MAX_ENERGY, "and spending energy again")
}

@(test)
a_day_is_two_thirds_awake_and_one_third_asleep :: proc(t: ^testing.T) {
	p := Person{energy = MAX_ENERGY, sleep_hours = DEFAULT_SLEEP_HOURS}
	slept, total := 0, 0
	for _ in 0 ..< 24 * 60 * 10 { // ten days in one-minute steps
		step_energy(&p, 1.0 / 60)
		total += 1
		if p.asleep {slept += 1}
	}
	frac := f32(slept) / f32(total)
	testing.expect(t, abs(frac - 1.0 / 3) < 0.01, "about a third asleep")
	// one huge step lands in the same place as many small ones
	a := Person{energy = MAX_ENERGY, sleep_hours = DEFAULT_SLEEP_HOURS}
	step_energy(&a, 100)
	b := Person{energy = MAX_ENERGY, sleep_hours = DEFAULT_SLEEP_HOURS}
	for _ in 0 ..< 10000 {
		step_energy(&b, 0.01)
	}
	testing.expect(t, a.asleep == b.asleep && abs(a.energy - b.energy) < 0.2, "step size does not matter")
}

@(test)
sleepers_do_not_act :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 10)
	p := &g.people[0]
	p.asleep, p.energy = true, 10
	p.next_move_hours = g.clock.hours
	g.people[1].next_move_hours = g.clock.hours + 1000
	g.clock.hours += 0.01
	update_people(&g)
	testing.expect_value(t, held_count(p^), 0)
	testing.expect_value(t, g.bushes[5 * g.width + 5].food, f32(10))
	p.asleep = false
	p.next_move_hours = g.clock.hours
	g.clock.hours += 0.01
	update_people(&g)
	testing.expect_value(t, held_count(p^), 1)
}

@(test)
new_people_start_rested_and_sleep_after_16_hours :: proc(t: ^testing.T) {
	rand.reset(8)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect_value(t, g.people[0].energy, f32(MAX_ENERGY))
	g.people[0].sleep_hours = DEFAULT_SLEEP_HOURS
	for _ in 0 ..< 159 { // 15.9 hours
		g.clock.hours += 0.1
		update_vitals(&g)
	}
	testing.expect(t, !g.people[0].asleep, "awake just before 16 hours")
	g.clock.hours += 0.2
	update_vitals(&g)
	testing.expect(t, g.people[0].asleep, "asleep after 16 hours")
}

@(test)
sleep_need_ranges_from_4_to_12_averaging_8 :: proc(t: ^testing.T) {
	rand.reset(13)
	lo, hi, sum: f32 = 100, 0, 0
	n := 20000
	for _ in 0 ..< n {
		h := random_sleep_hours()
		testing.expect(t, h >= MIN_SLEEP_HOURS && h <= MAX_SLEEP_HOURS, "in range")
		lo, hi, sum = min(lo, h), max(hi, h), sum + h
	}
	testing.expect(t, abs(sum / f32(n) - 8) < 0.1, "averages 8 hours")
	testing.expect(t, lo < 4.3 && hi > 11.7, "short and long sleepers both occur")
}

@(test)
each_person_sleeps_as_much_as_they_need :: proc(t: ^testing.T) {
	for need in ([?]f32{4, 6, 8, 10, 12}) {
		p := Person{energy = MAX_ENERGY, sleep_hours = need}
		awake := 24 - need
		step_energy(&p, awake - 0.01)
		testing.expect(t, !p.asleep, "awake until the day's waking hours are used")
		step_energy(&p, 0.02)
		testing.expect(t, p.asleep, "asleep once they are")
		step_energy(&p, need - 0.04)
		testing.expect(t, p.asleep, "still asleep just before they have slept enough")
		step_energy(&p, 0.05)
		testing.expect(t, !p.asleep, "awake after sleeping their need")
		// over ten days the asleep fraction is need / 24
		q := Person{energy = MAX_ENERGY, sleep_hours = need}
		slept, total := 0, 24 * 60 * 10
		for _ in 0 ..< total {
			step_energy(&q, 1.0 / 60)
			if q.asleep {slept += 1}
		}
		testing.expect(t, abs(f32(slept) / f32(total) - need / 24) < 0.01, "asleep fraction matches need")
	}
}

@(test)
people_are_created_with_a_sleep_need :: proc(t: ^testing.T) {
	rand.reset(17)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for p in g.people {
		testing.expect(t, p.sleep_hours >= MIN_SLEEP_HOURS && p.sleep_hours <= MAX_SLEEP_HOURS, "in range")
	}
}

@(test)
corpses_rot_to_skeletons_which_rot_away_more_slowly :: proc(t: ^testing.T) {
	testing.expect(t, SKELETON_ROT_HOURS > CORPSE_ROT_HOURS, "skeletons last longer")
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	start := g.clock.hours
	append(&g.corpses, Corpse{x = 1, y = 1, sex = .Male, melanin = 0.5, died_hours = start})
	g.clock.hours = start + CORPSE_ROT_HOURS / 2
	update_corpses(&g)
	testing.expect(t, !g.corpses[0].skeleton, "still a corpse")
	testing.expect(t, abs(corpse_rot_fraction(&g, g.corpses[0]) - 0.5) < 1e-4, "halfway rotted")
	g.clock.hours = start + CORPSE_ROT_HOURS + 1
	update_corpses(&g)
	testing.expect(t, g.corpses[0].skeleton, "rotted to a skeleton")
	testing.expect(t, corpse_rot_fraction(&g, g.corpses[0]) < 0.01, "a fresh skeleton")
	testing.expect(t, corpse_at(&g, 1, 1) == 0, "bones stay where they fell")
	g.clock.hours = start + CORPSE_ROT_HOURS + SKELETON_ROT_HOURS / 2
	update_corpses(&g)
	testing.expect_value(t, len(g.corpses), 1)
	testing.expect(t, abs(corpse_rot_fraction(&g, g.corpses[0]) - 0.5) < 1e-3, "skeleton halfway gone")
	g.clock.hours = start + CORPSE_ROT_HOURS + SKELETON_ROT_HOURS + 1
	update_corpses(&g)
	testing.expect_value(t, len(g.corpses), 0)
}

@(test)
a_long_jump_takes_a_corpse_straight_through_to_nothing :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	append(&g.corpses, Corpse{x = 1, y = 1, died_hours = g.clock.hours})
	g.clock.hours += CORPSE_ROT_HOURS + SKELETON_ROT_HOURS + 10
	update_corpses(&g)
	testing.expect_value(t, len(g.corpses), 0)
}

@(test)
people_start_as_adults_with_a_longer_life_ahead :: proc(t: ^testing.T) {
	rand.reset(91)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for p in g.people {
		testing.expect(t, p.age_years >= START_AGE_MIN && p.age_years <= START_AGE_MAX, "an adult")
		testing.expect(t, p.lifespan_years >= LIFESPAN_MIN && p.lifespan_years <= LIFESPAN_MAX, "a lifespan in range")
		testing.expect(t, p.lifespan_years > p.age_years, "not already doomed")
	}
}

@(test)
people_age_with_the_calendar :: proc(t: ^testing.T) {
	p := Person{age_years = 20, lifespan_years = 60}
	year := f32(HOURS_PER_DAY * 30 * 12)
	testing.expect_value(t, hours_per_year(DEFAULT_CALENDAR), f64(year))
	testing.expect(t, !step_age(&p, year / 2, year), "half a year is no problem")
	testing.expect(t, abs(p.age_years - 20.5) < 1e-4, "half a year older")
	short := Calendar_Config{day_real_seconds = 1440, days_per_month = 10, months_per_year = 4, latitude = 40}
	testing.expect_value(t, hours_per_year(short), f64(HOURS_PER_DAY * 40)) // a shorter calendar, a shorter year
}

@(test)
reaching_the_lifespan_is_death_by_old_age :: proc(t: ^testing.T) {
	rand.reset(92)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for &p in g.people {p.lifespan_years = 1000} // nobody else dies
	g.people[0].age_years, g.people[0].lifespan_years = 59.9995, 60
	g.clock.hours += f64(0.001 * hours_per_year(g.cfg)) // under nine hours: nobody starves meanwhile
	update_vitals(&g)
	testing.expect_value(t, len(g.people), START_PEOPLE - 1)
	testing.expect_value(t, len(g.corpses), 1)
}

@(test)
a_lifespan_of_zero_means_immortal :: proc(t: ^testing.T) {
	p := Person{age_years = 500}
	testing.expect(t, !step_age(&p, 1e6, 1000), "never dies of age")
}
