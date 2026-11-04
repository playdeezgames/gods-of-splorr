#+build !js
package gods

import "core:math/rand"
import "core:testing"

// An all-grass world with one able person at (5, 5) and no rabbits.
@(private = "file")
meadow :: proc(g: ^Game, w := 12, h := 12) {
	game_init_rect(g, w, h)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	for &f in g.fiber {f = 0}
	clear(&g.people)
	clear(&g.rabbits)
	append(&g.people, Person{id = 1, x = 5, y = 5, health = MAX_HEALTH, satiety = MAX_SATIETY, stomach = 50, energy = MAX_ENERGY, sleep_hours = 8, hand_count = DEFAULT_HANDS, crafting = MAX_SKILL, foraging = MAX_SKILL, ranged = MAX_SKILL, cooking = MAX_SKILL, next_move_hours = 1e9})
}

@(test)
a_new_world_has_rabbits_on_grass :: proc(t: ^testing.T) {
	rand.reset(601)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect_value(t, len(g.rabbits), RABBITS_PER_1024_CELLS)
	for r in g.rabbits {testing.expect_value(t, terrain_at(&g, r.x, r.y), Terrain.Grass)}
}

@(test)
a_rabbit_bolts_from_a_person :: proc(t: ^testing.T) {
	rand.reset(602)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	r := Rabbit{x = 6, y = 5}
	hop_away(&g, &r, 5, 5)
	testing.expect(t, abs(r.x - 5) + abs(r.y - 5) > 1, "farther from the person")
	testing.expect(t, rabbit_threat(&g, r) == 0, "still sees them")
}

@(test)
rabbits_breed_in_warm_weather_up_to_a_cap :: proc(t: ^testing.T) {
	rand.reset(603)
	g: Game
	meadow(&g, 32, 32)
	defer game_destroy(&g)
	clear(&g.people)
	for &f in g.fiber {f = FIBER_PER_GRASS}
	set_start_time(&g) // late spring
	spawn_rabbit(&g, 10, 10)
	spawn_rabbit(&g, 20, 20)
	for _ in 0 ..< 24 * 60 {
		g.clock.hours += 1
		update_rabbits(&g)
	}
	testing.expect(t, len(g.rabbits) > 2, "they bred")
	testing.expect(t, len(g.rabbits) <= rabbit_cap(&g, RABBIT_MAX_PER_1024_CELLS), "but not past the cap")
}

@(test)
no_kits_in_the_cold_but_one_wanders_in_to_an_empty_world :: proc(t: ^testing.T) {
	rand.reset(604)
	g: Game
	meadow(&g, 32, 32)
	defer game_destroy(&g)
	clear(&g.people)
	for &f in g.fiber {f = FIBER_PER_GRASS}
	g.clock.hours = 0 // midwinter
	spawn_rabbit(&g, 10, 10)
	spawn_rabbit(&g, 20, 20)
	for _ in 0 ..< 24 * 10 {
		g.clock.hours += 1
		update_rabbits(&g)
	}
	testing.expect_value(t, len(g.rabbits), 2)
	clear(&g.rabbits)
	for _ in 0 ..< 24 {
		g.clock.hours += 1
		update_rabbits(&g)
	}
	testing.expect_value(t, len(g.rabbits), 1)
}

@(test)
a_spear_kills_a_rabbit_and_a_sharp_stone_skins_it :: proc(t: ^testing.T) {
	rand.reset(605)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Spear
	append(&g.rabbits, Rabbit{x = 6, y = 5, dodge = 0, next_move_hours = 1e9})
	for _ in 0 ..< 20 {
		if len(g.rabbits) == 0 {break}
		testing.expect(t, hunt_rabbit(&g, p), "thrusting")
	}
	testing.expect_value(t, len(g.rabbits), 0)
	testing.expect_value(t, have_count(&g, p^, .Rabbit_Corpse), 1)
	testing.expect(t, !skin_rabbit(&g, p), "no sharp stone")
	p.hands[1] = .Sharp_Stone
	testing.expect(t, skin_rabbit(&g, p), "skinned")
	testing.expect_value(t, have_count(&g, p^, .Rabbit_Corpse), 0)
	testing.expect_value(t, have_count(&g, p^, .Rabbit_Meat), 1)
	testing.expect_value(t, have_count(&g, p^, .Fur), 1) // a master's cut never ruins it
	testing.expect_value(t, p.wear[1], 1)
}

