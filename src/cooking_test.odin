#+build !js
package gods

import "core:math/rand"
import "core:testing"

// A 9x5 grass world with one person at (3, 1), a pond at (3, 0) just above them and a firepit at (4, 1)
// just to their right (unlit, full of fuel), and no fiber, sticks or stone anywhere.
@(private = "file")
shore :: proc(g: ^Game) {
	game_init_rect(g, 9, 5)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	for &f in g.fiber {f = 0}
	for &s in g.stone {s = 0}
	for &s in g.sticks {s = 0}
	for &r in g.reeds {r = 0}
	for &f in g.fish {f = 0}
	g.cells[3] = .Pond
	g.fish[3] = FISH_PER_POND
	g.cells[4 + 9] = .Fire_Pit
	g.fuel[4 + 9] = FIRE_PIT_FUEL
	clear(&g.people)
	clear(&g.rabbits)
	append(&g.people, Person{x = 3, y = 1, health = MAX_HEALTH, satiety = MAX_SATIETY, energy = MAX_ENERGY, sleep_hours = 8, hand_count = 4, crafting = MAX_SKILL, foraging = MAX_SKILL, fishing = MAX_SKILL, cooking = MAX_SKILL, next_move_hours = 1e9})
}

@(private = "file")
pile :: proc(g: ^Game, x, y: int, item: Item, n: int) {
	for _ in 0 ..< n {append(&g.ground_items, Ground_Item{x = x, y = y, item = item})}
}

@(private = "file")
on_ground :: proc(g: ^Game, item: Item) -> int {
	n := 0
	for it in g.ground_items {
		if it.item == item {n += 1}
	}
	return n
}

@(private = "file")
count_held :: proc(p: Person, item: Item) -> int {
	n := 0
	for h in 0 ..< carry_slots(p) {
		if p.hands[h] == item {n += 1}
	}
	return n
}

// ---------- fire ----------

@(test)
a_lit_fire_burns_fuel_and_goes_out :: proc(t: ^testing.T) {
	rand.reset(161)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	g.lit[4 + 9] = true
	g.clock.hours += 8
	update_fire(&g)
	testing.expect(t, abs(g.fuel[4 + 9] - (FIRE_PIT_FUEL - 8 * FIRE_BURN_PER_HOUR)) < 1e-4, "eight hours of burning")
	testing.expect(t, g.lit[4 + 9], "still burning")
	g.clock.hours += 1000
	update_fire(&g)
	testing.expect_value(t, g.fuel[4 + 9], f32(0))
	testing.expect(t, !g.lit[4 + 9], "out of fuel, out")
}

@(test)
an_unlit_pit_keeps_its_fuel :: proc(t: ^testing.T) {
	rand.reset(162)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	g.clock.hours += 100
	update_fire(&g)
	testing.expect_value(t, g.fuel[4 + 9], f32(FIRE_PIT_FUEL))
}

@(test)
the_fire_drill_lights_a_neighbouring_pit_that_has_fuel :: proc(t: ^testing.T) {
	rand.reset(163)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !light_fire(&g, p), "no drill")
	p.hands[0] = .Fire_Drill
	p.x = 7 // away from the pit
	testing.expect(t, !light_fire(&g, p), "not beside it")
	p.x = 3
	g.fuel[4 + 9] = 0
	testing.expect(t, !light_fire(&g, p), "no fuel to light")
	g.fuel[4 + 9] = FIRE_PIT_FUEL
	testing.expect(t, light_fire(&g, p), "lit")
	testing.expect(t, fire_lit_at(&g, 4, 1), "burning")
	testing.expect(t, holds(p^, .Fire_Drill), "the drill is not used up")
	testing.expect(t, !light_fire(&g, p), "already lit")
}

@(test)
people_top_up_a_fire_that_is_nearly_out :: proc(t: ^testing.T) {
	rand.reset(164)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Stick
	g.lit[4 + 9] = true
	testing.expect(t, !feed_fire(&g, p), "a full fire needs nothing")
	g.fuel[4 + 9] = 1
	testing.expect(t, feed_fire(&g, p), "fed")
	testing.expect_value(t, g.fuel[4 + 9], f32(1 + FIRE_FEED_FUEL))
	testing.expect_value(t, held_count(p^), 0)
	g.lit[4 + 9] = false
	g.fuel[4 + 9] = 1
	p.hands[0] = .Stick
	testing.expect(t, feed_fire(&g, p), "a cold pit that is nearly empty gets topped up too")
	testing.expect_value(t, g.fuel[4 + 9], f32(2))
	testing.expect(t, !g.lit[4 + 9], "adding fuel does not light it")
}

