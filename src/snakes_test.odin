#+build !js
package gods

import "core:math/rand"
import "core:testing"

// A 5x1 strip of grass with nothing on it, so snake behaviour is easy to follow.
@(private = "file")
strip :: proc(g: ^Game) {
	game_init_rect(g, 5, 1)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	clear(&g.people)
}

@(private = "file")
add_person :: proc(g: ^Game, x, y: int) {
	append(&g.people, Person{x = x, y = y, health = MAX_HEALTH, satiety = MAX_SATIETY, stomach = 0, energy = MAX_ENERGY, sleep_hours = 8, hand_count = DEFAULT_HANDS, next_move_hours = 1e9})
}

@(test)
poison_drains_health_for_its_duration_only :: proc(t: ^testing.T) {
	p := Person{health = MAX_HEALTH, satiety = MAX_SATIETY, energy = MAX_ENERGY, sleep_hours = 8}
	poison_person(&p)
	testing.expect_value(t, p.poison_hours, f32(POISON_HOURS_PER_BITE))
	step_vitals(&p, 4)
	testing.expect(t, abs(p.health - (MAX_HEALTH - 4 * POISON_PER_HOUR)) < 1e-3, "4 hours of poison")
	step_vitals(&p, 8) // only the remaining 6 hours hurt
	testing.expect(t, abs(p.health - (MAX_HEALTH - POISON_HOURS_PER_BITE * POISON_PER_HOUR)) < 1e-3, "poison ran out")
	testing.expect_value(t, p.poison_hours, f32(0))
}

@(test)
bites_stack_up_to_a_cap :: proc(t: ^testing.T) {
	p: Person
	for _ in 0 ..< 10 {poison_person(&p)}
	testing.expect_value(t, p.poison_hours, f32(MAX_POISON_HOURS))
}

@(test)
snake_closes_in_and_bites_an_adjacent_person :: proc(t: ^testing.T) {
	rand.reset(31)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 4, 0)
	testing.expect(t, spawn_snake(&g, 0, 0), "spawned")
	for _ in 0 ..< 200 {
		g.clock.hours += 0.05
		update_snakes(&g)
	}
	testing.expect_value(t, g.snakes[0].x, 3) // right next to the person, who blocks the way
	testing.expect(t, g.people[0].poison_hours > 0, "bitten")
}

@(test)
snakes_and_people_never_share_a_cell :: proc(t: ^testing.T) {
	rand.reset(32)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 2, 0)
	testing.expect(t, !spawn_snake(&g, 2, 0), "occupied by a person")
	testing.expect(t, spawn_snake(&g, 1, 0), "free")
	testing.expect(t, !spawn_snake(&g, 1, 0), "occupied by a snake")
	testing.expect(t, !can_enter(&g, 1, 0), "people cannot step onto a snake")
}

@(test)
snake_leaves_after_its_lifetime :: proc(t: ^testing.T) {
	rand.reset(33)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	spawn_snake(&g, 2, 0)
	g.clock.hours += SNAKE_LIFE_HOURS - 1
	update_snakes(&g)
	testing.expect_value(t, len(g.snakes), 1)
	g.clock.hours += 2
	update_snakes(&g)
	testing.expect_value(t, len(g.snakes), 0)
}

@(test)
snake_wanders_when_nobody_is_near :: proc(t: ^testing.T) {
	rand.reset(34)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	spawn_snake(&g, 2, 0)
	moved := false
	for _ in 0 ..< 100 {
		g.clock.hours += 0.2
		update_snakes(&g)
		testing.expect(t, in_bounds(&g, g.snakes[0].x, g.snakes[0].y), "stays in the world")
		if g.snakes[0].x != 2 {moved = true}
	}
	testing.expect(t, moved, "it moved")
}

@(test)
people_step_away_from_a_close_snake :: proc(t: ^testing.T) {
	rand.reset(35)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 2, 0)
	spawn_snake(&g, 1, 0)
	testing.expect(t, flee_snake(&g, &g.people[0]), "snake is close")
	testing.expect_value(t, g.people[0].x, 3)
}

@(test)
cornered_people_stand_still_and_distant_ones_ignore_snakes :: proc(t: ^testing.T) {
	rand.reset(36)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 4, 0)
	spawn_snake(&g, 3, 0)
	testing.expect(t, flee_snake(&g, &g.people[0]), "snake is close")
	testing.expect_value(t, g.people[0].x, 4) // nowhere to go

	clear(&g.snakes)
	spawn_snake(&g, 0, 0) // four cells away is out of range
	testing.expect(t, !flee_snake(&g, &g.people[0]), "too far to care")
	testing.expect_value(t, g.people[0].x, 4)
}

@(test)
fleeing_people_in_the_open_keep_out_of_reach :: proc(t: ^testing.T) {
	rand.reset(37)
	g: Game
	game_init_rect(&g, 9, 9)
	defer game_destroy(&g)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	clear(&g.people)
	add_person(&g, 4, 4)
	g.people[0].next_move_hours = 0
	spawn_snake(&g, 3, 4)
	g.snakes[0].next_move_hours = 1e9 // a snake that stays put
	for _ in 0 ..< 20 {
		g.clock.hours += 0.2
		update_people(&g)
	}
	p := g.people[0]
	testing.expect(t, max(abs(p.x - 3), abs(p.y - 4)) > 1, "never next to the snake")
}
