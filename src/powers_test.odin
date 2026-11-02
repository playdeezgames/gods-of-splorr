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
