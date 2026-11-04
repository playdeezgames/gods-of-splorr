#+build !js
package gods

import "core:math/rand"
import "core:testing"

// An all-grass world with one hungry-ish person at (5, 5), the stockpile under them, and no rabbits.
@(private = "file")
yard :: proc(g: ^Game) {
	game_init_rect(g, 30, 12)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	for &f in g.fiber {f = 0}
	clear(&g.people)
	clear(&g.rabbits)
	append(&g.people, Person{id = 1, x = 5, y = 5, health = MAX_HEALTH, satiety = MAX_SATIETY, stomach = 50, energy = MAX_ENERGY, sleep_hours = 8, hand_count = DEFAULT_HANDS, foraging = MAX_SKILL, next_move_hours = 1e9})
	g.stockpile_x, g.stockpile_y = 5, 5
	append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Drying_Rack})
}

DEEP_WINTER_HOURS :: 290 * 24 // berries long stopped growing

@(test)
food_set_out_dries_and_then_keeps :: proc(t: ^testing.T) {
	rand.reset(701)
	g: Game
	yard(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0], p.hands[1] = .Food, .Rabbit_Meat
	testing.expect(t, set_out_to_dry(&g, p), "berry out")
	testing.expect(t, set_out_to_dry(&g, p), "meat out")
	testing.expect(t, !set_out_to_dry(&g, p), "nothing left to set out")
	g.clock.hours += DRY_HOURS - 1
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 3) // the rack and the two pieces on it
	_, drying := store_count(&g)
	testing.expect_value(t, drying, 2)
	g.clock.hours += 2
	update_ground_items(&g)
	testing.expect_value(t, have_count(&g, p^, .Dried_Berries), 1)
	testing.expect_value(t, have_count(&g, p^, .Dried_Meat), 1)
	g.clock.hours += 5000
	update_ground_items(&g)
	dried, _ := store_count(&g)
	testing.expect_value(t, dried, 2)
}

@(test)
food_dries_only_on_a_rack_with_room :: proc(t: ^testing.T) {
	rand.reset(706)
	g: Game
	yard(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	for _ in 0 ..< RACK_CAPACITY {
		p.hands[0] = .Food
		testing.expect(t, set_out_to_dry(&g, p), "hung up")
	}
	p.hands[0] = .Food
	testing.expect(t, !set_out_to_dry(&g, p), "the rack is full")
	testing.expect_value(t, p.hands[0], Item.Food)
	clear(&g.ground_items)
	testing.expect(t, !set_out_to_dry(&g, p), "no rack at all")
}

@(test)
the_toolmaker_lashes_a_rack_from_sticks_when_the_store_is_short :: proc(t: ^testing.T) {
	rand.reset(707)
	g: Game
	yard(&g)
	defer game_destroy(&g)
	clear(&g.ground_items) // no rack yet
	set_start_time(&g) // late spring: berries growing, the store empty
	g.cells[2 * g.width + 20] = .Bush
	g.bushes[2 * g.width + 20] = Bush{food = 15, max_food = 15, health = BUSH_MAX_HEALTH} // berries to spare
	p := &g.people[0]
	p.role, p.crafting = .Toolmaker, MAX_SKILL
	p.hands[0] = .Sharp_Stone
	for item in ([?]Item{.Net, .Fire_Drill, .Cooking_Stick}) {
		append(&g.ground_items, Ground_Item{x = 5, y = 5, item = item, dropped_hours = g.clock.hours})
	}
	for _ in 0 ..< RACK_STICKS {append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Stick, dropped_hours = g.clock.hours})}
	testing.expect(t, want_rack(&g), "needs one")
	testing.expect(t, pursue_toolmaker(&g, p), "lashing")
	testing.expect(t, holds(p^, .Drying_Rack), "made")
	testing.expect_value(t, stock_of(&g, .Stick), 0)
	testing.expect(t, !want_rack(&g), "one on its way is enough")
	testing.expect(t, pursue_toolmaker(&g, p), "setting it down")
	testing.expect_value(t, stock_of(&g, .Drying_Rack), 1)
}

@(test)
the_store_is_left_alone_while_berries_are_near :: proc(t: ^testing.T) {
	rand.reset(702)
	g: Game
	yard(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.satiety, p.stomach = 20, 0
	g.clock.hours = DEEP_WINTER_HOURS
	append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Dried_Meat, dropped_hours = g.clock.hours})
	g.cells[5 * g.width + 9] = .Bush
	g.bushes[5 * g.width + 9] = Bush{food = 3, max_food = 5, health = BUSH_MAX_HEALTH}
	testing.expect(t, !store_open(&g, p^), "berries a few steps off")
	testing.expect(t, !eat_from_ground(&g, p), "so the store keeps")
	g.bushes[5 * g.width + 9].food = 0
	testing.expect(t, store_open(&g, p^), "the bush is bare")
	testing.expect(t, eat_from_ground(&g, p), "ate from the store")
	testing.expect_value(t, p.stomach, f32(DRIED_MEAT_STOMACH))
	append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Dried_Meat, dropped_hours = g.clock.hours})
	p.stomach = 0
	g.clock.hours = 150 * 24 // summer: the store waits for the winter even with no berries near
	p.satiety = 30
	testing.expect(t, !eat_from_ground(&g, p), "kept for the winter")
	p.satiety = STORE_EMERGENCY_SATIETY - 1
	testing.expect(t, eat_from_ground(&g, p), "unless someone is starving")
}

