#+build !js
package gods

import "core:math/rand"
import "core:testing"

first_bush :: proc(g: ^Game) -> int {
	for t, i in g.cells {
		if t == .Bush {return i}
	}
	return -1
}

@(test)
bush_maximums_are_random_and_in_range :: proc(t: ^testing.T) {
	rand.reset(2)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	lo, hi: f32 = 1000, 0
	count := 0
	for cell, i in g.cells {
		if cell != .Bush {continue}
		b := g.bushes[i]
		count += 1
		testing.expect(t, b.max_food >= BUSH_MAX_FOOD_MIN && b.max_food <= BUSH_MAX_FOOD_MAX, "max in range")
		testing.expect(t, b.food >= 0 && b.food <= b.max_food, "starts within its max")
		lo, hi = min(lo, b.max_food), max(hi, b.max_food)
	}
	testing.expect(t, count > 0, "world has bushes")
	testing.expect(t, hi > lo, "maximums vary")
}

@(test)
berry_growth_follows_temperature :: proc(t: ^testing.T) {
	testing.expect_value(t, berry_growth_factor(BERRY_MIN_TEMP_C), f32(0))
	testing.expect_value(t, berry_growth_factor(BERRY_MIN_TEMP_C - 10), f32(0))
	testing.expect_value(t, berry_growth_factor(BERRY_MAX_TEMP_C), f32(0))
	testing.expect_value(t, berry_growth_factor(BERRY_MAX_TEMP_C + 10), f32(0))
	testing.expect_value(t, berry_growth_factor(BERRY_IDEAL_TEMP_C), f32(1))
	mid_cold := (BERRY_MIN_TEMP_C + BERRY_IDEAL_TEMP_C) / 2
	mid_hot := (BERRY_MAX_TEMP_C + BERRY_IDEAL_TEMP_C) / 2
	testing.expect(t, abs(berry_growth_factor(mid_cold) - 0.5) < 1e-5, "halfway up")
	testing.expect(t, abs(berry_growth_factor(mid_hot) - 0.5) < 1e-5, "halfway down")
}

@(test)
bushes_grow_with_the_temperature_then_cap :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	i := first_bush(&g)
	testing.expect(t, i >= 0, "need a bush")
	g.bushes[i] = Bush{food = 1, max_food = 10}
	g.bush_growth_per_hour = 0.5
	expected: f32 = 1
	for h in 0 ..< 4 { // one-hour steps, sampled at the middle of each
		sample := g.clock
		sample.hours += f64(h) + 0.5
		expected += 0.5 * berry_growth_factor(temperature_c(sample, g.cfg))
	}
	g.clock.hours += 4
	update_bushes(&g)
	testing.expect(t, expected > 1, "it is warm enough to grow at the start")
	testing.expect(t, abs(g.bushes[i].food - expected) < 1e-4, "growth scaled by temperature")
	g.clock.hours += 5000
	update_bushes(&g)
	testing.expect_value(t, g.bushes[i].food, f32(10))
}

@(test)
bushes_do_not_grow_in_the_cold :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.cfg.latitude = 90 // polar: freezing all year
	i := first_bush(&g)
	g.bushes[i] = Bush{food = 1, max_food = 10}
	g.clock.hours, g.bushes_updated_hours = 0, 0 // the start of the year, before spring
	g.clock.hours += 24 * 30
	update_bushes(&g)
	testing.expect_value(t, g.bushes[i].food, f32(1))
}

@(test)
no_time_no_growth_and_only_bushes_grow :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	i := first_bush(&g)
	g.bushes[i] = Bush{food = 0, max_food = 10}
	update_bushes(&g) // clock has not moved
	testing.expect_value(t, g.bushes[i].food, f32(0))
	for cell, j in g.cells {
		if cell == .Grass {g.bushes[j] = Bush{food = 0, max_food = 10}; break}
	}
	g.clock.hours += 10
	update_bushes(&g)
	for cell, j in g.cells {
		if cell != .Bush {
			testing.expect_value(t, g.bushes[j].food, f32(0))
		}
	}
}
