package gods

import "core:math/rand"

// World sizes planned: 32, 64, 128. Only 32 is in use so far.
START_PEOPLE :: 5
WORLD_SIZE :: 32

VIEW_W :: 20
VIEW_H :: 15

Terrain :: enum u8 {
	Grass,
	Tree,
	Bush,
	Pond,
	Stone_Field,
	Dirt,
}

TERRAIN_NAMES := [Terrain]string {
	.Grass = "Grass",
	.Tree  = "Tree",
	.Bush  = "Bush",
	.Pond  = "Pond",
	.Stone_Field = "Stone field",
	.Dirt  = "Dirt",
}

TERRAIN_WEIGHTS := [Terrain]int {
	.Grass = 100,
	.Tree  = 10,
	.Bush  = 5,
	.Pond  = 1,
	.Stone_Field = 3, // between pond and bush
	.Dirt  = 0, // only appears when a stone field is used up
}

Game :: struct {
	width:            int,
	height:           int,
	cells:            []Terrain,
	cursor_x:         int,
	cursor_y:         int,
	cam_x:            int,
	cam_y:            int,
	cfg:              Calendar_Config,
	clock:            Clock,
	people:           [dynamic]Person,
	bushes:           []Bush, // parallel to cells; only meaningful where the cell is a Bush
	corpses:           [dynamic]Corpse,
	vitals_updated_hours: f64,
	bush_growth_per_hour: f32,
	bushes_updated_hours: f64,
	sticks:           []f32, // parallel to cells; sticks left where the cell is a Tree
	fiber:            []f32, // parallel to cells; plant fiber left where the cell is Grass
	stone:            []f32, // parallel to cells; stone left where the cell is a Stone_Field
	terrain_updated_hours: f64,
	ground_items:     [dynamic]Ground_Item, // things people have dropped
	snakes:           [dynamic]Snake,
	armed:            Maybe(Power), // a click on the map casts this power there
	faith:            f32, // the god's power to act; see powers.odin
	faith_updated_hours: f64,
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
	game_init_rect(g, size, size)
}

// Worlds need not be square; a screen-sized one (VIEW_W by VIEW_H) is handy for testing.
game_init_rect :: proc(g: ^Game, width, height: int) {
	g.width, g.height = width, height
	g.cfg = normalize_config(DEFAULT_CALENDAR)
	g.clock = clock_init()
	g.cells = make([]Terrain, width * height)
	for i in 0 ..< len(g.cells) {
		g.cells[i] = pick_weighted(TERRAIN_WEIGHTS)
	}
	g.bushes = make([]Bush, width * height)
	g.bush_growth_per_hour = BUSH_GROWTH_PER_HOUR
	g.bushes_updated_hours = g.clock.hours
	g.vitals_updated_hours = g.clock.hours
	g.terrain_updated_hours = g.clock.hours
	g.faith, g.faith_updated_hours = START_FAITH, g.clock.hours
	g.stone = make([]f32, width * height)
	g.fiber = make([]f32, width * height)
	g.sticks = make([]f32, width * height)
	for t, i in g.cells {
		if t == .Bush {g.bushes[i] = roll_bush()}
		if t == .Stone_Field {g.stone[i] = STONE_FIELD_AMOUNT}
		if t == .Grass {g.fiber[i] = FIBER_PER_GRASS}
		if t == .Tree {g.sticks[i] = STICKS_PER_TREE}
	}
	spawn_person(g, .Male) // one of each sex guaranteed, the rest random
	spawn_person(g, .Female)
	for _ in 2 ..< START_PEOPLE {
		spawn_person(g, rand.int_max(2) == 0 ? .Male : .Female)
	}
	g.cursor_x = width / 2
	g.cursor_y = height / 2
	if len(g.people) > 0 { // start by looking at the first person
		g.cursor_x, g.cursor_y = g.people[0].x, g.people[0].y
	}
	g.cam_x, g.cam_y = 0, 0
	follow_cursor(g)
}

game_destroy :: proc(g: ^Game) {
	delete(g.cells)
	delete(g.people)
	delete(g.corpses)
	delete(g.bushes)
	delete(g.stone)
	delete(g.fiber)
	delete(g.sticks)
	delete(g.ground_items)
	delete(g.snakes)
}

// The only way to lose: nobody is left alive.
game_over :: proc(g: ^Game) -> bool {
	return len(g.people) == 0
}

// Replace the world with a fresh one of the same size, keeping the calendar settings.
restart_game :: proc(g: ^Game) {
	width, height, cfg := g.width, g.height, g.cfg
	game_destroy(g)
	g^ = {}
	game_init_rect(g, width, height)
	g.cfg = cfg
}

in_bounds :: proc(g: ^Game, x, y: int) -> bool {
	return x >= 0 && y >= 0 && x < g.width && y < g.height
}

terrain_at :: proc(g: ^Game, x, y: int) -> Terrain {
	return g.cells[y * g.width + x]
}

clamp_camera :: proc(g: ^Game) {
	g.cam_x = clamp(g.cam_x, 0, max(g.width - VIEW_W, 0))
	g.cam_y = clamp(g.cam_y, 0, max(g.height - VIEW_H, 0))
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
	g.cursor_x = clamp(g.cursor_x + dx, 0, g.width - 1)
	g.cursor_y = clamp(g.cursor_y + dy, 0, g.height - 1)
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
