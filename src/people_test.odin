#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(test)
two_people_start_on_grass :: proc(t: ^testing.T) {
	rand.reset(3)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect_value(t, len(g.people), 2)
	testing.expect_value(t, g.people[0].sex, Sex.Male)
	testing.expect_value(t, g.people[1].sex, Sex.Female)
	for p in g.people {
		testing.expect_value(t, terrain_at(&g, p.x, p.y), Terrain.Grass)
	}
	testing.expect(t, g.people[0].x != g.people[1].x || g.people[0].y != g.people[1].y, "distinct cells")
}

@(test)
people_only_ever_walk_on_grass :: proc(t: ^testing.T) {
	rand.reset(11)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	start := [2][2]int{{g.people[0].x, g.people[0].y}, {g.people[1].x, g.people[1].y}}
	moved := false
	for _ in 0 ..< 5000 {
		g.clock.hours += 0.1
		update_people(&g)
		for p in g.people {
			testing.expect(t, in_bounds(&g, p.x, p.y), "in bounds")
			testing.expect_value(t, terrain_at(&g, p.x, p.y), Terrain.Grass)
		}
		testing.expect(t, g.people[0].x != g.people[1].x || g.people[0].y != g.people[1].y, "never share a cell")
	}
	for p, i in g.people {
		if p.x != start[i].x || p.y != start[i].y {moved = true}
	}
	testing.expect(t, moved, "people wander")
}

@(test)
only_grass_is_walkable :: proc(t: ^testing.T) {
	for terrain in Terrain {
		testing.expect_value(t, walkable(terrain), terrain == .Grass)
	}
}

@(test)
cannot_walk_into_blocked_cells :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.cells[0] = .Tree
	testing.expect(t, !can_enter(&g, 0, 0), "tree blocks")
	g.cells[1] = .Grass
	g.people[0].x, g.people[0].y = 1, 0
	testing.expect(t, !can_enter(&g, 1, 0), "occupied blocks")
	testing.expect(t, !can_enter(&g, -1, 0), "edge blocks")
}

luminance :: proc(c: [3]f32) -> f32 {
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
}

@(test)
more_melanin_is_darker_and_always_brown :: proc(t: ^testing.T) {
	prev := luminance(skin_color(0))
	for i in 1 ..= 10 {
		c := skin_color(f32(i) / 10)
		testing.expect(t, luminance(c) < prev, "darker with more melanin")
		testing.expect(t, c.r > c.g && c.g > c.b, "always a shade of brown")
		prev = luminance(c)
	}
	testing.expect_value(t, skin_color(-5), skin_color(0))
	testing.expect_value(t, skin_color(5), skin_color(1))
}

@(test)
people_get_melanin_in_range_with_variety :: proc(t: ^testing.T) {
	rand.reset(5)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	lo, hi: f32 = 1, 0
	for _ in 0 ..< 200 {
		m := random_melanin()
		testing.expect(t, m >= 0 && m <= 1, "in range")
		lo, hi = min(lo, m), max(hi, m)
	}
	testing.expect(t, lo < 0.2 && hi > 0.8, "both light and dark occur")
	for p in g.people {
		testing.expect(t, p.melanin >= 0 && p.melanin <= 1, "person melanin in range")
	}
}

fresh :: proc(stomach, satiety, health: f32) -> Person {
	return Person{stomach = stomach, satiety = satiety, health = health}
}

@(test)
digesting_moves_stomach_into_satiety :: proc(t: ^testing.T) {
	p := fresh(30, 50, 100)
	step_vitals(&p, 2) // 5/hour for 2 hours
	testing.expect_value(t, p.stomach, f32(20))
	testing.expect_value(t, p.satiety, f32(60))
	testing.expect_value(t, p.health, f32(100))
}

@(test)
empty_stomach_drains_satiety_then_health :: proc(t: ^testing.T) {
	p := fresh(0, 10, 100)
	step_vitals(&p, 2)
	testing.expect(t, abs(p.satiety - 7) < 1e-4, "1.5/hour")
	testing.expect_value(t, p.health, f32(100))
	p = fresh(0, 0, 100)
	step_vitals(&p, 10)
	testing.expect_value(t, p.satiety, f32(0))
	testing.expect(t, abs(p.health - 90) < 1e-4, "1/hour once satiety is 0")
}

