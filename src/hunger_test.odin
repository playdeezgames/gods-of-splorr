#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(private = "file")
field :: proc(g: ^Game, w, h: int) {
	game_init_rect(g, w, h)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	clear(&g.people)
	clear(&g.rabbits)
	append(&g.people, Person{x = 0, y = 0, health = MAX_HEALTH, satiety = 30, energy = MAX_ENERGY, sleep_hours = 8, hand_count = DEFAULT_HANDS, crafting = MAX_SKILL, foraging = MAX_SKILL, dopamine = 90, next_move_hours = 1e9})
}

@(test)
hunger_needs_low_satiety_and_an_empty_stomach :: proc(t: ^testing.T) {
	p := Person{satiety = 30, stomach = 0}
	testing.expect(t, hungry(p))
	p.stomach = 50
	testing.expect(t, !hungry(p), "a full stomach is not hunger")
	p.stomach, p.satiety = 0, 90
	testing.expect(t, !hungry(p), "fed")
}

@(test)
hungry_person_walks_to_a_berry_bush_and_picks :: proc(t: ^testing.T) {
	rand.reset(501)
	g: Game
	field(&g, 8, 1)
	defer game_destroy(&g)
	g.cells[5] = .Bush
	g.bushes[5] = Bush{food = 3, max_food = 5}
	p := &g.people[0]
	for _ in 0 ..< 10 {
		if !pursue_food(&g, p) {break}
	}
	testing.expect_value(t, p.x, 4)
	testing.expect_value(t, p.hands[0], Item.Food)
}

@(test)
hungry_person_goes_for_fresh_food_on_the_ground :: proc(t: ^testing.T) {
	rand.reset(502)
	g: Game
	field(&g, 6, 1)
	defer game_destroy(&g)
	append(&g.ground_items, Ground_Item{x = 3, y = 0, item = .Food, dropped_hours = g.clock.hours})
	p := &g.people[0]
	for _ in 0 ..< 3 {pursue_food(&g, p)}
	testing.expect_value(t, p.x, 3)
}

@(test)
fed_person_ignores_food_seeking :: proc(t: ^testing.T) {
	rand.reset(503)
	g: Game
	field(&g, 6, 1)
	defer game_destroy(&g)
	g.cells[4] = .Bush
	g.bushes[4] = Bush{food = 3, max_food = 5}
	g.people[0].satiety = 90
	testing.expect(t, !pursue_food(&g, &g.people[0]))
}

@(test)
hungry_person_with_full_hands_drops_junk_for_berries :: proc(t: ^testing.T) {
	rand.reset(504)
	g: Game
	field(&g, 6, 1)
	defer game_destroy(&g)
	g.cells[3] = .Bush
	g.bushes[3] = Bush{food = 3, max_food = 5}
	p := &g.people[0]
	p.hands[0], p.hands[1] = .Stone, .Stone
	for _ in 0 ..< 6 {pursue_food(&g, p)}
	testing.expect(t, holds(p^, .Food), "made room and picked a berry")
}

@(test)
hungry_person_with_a_net_fishes_when_no_berries :: proc(t: ^testing.T) {
	rand.reset(505)
	g: Game
	field(&g, 6, 1)
	defer game_destroy(&g)
	g.cells[2] = .Pond
	g.fish[2] = 4
	g.cells[5] = .Fire_Pit
	p := &g.people[0]
	p.fishing = MAX_SKILL
	p.hands[0], p.hands[1] = .Net, .Cooking_Stick
	for _ in 0 ..< 6 {pursue_food(&g, p)}
	testing.expect(t, holds(p^, .Fish) || p.fish_level > 0 || g.fish[2] < 4, "went fishing for a meal")
}

@(test)
a_hungry_worker_with_full_hands_frees_one_and_then_picks :: proc(t: ^testing.T) {
	rand.reset(505)
	g: Game
	field(&g, 6, 1)
	defer game_destroy(&g)
	g.cells[1] = .Bush
	g.bushes[1] = Bush{food = 3, max_food = 5}
	p := &g.people[0]
	p.satiety, p.stomach = 0, 0
	p.hands[0], p.hands[1] = .Cooking_Stick, .Fire_Drill
	testing.expect(t, pursue_food(&g, p), "setting a tool down is the turn")
	testing.expect(t, free_hand(p^) >= 0, "a hand is free")
	for _ in 0 ..< 6 {
		if holds(p^, .Food) {break}
		gather_adjacent(&g, p)
	}
	testing.expect(t, holds(p^, .Food), "picked a berry")
}