@(test)
a_stick_can_be_added_to_a_lit_fire_or_a_cold_pit_up_to_the_capacity :: proc(t: ^testing.T) {
	rand.reset(182)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	g.fuel[4 + 9] = 3
	p.hands[0] = .Stick
	testing.expect(t, add_stick(&g, p, 4, 1), "added to a cold pit")
	testing.expect_value(t, g.fuel[4 + 9], f32(4))
	g.lit[4 + 9] = true
	pile(&g, 3, 1, .Stick, 1) // one at the feet works too
	testing.expect(t, add_stick(&g, p, 4, 1), "added to a lit fire")
	testing.expect_value(t, g.fuel[4 + 9], f32(5))
	g.fuel[4 + 9] = FIRE_PIT_FUEL
	pile(&g, 3, 1, .Stick, 1)
	testing.expect(t, !add_stick(&g, p, 4, 1), "full: it will not fit")
	testing.expect_value(t, on_ground(&g, .Stick), 1) // and the stick is not lost
	g.fuel[4 + 9] = FIRE_PIT_FUEL - 0.5
	testing.expect(t, !add_stick(&g, p, 4, 1), "half a stick of room is not enough for a whole one")
	p.x = 7
	g.fuel[4 + 9] = 1
	testing.expect(t, !add_stick(&g, p, 4, 1), "too far away")
	testing.expect(t, !add_stick(&g, &g.people[0], 3, 3), "not a pit")
}

@(test)
every_lighting_wears_the_fire_drill_until_it_breaks :: proc(t: ^testing.T) {
	rand.reset(183)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Fire_Drill
	n, _ := uses_left(p^, .Fire_Drill)
	testing.expect_value(t, n, FIRE_DRILL_DURABILITY)
	for i in 1 ..= FIRE_DRILL_DURABILITY {
		g.lit[4 + 9] = false
		g.fuel[4 + 9] = FIRE_PIT_FUEL
		testing.expect(t, holds(p^, .Fire_Drill), "still has the drill")
		testing.expect(t, light_fire(&g, p), "lit")
		if i < FIRE_DRILL_DURABILITY {
			n, _ = uses_left(p^, .Fire_Drill)
			testing.expect_value(t, n, FIRE_DRILL_DURABILITY - i)
		}
	}
	testing.expect(t, !holds(p^, .Fire_Drill), "worn out and gone")
	testing.expect(t, fire_lit_at(&g, 4, 1), "the last lighting still worked")
}

@(test)
a_failed_light_attempt_does_not_wear_the_drill :: proc(t: ^testing.T) {
	rand.reset(184)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Fire_Drill
	g.fuel[4 + 9] = 0
	testing.expect(t, !light_fire(&g, p), "no fuel")
	n, _ := uses_left(p^, .Fire_Drill)
	testing.expect_value(t, n, FIRE_DRILL_DURABILITY)
}

@(test)
a_person_after_a_cooking_goal_revives_a_dead_pit_with_a_stick_then_lights_it :: proc(t: ^testing.T) {
	rand.reset(185)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	g.fuel[4 + 9] = 0 // burnt out
	p := &g.people[0]
	p.hands[0], p.hands[1] = .Fire_Drill, .Stick
	p.dopamine = 0
	lit := false
	for _ in 0 ..< 100 {
		pursue_lighting(&g, p)
		if fire_lit_at(&g, 4, 1) {lit = true; break}
	}
	testing.expect(t, lit, "a stick, then a spark")
	testing.expect_value(t, g.fuel[4 + 9], f32(FIRE_FEED_FUEL))
}

// ---------- net and fish ----------

@(test)
a_net_is_four_twine :: proc(t: ^testing.T) {
	rand.reset(165)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	pile(&g, 3, 1, .Twine, 3)
	testing.expect(t, !craft_net(&g, p), "three is not enough")
	pile(&g, 3, 1, .Twine, 1)
	testing.expect(t, craft_net(&g, p), "net")
	testing.expect(t, holds(p^, .Net), "holding a net")
	testing.expect_value(t, on_ground(&g, .Twine), 0)
	testing.expect(t, !craft_net(&g, p), "one net is plenty")
}

