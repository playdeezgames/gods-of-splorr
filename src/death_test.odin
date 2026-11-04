#+build !js
package gods

import "core:testing"

@(test)
starvation_is_blamed_for_a_starved_person :: proc(t: ^testing.T) {
	p := fresh(0, 0, 5)
	step_vitals(&p, 10)
	testing.expect_value(t, p.health, f32(0))
	testing.expect_value(t, death_cause(p, false), Death_Cause.Starvation)
}

@(test)
cold_and_heat_are_told_apart :: proc(t: ^testing.T) {
	cold := fresh(0, 50, 5)
	step_thermal(&cold, -20, 0, 200)
	testing.expect_value(t, death_cause(cold, false), Death_Cause.Cold)
	hot := fresh(0, 50, 5)
	step_thermal(&hot, 45, 0, 200)
	testing.expect_value(t, death_cause(hot, false), Death_Cause.Heat)
}

@(test)
the_biggest_harm_gets_the_blame :: proc(t: ^testing.T) {
	p := fresh(0, 50, 100)
	p.harm[.Poison], p.harm[.Cold], p.harm[.Starvation] = 20, 60, 10
	testing.expect_value(t, death_cause(p, false), Death_Cause.Cold)
}

@(test)
old_age_and_smiting_are_recorded :: proc(t: ^testing.T) {
	p := fresh(0, 50, 100)
	testing.expect_value(t, death_cause(p, true), Death_Cause.Old_Age)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	kill_person(&g, 0)
	testing.expect_value(t, g.deaths[.Smitten], 1)
	testing.expect_value(t, g.corpses[0].cause, Death_Cause.Smitten)
}

@(test)
only_the_first_person_builds_the_fire :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect(t, fire_builder(&g, g.people[0]), "first person")
	testing.expect(t, !fire_builder(&g, g.people[1]), "the others")
}
