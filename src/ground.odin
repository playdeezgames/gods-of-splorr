package gods

import "core:math"
import "core:math/rand"

// A stone field holds a fixed amount of stone. Once it is used up it becomes dirt, and dirt
// beside grass slowly turns back into grass.
STONE_FIELD_AMOUNT :: 20
DIRT_TO_GRASS_PER_HOUR :: 1.0 / 48 // chance rate for a dirt cell next to grass: about once per two game days

// Grass carries plant fiber that people can gather. Taking it all turns the tile to dirt; a
// partly gathered tile slowly regrows, much more slowly than berries do.
FIBER_PER_GRASS :: 5
FIBER_REGROW_PER_HOUR :: 0.02 // berries manage up to 0.125
FIBER_ON_NEW_GRASS :: 1 // dirt that greens over starts with a little

fiber_at :: proc(g: ^Game, x, y: int) -> (f32, bool) {
	if !in_bounds(g, x, y) || terrain_at(g, x, y) != .Grass {return 0, false}
	return g.fiber[y * g.width + x], true
}

// Take up to one unit of fiber from the grass at (x, y); returns how much was taken. A tile
// with none left becomes dirt.
take_fiber :: proc(g: ^Game, x, y: int) -> f32 {
	if _, ok := fiber_at(g, x, y); !ok {return 0}
	i := y * g.width + x
	taken := min(f32(1), g.fiber[i])
	g.fiber[i] -= taken
	if g.fiber[i] <= 0 {
		g.fiber[i] = 0
		g.cells[i] = .Dirt
	}
	return taken
}

// Trees carry sticks that people can gather from beside them. A tree stays a tree when it is
// picked bare, and regrows its sticks very slowly (fiber regrows ten times faster).
STICKS_PER_TREE :: 3
STICK_REGROW_PER_HOUR :: 0.002

sticks_at :: proc(g: ^Game, x, y: int) -> (f32, bool) {
	if !in_bounds(g, x, y) || terrain_at(g, x, y) != .Tree {return 0, false}
	return g.sticks[y * g.width + x], true
}

stone_at :: proc(g: ^Game, x, y: int) -> (f32, bool) {
	if !in_bounds(g, x, y) || terrain_at(g, x, y) != .Stone_Field {return 0, false}
	return g.stone[y * g.width + x], true
}

// Take up to `amount` stone from a field; returns how much was taken. An emptied field becomes dirt.
take_stone :: proc(g: ^Game, x, y: int, amount: f32) -> f32 {
	if _, ok := stone_at(g, x, y); !ok {return 0}
	i := y * g.width + x
	taken := min(amount, g.stone[i])
	g.stone[i] -= taken
	if g.stone[i] <= 0 {
		g.stone[i] = 0
		g.cells[i] = .Dirt
	}
	return taken
}

next_to_grass :: proc(g: ^Game, x, y: int) -> bool {
	for d in DIRS {
		if in_bounds(g, x + d.x, y + d.y) && terrain_at(g, x + d.x, y + d.y) == .Grass {return true}
	}
	return false
}

// Dirt next to grass turns to grass over game time. Changes are applied together after the
// scan so grass spreads at most one cell per update.
update_ground :: proc(g: ^Game) {
	elapsed := g.clock.hours - g.terrain_updated_hours
	g.terrain_updated_hours = g.clock.hours
	if elapsed <= 0 {return}
	for t, i in g.cells {
		if t == .Grass {g.fiber[i] = min(g.fiber[i] + FIBER_REGROW_PER_HOUR * f32(elapsed), FIBER_PER_GRASS)}
	}
	for t, i in g.cells {
		if t == .Tree {g.sticks[i] = min(g.sticks[i] + STICK_REGROW_PER_HOUR * f32(elapsed), STICKS_PER_TREE)}
	}
	chance := 1 - math.exp(-DIRT_TO_GRASS_PER_HOUR * elapsed)
	changed := make([dynamic]int, context.temp_allocator)
	for t, i in g.cells {
		if t != .Dirt {continue}
		if next_to_grass(g, i % g.width, i / g.width) && rand.float64() < chance {append(&changed, i)}
	}
	for i in changed {
		g.cells[i] = .Grass
		g.fiber[i] = FIBER_ON_NEW_GRASS
	}
}
