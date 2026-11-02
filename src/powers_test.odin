#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(test)
faith_regrows_with_game_time_up_to_the_cap :: proc(t: ^testing.T) {
	rand.reset(21)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.faith = 0
	g.clock.hours += 10
	update_faith(&g)
	testing.expect(t, abs(g.faith - 10 * FAITH_PER_HOUR) < 1e-3, "10 hours of faith")
	g.clock.hours += 1000
	update_faith(&g)
	testing.expect_value(t, g.faith, MAX_FAITH)
}

@(test)
manna_drops_food_on_open_ground_for_a_price :: proc(t: ^testing.T) {
	rand.reset(22)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.cursor_x, g.cursor_y = g.people[0].x, g.people[0].y // people stand on open ground
	g.faith = 25
	testing.expect(t, use_power(&g, .Manna), "affordable on open ground")
	testing.expect_value(t, g.faith, 15)
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].item, Item.Food)
	g.faith = POWER_COSTS[.Manna] - 1
	testing.expect(t, !use_power(&g, .Manna), "cannot afford")
	testing.expect_value(t, len(g.ground_items), 1)
}

@(test)
manna_needs_open_ground :: proc(t: ^testing.T) {
	rand.reset(23)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.cells[0] = .Pond
	g.cursor_x, g.cursor_y = 0, 0
	g.faith = MAX_FAITH
	testing.expect(t, !use_power(&g, .Manna), "not on a pond")
	testing.expect_value(t, g.faith, MAX_FAITH)
}

@(test)
smite_kills_the_person_under_the_cursor :: proc(t: ^testing.T) {
	rand.reset(24)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.faith = MAX_FAITH
	victim := g.people[2]
	g.cursor_x, g.cursor_y = victim.x, victim.y
	testing.expect(t, use_power(&g, .Smite), "smote")
	testing.expect_value(t, len(g.people), START_PEOPLE - 1)
	testing.expect_value(t, len(g.corpses), 1)
	testing.expect_value(t, g.corpses[0].x, victim.x)
	testing.expect_value(t, g.faith, MAX_FAITH - POWER_COSTS[.Smite])
	testing.expect(t, !use_power(&g, .Smite), "nobody left there")
	testing.expect_value(t, g.faith, MAX_FAITH - POWER_COSTS[.Smite])
}

@(test)
no_powers_after_game_over :: proc(t: ^testing.T) {
	rand.reset(25)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.cursor_x, g.cursor_y = g.people[0].x, g.people[0].y
	for len(g.people) > 0 {kill_person(&g, 0)}
	g.faith = MAX_FAITH
	testing.expect(t, !use_power(&g, .Manna), "the game is over")
}

@(test)
snake_needs_a_free_cell_and_a_price :: proc(t: ^testing.T) {
	rand.reset(26)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.cursor_x, g.cursor_y = g.people[0].x, g.people[0].y
	g.faith = MAX_FAITH
	testing.expect(t, !use_power(&g, .Snake), "a person is standing there")
	for y in 0 ..< g.height { // find some open ground with nobody on it
		for x in 0 ..< g.width {
			if can_enter(&g, x, y) {g.cursor_x, g.cursor_y = x, y}
		}
	}
	testing.expect(t, use_power(&g, .Snake), "free ground")
	testing.expect_value(t, len(g.snakes), 1)
	testing.expect_value(t, g.faith, MAX_FAITH - POWER_COSTS[.Snake])
	testing.expect(t, !use_power(&g, .Snake), "already a snake there")
}

@(test)
smite_bush_scorches_a_bush_to_dirt :: proc(t: ^testing.T) {
	rand.reset(81)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.faith = MAX_FAITH
	g.cells[0] = .Bush
	g.bushes[0] = Bush{food = 3, max_food = 5}
	g.cursor_x, g.cursor_y = 0, 0
	testing.expect(t, use_power(&g, .Smite_Bush), "smote the bush")
	testing.expect_value(t, terrain_at(&g, 0, 0), Terrain.Dirt)
	testing.expect_value(t, g.bushes[0], Bush{})
	testing.expect_value(t, g.faith, MAX_FAITH - POWER_COSTS[.Smite_Bush])
	testing.expect(t, !use_power(&g, .Smite_Bush), "no bush left")
}

@(test)
miracle_bush_grows_on_open_ground_for_a_price :: proc(t: ^testing.T) {
	rand.reset(82)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.faith = MAX_FAITH
	g.cells[5] = .Stone_Field
	g.stone[5] = 9
	g.cursor_x, g.cursor_y = 5, 0
	testing.expect(t, use_power(&g, .Miracle_Bush), "created")
	b, ok := bush_at(&g, 5, 0)
	testing.expect(t, ok && b.miracle, "a miracle bush")
	testing.expect_value(t, b.food, f32(MIRACLE_MAX_FOOD))
	testing.expect_value(t, g.stone[5], f32(0))
	testing.expect_value(t, g.faith, MAX_FAITH - POWER_COSTS[.Miracle_Bush])
	g.faith = MAX_FAITH
	testing.expect(t, !use_power(&g, .Miracle_Bush), "already a bush, not open ground")
	g.cells[6] = .Pond
	g.cursor_x = 6
	testing.expect(t, !use_power(&g, .Miracle_Bush), "not on a pond")
	g.cells[7] = .Grass
	g.cursor_x = 7
	g.people[0].x, g.people[0].y = 7, 0
	testing.expect(t, !use_power(&g, .Miracle_Bush), "not on a person")
}

// A six-hour stretch of the calendar where every sample of the berry growth factor satisfies ok.
@(private = "file")
find_window :: proc(g: ^Game, ok: proc(factor: f32) -> bool) -> f64 {
	for h := 0.0; h < 24 * 360; h += 1 {
		all := true
		for k in 0 ..< 6 {
			c := g.clock
			c.hours = h + f64(k) + 0.5
			all &&= ok(berry_growth_factor(temperature_c(c, g.cfg)))
		}
		if all {return h}
	}
	return -1
}

@(private = "file")
two_bushes :: proc(g: ^Game, from: f64) {
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	g.cells[0], g.cells[1] = .Bush, .Bush
	g.bushes[0] = Bush{food = 0, max_food = 20, miracle = true}
	g.bushes[1] = Bush{food = 0, max_food = 20}
	g.clock.hours = from + 6
	g.bushes_updated_hours = from
}

@(test)
miracle_bush_bears_in_the_cold :: proc(t: ^testing.T) {
	rand.reset(83)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	from := find_window(&g, proc(f: f32) -> bool {return f == 0})
	testing.expect(t, from >= 0, "the calendar has a cold stretch")
	two_bushes(&g, from)
	update_bushes(&g)
	testing.expect_value(t, g.bushes[1].food, f32(0))
	testing.expect(t, g.bushes[0].food > 0, "the miracle bush still grows")
}

@(test)
miracle_bush_grows_faster_than_an_ordinary_one :: proc(t: ^testing.T) {
	rand.reset(84)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	from := find_window(&g, proc(f: f32) -> bool {return f > 0.5})
	testing.expect(t, from >= 0, "the calendar has a warm stretch")
	two_bushes(&g, from)
	update_bushes(&g)
	testing.expect(t, g.bushes[0].food > 2 * g.bushes[1].food, "much faster")
	testing.expect(t, g.bushes[1].food > 0, "ordinary bushes grow when warm")
}