@(test)
a_hunter_closes_in_on_a_far_rabbit :: proc(t: ^testing.T) {
	rand.reset(606)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Spear
	append(&g.rabbits, Rabbit{x = 10, y = 5, next_move_hours = 1e9})
	testing.expect(t, hunt_rabbit(&g, p), "after it")
	testing.expect_value(t, p.x, 6)
	g.rabbits[0].x = 5 + HUNT_RABBIT_RANGE + 2
	g.width = 30 // not walked to: just out of range
	testing.expect(t, !hunt_rabbit(&g, p), "too far to bother")
}

@(test)
fur_and_twine_make_a_coat_that_is_put_on :: proc(t: ^testing.T) {
	rand.reset(607)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Twine
	for _ in 0 ..< COAT_FUR - 1 {append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Fur, dropped_hours = g.clock.hours})}
	testing.expect(t, !craft_coat(&g, p), "one fur short")
	append(&g.ground_items, Ground_Item{x = 5, y = 6, item = .Fur, dropped_hours = g.clock.hours})
	testing.expect(t, craft_coat(&g, p), "sewn")
	testing.expect(t, p.coat, "worn at once")
	testing.expect_value(t, have_count(&g, p^, .Fur), 0)
	testing.expect_value(t, have_count(&g, p^, .Fur_Coat), 0)
}

@(test)
a_coat_keeps_the_chill_off :: proc(t: ^testing.T) {
	bare, coated := fresh(0, 50, 100), fresh(0, 50, 100)
	coated.coat = true
	step_thermal(&bare, -5, 0, 10)
	step_thermal(&coated, -5, 0, 10)
	testing.expect(t, bare.chill > 0, "the cold bites")
	testing.expect_value(t, coated.chill, f32(0))
	hot_bare, hot_coated := fresh(0, 50, 100), fresh(0, 50, 100)
	hot_coated.coat = true
	step_thermal(&hot_bare, 40, 0, 10)
	step_thermal(&hot_coated, 40, 0, 10)
	testing.expect_value(t, hot_coated.heat, hot_bare.heat) // and is opened up in the heat
}

@(test)
people_put_on_a_coat_lying_near_and_leave_it_when_they_die :: proc(t: ^testing.T) {
	rand.reset(608)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	g.clock.hours = 3 // a winter night
	p := &g.people[0]
	append(&g.ground_items, Ground_Item{x = 9, y = 5, item = .Fur_Coat, dropped_hours = g.clock.hours})
	for _ in 0 ..< 10 {
		if p.coat {break}
		testing.expect(t, put_on_coat(&g, p), "going for the coat")
	}
	testing.expect(t, p.coat, "wearing it")
	testing.expect(t, !put_on_coat(&g, p), "one is enough")
	x, y := p.x, p.y
	kill_person(&g, 0)
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].item, Item.Fur_Coat)
	testing.expect(t, g.ground_items[0].x == x && g.ground_items[0].y == y, "where they fell")
}

@(test)
rabbit_meat_cooks :: proc(t: ^testing.T) {
	rand.reset(609)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	g.cells[5 * g.width + 6] = .Fire_Pit
	g.lit[5 * g.width + 6] = true
	p := &g.people[0]
	p.hands[0] = .Cooking_Stick
	append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Rabbit_Meat, dropped_hours = g.clock.hours})
	testing.expect(t, load_stick(&g, p), "skewered")
	testing.expect_value(t, p.loaded[0], Item.Rabbit_Meat)
	testing.expect(t, cook_on_fire(&g, p), "cooked")
	testing.expect_value(t, p.loaded[0], Item.Cooked_Rabbit_Meat)
}

@(test)
the_toolmaker_skins_kills_and_sews_coats_at_the_stockpile :: proc(t: ^testing.T) {
	rand.reset(610)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	g.stockpile_x, g.stockpile_y = 5, 5
	p := &g.people[0]
	p.role = .Toolmaker
	p.hands[0] = .Sharp_Stone
	for item in ([?]Item{.Net, .Fire_Drill, .Cooking_Stick, .Twine}) {
		append(&g.ground_items, Ground_Item{x = 5, y = 5, item = item, dropped_hours = g.clock.hours})
	}
	for _ in 0 ..< COAT_FUR {
		append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Rabbit_Corpse, dropped_hours = g.clock.hours})
	}
	for _ in 0 ..< COAT_FUR {testing.expect(t, pursue_toolmaker(&g, p), "skinning")}
	testing.expect_value(t, stock_of(&g, .Fur), COAT_FUR)
	testing.expect_value(t, stock_of(&g, .Rabbit_Meat), COAT_FUR)
	testing.expect(t, pursue_toolmaker(&g, p), "sewing")
	testing.expect(t, p.coat, "the toolmaker wears the first")
	testing.expect_value(t, stock_of(&g, .Fur), 0)
}