@(test)
failed_net_destroys_exactly_two_twine :: proc(t: ^testing.T) {
	rand.reset(166)
	failures := 0
	for _ in 0 ..< 60 {
		g: Game
		shore(&g)
		p := &g.people[0]
		p.crafting = 0
		pile(&g, 3, 1, .Twine, 4)
		testing.expect(t, craft_net(&g, p), "an attempt is made")
		if !holds(p^, .Net) {
			failures += 1
			testing.expect_value(t, on_ground(&g, .Twine), 2) // two ruined, two left
		}
		game_destroy(&g)
	}
	testing.expect(t, failures > 0, "some attempts fail")
}

@(test)
ponds_hold_fish_that_breed_back_slowly :: proc(t: ^testing.T) {
	rand.reset(167)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for t_, i in g.cells {
		testing.expect_value(t, g.fish[i], f32(FISH_PER_POND if t_ == .Pond else 0))
	}
	shore(&g)
	g.fish[3] = 0
	g.clock.hours += 10
	update_ground(&g)
	testing.expect(t, abs(g.fish[3] - 10 * FISH_REGROW_PER_HOUR) < 1e-4, "ten hours")
	g.clock.hours += 1e6
	update_ground(&g)
	testing.expect_value(t, g.fish[3], f32(FISH_PER_POND))
}

@(test)
fishing_needs_a_net_a_pond_beside_you_and_a_whole_fish :: proc(t: ^testing.T) {
	rand.reset(168)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !fish_adjacent(&g, p), "no net")
	p.hands[0] = .Net
	testing.expect(t, fish_adjacent(&g, p), "fished")
	testing.expect_value(t, g.fish[3], f32(FISH_PER_POND - 1)) // the pond is a fish down
	testing.expect_value(t, count_held(p^, .Fish), 1)
	testing.expect_value(t, p.fish_level, 1)
	g.fish[3] = 0.9
	testing.expect(t, !fish_adjacent(&g, p), "less than one whole fish")
	g.fish[3] = FISH_PER_POND
	p.x, p.y = 7, 3
	testing.expect(t, !fish_adjacent(&g, p), "too far from the water")
}

@(test)
every_cast_wears_the_net_and_it_breaks :: proc(t: ^testing.T) {
	rand.reset(169)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Net
	n, _ := uses_left(p^, .Net)
	testing.expect_value(t, n, NET_DURABILITY)
	fish_adjacent(&g, p)
	n, _ = uses_left(p^, .Net)
	testing.expect_value(t, n, NET_DURABILITY - 1)
	for _ in 0 ..< NET_DURABILITY - 1 {
		g.fish[3] = FISH_PER_POND
		fish_adjacent(&g, p)
	}
	testing.expect(t, !holds(p^, .Net), "worn out")
}

@(test)
a_miss_wastes_a_cast_but_not_a_fish :: proc(t: ^testing.T) {
	rand.reset(170)
	misses := 0
	for _ in 0 ..< 80 {
		g: Game
		shore(&g)
		p := &g.people[0]
		p.fishing = 0
		p.hands[0] = .Net
		fish_adjacent(&g, p)
		if p.fish_level == 0 {
			misses += 1
			testing.expect_value(t, g.fish[3], f32(FISH_PER_POND))
			n, _ := uses_left(p^, .Net)
			testing.expect_value(t, n, NET_DURABILITY - 1)
			testing.expect_value(t, p.dopamine, f32(0)) // a miss feels like nothing
		}
		game_destroy(&g)
	}
	testing.expect(t, misses > 0, "an unskilled fisher misses sometimes")
}

@(test)
fishing_experience_adds_to_the_skill_check :: proc(t: ^testing.T) {
	rand.reset(171)
	novice, veteran := Person{fishing = 0}, Person{fishing = 0, fish_level = 100}
	novice_wins := 0
	for _ in 0 ..< 400 {
		if fishing_check(novice) {novice_wins += 1}
		testing.expect(t, fishing_check(veteran), "experience 100 never misses")
	}
	testing.expect(t, novice_wins > 40 && novice_wins < 200, "a 25% chance with no skill and no experience")
}

