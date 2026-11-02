package gods

// The god acts on the cell under the cursor and pays for it in faith, which slowly returns.
MAX_FAITH :: 100.0
START_FAITH :: 50.0
FAITH_PER_HOUR :: 2.0

Power :: enum u8 {
	Manna, // drops a berry on the ground
	Smite, // kills the person standing there
	Snake, // a poisonous snake that hunts nearby people
	Smite_Bush, // scorches a bush away, leaving bare dirt
	Miracle_Bush, // grows a bush that holds a lot of berries and bears in any weather
}

POWER_NAMES := [Power]string {
	.Manna = "Manna",
	.Smite = "Smite",
	.Snake = "Snake",
	.Smite_Bush = "Smite Bush",
	.Miracle_Bush = "Miracle Bush",
}

POWER_COSTS := [Power]f32 {
	.Manna = 10,
	.Smite = 30,
	.Snake = 25,
	.Smite_Bush = 15,
	.Miracle_Bush = 40,
}

// Regain faith for the game time since the last call.
update_faith :: proc(g: ^Game) {
	elapsed := f32(g.clock.hours - g.faith_updated_hours)
	g.faith_updated_hours = g.clock.hours
	if elapsed <= 0 {return}
	g.faith = min(g.faith + FAITH_PER_HOUR * elapsed, MAX_FAITH)
}

// Whether the power could take effect at the cursor right now, ignoring cost.
power_has_target :: proc(g: ^Game, power: Power) -> bool {
	x, y := g.cursor_x, g.cursor_y
	switch power {
	case .Manna: return walkable(terrain_at(g, x, y))
	case .Smite: return person_at(g, x, y) >= 0
	case .Snake: return can_enter(g, x, y)
	case .Smite_Bush: return terrain_at(g, x, y) == .Bush
	case .Miracle_Bush: return can_enter(g, x, y)
	}
	return false
}

// Use a power on the cursor cell. Returns false, and spends nothing, if it cannot be afforded
// or has nothing to act on.
use_power :: proc(g: ^Game, power: Power) -> bool {
	if game_over(g) || g.faith < POWER_COSTS[power] || !power_has_target(g, power) {return false}
	x, y := g.cursor_x, g.cursor_y
	switch power {
	case .Manna:
		append(&g.ground_items, Ground_Item{x = x, y = y, item = .Food, dropped_hours = g.clock.hours})
	case .Smite:
		kill_person(g, person_at(g, x, y))
	case .Snake:
		spawn_snake(g, x, y)
	case .Smite_Bush:
		clear_cell(g, x, y, .Dirt)
	case .Miracle_Bush:
		clear_cell(g, x, y, .Bush)
		g.bushes[y * g.width + x] = Bush{food = MIRACLE_MAX_FOOD, max_food = MIRACLE_MAX_FOOD, miracle = true}
	}
	g.faith -= POWER_COSTS[power]
	return true
}

// Turn a cell into a different kind of terrain with nothing left of what was there.
clear_cell :: proc(g: ^Game, x, y: int, to: Terrain) {
	i := y * g.width + x
	g.cells[i] = to
	g.bushes[i], g.fiber[i], g.stone[i], g.sticks[i] = {}, 0, 0, 0
}
