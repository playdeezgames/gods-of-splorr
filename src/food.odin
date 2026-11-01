package gods

import "core:math"
import "core:math/rand"

// Each bush holds some berries (food), up to its own maximum, and regrows them over game time.
Bush :: struct {
	food:     f32,
	max_food: f32, // randomly rolled per bush when the world is generated
}

BUSH_MAX_FOOD_MIN :: 2.5
BUSH_MAX_FOOD_MAX :: 10
BUSH_GROWTH_PER_HOUR :: 0.125 // food gained per game hour at the ideal temperature

// Berries only grow between a lowest and a highest temperature (degrees C), fastest at the ideal.
BERRY_MIN_TEMP_C :: 5.0
BERRY_IDEAL_TEMP_C :: 22.0
BERRY_MAX_TEMP_C :: 38.0

// Fraction of the full growth rate at a temperature: 0 at or beyond the limits, rising
// linearly to 1 at the ideal.
berry_growth_factor :: proc(temp_c: f64) -> f32 {
	if temp_c <= BERRY_MIN_TEMP_C || temp_c >= BERRY_MAX_TEMP_C {return 0}
	if temp_c <= BERRY_IDEAL_TEMP_C {
		return f32((temp_c - BERRY_MIN_TEMP_C) / (BERRY_IDEAL_TEMP_C - BERRY_MIN_TEMP_C))
	}
	return f32((BERRY_MAX_TEMP_C - temp_c) / (BERRY_MAX_TEMP_C - BERRY_IDEAL_TEMP_C))
}

BUSH_GROWTH_STEP_HOURS :: 1.0 // temperature is sampled this often so big time jumps stay accurate

roll_bush :: proc() -> Bush {
	max_food := math.round(2 * (f32(BUSH_MAX_FOOD_MIN) + rand.float32() * f32(BUSH_MAX_FOOD_MAX - BUSH_MAX_FOOD_MIN))) / 2
	return Bush{food = rand.float32() * max_food, max_food = max_food}
}

// Grow every bush by the game time elapsed since the last call, at a rate that follows
// the temperature (sampled at the middle of each step).
update_bushes :: proc(g: ^Game) {
	from := g.bushes_updated_hours
	g.bushes_updated_hours = g.clock.hours
	for from < g.clock.hours {
		step := min(BUSH_GROWTH_STEP_HOURS, g.clock.hours - from)
		sample := g.clock
		sample.hours = from + step / 2
		gain := g.bush_growth_per_hour * berry_growth_factor(temperature_c(sample, g.cfg)) * f32(step)
		from += step
		if gain <= 0 {continue}
		for t, i in g.cells {
			if t != .Bush {continue}
			b := &g.bushes[i]
			b.food = min(b.food + gain, b.max_food)
		}
	}
}

bush_at :: proc(g: ^Game, x, y: int) -> (Bush, bool) {
	if terrain_at(g, x, y) != .Bush {return {}, false}
	return g.bushes[y * g.width + x], true
}
