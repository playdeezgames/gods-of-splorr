package gods

import "core:math/rand"

// World sizes planned: 32, 64, 128. Only 32 is in use so far.
START_PEOPLE :: 5
WORLD_SIZE :: 32

DEFAULT_ZOOM :: 15 // cells across the visible square
MIN_ZOOM :: 5

Terrain :: enum u8 {
	Grass,
	Tree,
	Bush,
	Pond,
	Stone_Field,
	Dirt,
	Fire_Pit, // built by people; nobody can walk on it
}

TERRAIN_NAMES := [Terrain]string {
	.Grass = "Grass",
	.Tree  = "Tree",
	.Bush  = "Bush",
	.Pond  = "Pond",
	.Stone_Field = "Stone field",
	.Dirt  = "Dirt",
	.Fire_Pit = "Fire pit",
}

TERRAIN_WEIGHTS := [Terrain]int {
	.Grass = 100,
	.Tree  = 10,
	.Bush  = 5,
	.Pond  = 1,
	.Stone_Field = 3, // between pond and bush
	.Dirt  = 0, // only appears when a stone field is used up
	.Fire_Pit = 0, // only people build these
}

Game :: struct {
	width:            int,
	height:           int,
	cells:            []Terrain,
	cursor_x:         int,
	cursor_y:         int,
	cam_x:            int,
	cam_y:            int,
	zoom:             int, // cells across the visible square, before the world's own size limits it
	view_w:           int, // cells visible across and down: the zoom, or the whole world if that is smaller
	view_h:           int,
	following:        int, // id of the person the view follows, or 0
	next_person_id:   int,
	deaths:           [Death_Cause]int, // how many people have died of each cause
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
	stockpile_x:      int, // the cell where the tribe keeps its things; see roles.odin
	stockpile_y:      int,
	lit:              []bool, // parallel to cells; whether the Fire_Pit there is burning
	fire_updated_hours: f64,
	fish:             []f32, // parallel to cells; fish left where the cell is a Pond
	fuel:             []f32, // parallel to cells; sticks' worth of fuel where the cell is a Fire_Pit
	reeds:            []f32, // parallel to cells; reeds left where the cell is a Pond
	stone:            []f32, // parallel to cells; stone left where the cell is a Stone_Field
	terrain_updated_hours: f64,
	ground_items:     [dynamic]Ground_Item, // things people have dropped
	snakes:           [dynamic]Snake,
	rabbits:          [dynamic]Rabbit,
	next_rabbit_hours: f64, // when a rabbit may next wander in to a nearly empty world
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

// Worlds need not be square; a screen-sized one (15 by 15 cells) is handy for testing.
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
	g.reeds = make([]f32, width * height)
	g.fuel = make([]f32, width * height)
	g.lit = make([]bool, width * height)
	g.fish = make([]f32, width * height)
	g.fire_updated_hours = g.clock.hours
	for t, i in g.cells {
		if t == .Bush {g.bushes[i] = roll_bush()}
		if t == .Stone_Field {g.stone[i] = STONE_FIELD_AMOUNT}
		if t == .Grass {g.fiber[i] = FIBER_PER_GRASS}
		if t == .Tree {g.sticks[i] = STICKS_PER_TREE}
		if t == .Pond {g.reeds[i], g.fish[i] = REEDS_PER_POND, FISH_PER_POND}
	}
	spawn_person(g, .Male) // one of each sex guaranteed, the rest random
	spawn_person(g, .Female)
	for _ in 2 ..< START_PEOPLE {
		spawn_person(g, rand.int_max(2) == 0 ? .Male : .Female)
	}
	if len(g.people) > 0 {g.stockpile_x, g.stockpile_y = g.people[0].x, g.people[0].y}
	populate_rabbits(g)
	assign_roles(g)
	g.cursor_x = width / 2
	g.cursor_y = height / 2
	if len(g.people) > 0 { // start by looking at the first person
		g.cursor_x, g.cursor_y = g.people[0].x, g.people[0].y
	}
	g.cam_x, g.cam_y = 0, 0
	g.zoom = DEFAULT_ZOOM
	fit_view(g)
	follow_cursor(g)
	set_start_time(g)
}

// Open the game in spring and point every "last updated" stamp at that moment. Needs the calendar config.
set_start_time :: proc(g: ^Game) {
	h := hours_per_year(g.cfg) * START_YEAR_FRACTION + START_HOUR
	g.clock.hours = h
	g.bushes_updated_hours, g.vitals_updated_hours, g.terrain_updated_hours = h, h, h
	g.faith_updated_hours, g.fire_updated_hours = h, h
	for &p in g.people {p.next_move_hours = next_step_time(h)}
}