@(test)
a_hungry_person_walks_to_the_store_when_berries_are_gone :: proc(t: ^testing.T) {
	rand.reset(703)
	g: Game
	yard(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.satiety, p.stomach, p.x = 20, 0, 12
	g.clock.hours = DEEP_WINTER_HOURS
	append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Dried_Berries, dropped_hours = g.clock.hours})
	for _ in 0 ..< 10 {
		if eat_from_ground(&g, p) {break}
		testing.expect(t, pursue_food(&g, p), "heading for the store")
	}
	testing.expect_value(t, p.stomach, f32(FOOD_STOMACH))
}

@(test)
a_forager_with_nothing_to_haul_lays_in_berries :: proc(t: ^testing.T) {
	rand.reset(704)
	g: Game
	yard(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.role = .Forager
	target := HAUL_TARGET
	for raw in ([?]Item{.Fiber, .Stone, .Stick}) {
		for _ in 0 ..< target[raw] {append(&g.ground_items, Ground_Item{x = 5, y = 5, item = raw, dropped_hours = g.clock.hours})}
	}
	g.cells[5 * g.width + 9] = .Bush
	g.bushes[5 * g.width + 9] = Bush{food = 15, max_food = 15, health = BUSH_MAX_HEALTH} // berries to spare
	set_start_time(&g)
	for _ in 0 ..< 40 {pursue_forager(&g, p)}
	_, drying := store_count(&g)
	testing.expect(t, drying >= 2, "berries set out to dry at the stockpile")
}

@(test)
the_firekeeper_dries_meat_when_there_is_no_fire :: proc(t: ^testing.T) {
	rand.reset(705)
	g: Game
	yard(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.role = .Firekeeper
	g.cells[5 * g.width + 6] = .Fire_Pit // built, cold, and warm weather: no reason to light it
	set_start_time(&g)
	g.clock.hours += 12 // midday
	append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Fish_Filet, dropped_hours = g.clock.hours})
	testing.expect(t, pursue_firekeeper(&g, p), "busy")
	_, drying := store_count(&g)
	testing.expect_value(t, drying, 1)
}

@(test)
the_firekeeper_puts_down_idle_tools_to_lay_in_berries :: proc(t: ^testing.T) {
	rand.reset(708)
	g: Game
	yard(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.role = .Firekeeper
	p.hands[0], p.hands[1] = .Cooking_Stick, .Fire_Drill
	g.cells[5 * g.width + 6] = .Fire_Pit // cold, in warm weather
	g.cells[5 * g.width + 9] = .Bush
	g.bushes[5 * g.width + 9] = Bush{food = 15, max_food = 15, health = BUSH_MAX_HEALTH}
	set_start_time(&g)
	g.clock.hours += 12
	testing.expect(t, !pursue_firekeeper(&g, p), "no fire wanted, nothing to cook")
	for _ in 0 ..< 40 {gather_for_store(&g, p)}
	_, drying := store_count(&g)
	testing.expect(t, drying >= 2, "berries set out to dry")
	testing.expect(t, stock_of(&g, .Fire_Drill) + stock_of(&g, .Cooking_Stick) >= 1, "a tool left at the stockpile")
}

@(test)
a_firepit_built_on_a_rack_moves_it_aside :: proc(t: ^testing.T) {
	rand.reset(709)
	g: Game
	yard(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	for d in DIRS {
		if d.x == 1 && d.y == 0 {continue}
		g.cells[(5 + d.y) * g.width + 5 + d.x] = .Tree // only east is open, and the rack stands there
	}
	clear(&g.ground_items)
	append(&g.ground_items, Ground_Item{x = 6, y = 5, item = .Drying_Rack})
	append(&g.ground_items, Ground_Item{x = 6, y = 5, item = .Drying, loaded = .Food})
	for _ in 0 ..< FIRE_PIT_STONES {append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Stone})}
	for _ in 0 ..< FIRE_PIT_STICKS {append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Stick})}
	testing.expect(t, build_fire_pit(&g, p), "built")
	testing.expect_value(t, terrain_at(&g, 6, 5), Terrain.Fire_Pit)
	testing.expect_value(t, on_rack(&g, 5, 5), 1)
	testing.expect_value(t, have_count(&g, p^, .Drying_Rack), 1)
}

@(test)
dried_food_in_hand_is_eaten :: proc(t: ^testing.T) {
	p := fresh(0, 50, 100)
	p.hand_count = DEFAULT_HANDS
	p.hands[1] = .Dried_Meat
	testing.expect(t, eat_food(&p), "ate it")
	testing.expect_value(t, p.stomach, f32(DRIED_MEAT_STOMACH))
	testing.expect_value(t, p.hands[1], Item.None)
}
