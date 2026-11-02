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
	set_layout :: proc(info_right, clock_bottom: bool) ---
	set_powers :: proc(ptr: [^]byte, n: i32, armed: i32, affordable: i32) --- // button labels, one per line; armed power or -1; bitmask of affordable ones
	set_over :: proc(ptr: [^]byte, n: i32) --- // text for the game-over screen; empty hides it
}

// Urizen sheet coordinates (col, row).
Tile :: struct {
	col, row: i32,
}

GRASS_TILE :: Tile{15, 5}
MIRACLE_COLOR :: [3]f32{1.0, 0.85, 0.3}
TERRAIN_TILES := [Terrain]Tile {
	.Grass = {15, 5},
	.Tree  = {0, 8},
	.Bush  = {18, 9},
	.Pond  = {16, 6},
	.Stone_Field = {14, 5},
	.Dirt  = {0, 7},
	.Fire_Pit = {0, 42}, // the campfire
}

PERSON_TILES := [Sex]Tile {
	.Male   = {104, 0},
	.Female = {112, 46},
}

CORPSE_TILE :: Tile{201, 0}
SKELETON_TILE :: Tile{4, 38} // a pile of bones
SKELETON_COLOR :: [3]f32{0.88, 0.85, 0.75}
CORPSE_SHADE :: 0.55 // corpses are their owner's skin colour, dimmed

