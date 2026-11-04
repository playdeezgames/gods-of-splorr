#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(private = "file")
yard :: proc(g: ^Game, w, h: int) {
	game_init_rect(g, w, h)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	for &f in g.fiber {f = 0}
	for &s in g.stone {s = 0}
	for &s in g.sticks {s = 0}
	for &r in g.reeds {r = 0}
	clear(&g.people)
	clear(&g.rabbits)
	append(&g.people, Person{x = 0, y = 0, health = MAX_HEALTH, satiety = MAX_SATIETY, energy = MAX_ENERGY, sleep_hours = 8, hand_count = DEFAULT_HANDS, crafting = MAX_SKILL, foraging = MAX_SKILL, next_move_hours = 1e9})
}

@(test)
first_time_rewards_most_and_repeats_shrink :: proc(t: ^testing.T) {
	p := Person{}
	first := craft_reward(p, .Sharp_Stone)
	testing.expect_value(t, first, f32(CRAFT_REWARD * FIRST_CRAFT_MULT))
	p.craft_levels[.Sharp_Stone] = 1
	second := craft_reward(p, .Sharp_Stone)
	p.craft_levels[.Sharp_Stone] = 2
	third := craft_reward(p, .Sharp_Stone)
	testing.expect(t, first > second && second > third && third > 0, "less and less")
}

@(test)
success_at_other_things_dulls_every_reward :: proc(t: ^testing.T) {
	fresh, jaded := Person{}, Person{}
	jaded.craft_levels[.Twine] = 100
	testing.expect(t, craft_reward(jaded, .Sharp_Stone) < craft_reward(fresh, .Sharp_Stone), "a seasoned crafter is harder to thrill")
	testing.expect_value(t, total_crafts(jaded), 100)
}

@(test)
only_success_pays_dopamine_and_it_is_capped :: proc(t: ^testing.T) {
	rand.reset(131)
	p := Person{crafting = MAX_SKILL, dopamine = 20}
	testing.expect(t, craft_roll(&p, .Twine), "always succeeds at skill 100")
	testing.expect_value(t, p.dopamine, f32(20 + CRAFT_REWARD * FIRST_CRAFT_MULT))
	p.dopamine = MAX_DOPAMINE - 1
	craft_roll(&p, .Sharp_Stone)
	testing.expect_value(t, p.dopamine, f32(MAX_DOPAMINE))

	failing := Person{crafting = -1000, dopamine = 20}
	losses := 0
	for _ in 0 ..< 200 {
		failing.dopamine = 20
		failing.craft_levels = {}
		if !craft_roll(&failing, .Twine) {
			losses += 1
			testing.expect_value(t, failing.dopamine, f32(20)) // a failure feels like nothing
		}
	}
	testing.expect(t, losses > 0, "some attempts fail")
}

@(test)
dopamine_bleeds_off_with_a_half_life :: proc(t: ^testing.T) {
	p := Person{dopamine = 80}
	step_dopamine(&p, DOPAMINE_HALF_LIFE_HOURS)
	testing.expect(t, abs(p.dopamine - 40) < 1e-3, "half after one half-life")
	step_dopamine(&p, 2 * DOPAMINE_HALF_LIFE_HOURS)
	testing.expect(t, abs(p.dopamine - 10) < 1e-3, "a quarter after two more")
	p.dopamine = 50
	step_dopamine(&p, 0)
	testing.expect_value(t, p.dopamine, f32(50))
}

@(test)
dopamine_bleeds_during_vitals_updates :: proc(t: ^testing.T) {
	rand.reset(132)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for &p in g.people {p.dopamine = 80; p.lifespan_years = 1000}
	g.clock.hours += DOPAMINE_HALF_LIFE_HOURS
	update_vitals(&g)
	for p in g.people {testing.expect(t, abs(p.dopamine - 40) < 1e-3, "half left")}
}

@(test)
people_start_content_and_mood_follows_dopamine :: proc(t: ^testing.T) {
	rand.reset(133)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for p in g.people {
		testing.expect_value(t, p.dopamine, f32(START_DOPAMINE))
		testing.expect_value(t, mood_of(p.dopamine), Mood.Content)
		testing.expect(t, !craving(p), "not craving")
	}
	testing.expect_value(t, mood_of(0), Mood.Despondent)
	testing.expect_value(t, mood_of(20), Mood.Gloomy)
	testing.expect_value(t, mood_of(50), Mood.Content)
	testing.expect_value(t, mood_of(70), Mood.Cheerful)
	testing.expect_value(t, mood_of(100), Mood.Elated)
	testing.expect(t, craving(Person{dopamine = CRAVING_BELOW - 1}), "gloomy people crave")
}

@(test)
rewards_order_the_craftables_best_first_with_ties_in_listed_order :: proc(t: ^testing.T) {
	p := Person{}
	testing.expect_value(t, by_reward(p)[0], Item.Twine) // all new: listed order
	p.craft_levels[.Twine] = 3
	p.craft_levels[.Sharp_Stone] = 1
	order := by_reward(p)
	testing.expect_value(t, order[0], Item.Short_Stick)
	testing.expect_value(t, order[len(order) - 1], Item.Twine) // the most practiced feels least new
}