@(test)
catches_pay_less_and_less_dopamine :: proc(t: ^testing.T) {
	rand.reset(172)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Net
	gains: [4]f32
	for i in 0 ..< 4 {
		g.fish[3] = FISH_PER_POND
		p.dopamine = 0
		before := p.fish_level
		for p.fish_level == before {fish_adjacent(&g, p)} // keep casting until a catch
		gains[i] = p.dopamine
		p.hands[0] = .Net
		p.wear = {}
	}
	testing.expect(t, gains[0] > gains[1] && gains[1] > gains[2] && gains[2] > gains[3] && gains[3] > 0, "less and less")
}

// ---------- filets, stick, cooking ----------

@(test)
a_sharp_stone_turns_one_fish_into_two_filets :: proc(t: ^testing.T) {
	rand.reset(173)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Fish
	testing.expect(t, !fillet_fish(&g, p), "no sharp stone")
	p.hands[1] = .Sharp_Stone
	testing.expect(t, fillet_fish(&g, p), "filleted")
	testing.expect_value(t, count_held(p^, .Fish_Filet) + on_ground(&g, .Fish_Filet), 2)
	testing.expect_value(t, count_held(p^, .Fish), 0)
	n, _ := uses_left(p^, .Sharp_Stone)
	testing.expect_value(t, n, SHARP_STONE_DURABILITY - 1)
	testing.expect(t, !fillet_fish(&g, p), "no fish left")
}

@(test)
a_sharp_stone_turns_a_stick_into_a_cooking_stick :: proc(t: ^testing.T) {
	rand.reset(174)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Stick
	testing.expect(t, !craft_cooking_stick(&g, p), "no sharp stone")
	p.hands[1] = .Sharp_Stone
	testing.expect(t, craft_cooking_stick(&g, p), "made")
	testing.expect(t, holds(p^, .Cooking_Stick) && !holds(p^, .Stick), "the stick became a cooking stick")
	testing.expect_value(t, p.craft_levels[.Cooking_Stick], 1)
	n, _ := uses_left(p^, .Sharp_Stone)
	testing.expect_value(t, n, SHARP_STONE_DURABILITY - 1)
}

@(test)
meat_goes_onto_an_empty_cooking_stick :: proc(t: ^testing.T) {
	rand.reset(175)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	pile(&g, 3, 1, .Snake_Meat, 1)
	testing.expect(t, !load_stick(&g, p), "no stick")
	p.hands[0] = .Cooking_Stick
	testing.expect(t, load_stick(&g, p), "loaded from the ground")
	testing.expect_value(t, p.loaded[0], Item.Snake_Meat)
	testing.expect_value(t, on_ground(&g, .Snake_Meat), 0)
	pile(&g, 3, 1, .Fish_Filet, 1)
	testing.expect(t, !load_stick(&g, p), "the stick is full")
	p.loaded[0] = .None
	testing.expect(t, load_stick(&g, p), "a filet this time")
	testing.expect_value(t, p.loaded[0], Item.Fish_Filet)
}

@(test)
cooking_needs_a_lit_fire_beside_you :: proc(t: ^testing.T) {
	rand.reset(176)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Cooking_Stick
	p.loaded[0] = .Fish_Filet
	testing.expect(t, !cook_on_fire(&g, p), "the pit is cold")
	g.lit[4 + 9] = true
	p.x = 7
	testing.expect(t, !cook_on_fire(&g, p), "too far from the fire")
	p.x = 3
	testing.expect(t, cook_on_fire(&g, p), "cooked")
	testing.expect_value(t, p.loaded[0], Item.Cooked_Fish_Filet)
	testing.expect_value(t, p.cook_level, 1)
	testing.expect(t, p.dopamine > 0, "a good meal feels good")
	testing.expect(t, !cook_on_fire(&g, p), "nothing raw left on the stick")
}

@(test)
snake_meat_cooks_into_cooked_snake_meat :: proc(t: ^testing.T) {
	rand.reset(177)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	g.lit[4 + 9] = true
	p := &g.people[0]
	p.hands[1] = .Cooking_Stick
	p.loaded[1] = .Snake_Meat
	cook_on_fire(&g, p)
	testing.expect_value(t, p.loaded[1], Item.Cooked_Snake_Meat)
}

