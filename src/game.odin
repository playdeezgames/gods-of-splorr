package gods

import "core:math/rand"

// World sizes planned: 32, 64, 128. Only 32 is in use so far.
WORLD_SIZE :: 32

VIEW_W :: 20
VIEW_H :: 15

Terrain :: enum u8 {
	Grass,
	Tree,
	Bush,
	Pond,
}

TERRAIN_NAMES := [Terrain]string {
	.Grass = "Grass",
	.Tree  = "Tree",
	.Bush  = "Bush",
	.Pond  = "Pond",
}

TERRAIN_WEIGHTS := [Terrain]int {
	.Grass = 100,
	.Tree  = 10,
	.Bush  = 5,
	.Pond  = 1,
}

Game :: struct {
	size:             int,
	cells:            []Terrain,
	cursor_x:         int,
	cursor_y:         int,
	cam_x:            int,
	cam_y:            int,
	cfg:              Calendar_Config,
	clock:            Clock,
	people:           [dynamic]Person,
}

pick_weighted :: proc(weights: [$E]int) -> E {
	total := 0
	for w in weights {
		total += w
	}
	roll := rand.int_max(total)
	for w, e in weights {
		if roll < w {
			return e
		}
		roll -= w
	}
	return E(0)
}

game_init :: proc(g: ^Game, size: int) {
	g.size = size
	g.cfg = normalize_config(DEFAULT_CALENDAR)
	g.clock = clock_init()
	g.cells = make([]Terrain, size * size)
	for i in 0 ..< len(g.cells) {
		g.cells[i] = pick_weighted(TERRAIN_WEIGHTS)
	}
	spawn_person(g, .Male)
	spawn_person(g, .Female)
	g.cursor_x = size / 2
	g.cursor_y = size / 2
	if len(g.people) > 0 { // start by looking at the first person
		g.cursor_x, g.cursor_y = g.people[0].x, g.people[0].y
	}
	g.cam_x, g.cam_y = 0, 0
	follow_cursor(g)
}

game_destroy :: proc(g: ^Game) {
	delete(g.cells)
	delete(g.people)
}

in_bounds :: proc(g: ^Game, x, y: int) -> bool {
	return x >= 0 && y >= 0 && x < g.size && y < g.size
}

terrain_at :: proc(g: ^Game, x, y: int) -> Terrain {
	return g.cells[y * g.size + x]
}

clamp_camera :: proc(g: ^Game) {
	g.cam_x = clamp(g.cam_x, 0, max(g.size - VIEW_W, 0))
	g.cam_y = clamp(g.cam_y, 0, max(g.size - VIEW_H, 0))
}

// Scroll the camera the minimum amount that keeps the cursor on screen.
follow_cursor :: proc(g: ^Game) {
	if g.cursor_x < g.cam_x {g.cam_x = g.cursor_x}
	if g.cursor_x >= g.cam_x + VIEW_W {g.cam_x = g.cursor_x - VIEW_W + 1}
	if g.cursor_y < g.cam_y {g.cam_y = g.cursor_y}
	if g.cursor_y >= g.cam_y + VIEW_H {g.cam_y = g.cursor_y - VIEW_H + 1}
	clamp_camera(g)
}

move_cursor :: proc(g: ^Game, dx, dy: int) {
	g.cursor_x = clamp(g.cursor_x + dx, 0, g.size - 1)
	g.cursor_y = clamp(g.cursor_y + dy, 0, g.size - 1)
	follow_cursor(g)
}

// Cell offsets are relative to the camera (what the mouse sees).
hover_cell :: proc(g: ^Game, view_x, view_y: int) {
	x, y := g.cam_x + view_x, g.cam_y + view_y
	if in_bounds(g, x, y) {
		g.cursor_x, g.cursor_y = x, y
	}
}

// Pan the camera without moving the cursor off its screen position, so the
// cell under a stationary mouse is the one the cursor lands on.
pan_camera :: proc(g: ^Game, dx, dy: int) {
	g.cam_x += dx
	g.cam_y += dy
	clamp_camera(g)
	g.cursor_x = clamp(g.cursor_x, g.cam_x, g.cam_x + VIEW_W - 1)
	g.cursor_y = clamp(g.cursor_y, g.cam_y, g.cam_y + VIEW_H - 1)
}
