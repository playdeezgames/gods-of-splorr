#+build !js
package gods

import "core:testing"

// A 5x1 grass world with one person at x=2.
item_world :: proc(g: ^Game) {
	game_init_rect(g, 5, 1)
	clear(&g.people)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	append(&g.people, Person{x = 2, y = 0, health = MAX_HEALTH, satiety = 50, stomach = 50, energy = 100, sleep_hours = 8, hand_count = DEFAULT_HANDS})
}

@(test)
person_gathers_stone_from_the_field_they_stand_on :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !gather_stone_here(&g, p), "not on a stone field")
	g.cells[2], g.stone[2] = .Stone_Field, 2
	testing.expect(t, gather_stone_here(&g, p), "first")
	testing.expect_value(t, p.hands[0], Item.Stone)
	testing.expect_value(t, g.stone[2], f32(1))
	testing.expect(t, gather_stone_here(&g, p), "second")
	testing.expect_value(t, g.cells[2], Terrain.Dirt) // used up
	testing.expect(t, !gather_stone_here(&g, p), "hands full and field gone")
}

@(test)
dropped_items_land_at_the_persons_feet :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[1] = .Stone
	testing.expect(t, !drop_item(&g, p, 0), "empty hand")
	testing.expect(t, drop_item(&g, p, 1), "drop")
	testing.expect_value(t, p.hands[1], Item.None)
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].item, Item.Stone)
	testing.expect_value(t, g.ground_items[0].x, 2)
}

@(test)
dropped_food_spoils_and_rots_away_but_stone_stays :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0], p.hands[1] = .Food, .Stone
	drop_item(&g, p, 0)
	drop_item(&g, p, 1)
	g.clock.hours += FOOD_SPOIL_HOURS / 2
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 2)
	testing.expect(t, abs(ground_food_freshness(&g, g.ground_items[0]) - 0.5) < 1e-4, "half fresh")
	g.clock.hours += FOOD_SPOIL_HOURS
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].item, Item.Stone)
}

@(test)
hungry_person_eats_dropped_food_in_proportion_to_freshness :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.stomach = 0
	append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Food, dropped_hours = g.clock.hours})
	g.clock.hours += FOOD_SPOIL_HOURS / 2
	testing.expect(t, eat_from_ground(&g, p), "eats")
	testing.expect(t, abs(p.stomach - FOOD_STOMACH / 2) < 1e-3, "half-spoiled food fills half")
	testing.expect_value(t, len(g.ground_items), 0)
	p.stomach = 80 // not hungry
	append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Food, dropped_hours = g.clock.hours})
	testing.expect(t, !eat_from_ground(&g, p), "not hungry")
}

@(test)
full_hands_beside_a_berry_bush_drop_a_stone :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0], p.hands[1] = .Stone, .Stone
	testing.expect(t, !drop_something(&g, p) || len(g.ground_items) == 1, "only a chance drop without a bush")
	clear(&g.ground_items)
	p.hands[0], p.hands[1] = .Stone, .Stone
	g.cells[3] = .Bush
	g.bushes[3] = Bush{food = 5, max_food = 5}
	testing.expect(t, drop_something(&g, p), "drops to make room")
	testing.expect_value(t, held_count(p^), 1)
	testing.expect(t, gather_adjacent(&g, p), "can now take berries")
}

@(test)
person_gathers_and_drops_plant_fiber :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	g.fiber[2] = 1.5
	testing.expect(t, gather_fiber_here(&g, p), "first")
	testing.expect_value(t, p.hands[0], Item.Fiber)
	testing.expect(t, gather_fiber_here(&g, p), "second takes the rest")
	testing.expect_value(t, g.cells[2], Terrain.Dirt)
	testing.expect(t, !gather_fiber_here(&g, p), "hands full")
	testing.expect(t, drop_item(&g, p, 0), "drop")
	testing.expect_value(t, g.ground_items[0].item, Item.Fiber)
	buf: [80]byte
	testing.expect_value(t, describe_ground_items(&g, 2, 0, buf[:]), "1 fiber")
	g.clock.hours += 1000
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 1) // fiber does not spoil
}

@(test)
person_gathers_sticks_from_an_adjacent_tree_until_it_is_bare :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	g.cells[3] = .Tree
	g.sticks[3] = 2
	testing.expect(t, !gather_stick(&g, p, 4, 0), "not adjacent")
	testing.expect(t, gather_stick_adjacent(&g, p), "first")
	testing.expect_value(t, p.hands[0], Item.Stick)
	testing.expect(t, gather_stick_adjacent(&g, p), "second")
	p.hands[0], p.hands[1] = .None, .None
	testing.expect(t, !gather_stick_adjacent(&g, p), "bare")
	testing.expect_value(t, g.cells[3], Terrain.Tree) // the tree stays
	p.hands[0], p.hands[1] = .Stick, .Stick
	testing.expect(t, !gather_stick_adjacent(&g, p), "hands full")
	drop_item(&g, p, 0)
	buf: [80]byte
	testing.expect_value(t, describe_ground_items(&g, 2, 0, buf[:]), "1 stick")
}

@(test)
two_fibers_make_one_twine_which_can_be_dropped :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !craft_twine(p), "nothing in hand")
	p.hands[0] = .Fiber
	testing.expect(t, !craft_twine(p), "one fiber is not enough")
	p.hands[1] = .Stick
	testing.expect(t, !craft_twine(p), "a stick is not fiber")
	p.hands[1] = .Fiber
	testing.expect(t, craft_twine(p), "two fibers")
	testing.expect_value(t, p.hands[0], Item.Twine)
	testing.expect_value(t, p.hands[1], Item.None)
	testing.expect(t, !craft_twine(p), "the fibers are used up")
	testing.expect(t, drop_item(&g, p, 0), "drop twine")
	buf: [80]byte
	testing.expect_value(t, describe_ground_items(&g, 2, 0, buf[:]), "1 twine")
	g.clock.hours += 1000
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 1) // twine does not spoil
}

@(test)
twine_crafting_works_with_fibers_in_any_hands :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hand_count = 4
	p.hands = {.Stone, .Fiber, .Stick, .Fiber}
	testing.expect(t, craft_twine(p), "craft")
	testing.expect_value(t, p.hands, [MAX_HANDS]Item{.Stone, .Twine, .Stick, .None})
}
