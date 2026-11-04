package gods

// Keeping food for the winter. Berries and raw meat hung on a drying rack (a ground item made of sticks)
// lie on the rack's cell as `.Drying`, with what it is in `Ground_Item.loaded`, and become dried berries
// or dried meat after DRY_HOURS; dried food never spoils. A rack holds RACK_CAPACITY pieces at a time. Foragers with nothing to haul pick berries for the store and the firekeeper dries the meat
// that is not cooked; nobody eats from the store while there are berries on a bush nearby.
DRY_HOURS :: 24.0 // a day in the sun and wind; drying food does not rot meanwhile
DRIED_MEAT_STOMACH :: 30.0 // less than a cooked meal, more than a berry
STORE_BUSH_RANGE :: 10 // with berries on a bush this near (in steps), the store is left alone
STORE_PER_PERSON :: 250 // a winter's worth: foragers put laying it in ahead of topping up the raw materials

STORE_SPARE_BERRIES_PER_PERSON :: 10 // with fewer berries than this on the bushes, they are left for eating
STORE_EMERGENCY_SATIETY :: 20.0 // someone this close to starving may eat from the store in any season

// Does the tribe still want more in the store while the berries are growing, and are there berries to spare?
store_short :: proc(g: ^Game) -> bool {
	if mean_temperature_c(g.clock, g.cfg) <= BERRY_MIN_TEMP_C {return false}
	dried, drying := store_count(g)
	if dried + drying >= STORE_PER_PERSON * len(g.people) {return false}
	berries: f32
	for t, i in g.cells {
		if t == .Bush {berries += g.bushes[i].food}
	}
	return berries >= f32(STORE_SPARE_BERRIES_PER_PERSON * len(g.people))
}

// The season (or a person's hunger) allows eating from the store.
store_season :: proc(g: ^Game, p: Person) -> bool {
	return mean_temperature_c(g.clock, g.cfg) <= BERRY_MIN_TEMP_C || p.satiety < STORE_EMERGENCY_SATIETY
}

RACK_STICKS :: 4
RACK_CAPACITY :: 6
MAX_RACKS :: 3 // the toolmaker builds another while the store is short and every rack is full

// Lash sticks, held or lying at the person's feet, into a drying rack. A clumsy lashing breaks one stick.
craft_drying_rack :: proc(g: ^Game, p: ^Person) -> bool {
	ingredients: [RACK_STICKS]Item
	for &item in ingredients {item = .Stick}
	return craft_recipe(g, p, ingredients[:], .Drying_Rack)
}

// Pieces drying on the rack at (x, y).
on_rack :: proc(g: ^Game, x, y: int) -> int {
	n := 0
	for it in g.ground_items {
		if it.item == .Drying && it.x == x && it.y == y {n += 1}
	}
	return n
}

// A rack within the person's reach with room on it.
rack_with_room :: proc(g: ^Game, p: Person) -> (x, y: int, ok: bool) {
	for it in g.ground_items {
		if it.item == .Drying_Rack && in_reach(it.x, it.y, p.x, p.y) && on_rack(g, it.x, it.y) < RACK_CAPACITY {
			return it.x, it.y, true
		}
	}
	return
}

// Does the tribe need another rack: none at all, or all of them full while the store is short?
want_rack :: proc(g: ^Game) -> bool {
	racks, room := 0, false
	for it in g.ground_items {
		if it.item != .Drying_Rack {continue}
		racks += 1
		room ||= on_rack(g, it.x, it.y) < RACK_CAPACITY
	}
	for p in g.people {
		for h in 0 ..< carry_slots(p) {
			if p.hands[h] == .Drying_Rack {racks += 1; room = true} // one on its way to the stockpile
		}
	}
	return store_short(g) && racks < MAX_RACKS && !room
}

is_dryable :: proc(item: Item) -> bool {
	#partial switch item {
	case .Food, .Fish_Filet, .Rabbit_Meat, .Snake_Meat: return true
	}
	return false
}

is_dried :: proc(item: Item) -> bool {
	return item == .Dried_Berries || item == .Dried_Meat
}

// How much of the stomach a piece of dried food fills.
dried_stomach :: proc(item: Item) -> f32 {
	return FOOD_STOMACH if item == .Dried_Berries else DRIED_MEAT_STOMACH
}

