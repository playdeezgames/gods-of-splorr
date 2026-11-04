#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(test)
comfortable_weather_changes_nothing :: proc(t: ^testing.T) {
	p := fresh(0, 50, 100)
	step_thermal(&p, 20, 0, 100)
	testing.expect_value(t, p.chill, f32(0))
	testing.expect_value(t, p.heat, f32(0))
	testing.expect_value(t, p.health, f32(100))
}

@(test)
cold_builds_chill_before_hypothermia :: proc(t: ^testing.T) {
	p := fresh(0, 50, 100)
	step_thermal(&p, -10, 0, 10) // 20 degrees under: 5 chill an hour, less 1 fought off by the body
	testing.expect(t, abs(p.chill - 40) < 1e-3, "chill builds")
	testing.expect_value(t, p.hypothermia, f32(0))
	testing.expect_value(t, p.health, f32(100))
	step_thermal(&p, -10, 0, 20) // full after 15 more hours, then 5 hours of hypothermia
	testing.expect_value(t, p.chill, f32(MAX_THERMAL))
	testing.expect(t, abs(p.hypothermia - 10) < 1e-3, "2 per hour once chill is full")
	testing.expect(t, p.health < 100, "hypothermia costs health")
}

@(test)
mild_cold_does_not_build_chill_and_a_sleeper_resists_more :: proc(t: ^testing.T) {
	p := fresh(0, 50, 100)
	step_thermal(&p, 7, 0, 10) // 3 under: 0.75 an hour, less than the body fights off
	testing.expect_value(t, p.chill, f32(0))
	p.chill = 50
	step_thermal(&p, 7, 0, 10) // and the chill it already has slowly drains
	testing.expect(t, abs(p.chill - 47.5) < 1e-3, "drains 0.25 an hour")
	awake, asleep := fresh(0, 50, 100), fresh(0, 50, 100)
	asleep.asleep = true
	step_thermal(&awake, 0, 0, 10) // 10 under: 2.5 an hour
	step_thermal(&asleep, 0, 0, 10)
	testing.expect(t, abs(awake.chill - 15) < 1e-3, "awake: 1.5 an hour")
	testing.expect(t, abs(asleep.chill - 5) < 1e-3, "asleep: 0.5 an hour")
}

@(test)
heat_builds_into_heat_stress :: proc(t: ^testing.T) {
	p := fresh(0, 50, 100)
	step_thermal(&p, 40, 0, 60) // 5 per hour: full in 20 hours, then 40 hours of stress
	testing.expect_value(t, p.heat, f32(MAX_THERMAL))
	testing.expect(t, abs(p.heat_stress - 80) < 1e-3, "2 per hour for 40 hours")
	testing.expect(t, p.health < 100, "heat stress costs health")
	testing.expect_value(t, p.chill, f32(0))
}

@(test)
chill_bleeds_faster_than_hypothermia :: proc(t: ^testing.T) {
	p := fresh(0, 50, 100)
	p.chill, p.hypothermia = MAX_THERMAL, 50
	step_thermal(&p, 20, 0, 10)
	testing.expect(t, abs(p.chill - 60) < 1e-3, "4 per hour")
	testing.expect(t, abs(p.hypothermia - 45) < 1e-3, "0.5 per hour")
	testing.expect(t, p.health < 100, "still hurting while it lingers")
}

@(test)
a_fire_keeps_the_cold_off :: proc(t: ^testing.T) {
	p := fresh(0, 50, 100)
	step_thermal(&p, 0, 15, 10) // 0 C air, 15 C of fire
	testing.expect_value(t, p.chill, f32(0))
}

@(test)
a_fire_makes_hot_weather_worse :: proc(t: ^testing.T) {
	a, b := fresh(0, 50, 100), fresh(0, 50, 100)
	step_thermal(&a, 28, 0, 10) // comfortable
	step_thermal(&b, 28, 15, 10) // 43 C beside a fire
	testing.expect_value(t, a.heat, f32(0))
	testing.expect(t, b.heat > 0, "the fire adds to the heat")
}