@(test)
next_step_follows_the_recipe_chain :: proc(t: ^testing.T) {
	rand.reset(135)
	g: Game
	yard(&g, 4, 1)
	defer game_destroy(&g)
	p := &g.people[0]
	step := next_step(&g, p^, .Spear)
	testing.expect_value(t, step, Step{raw = .Stone}) // a spear starts with a sharp stone, so stone
	p.hands[0] = .Sharp_Stone
	testing.expect_value(t, next_step(&g, p^, .Spear), Step{raw = .Stick}) // then a stick for the shaft
	p.hands[1] = .Stick
	testing.expect_value(t, next_step(&g, p^, .Spear), Step{raw = .Fiber}) // then fiber for twine
	append(&g.ground_items, Ground_Item{x = 0, y = 0, item = .Fiber})
	append(&g.ground_items, Ground_Item{x = 0, y = 0, item = .Fiber}) // two fibers at their feet: twist twine
	testing.expect_value(t, next_step(&g, p^, .Spear), Step{craft = .Twine})
	append(&g.ground_items, Ground_Item{x = 0, y = 0, item = .Twine})
	testing.expect_value(t, next_step(&g, p^, .Spear), Step{craft = .Spear}) // everything to hand
}

@(test)
reeds_for_a_basket_come_after_a_sharp_stone :: proc(t: ^testing.T) {
	rand.reset(136)
	g: Game
	yard(&g, 4, 1)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect_value(t, next_step(&g, p^, .Basket), Step{raw = .Stone}) // no sharp stone yet: start on one
	p.hands[0] = .Sharp_Stone
	testing.expect_value(t, next_step(&g, p^, .Basket), Step{raw = .Reed})
	for _ in 0 ..< BASKET_REEDS {append(&g.ground_items, Ground_Item{x = 0, y = 0, item = .Reed})}
	testing.expect_value(t, next_step(&g, p^, .Basket), Step{craft = .Basket})
}

@(test)
craving_people_walk_to_the_materials_their_goal_needs :: proc(t: ^testing.T) {
	rand.reset(137)
	g: Game
	yard(&g, 6, 1)
	defer game_destroy(&g)
	g.cells[5] = .Stone_Field
	g.stone[5] = 3
	p := &g.people[0]
	p.dopamine = 0
	p.satiety = MAX_SATIETY
	p.craft_levels[.Twine] = 9 // twine is dull, so the goal is a sharp stone, which needs stone
	testing.expect(t, pursue_goal(&g, p), "heading somewhere")
	testing.expect_value(t, p.x, 1)
	for _ in 0 ..< 10 {pursue_goal(&g, p)}
	testing.expect_value(t, p.x, 5) // on the stone field, where stone gets picked up
	testing.expect(t, holds(p^, .Stone), "picked up stone")
}

@(test)
a_craving_person_with_ingredients_makes_the_goal_not_the_dull_thing :: proc(t: ^testing.T) {
	rand.reset(134)
	g: Game
	yard(&g, 4, 1)
	defer game_destroy(&g)
	p := &g.people[0]
	p.dopamine = 0
	p.satiety = MAX_SATIETY
	for item in ([?]Item{.Twine, .Sharp_Stone, .Short_Stick, .Sharp_Stone}) {p.craft_levels[item] = 5} // old hat
	p.hands = {0 = .Sharp_Stone, 1 = .Stick}
	append(&g.ground_items, Ground_Item{x = 0, y = 0, item = .Twine})
	testing.expect(t, pursue_goal(&g, p), "made something")
	testing.expect(t, holds(p^, .Spear), "the one new thing within reach")
	p.dopamine = 80 // a happy person has no goal
	testing.expect(t, !pursue_goal(&g, p), "not craving")
}

@(test)
goals_skip_what_is_already_in_hand_and_wait_for_hunger :: proc(t: ^testing.T) {
	rand.reset(138)
	g: Game
	yard(&g, 6, 1)
	defer game_destroy(&g)
	g.cells[5] = .Stone_Field
	g.stone[5] = 3
	p := &g.people[0]
	p.dopamine = 0
	p.satiety = MAX_SATIETY
	p.hands[0], p.hands[1] = .Food, .Food
	testing.expect(t, !pursue_goal(&g, p), "nowhere to put anything")
	testing.expect_value(t, p.x, 0)
	p.hands = {}
	p.satiety = SEEK_MIN_SATIETY - 1
	testing.expect(t, !pursue_goal(&g, p), "too hungry to go looking")
	p.satiety = MAX_SATIETY
	testing.expect(t, pursue_goal(&g, p), "fed, so it sets off")
}

@(test)
no_source_in_the_world_means_no_goal_to_walk_to :: proc(t: ^testing.T) {
	rand.reset(139)
	g: Game
	yard(&g, 4, 1) // bare grass with no fiber, stone, sticks or reeds anywhere
	defer game_destroy(&g)
	g.people[0].dopamine = 0
	g.people[0].satiety = MAX_SATIETY
	testing.expect(t, !pursue_goal(&g, &g.people[0]), "nothing to find")
}
