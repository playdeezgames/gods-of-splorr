#+build js
package gods

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:time"

TILE_PX :: 12
SCALE :: 4
CELL :: TILE_PX * SCALE // on-screen cell size in canvas pixels
CANVAS_W :: VIEW_W * CELL
CANVAS_H :: VIEW_H * CELL

MINI_CELL :: 3
MINI_MARGIN :: 8

foreign import host "env"
@(default_calling_convention = "contextless")
foreign host {
	clear_canvas :: proc(r, g, b: f32) ---
	fill_rect :: proc(x, y, w, h: f32, r, g, b, a: f32) ---
	stroke_rect :: proc(x, y, w, h: f32, r, g, b: f32, line: f32) ---
	draw_tile :: proc(col, row: i32, x, y, size: f32) ---
	draw_tile_tinted :: proc(col, row: i32, x, y, size: f32, r, g, b: f32) ---
	set_info :: proc(ptr: [^]byte, n: i32) ---
	set_clock :: proc(ptr: [^]byte, n: i32) ---
}

// Urizen sheet coordinates (col, row).
Tile :: struct {
	col, row: i32,
}

GRASS_TILE :: Tile{15, 5}
TERRAIN_TILES := [Terrain]Tile {
	.Grass = {15, 5},
	.Tree  = {0, 8},
	.Bush  = {18, 9},
	.Pond  = {16, 6},
}

PERSON_TILES := [Sex]Tile {
	.Male   = {104, 0},
	.Female = {112, 46},
}

CORPSE_TILE :: Tile{201, 0}
CORPSE_SHADE :: 0.55 // corpses are their owner's skin colour, dimmed

MINI_COLORS := [Terrain][3]f32 {
	.Grass = {0.10, 0.35, 0.10},
	.Tree  = {0.15, 0.80, 0.15},
	.Bush  = {0.55, 0.65, 0.10},
	.Pond  = {0.10, 0.60, 1.00},
}

game: Game
ctx: runtime.Context

main :: proc() {
	ctx = context
	rand.reset(u64(time.now()._nsec))
	game_init(&game, WORLD_SIZE)
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	free_all(context.temp_allocator)
	advance_clock(&game.clock, game.cfg, min(dt, 0.25))
	update_people(&game)
	update_bushes(&game)
	update_vitals(&game)
	draw()
	return true
}

draw :: proc() {
	clear_canvas(0.03, 0.07, 0.03)
	for vy in 0 ..< VIEW_H {
		for vx in 0 ..< VIEW_W {
			x, y := game.cam_x + vx, game.cam_y + vy
			if !in_bounds(&game, x, y) {continue}
			px, py := f32(vx * CELL), f32(vy * CELL)
			t := terrain_at(&game, x, y)
			if t != .Grass {
				draw_tile(GRASS_TILE.col, GRASS_TILE.row, px, py, CELL)
			}
			tile := TERRAIN_TILES[t]
			draw_tile(tile.col, tile.row, px, py, CELL)
			if b, ok := bush_at(&game, x, y); ok { // berry bar: how full this bush is
				fill_rect(px + 4, py + CELL - 8, CELL - 8, 4, 0, 0, 0, 0.6)
				fill_rect(px + 4, py + CELL - 8, (CELL - 8) * b.food / b.max_food, 4, 0.9, 0.15, 0.25, 1)
			}
		}
	}

	for c in game.corpses {
		vx, vy := c.x - game.cam_x, c.y - game.cam_y
		if vx < 0 || vy < 0 || vx >= VIEW_W || vy >= VIEW_H {continue}
		col := skin_color(c.melanin) * CORPSE_SHADE
		draw_tile_tinted(CORPSE_TILE.col, CORPSE_TILE.row, f32(vx * CELL), f32(vy * CELL), CELL, col.r, col.g, col.b)
	}
	for p in game.people {
		vx, vy := p.x - game.cam_x, p.y - game.cam_y
		if vx < 0 || vy < 0 || vx >= VIEW_W || vy >= VIEW_H {continue}
		tile, c := PERSON_TILES[p.sex], skin_color(p.melanin)
		draw_tile_tinted(tile.col, tile.row, f32(vx * CELL), f32(vy * CELL), CELL, c.r, c.g, c.b)
		for h in 0 ..< p.hand_count { // a red berry for each hand that holds food
			if p.hands[h] == .Food {
				fill_rect(f32(vx * CELL + 2 + h * 12), f32(vy * CELL + CELL - 10), 8, 8, 0.9, 0.15, 0.25, 1)
			}
		}
	}

	tint := ambient_overlay(sun_sin(game.clock, game.cfg))
	if tint[3] > 0 {
		fill_rect(0, 0, CANVAS_W, CANVAS_H, tint.r, tint.g, tint.b, tint.a)
	}

	cx := f32((game.cursor_x - game.cam_x) * CELL)
	cy := f32((game.cursor_y - game.cam_y) * CELL)
	stroke_rect(cx, cy, CELL, CELL, 1, 1, 0.2, 3)

	draw_minimap()

	buf: [160]byte
	t := terrain_at(&game, game.cursor_x, game.cursor_y)
	s := fmt.bprintf(buf[:], "(%d, %d)  %s", game.cursor_x, game.cursor_y, TERRAIN_NAMES[t])
	if b, ok := bush_at(&game, game.cursor_x, game.cursor_y); ok {
		s = fmt.bprintf(buf[:], "(%d, %d)  Bush  -  Food %.1f / %.0f", game.cursor_x, game.cursor_y, b.food, b.max_food)
	}
	if i := person_at(&game, game.cursor_x, game.cursor_y); i >= 0 {
		p := game.people[i]
		s = fmt.bprintf(
			buf[:],
			"(%d, %d)  Person (%s, melanin %.2f)  Health %.0f  Satiety %.0f  Stomach %.0f  Hands %d/%d",
			game.cursor_x, game.cursor_y, SEX_NAMES[p.sex], p.melanin, p.health, p.satiety, p.stomach, held_count(p), p.hand_count,
		)
	} else if i := corpse_at(&game, game.cursor_x, game.cursor_y); i >= 0 {
		c := game.corpses[i]
		s = fmt.bprintf(buf[:], "(%d, %d)  Corpse (%s, melanin %.2f)", game.cursor_x, game.cursor_y, SEX_NAMES[c.sex], c.melanin)
	}
	set_info(raw_data(s), i32(len(s)))

	d := date_of(game.clock, game.cfg)
	speed := "paused"
	sbuf: [16]byte
	if !game.clock.paused {
		speed = fmt.bprintf(sbuf[:], "%gx", SPEEDS[game.clock.speed_index])
	}
	cbuf: [160]byte
	cs := fmt.bprintf(
		cbuf[:],
		"Year %d, Month %d, Day %d  %02d:%02d  %s  %.1f\u00b0C  [%s]",
		d.year, d.month, d.day, d.hour, d.minute, SEASON_NAMES[d.season],
		temperature_c(game.clock, game.cfg), speed,
	)
	set_clock(raw_data(cs), i32(len(cs)))
}