@(test)
one_big_step_crosses_every_boundary_exactly :: proc(t: ^testing.T) {
	// 10 stomach lasts 2h (satiety 0 -> 10), 10 satiety lasts 6.67h, then 5h of starving
	p := fresh(10, 0, 100)
	step_vitals(&p, 2 + 10.0 / HUNGER_PER_HOUR + 5)
	testing.expect_value(t, p.stomach, f32(0))
	testing.expect_value(t, p.satiety, f32(0))
	testing.expect(t, abs(p.health - 95) < 1e-3, "5 hours of starvation")
	// same total time in tiny steps agrees
	q := fresh(10, 0, 100)
	for _ in 0 ..< 1000 {
		step_vitals(&q, (2 + 10.0 / HUNGER_PER_HOUR + 5) / 1000)
	}
	testing.expect(t, abs(q.health - p.health) < 0.05, "step size does not matter")
}

@(test)
satiety_and_stats_stay_in_bounds :: proc(t: ^testing.T) {
	p := fresh(100, 95, 100)
	step_vitals(&p, 20)
	testing.expect_value(t, p.satiety, f32(MAX_SATIETY))
	testing.expect_value(t, p.stomach, f32(0))
	p = fresh(0, 0, 1)
	step_vitals(&p, 100)
	testing.expect_value(t, p.health, f32(0))
}

@(test)
starved_person_becomes_a_corpse :: proc(t: ^testing.T) {
	rand.reset(9)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.people[0].stomach, g.people[0].satiety, g.people[0].health = 0, 0, 1
	x, y, mel := g.people[0].x, g.people[0].y, g.people[0].melanin
	g.clock.hours += 2
	update_vitals(&g)
	testing.expect_value(t, len(g.people), 1)
	testing.expect_value(t, len(g.corpses), 1)
	testing.expect_value(t, g.people[0].sex, Sex.Female)
	c := g.corpses[0]
	testing.expect(t, c.x == x && c.y == y && c.melanin == mel && c.sex == .Male, "corpse stays where they fell")
	testing.expect(t, corpse_at(&g, x, y) == 0, "findable")
}

// A world with a bush at (5,5) and the first person standing at (4,5).
gather_setup :: proc(g: ^Game, food: f32) {
	for i in 0 ..< len(g.cells) {
		g.cells[i] = .Grass
	}
	g.cells[5 * g.width + 5] = .Bush
	g.bushes[5 * g.width + 5] = Bush{food = food, max_food = 20}
	g.people[0].x, g.people[0].y = 4, 5
	g.people[0].hands = {}
}

@(test)
gathering_takes_from_bush_into_a_hand :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 3)
	p := &g.people[0]
	testing.expect_value(t, p.hand_count, 2)
	testing.expect(t, gather_food(&g, p, 5, 5), "first gather")
	testing.expect_value(t, g.bushes[5 * g.width + 5].food, f32(2))
	testing.expect_value(t, p.hands[0], Item.Food)
	testing.expect(t, gather_food(&g, p, 5, 5), "second gather")
	testing.expect_value(t, held_count(p^), 2)
	testing.expect(t, !gather_food(&g, p, 5, 5), "hands are full")
	testing.expect_value(t, g.bushes[5 * g.width + 5].food, f32(1))
}

@(test)
gathering_needs_adjacency_and_a_whole_food :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 3)
	p := &g.people[0]
	p.x = 3 // two cells away
	testing.expect(t, !gather_food(&g, p, 5, 5), "too far")
	p.x, p.y = 4, 4 // diagonal
	testing.expect(t, !gather_food(&g, p, 5, 5), "diagonal is not adjacent")
	p.x, p.y = 4, 5
	g.bushes[5 * g.width + 5].food = 0.9
	testing.expect(t, !gather_food(&g, p, 5, 5), "less than one food")
	testing.expect_value(t, held_count(p^), 0)
	testing.expect(t, !gather_food(&g, p, 4, 5), "not a bush")
}

@(test)
hand_count_limits_what_can_be_carried :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 10)
	p := &g.people[0]
	p.hand_count = 3
	for _ in 0 ..< 5 {
		gather_food(&g, p, 5, 5)
	}
	testing.expect_value(t, held_count(p^), 3)
	testing.expect_value(t, g.bushes[5 * g.width + 5].food, f32(7))
}

@(test)
people_next_to_bushes_gather_on_their_own :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	gather_setup(&g, 10)
	g.people[0].next_move_hours = g.clock.hours
	g.people[1].next_move_hours = g.clock.hours + 1000
	g.clock.hours += 0.01
	update_people(&g)
	testing.expect_value(t, held_count(g.people[0]), 1)
	testing.expect_value(t, g.people[0].x, 4) // gathering used the action, so no step
}