@(test)
fire_warmth_fades_with_distance :: proc(t: ^testing.T) {
	g: Game
	game_init_rect(&g, 10, 10)
	defer game_destroy(&g)
	g.cells[5 * g.width + 5] = .Fire_Pit
	testing.expect_value(t, fire_warmth_c(&g, 6, 5), 0.0) // cold pit
	g.lit[5 * g.width + 5] = true
	testing.expect_value(t, fire_warmth_c(&g, 6, 5), FIRE_WARMTH_C)
	testing.expect_value(t, fire_warmth_c(&g, 7, 6), FIRE_WARMTH_C / 2)
	testing.expect_value(t, fire_warmth_c(&g, 8, 5), 0.0)
}

@(test)
affliction_means_more_rest :: proc(t: ^testing.T) {
	healthy := Person{sleep_hours = 8}
	sick := Person{sleep_hours = 8, hypothermia = 100}
	testing.expect(t, energy_drain_per_hour(sick) > energy_drain_per_hour(healthy), "tires faster")
	testing.expect(t, energy_recover_per_hour(sick) < energy_recover_per_hour(healthy), "recovers slower")
}

@(test)
hypothermia_can_kill :: proc(t: ^testing.T) {
	p := fresh(0, 50, 10)
	step_thermal(&p, -20, 0, 200)
	testing.expect_value(t, p.health, f32(0))
}

@(test)
an_overheating_person_steps_away_from_a_fire :: proc(t: ^testing.T) {
	rand.reset(137)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	g.cells[10 * g.width + 10] = .Fire_Pit
	g.lit[10 * g.width + 10] = true
	p := &g.people[0]
	p.x, p.y, p.heat = 10, 11, 50
	here := fire_warmth_c(&g, p.x, p.y)
	testing.expect(t, avoid_fire_heat(&g, p), "moved")
	testing.expect(t, fire_warmth_c(&g, p.x, p.y) < here, "cooler")
	p.heat = 0
	x, y := p.x, p.y
	testing.expect(t, !avoid_fire_heat(&g, p), "comfortable people stay")
	testing.expect(t, p.x == x && p.y == y, "didn't move")
}

@(test)
a_chilled_person_goes_to_a_fire_and_stays_until_warm :: proc(t: ^testing.T) {
	rand.reset(142)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	g.cells[10 * g.width + 10] = .Fire_Pit
	g.lit[10 * g.width + 10] = true
	g.clock.hours = 3 // the small hours of a winter's day-zero: cold
	g.cfg.latitude = 60
	for i in 1 ..< len(g.people) {g.people[i].x, g.people[i].y = 30 + i % 2, 30 + i / 2}
	p := &g.people[0]
	p.role = .Forager
	p.x, p.y, p.chill, p.energy = 10, 18, 50, 80
	testing.expect(t, temperature_c(g.clock, g.cfg) < COLD_BELOW_C, "it is cold")
	for _ in 0 ..< 30 {
		if fire_warmth_c(&g, p.x, p.y) > 0 {break}
		testing.expect(t, seek_warmth(&g, p), "heading for the fire")
	}
	testing.expect(t, fire_warmth_c(&g, p.x, p.y) > 0, "reached its warmth")
	testing.expect(t, seek_warmth(&g, p), "stays while chilled")
	p.chill = 0
	testing.expect(t, !seek_warmth(&g, p), "warm again: back to work")
	p.chill, p.x, p.y = 5, 10, 18 // only a little chilled and far away
	testing.expect(t, !seek_warmth(&g, p), "not bothered yet")
	p.role = .Firekeeper
	p.chill = 90
	testing.expect(t, !seek_warmth(&g, p), "the firekeeper tends the fire instead")
}
