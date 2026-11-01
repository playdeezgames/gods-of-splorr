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
bushes_grow_at_the_rate_then_cap :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	i := first_bush(&g)
	testing.expect(t, i >= 0, "need a bush")
	g.bushes[i] = Bush{food = 1, max_food = 10}
	g.bush_growth_per_hour = 0.5
	g.clock.hours += 4
	update_bushes(&g)
	testing.expect(t, abs(g.bushes[i].food - 3) < 1e-4, "1 + 0.5 * 4 hours")
	g.clock.hours += 1000
	update_bushes(&g)
	testing.expect_value(t, g.bushes[i].food, f32(10))
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
