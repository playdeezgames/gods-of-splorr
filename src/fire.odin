package gods

// A lit firepit burns its fuel down, a stick's worth at a time, and goes out when the fuel is gone.
FIRE_BURN_PER_HOUR :: 0.5 // so eight sticks of fuel last sixteen game hours
FIRE_FEED_BELOW :: 2.0 // people top up a fire that is about to go out
FIRE_FEED_FUEL :: 1.0 // one stick, one stick's worth

fire_lit_at :: proc(g: ^Game, x, y: int) -> bool {
	return in_bounds(g, x, y) && terrain_at(g, x, y) == .Fire_Pit && g.lit[y * g.width + x]
}

// Burn the fuel of every lit pit by the game time since the last call.
update_fire :: proc(g: ^Game) {
	elapsed := f32(g.clock.hours - g.fire_updated_hours)
	g.fire_updated_hours = g.clock.hours
	if elapsed <= 0 {return}
	for t, i in g.cells {
		if t != .Fire_Pit || !g.lit[i] {continue}
		g.fuel[i] -= FIRE_BURN_PER_HOUR * elapsed
		if g.fuel[i] <= 0 {g.fuel[i], g.lit[i] = 0, false}
	}
}

// A neighbouring cell (orthogonal) that satisfies match, if any.
neighbour_where :: proc(g: ^Game, p: Person, match: proc(g: ^Game, x, y: int) -> bool) -> (x, y: int, ok: bool) {
	for d in DIRS {
		if match(g, p.x + d.x, p.y + d.y) {return p.x + d.x, p.y + d.y, true}
	}
	return 0, 0, false
}

unlit_pit_with_fuel :: proc(g: ^Game, x, y: int) -> bool {
	return in_bounds(g, x, y) && terrain_at(g, x, y) == .Fire_Pit && !g.lit[y * g.width + x] && g.fuel[y * g.width + x] > 0
}

// Strike the fire drill: a person holding one lights an unlit pit that still has fuel, beside them.
light_fire :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Fire_Drill) {return false}
	x, y, ok := neighbour_where(g, p^, unlit_pit_with_fuel)
	if !ok {return false}
	g.lit[y * g.width + x] = true
	wear_tool(p, .Fire_Drill) // every lighting wears the drill
	return true
}

// A pit (lit or cold) whose fuel is nearly gone.
low_pit :: proc(g: ^Game, x, y: int) -> bool {
	return in_bounds(g, x, y) && terrain_at(g, x, y) == .Fire_Pit && g.fuel[y * g.width + x] < FIRE_FEED_BELOW
}

// Whether a stick could be added to the pit at (x, y): anything short of full.
pit_has_room :: proc(g: ^Game, x, y: int) -> bool {
	return in_bounds(g, x, y) && terrain_at(g, x, y) == .Fire_Pit && g.fuel[y * g.width + x] <= FIRE_PIT_FUEL - FIRE_FEED_FUEL
}

// Put a stick, held or lying at the person's feet, onto the firepit at (x, y), lit or cold. A stick adds
// a stick's worth of fuel, up to the pit's capacity, and is not taken if it would not fit.
add_stick :: proc(g: ^Game, p: ^Person, x, y: int) -> bool {
	if abs(p.x - x) + abs(p.y - y) != 1 || !pit_has_room(g, x, y) {return false}
	if !spend(g, p, .Stick, 1) {return false}
	g.fuel[y * g.width + x] += FIRE_FEED_FUEL
	return true
}

// People top up any pit that is nearly out of fuel, so a fire does not die while they are by it.
feed_fire :: proc(g: ^Game, p: ^Person) -> bool {
	x, y, ok := neighbour_where(g, p^, low_pit)
	return ok && add_stick(g, p, x, y)
}

lit_pit :: proc(g: ^Game, x, y: int) -> bool {
	return fire_lit_at(g, x, y)
}