@(test)
burnt_meat_is_ruined_and_cooking_improves_with_experience :: proc(t: ^testing.T) {
	rand.reset(178)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	g.lit[4 + 9] = true
	burnt := 0
	for _ in 0 ..< 80 {
		p := Person{x = 3, y = 1, hand_count = 2, cooking = 0}
		p.hands[0], p.loaded[0] = .Cooking_Stick, .Fish_Filet
		cook_on_fire(&g, &p)
		if p.loaded[0] == .None {
			burnt += 1
			testing.expect_value(t, p.cook_level, 0)
			testing.expect_value(t, p.dopamine, f32(0))
		}
	}
	testing.expect(t, burnt > 20, "an unskilled cook burns a lot")
	pro := Person{x = 3, y = 1, hand_count = 2, cooking = 0, cook_level = 100}
	for _ in 0 ..< 60 {
		pro.hands[0], pro.loaded[0] = .Cooking_Stick, .Fish_Filet
		cook_on_fire(&g, &pro)
		testing.expect_value(t, pro.loaded[0], Item.Cooked_Fish_Filet)
	}
}

@(test)
hungry_people_eat_cooked_meals_off_the_stick :: proc(t: ^testing.T) {
	p := Person{hand_count = 2, stomach = 5}
	p.hands[0], p.loaded[0] = .Cooking_Stick, .Cooked_Snake_Meat
	testing.expect(t, eat_cooked(&p), "ate")
	testing.expect_value(t, p.stomach, f32(5 + COOKED_STOMACH))
	testing.expect_value(t, p.loaded[0], Item.None)
	testing.expect(t, holds(p, .Cooking_Stick), "the stick stays")
	p.hands[0], p.loaded[0] = .Cooking_Stick, .Fish_Filet
	testing.expect(t, !eat_cooked(&p), "raw meat is not a meal")
	p.loaded[0] = .Cooked_Fish_Filet
	p.stomach = 90
	testing.expect(t, !eat_cooked(&p), "full")
}

@(test)
a_dropped_stick_loses_its_meat_and_new_sticks_start_bare :: proc(t: ^testing.T) {
	rand.reset(179)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0], p.loaded[0] = .Cooking_Stick, .Fish_Filet
	drop_item(&g, p, 0)
	testing.expect_value(t, p.loaded[0], Item.None)
	p.loaded[0] = .Cooked_Fish_Filet // stale leftovers
	give_or_drop(&g, p, .Cooking_Stick)
	testing.expect_value(t, p.loaded[0], Item.None)
}

// ---------- goals ----------

@(test)
a_craving_person_makes_a_net_and_goes_fishing :: proc(t: ^testing.T) {
	rand.reset(180)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.x, p.y = 7, 3 // well away from the pond
	pile(&g, 7, 3, .Twine, 4)
	for item in Item {p.craft_levels[item] = 50}
	p.craft_levels[.Net] = 0
	caught := false
	for _ in 0 ..< 400 {
		p.dopamine = 0
		p.satiety = MAX_SATIETY
		p.craft_levels[.Net] = 0 // keep the net the newest thing
		pursue_goal(&g, p)
		if p.fish_level > 0 {caught = true; break}
	}
	testing.expect(t, caught, "made a net, walked to the pond and caught a fish")
}

@(test)
a_craving_person_cooks_a_meal :: proc(t: ^testing.T) {
	rand.reset(181)
	g: Game
	shore(&g)
	defer game_destroy(&g)
	g.lit[4 + 9] = true
	g.fuel[4 + 9] = 1000 // a fire that lasts, so the test is about the person
	for i in 0 ..< len(g.cells) { // a tree with sticks, away from the water and fire
		if i == 8 + 4 * 9 {g.cells[i] = .Tree; g.sticks[i] = 20}
	}
	p := &g.people[0]
	p.hands[0], p.hands[1] = .Sharp_Stone, .Net
	for item in Item {p.craft_levels[item] = 50}
	p.craft_levels[.Fish], p.craft_levels[.Cooked_Fish_Filet] = 0, 0 // unused slots, but harmless
	p.fish_level = 5 // fishing is old news, so the goal is the meal
	cooked := false
	for _ in 0 ..< 3000 {
		p.dopamine = 0
		p.satiety = MAX_SATIETY
		pursue_goal(&g, p)
		if p.cook_level > 0 {cooked = true; break}
	}
	testing.expect(t, cooked, "fished, cut, skewered, walked to the fire and cooked")
}
