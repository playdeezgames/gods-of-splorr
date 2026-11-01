package gods

import "core:math"
import "core:math/rand"

// Each bush holds some berries (food), up to its own maximum, and regrows them over game time.
Bush :: struct {
	food:     f32,
	max_food: f32, // randomly rolled per bush when the world is generated
}

BUSH_MAX_FOOD_MIN :: 5
BUSH_MAX_FOOD_MAX :: 20
BUSH_GROWTH_PER_HOUR :: 0.25 // food gained per game hour; 6 per game day

roll_bush :: proc() -> Bush {
	max_food := math.round(f32(BUSH_MAX_FOOD_MIN) + rand.float32() * f32(BUSH_MAX_FOOD_MAX - BUSH_MAX_FOOD_MIN))
	return Bush{food = rand.float32() * max_food, max_food = max_food}
}

// Grow every bush by the game time elapsed since the last call.
update_bushes :: proc(g: ^Game) {
	elapsed := f32(g.clock.hours - g.bushes_updated_hours)
	g.bushes_updated_hours = g.clock.hours
	if elapsed <= 0 {return}
	for t, i in g.cells {
		if t != .Bush {continue}
		b := &g.bushes[i]
		b.food = min(b.food + g.bush_growth_per_hour * elapsed, b.max_food)
	}
}

bush_at :: proc(g: ^Game, x, y: int) -> (Bush, bool) {
	if terrain_at(g, x, y) != .Bush {return {}, false}
	return g.bushes[y * g.size + x], true
}