MINI_COLORS := [Terrain][3]f32 {
	.Grass = {0.10, 0.35, 0.10},
	.Tree  = {0.15, 0.80, 0.15},
	.Bush  = {0.55, 0.65, 0.10},
	.Pond  = {0.10, 0.60, 1.00},
	.Stone_Field = {0.60, 0.60, 0.65},
	.Dirt  = {0.45, 0.30, 0.15},
	.Fire_Pit = {0.95, 0.40, 0.10},
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
	if !game_over(&game) { // the world stops when the last person dies
		advance_clock(&game.clock, game.cfg, min(dt, 0.25))
		update_people(&game)
		update_bushes(&game)
		update_ground(&game)
		update_ground_items(&game)
		update_corpses(&game)
		update_vitals(&game)
		update_faith(&game)
		update_fire(&game)
		update_snakes(&game)
	}
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
			if t == .Fire_Pit && !game.lit[y * game.width + x] { // an unlit pit is cold ashes
				draw_tile_tinted(tile.col, tile.row, px, py, CELL, 0.45, 0.32, 0.25)
				continue
			}
			if b, ok := bush_at(&game, x, y); ok && b.miracle {
				draw_tile_tinted(tile.col, tile.row, px, py, CELL, MIRACLE_COLOR.r, MIRACLE_COLOR.g, MIRACLE_COLOR.b)
			} else {
				draw_tile(tile.col, tile.row, px, py, CELL)
			}
			if reeds, ok := reeds_at(&game, x, y); ok { // reed bar: how many reeds are left to cut
				fill_rect(px + 4, py + CELL - 8, CELL - 8, 4, 0, 0, 0, 0.6)
				fill_rect(px + 4, py + CELL - 8, (CELL - 8) * reeds / REEDS_PER_POND, 4, 0.5, 0.85, 0.4, 1)
			}
			if b, ok := bush_at(&game, x, y); ok { // berry bar: how full this bush is
				fill_rect(px + 4, py + CELL - 8, CELL - 8, 4, 0, 0, 0, 0.6)
				fill_rect(px + 4, py + CELL - 8, (CELL - 8) * b.food / b.max_food, 4, 0.9, 0.15, 0.25, 1)
			}
		}
	}

	for it, i in game.ground_items { // dropped things sit in the bottom corner of their cell
		vx, vy := it.x - game.cam_x, it.y - game.cam_y
		if vx < 0 || vy < 0 || vx >= VIEW_W || vy >= VIEW_H {continue}
		slot := 0
		for other in game.ground_items[:i] {
			if other.x == it.x && other.y == it.y {slot += 1}
		}
		ix, iy := f32(vx * CELL + CELL - 12 - slot * 10), f32(vy * CELL + CELL - 12)
		f := ground_freshness(&game, it)
		fade := 0.4 + 0.6 * f // things darken as they rot
		switch it.item {
		case .Stone: fill_rect(ix, iy, 8, 8, 0.7, 0.7, 0.75, 1)
		case .Sharp_Stone: fill_rect(ix, iy, 8, 8, 0.85, 0.95, 1, 1)
		case .Short_Stick: fill_rect(ix, iy, 8, 8, 0.8 * fade, 0.6 * fade, 0.35 * fade, 1)
		case .Knife: fill_rect(ix, iy, 8, 8, 0.95, 0.95, 0.4, 1)
		case .Spear: fill_rect(ix, iy, 8, 8, 0.95, 0.6, 0.2, 1)
		case .Reed: fill_rect(ix, iy, 8, 8, 0.5 * fade, 0.85 * fade, 0.4 * fade, 1)
		case .Bow: fill_rect(ix, iy, 8, 8, 0.7, 0.5, 0.25, 1)
		case .Stake: fill_rect(ix, iy, 8, 8, 0.85, 0.7, 0.45, 1)
		case .Fire_Drill: fill_rect(ix, iy, 8, 8, 0.95, 0.45, 0.2, 1)
		case .Net: fill_rect(ix, iy, 8, 8, 0.8, 0.8, 0.9, 1)
		case .Fish: fill_rect(ix, iy, 8, 8, 0.4 * fade, 0.7 * fade, 0.95 * fade, 1)
		case .Fish_Filet: fill_rect(ix, iy, 8, 8, 0.95 * fade, 0.7 * fade, 0.6 * fade, 1)
		case .Cooking_Stick: fill_rect(ix, iy, 8, 8, 0.75, 0.55, 0.3, 1)
		case .Cooked_Snake_Meat, .Cooked_Fish_Filet: fill_rect(ix, iy, 8, 8, 0.7, 0.4, 0.2, 1) // only ever on a stick
		case .Fire_Pit: // never lies on the ground
		case .Basket: fill_rect(ix, iy, 8, 8, 0.8 * fade, 0.6 * fade, 0.25 * fade, 1)
		case .Snake_Corpse: fill_rect(ix, iy, 8, 8, 0.2 + 0.2 * fade, 0.5 * fade, 0.15, 1)
		case .Snake_Meat: fill_rect(ix, iy, 8, 8, 0.95 * fade, 0.55 * fade, 0.6 * fade, 1)
		case .Snake_Skin: fill_rect(ix, iy, 8, 8, 0.3 * fade, 0.7 * fade, 0.5 * fade, 1)
		case .Fiber: fill_rect(ix, iy, 8, 8, 0.75 * fade, 0.85 * fade, 0.35 * fade, 1)
		case .Stick: fill_rect(ix, iy, 8, 8, 0.6 * fade, 0.4 * fade, 0.2 * fade, 1)
		case .Twine: fill_rect(ix, iy, 8, 8, 0.9 * fade, 0.75 * fade, 0.5 * fade, 1)
		case .Food: // berries go from red to brown
			fill_rect(ix, iy, 8, 8, 0.35 + 0.55 * f, 0.25 - 0.1 * f, 0.1 + 0.15 * f, 1)
		case .None:
		}
	}

	SNAKE_TILE :: Tile{2, 14}
	for s in game.snakes {
		vx, vy := s.x - game.cam_x, s.y - game.cam_y
		if vx < 0 || vy < 0 || vx >= VIEW_W || vy >= VIEW_H {continue}
		draw_tile(SNAKE_TILE.col, SNAKE_TILE.row, f32(vx * CELL), f32(vy * CELL), CELL)
	}

	for c in game.corpses {
		vx, vy := c.x - game.cam_x, c.y - game.cam_y
		if vx < 0 || vy < 0 || vx >= VIEW_W || vy >= VIEW_H {continue}
		if c.skeleton {
			col := SKELETON_COLOR * (1 - 0.4 * corpse_rot_fraction(&game, c)) // bones dim as they crumble
			draw_tile_tinted(SKELETON_TILE.col, SKELETON_TILE.row, f32(vx * CELL), f32(vy * CELL), CELL, col.r, col.g, col.b)
		} else {
			col := skin_color(c.melanin) * CORPSE_SHADE * (1 - 0.4 * corpse_rot_fraction(&game, c)) // darkens as it rots
			draw_tile_tinted(CORPSE_TILE.col, CORPSE_TILE.row, f32(vx * CELL), f32(vy * CELL), CELL, col.r, col.g, col.b)
		}
	}
	for p in game.people {
		vx, vy := p.x - game.cam_x, p.y - game.cam_y
		if vx < 0 || vy < 0 || vx >= VIEW_W || vy >= VIEW_H {continue}
		tile, c := PERSON_TILES[p.sex], skin_color(p.melanin)
		if p.asleep {c *= 0.5} // sleepers are dimmed
		draw_tile_tinted(tile.col, tile.row, f32(vx * CELL), f32(vy * CELL), CELL, c.r, c.g, c.b)
		if p.poison_hours > 0 {fill_rect(f32(vx * CELL + 2), f32(vy * CELL + 2), 8, 8, 0.3, 0.9, 0.2, 1)} // poisoned
		slots := carry_slots(p)
		step := min(f32(12), f32(CELL - 4) / f32(slots)) // a basket makes room for more markers, so squeeze them
		size := min(f32(8), step - 1)
		for h in 0 ..< slots { // a marker for each place that holds something
			hx, hy := f32(vx * CELL + 2) + f32(h) * step, f32(vy * CELL + CELL - 10)
			#partial switch p.hands[h] {
			case .Food: fill_rect(hx, hy, size, size, 0.9, 0.15, 0.25, 1)
			case .Stone: fill_rect(hx, hy, size, size, 0.7, 0.7, 0.75, 1)
			case .Fiber: fill_rect(hx, hy, size, size, 0.75, 0.85, 0.35, 1)
			case .Stick: fill_rect(hx, hy, size, size, 0.6, 0.4, 0.2, 1)
			case .Twine: fill_rect(hx, hy, size, size, 0.9, 0.75, 0.5, 1)
			case .Sharp_Stone: fill_rect(hx, hy, size, size, 0.85, 0.95, 1, 1)
			case .Short_Stick: fill_rect(hx, hy, size, size, 0.8, 0.6, 0.35, 1)
			case .Knife: fill_rect(hx, hy, size, size, 0.95, 0.95, 0.4, 1)
			case .Spear: fill_rect(hx, hy, size, size, 0.95, 0.6, 0.2, 1)
			case .Reed: fill_rect(hx, hy, size, size, 0.5, 0.85, 0.4, 1)
			case .Fish: fill_rect(hx, hy, size, size, 0.4, 0.7, 0.95, 1)
			case .Fish_Filet: fill_rect(hx, hy, size, size, 0.95, 0.7, 0.6, 1)
			case .Bow: fill_rect(hx, hy, size, size, 0.7, 0.5, 0.25, 1)
			case .Stake: fill_rect(hx, hy, size, size, 0.85, 0.7, 0.45, 1)
			case .Fire_Drill: fill_rect(hx, hy, size, size, 0.95, 0.45, 0.2, 1)
			case .Net: fill_rect(hx, hy, size, size, 0.8, 0.8, 0.9, 1)
			case .Cooking_Stick: // a stick, with whatever is on it as a dot beside it
				fill_rect(hx, hy, size, size, 0.75, 0.55, 0.3, 1)
				#partial switch p.loaded[h] {
				case .Snake_Meat, .Fish_Filet: fill_rect(hx + size / 2, hy, size / 2, size / 2, 0.95, 0.5, 0.55, 1)
				case .Cooked_Snake_Meat, .Cooked_Fish_Filet: fill_rect(hx + size / 2, hy, size / 2, size / 2, 0.55, 0.3, 0.1, 1)
				}
			case .Basket: fill_rect(hx, hy, size, size, 0.8, 0.6, 0.25, 1)
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

	buf, buf2: [300]byte
	gbuf: [200]byte
	t := terrain_at(&game, game.cursor_x, game.cursor_y)
	s := fmt.bprintf(buf[:], "(%d, %d)  %s", game.cursor_x, game.cursor_y, TERRAIN_NAMES[t])
	if sticks, ok := sticks_at(&game, game.cursor_x, game.cursor_y); ok {
		s = fmt.bprintf(buf[:], "(%d, %d)  Tree  -  Sticks %.1f / %.0f", game.cursor_x, game.cursor_y, sticks, f32(STICKS_PER_TREE))
	} else if fiber, ok := fiber_at(&game, game.cursor_x, game.cursor_y); ok {
		s = fmt.bprintf(buf[:], "(%d, %d)  Grass  -  Fiber %.1f / %.0f", game.cursor_x, game.cursor_y, fiber, f32(FIBER_PER_GRASS))
	} else if fuel, ok := fuel_at(&game, game.cursor_x, game.cursor_y); ok {
		s = fmt.bprintf(buf[:], "(%d, %d)  Fire pit (%s)  -  Fuel %.1f / %.0f sticks", game.cursor_x, game.cursor_y, "lit" if fire_lit_at(&game, game.cursor_x, game.cursor_y) else "cold", fuel, f32(FIRE_PIT_FUEL))
	} else if reeds, ok := reeds_at(&game, game.cursor_x, game.cursor_y); ok {
		fish, _ := fish_at(&game, game.cursor_x, game.cursor_y)
		s = fmt.bprintf(buf[:], "(%d, %d)  Pond  -  Reeds %.1f / %.0f  Fish %.1f / %.0f", game.cursor_x, game.cursor_y, reeds, f32(REEDS_PER_POND), fish, f32(FISH_PER_POND))
	} else if left, ok := stone_at(&game, game.cursor_x, game.cursor_y); ok {
		s = fmt.bprintf(buf[:], "(%d, %d)  Stone field  -  Stone %.0f / %.0f", game.cursor_x, game.cursor_y, left, f32(STONE_FIELD_AMOUNT))
	} else if b, ok := bush_at(&game, game.cursor_x, game.cursor_y); ok {
		s = fmt.bprintf(buf[:], "(%d, %d)  %s  -  Food %.1f / %.1f", game.cursor_x, game.cursor_y, "Miracle bush" if b.miracle else "Bush", b.food, b.max_food)
	}
	if snake_at(&game, game.cursor_x, game.cursor_y) >= 0 {
		s = fmt.bprintf(buf[:], "(%d, %d)  Poisonous snake  -  Dodge %.0f", game.cursor_x, game.cursor_y, game.snakes[snake_at(&game, game.cursor_x, game.cursor_y)].dodge)
	}
	if on_ground := describe_ground_items(&game, game.cursor_x, game.cursor_y, gbuf[:]); len(on_ground) > 0 {
		s = fmt.bprintf(buf2[:], "%s\nOn the ground: %s", s, on_ground)
	}
	if i := person_at(&game, game.cursor_x, game.cursor_y); i >= 0 {
		p := game.people[i]
		s = fmt.bprintf(
			buf[:],
			"(%d, %d)  Person (%s, melanin %.2f)%s\nHealth %.0f  Satiety %.0f\nStomach %.0f  Energy %.0f\nSleeps %.1fh  Carrying %d/%d\nForaging %.0f  Crafting %.0f  Ranged %.0f",
			game.cursor_x, game.cursor_y, SEX_NAMES[p.sex], p.melanin, " - asleep" if p.asleep else "",
			p.health, p.satiety, p.stomach, p.energy, p.sleep_hours, held_count(p), carry_slots(p), p.foraging, p.crafting, p.ranged,
		)
		s = fmt.tprintf("%s\nAge %.0f of %.0f", s, p.age_years, p.lifespan_years)
		s = fmt.tprintf("%s\nMood: %s (dopamine %.0f)%s", s, MOOD_NAMES[mood_of(p.dopamine)], p.dopamine, " - craving" if craving(p) else "")
		if made := describe_craft_levels(p); len(made) > 0 {
			s = fmt.tprintf("%s\nCrafted: %s", s, made)
		}
		if p.poison_hours > 0 {
			s = fmt.tprintf("%s\nPoisoned for %.1fh", s, p.poison_hours)
		}
		if n, ok := uses_left(p, .Spear); ok {
			s = fmt.tprintf("%s\nSpear: %d uses left", s, n)
		}
		if n, ok := uses_left(p, .Fire_Drill); ok {
			s = fmt.tprintf("%s\nFire drill: %d uses left", s, n)
		}
		if n, ok := uses_left(p, .Net); ok {
			s = fmt.tprintf("%s\nNet: %d uses left", s, n)
		}
		s = fmt.tprintf("%s\nFishing %.0f (+%d)  Cooking %.0f (+%d)", s, p.fishing, p.fish_level, p.cooking, p.cook_level)
		if n, ok := uses_left(p, .Knife); ok {
			s = fmt.tprintf("%s\nKnife: %d uses left", s, n)
		}
	} else if i := corpse_at(&game, game.cursor_x, game.cursor_y); i >= 0 {
		c := game.corpses[i]
		kind := "Skeleton" if c.skeleton else "Corpse"
		s = fmt.bprintf(buf[:], "(%d, %d)  %s (%s, melanin %.2f)  -  %.0f%% rotted", game.cursor_x, game.cursor_y, kind, SEX_NAMES[c.sex], c.melanin, 100 * corpse_rot_fraction(&game, c))
	}
	set_info(raw_data(s), i32(len(s)))
	// Keep the panels out of the cursor's way: info on the opposite side, clock on the opposite edge.
	set_layout(game.cursor_x - game.cam_x < VIEW_W / 2, game.cursor_y - game.cam_y < VIEW_H / 2)

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
	pbuf: [120]byte
	cs = fmt.bprintf(
		pbuf[:],
		"%s\nFaith %.0f",
		cs, game.faith,
	)
	set_clock(raw_data(cs), i32(len(cs)))

	lbuf: [120]byte
	armed_index, affordable: i32 = -1, 0
	labels := ""
	for power in Power {
		labels = fmt.bprintf(lbuf[:], "%s[%d] %s %.0f\n", labels, int(power) + 1, POWER_NAMES[power], POWER_COSTS[power])
		if game.faith >= POWER_COSTS[power] {affordable |= 1 << u32(power)}
		if a, ok := game.armed.?; ok && a == power {armed_index = i32(power)}
	}
	labels = labels[:len(labels) - 1]
	set_powers(raw_data(labels), i32(len(labels)), armed_index, affordable)

	obuf: [200]byte
	os := ""
	if game_over(&game) {
		os = fmt.bprintf(
			obuf[:],
			"All of your people are dead.\nYou lasted %d years, %d months, %d days.\n\nPress R or click to begin again.",
			d.year - 1, d.month - 1, d.day - 1,
		)
	}
	set_over(raw_data(os), i32(len(os)))
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
			if b, ok := bush_at(&game, x, y); ok && b.miracle {c = MIRACLE_COLOR}
			fill_rect(ox + f32(x * MINI_CELL), oy + f32(y * MINI_CELL), MINI_CELL, MINI_CELL, c.r, c.g, c.b, 1)
		}
	}
	for c in game.corpses {
		shade: f32 = 0.7 if c.skeleton else 0.4
		fill_rect(ox + f32(c.x * MINI_CELL), oy + f32(c.y * MINI_CELL), MINI_CELL, MINI_CELL, shade, shade, shade, 1)
	}
	for s in game.snakes {
		fill_rect(ox + f32(s.x * MINI_CELL), oy + f32(s.y * MINI_CELL), MINI_CELL, MINI_CELL, 0.3, 0.9, 0.2, 1)
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

@(export)
on_power :: proc "c" (power: i32) {
	context = ctx
	if power >= 0 && power < len(Power) {_ = use_power(&game, Power(power))}
}

// Arming a power makes the next click on the map cast it there; arming it again disarms it.
@(export)
on_arm :: proc "c" (power: i32) {
	context = ctx
	if power < 0 || power >= len(Power) {return}
	if a, ok := game.armed.?; ok && a == Power(power) {
		game.armed = nil
	} else {
		game.armed = Power(power)
	}
}

@(export)
on_disarm :: proc "c" () {
	context = ctx
	game.armed = nil
}

@(export)
on_click :: proc "c" (view_x, view_y: i32) {
	context = ctx
	hover_cell(&game, int(view_x), int(view_y))
	if a, ok := game.armed.?; ok {use_power(&game, a)}
}

@(export)
on_restart :: proc "c" () {
	context = ctx
	if game_over(&game) {restart_game(&game)}
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
