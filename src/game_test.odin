#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(test)
generation_fills_every_cell :: proc(t: ^testing.T) {
	rand.reset(1)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect_value(t, len(g.cells), WORLD_SIZE * WORLD_SIZE)
	counts: [Terrain]int
	for c in g.cells {
		counts[c] += 1
	}
	testing.expect(t, counts[.Grass] > counts[.Tree], "grass should outnumber trees")
	testing.expect(t, counts[.Tree] > counts[.Pond], "trees should outnumber ponds")
}

@(test)
weights_are_respected :: proc(t: ^testing.T) {
	rand.reset(7)
	counts: [Terrain]int
	for _ in 0 ..< 119000 {
		counts[pick_weighted(TERRAIN_WEIGHTS)] += 1
	}
	// expected: 100000 / 10000 / 5000 / 1000 / 3000
	testing.expect(t, abs(counts[.Grass] - 100000) < 1500, "grass weight")
	testing.expect(t, abs(counts[.Tree] - 10000) < 500, "tree weight")
	testing.expect(t, abs(counts[.Bush] - 5000) < 400, "bush weight")
	testing.expect(t, abs(counts[.Pond] - 1000) < 200, "pond weight")
	testing.expect(t, abs(counts[.Stone_Field] - 3000) < 300, "stone field weight")
	testing.expect_value(t, counts[.Dirt], 0)
}

@(test)
cursor_clamps_and_camera_follows :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	move_cursor(&g, -100, -100)
	testing.expect_value(t, g.cursor_x, 0)
	testing.expect_value(t, g.cam_x, 0)
	move_cursor(&g, 100, 100)
	testing.expect_value(t, g.cursor_x, WORLD_SIZE - 1)
	testing.expect_value(t, g.cam_x, WORLD_SIZE - DEFAULT_ZOOM)
	testing.expect_value(t, g.cam_y, WORLD_SIZE - DEFAULT_ZOOM)
}

@(test)
hover_and_pan :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	pan_camera(&g, 100, 100)
	hover_cell(&g, 0, 0)
	testing.expect_value(t, g.cursor_x, WORLD_SIZE - DEFAULT_ZOOM)
	testing.expect_value(t, g.cursor_y, WORLD_SIZE - DEFAULT_ZOOM)
	pan_camera(&g, -100, -100)
	testing.expect(t, g.cursor_x < DEFAULT_ZOOM && g.cursor_y < DEFAULT_ZOOM, "cursor stays on screen")
}

@(test)
screen_sized_world_works :: proc(t: ^testing.T) {
	rand.reset(4)
	g: Game
	game_init_rect(&g, DEFAULT_ZOOM, DEFAULT_ZOOM)
	defer game_destroy(&g)
	testing.expect_value(t, len(g.cells), DEFAULT_ZOOM * DEFAULT_ZOOM)
	testing.expect_value(t, len(g.bushes), DEFAULT_ZOOM * DEFAULT_ZOOM)
	testing.expect_value(t, len(g.people), START_PEOPLE)
	testing.expect(t, in_bounds(&g, DEFAULT_ZOOM - 1, DEFAULT_ZOOM - 1) && !in_bounds(&g, DEFAULT_ZOOM, 0) && !in_bounds(&g, 0, DEFAULT_ZOOM), "bounds")
	move_cursor(&g, 100, 100)
	testing.expect_value(t, g.cursor_x, DEFAULT_ZOOM - 1)
	testing.expect_value(t, g.cursor_y, DEFAULT_ZOOM - 1)
	testing.expect_value(t, g.cam_x, 0)
	testing.expect_value(t, g.cam_y, 0)
	// a non-square world indexes by its own width
	game_destroy(&g)
	g = {}
	game_init_rect(&g, 7, 3)
	testing.expect_value(t, len(g.cells), 21)
	g.cells[2 * 7 + 6] = .Tree
	testing.expect_value(t, terrain_at(&g, 6, 2), Terrain.Tree)
}

@(test)
game_is_over_only_when_nobody_is_left :: proc(t: ^testing.T) {
	rand.reset(5)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect(t, !game_over(&g), "people alive")
	for len(g.people) > 1 {
		ordered_remove(&g.people, 0)
		testing.expect(t, !game_over(&g), "one person is enough")
	}
	ordered_remove(&g.people, 0)
	testing.expect(t, game_over(&g), "no people left")
}

@(test)
starvation_of_everyone_ends_the_game_and_restart_begins_again :: proc(t: ^testing.T) {
	rand.reset(6)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.cfg.days_per_month = 7
	for &p in g.people {p.health = 1}
	g.clock.hours += 100
	update_vitals(&g)
	testing.expect(t, game_over(&g), "everyone starved")
	testing.expect_value(t, len(g.corpses), START_PEOPLE)

	restart_game(&g)
	testing.expect(t, !game_over(&g), "fresh people")
	testing.expect_value(t, len(g.people), START_PEOPLE)
	testing.expect_value(t, len(g.corpses), 0)
	testing.expect_value(t, g.cfg.days_per_month, 7)
	testing.expect_value(t, g.clock.hours, hours_per_year(g.cfg) * START_YEAR_FRACTION + START_HOUR)
}