draw_minimap :: proc() {
	w := f32(game.width * MINI_CELL)
	h := f32(game.height * MINI_CELL)
	// Stay out of the cursor's way: the minimap sits on the opposite side of the screen.
	cursor_on_right := game.cursor_x - game.cam_x >= VIEW_W / 2
	ox := f32(MINI_MARGIN)
	if !cursor_on_right {
		ox = f32(CANVAS_W) - w - MINI_MARGIN
	}
	oy := f32(MINI_MARGIN)
	fill_rect(ox - 2, oy - 2, w + 4, h + 4, 0, 0, 0, 0.8)
	for y in 0 ..< game.height {
		for x in 0 ..< game.width {
			c := MINI_COLORS[terrain_at(&game, x, y)]
			fill_rect(ox + f32(x * MINI_CELL), oy + f32(y * MINI_CELL), MINI_CELL, MINI_CELL, c.r, c.g, c.b, 1)
		}
	}
	for c in game.corpses {
		fill_rect(ox + f32(c.x * MINI_CELL), oy + f32(c.y * MINI_CELL), MINI_CELL, MINI_CELL, 0.4, 0.4, 0.4, 1)
	}
	for p in game.people {
		c := skin_color(p.melanin)
		fill_rect(ox + f32(p.x * MINI_CELL), oy + f32(p.y * MINI_CELL), MINI_CELL, MINI_CELL, c.r, c.g, c.b, 1)
	}
	stroke_rect(
		ox + f32(game.cam_x * MINI_CELL),
		oy + f32(game.cam_y * MINI_CELL),
		VIEW_W * MINI_CELL,
		VIEW_H * MINI_CELL,
		1, 1, 1, 1,
	)
	stroke_rect(
		ox + f32(game.cursor_x * MINI_CELL),
		oy + f32(game.cursor_y * MINI_CELL),
		MINI_CELL,
		MINI_CELL,
		1, 1, 0.2, 1,
	)
}

// Input arrives from the page as plain exported calls.

@(export)
on_move :: proc "c" (dx, dy: i32) {
	context = ctx
	move_cursor(&game, int(dx), int(dy))
}

@(export)
on_hover :: proc "c" (view_x, view_y: i32) {
	context = ctx
	hover_cell(&game, int(view_x), int(view_y))
}

@(export)
on_pan :: proc "c" (dx, dy: i32) {
	context = ctx
	pan_camera(&game, int(dx), int(dy))
}

@(export)
on_speed :: proc "c" (delta: i32) {
	context = ctx
	change_speed(&game.clock, int(delta))
	game.clock.paused = false
}

@(export)
on_pause :: proc "c" () {
	context = ctx
	game.clock.paused = !game.clock.paused
}

// Non-positive numbers (and NaN latitude) keep the current value.
@(export)
configure :: proc "c" (day_real_seconds: f64, days_per_month, months_per_year: i32, latitude: f64) {
	context = ctx
	c := game.cfg
	if day_real_seconds > 0 {c.day_real_seconds = day_real_seconds}
	if days_per_month > 0 {c.days_per_month = int(days_per_month)}
	if months_per_year > 0 {c.months_per_year = int(months_per_year)}
	if !math.is_nan(latitude) {c.latitude = latitude}
	game.cfg = normalize_config(c)
}

// Replace the world with a fresh one. A world of 0 by 0 means "screen sized".
@(export)
new_world :: proc "c" (width, height: i32) {
	context = ctx
	w, h := int(width), int(height)
	if w <= 0 || h <= 0 {
		w, h = VIEW_W, VIEW_H
	}
	game_destroy(&game)
	game = {}
	game_init_rect(&game, w, h)
}
