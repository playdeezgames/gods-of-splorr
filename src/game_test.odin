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
	for _ in 0 ..< 116000 {
		counts[pick_weighted(TERRAIN_WEIGHTS)] += 1
	}
	// expected: 100000 / 10000 / 5000 / 1000
	testing.expect(t, abs(counts[.Grass] - 100000) < 1500, "grass weight")
	testing.expect(t, abs(counts[.Tree] - 10000) < 500, "tree weight")
	testing.expect(t, abs(counts[.Bush] - 5000) < 400, "bush weight")
	testing.expect(t, abs(counts[.Pond] - 1000) < 200, "pond weight")
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
	testing.expect_value(t, g.cam_x, WORLD_SIZE - VIEW_W)
	testing.expect_value(t, g.cam_y, WORLD_SIZE - VIEW_H)
}

@(test)
hover_and_pan :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	pan_camera(&g, 100, 100)
	hover_cell(&g, 0, 0)
	testing.expect_value(t, g.cursor_x, WORLD_SIZE - VIEW_W)
	testing.expect_value(t, g.cursor_y, WORLD_SIZE - VIEW_H)
	pan_camera(&g, -100, -100)
	testing.expect(t, g.cursor_x < VIEW_W && g.cursor_y < VIEW_H, "cursor stays on screen")
}

@(test)
screen_sized_world_works :: proc(t: ^testing.T) {
	rand.reset(4)
	g: Game
	game_init_rect(&g, VIEW_W, VIEW_H)
	defer game_destroy(&g)
	testing.expect_value(t, len(g.cells), VIEW_W * VIEW_H)
	testing.expect_value(t, len(g.bushes), VIEW_W * VIEW_H)
	testing.expect_value(t, len(g.people), START_PEOPLE)
	testing.expect(t, in_bounds(&g, VIEW_W - 1, VIEW_H - 1) && !in_bounds(&g, VIEW_W, 0) && !in_bounds(&g, 0, VIEW_H), "bounds")
	move_cursor(&g, 100, 100)
	testing.expect_value(t, g.cursor_x, VIEW_W - 1)
	testing.expect_value(t, g.cursor_y, VIEW_H - 1)
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