@(test)
the_hunter_brings_a_kill_home :: proc(t: ^testing.T) {
	rand.reset(611)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	g.stockpile_x, g.stockpile_y = 1, 1
	p := &g.people[0]
	p.role = .Hunter
	p.hands[0] = .Spear
	append(&g.ground_items, Ground_Item{x = 6, y = 5, item = .Rabbit_Corpse, dropped_hours = g.clock.hours})
	for _ in 0 ..< 20 {
		if stock_of(&g, .Rabbit_Corpse) > 0 {break}
		testing.expect(t, pursue_hunter(&g, p), "carrying it")
	}
	testing.expect_value(t, stock_of(&g, .Rabbit_Corpse), 1)
	testing.expect(t, holds(p^, .Spear), "kept the spear")
}

@(test)
the_hunter_leaves_a_breeding_stock :: proc(t: ^testing.T) {
	rand.reset(613)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	g.stockpile_x, g.stockpile_y = 5, 5
	p := &g.people[0]
	p.role = .Hunter
	p.hands[0] = .Spear
	stock := rabbit_cap(&g, RABBITS_PER_1024_CELLS)
	for i in 0 ..< stock {append(&g.rabbits, Rabbit{x = 7 + i, y = 5, next_move_hours = 1e9})}
	pursue_hunter(&g, p)
	testing.expect_value(t, len(g.rabbits), stock)
	testing.expect(t, p.x == 5 && p.y == 5, "no chase after the breeding stock")
	append(&g.rabbits, Rabbit{x = 5, y = 6, next_move_hours = 1e9})
	for _ in 0 ..< 20 {
		if len(g.rabbits) == stock {break}
		pursue_hunter(&g, p)
	}
	testing.expect_value(t, len(g.rabbits), stock) // one more than the stock is fair game
}

@(test)
a_hungry_rabbit_grazes_fiber_and_hops_to_more :: proc(t: ^testing.T) {
	rand.reset(612)
	g: Game
	meadow(&g)
	defer game_destroy(&g)
	r := Rabbit{x = 2, y = 2, fullness = 10}
	g.fiber[2 * g.width + 2] = 1
	testing.expect(t, graze(&g, &r), "nibbled")
	testing.expect(t, abs(g.fiber[2 * g.width + 2] - (1 - RABBIT_BITE)) < 1e-4, "fiber eaten")
	testing.expect(t, abs(r.fullness - (10 + RABBIT_BITE_HOURS)) < 1e-4, "fuller")
	g.fiber[2 * g.width + 2] = RABBIT_BITE / 2 // the last of it
	testing.expect(t, graze(&g, &r), "nibbled the last")
	testing.expect_value(t, terrain_at(&g, 2, 2), Terrain.Dirt)
	g.fiber[2 * g.width + 3] = 2
	testing.expect(t, hop_to_grass(&g, &r), "off to fresh grass")
	testing.expect(t, r.x == 3 && r.y == 2, "to the grassiest neighbour")
	r.fullness = RABBIT_FULL_HOURS
	testing.expect(t, !graze(&g, &r), "full")
}

@(test)
a_rabbit_with_no_grass_starves_to_a_corpse :: proc(t: ^testing.T) {
	rand.reset(613)
	g: Game
	meadow(&g) // no fiber anywhere
	defer game_destroy(&g)
	g.next_rabbit_hours = 1e9 // and none wander in
	spawn_rabbit(&g, 2, 2)
	for _ in 0 ..< int(RABBIT_FULL_HOURS) + 2 {
		g.clock.hours += 1
		update_rabbits(&g)
	}
	testing.expect_value(t, len(g.rabbits), 0)
	n := 0
	for it in g.ground_items {
		if it.item == .Rabbit_Corpse {n += 1}
	}
	testing.expect_value(t, n, 1)
}