game_destroy :: proc(g: ^Game) {
	delete(g.cells)
	delete(g.people)
	delete(g.corpses)
	delete(g.bushes)
	delete(g.stone)
	delete(g.fiber)
	delete(g.sticks)
	delete(g.reeds)
	delete(g.fuel)
	delete(g.lit)
	delete(g.fish)
	delete(g.ground_items)
	delete(g.snakes)
	delete(g.rabbits)
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
	set_start_time(g)
}

in_bounds :: proc(g: ^Game, x, y: int) -> bool {
	return x >= 0 && y >= 0 && x < g.width && y < g.height
}

terrain_at :: proc(g: ^Game, x, y: int) -> Terrain {
	return g.cells[y * g.width + x]
}

// The visible square is `zoom` cells across, or the whole world if that is smaller.
fit_view :: proc(g: ^Game) {
	g.zoom = clamp(g.zoom, MIN_ZOOM, max(g.width, g.height, MIN_ZOOM))
	g.view_w, g.view_h = min(g.zoom, g.width), min(g.zoom, g.height)
	clamp_camera(g)
}

clamp_camera :: proc(g: ^Game) {
	g.cam_x = clamp(g.cam_x, 0, max(g.width - g.view_w, 0))
	g.cam_y = clamp(g.cam_y, 0, max(g.height - g.view_h, 0))
}

// Put the view's centre on (x, y), as near as the edges of the world allow.
center_camera :: proc(g: ^Game, x, y: int) {
	g.cam_x, g.cam_y = x - g.view_w / 2, y - g.view_h / 2
	clamp_camera(g)
}

// Zoom in (negative) or out (positive) by delta cells, keeping the middle of the view where it was.
zoom_view :: proc(g: ^Game, delta: int) {
	cx, cy := g.cam_x + g.view_w / 2, g.cam_y + g.view_h / 2
	g.zoom += delta
	fit_view(g)
	center_camera(g, cx, cy)
	g.cursor_x = clamp(g.cursor_x, g.cam_x, g.cam_x + g.view_w - 1)
	g.cursor_y = clamp(g.cursor_y, g.cam_y, g.cam_y + g.view_h - 1)
}

// Look at one person: the view stays centred on them until the follow is dropped (or they die).
follow_person :: proc(g: ^Game, id: int) {
	g.following = id
}

// The one action button (a gamepad's A): begin again after a loss, cast the armed miracle at the
// cursor, or else follow the person under the cursor, or stop following them.
act_at_cursor :: proc(g: ^Game) {
	if game_over(g) {
		restart_game(g)
	} else if power, ok := g.armed.?; ok {
		use_power(g, power)
	} else if i := person_at(g, g.cursor_x, g.cursor_y); i >= 0 {
		follow_person(g, 0 if g.following == g.people[i].id else g.people[i].id)
	}
}

// Index of the person being followed, or -1 (and the follow is dropped if they are gone).
followed_index :: proc(g: ^Game) -> int {
	if g.following == 0 {return -1}
	for p, i in g.people {
		if p.id == g.following {return i}
	}
	g.following = 0
	return -1
}

// Keep the view on the followed person; called every frame.
update_follow :: proc(g: ^Game) {
	if i := followed_index(g); i >= 0 { // the cursor rides on them too, so a miracle or the action button acts on them
		center_camera(g, g.people[i].x, g.people[i].y)
		g.cursor_x, g.cursor_y = g.people[i].x, g.people[i].y
	}
}
// Scroll the camera the minimum amount that keeps the cursor on screen.
follow_cursor :: proc(g: ^Game) {
	if g.cursor_x < g.cam_x {g.cam_x = g.cursor_x}
	if g.cursor_x >= g.cam_x + g.view_w {g.cam_x = g.cursor_x - g.view_w + 1}
	if g.cursor_y < g.cam_y {g.cam_y = g.cursor_y}
	if g.cursor_y >= g.cam_y + g.view_h {g.cam_y = g.cursor_y - g.view_h + 1}
	clamp_camera(g)
}

move_cursor :: proc(g: ^Game, dx, dy: int) {
	g.following = 0 // steering the cursor means looking where you like
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
	g.following = 0
	g.cam_x += dx
	g.cam_y += dy
	clamp_camera(g)
	g.cursor_x = clamp(g.cursor_x, g.cam_x, g.cam_x + g.view_w - 1)
	g.cursor_y = clamp(g.cursor_y, g.cam_y, g.cam_y + g.view_h - 1)
}