dried_form :: proc(item: Item) -> Item {
	return .Dried_Berries if item == .Food else .Dried_Meat
}

// Hang one dryable thing held in the open (not one in a basket, which keeps anyway) on a rack within reach.
set_out_to_dry :: proc(g: ^Game, p: ^Person) -> bool {
	rx, ry, ok := rack_with_room(g, p^)
	if !ok {return false}
	for h in 0 ..< carry_slots(p^) {
		if !is_dryable(p.hands[h]) {continue}
		append(&g.ground_items, Ground_Item{x = rx, y = ry, item = .Drying, loaded = p.hands[h], dropped_hours = g.clock.hours})
		p.hands[h] = .None
		return true
	}
	return false
}

// A rack at the stockpile with room on it.
stockpile_rack :: proc(g: ^Game) -> (x, y: int, ok: bool) {
	return rack_with_room(g, Person{x = g.stockpile_x, y = g.stockpile_y})
}

// Hang one piece of raw meat lying at the stockpile on a rack there (the firekeeper's work).
dry_meat_at_stockpile :: proc(g: ^Game) -> bool {
	rx, ry, ok := stockpile_rack(g)
	if !ok {return false}
	for &it in g.ground_items {
		if it.item == .Food || !is_dryable(it.item) || !in_reach(it.x, it.y, g.stockpile_x, g.stockpile_y) {continue}
		it.loaded, it.item, it.dropped_hours, it.x, it.y = it.item, .Drying, g.clock.hours, rx, ry
		return true
	}
	return false
}

// Food that has been out long enough is dried.
update_drying :: proc(g: ^Game) {
	for &it in g.ground_items {
		if it.item != .Drying || g.clock.hours - it.dropped_hours < DRY_HOURS {continue}
		it.item, it.loaded, it.dropped_hours = dried_form(it.loaded), .None, g.clock.hours
	}
}

// The store is for the winter: once the berries have stopped growing (by the season's daily mean), or for
// someone near starving, and only with no berries on a bush within STORE_BUSH_RANGE. Picking the bushes
// near home bare in autumn must not open it, or it is eaten before the cold.
store_open :: proc(g: ^Game, p: Person) -> bool {
	if !store_season(g, p) {return false}
	bx, by, ok := nearest_match(g, p, bush_with_food)
	return !ok || abs(bx - p.x) + abs(by - p.y) > STORE_BUSH_RANGE
}

// A forager with nothing to haul picks berries for the store: from a bush beside them, then from the
// nearest one, carrying them to a rack at the stockpile when their hands are full or the bushes are bare.
gather_for_store :: proc(g: ^Game, p: ^Person) -> bool {
	held := 0
	for h in 0 ..< carry_slots(p^) {
		if p.hands[h] == .Food {held += 1}
	}
	rx, ry, room := stockpile_rack(g)
	if !room {return false} // the racks are full (or not built): nothing to lay in for now
	if held > 0 && in_reach(rx, ry, p.x, p.y) {return set_out_to_dry(g, p)}
	if free_hand(p^) < 0 && held == 0 { // hands full of tools not needed just now: leave one at the stockpile
		for h in 0 ..< carry_slots(p^) {
			if p.hands[h] != .Fire_Drill && (p.hands[h] != .Cooking_Stick || p.loaded[h] != .None) {continue}
			if !at_stockpile(g, p^) {return step_toward(g, p, g.stockpile_x, g.stockpile_y)}
			return drop_item(g, p, h)
		}
		return false
	}
	if free_hand(p^) >= 0 {
		for d in DIRS {
			if gather_food(g, p, p.x + d.x, p.y + d.y) {return true}
		}
		if bx, by, ok := nearest_match(g, p^, bush_with_food); ok {return step_toward(g, p, bx, by)}
	}
	if held > 0 {return step_toward(g, p, rx, ry)}
	return false
}

// Dried food in the store for the tribe, and the pieces drying.
store_count :: proc(g: ^Game) -> (dried, drying: int) {
	for it in g.ground_items {
		if is_dried(it.item) {dried += 1}
		if it.item == .Drying {drying += 1}
	}
	return
}
