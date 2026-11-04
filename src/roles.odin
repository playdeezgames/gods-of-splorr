package gods

// Division of labour. Each person takes a specialty from the tribe's needs and their own aptitude, and
// works at it: foragers haul raw materials to the stockpile, a toolmaker turns them into tools there,
// a fisher takes a net from it and brings fish back, and a firekeeper builds, lights and tends the fire
// and cooks at it. The stockpile is a cell (the first person's starting cell) where things lie on the
// ground, which crafting and cooking can use directly, so nobody has to carry a whole recipe in two hands.
Role :: enum u8 {
	Generalist, // no specialty yet: does a bit of everything, as before
	Forager,
	Toolmaker,
	Fisher,
	Firekeeper,
	Hunter,
}

ROLE_NAMES := [Role]string {
	.Generalist = "Generalist",
	.Forager    = "Forager",
	.Toolmaker  = "Toolmaker",
	.Fisher     = "Fisher",
	.Firekeeper = "Firekeeper",
	.Hunter     = "Hunter",
}

// The jobs a tribe of n people needs, in the order they fill up: mostly foragers, one of each other.
// The hunter hauls for the stockpile too when there is no rabbit about.
ROLE_PATTERN := [?]Role{.Forager, .Toolmaker, .Firekeeper, .Fisher, .Hunter, .Forager}

aptitude :: proc(p: Person, r: Role) -> f32 {
	switch r {
	case .Forager: return p.foraging
	case .Toolmaker: return p.crafting
	case .Fisher: return p.fishing
	case .Firekeeper: return p.cooking
	case .Hunter: return p.ranged
	case .Generalist: return 0
	}
	return 0
}

role_count :: proc(g: ^Game, r: Role) -> int {
	n := 0
	for p in g.people {
		if p.role == r {n += 1}
	}
	return n
}

// Fill every vacant job with the best-suited person who has none. People keep the specialty they have
// while the tribe still needs it; if it shrank away (deaths), they go back to being open to a new one.
assign_roles :: proc(g: ^Game) {
	n := len(g.people)
	if n < 2 {
		for &p in g.people {p.role = .Generalist}
		return
	}
	slots: [dynamic]Role
	defer delete(slots)
	for k in 0 ..< n {append(&slots, ROLE_PATTERN[k % len(ROLE_PATTERN)])}
	for &p in g.people { // keep what still fits
		if p.role == .Generalist {continue}
		kept := false
		for s, i in slots {
			if s == p.role {unordered_remove(&slots, i); kept = true; break}
		}
		if !kept {p.role = .Generalist}
	}
	for len(slots) > 0 { // the best person for the best-fitting job, one at a time
		bi, bs := -1, -1
		best: f32 = -1
		for p, i in g.people {
			if p.role != .Generalist {continue}
			for s, k in slots {
				if a := aptitude(p, s); a > best {best, bi, bs = a, i, k}
			}
		}
		if bi < 0 {break}
		g.people[bi].role = slots[bs]
		unordered_remove(&slots, bs)
	}
}

// Where the tribe keeps its things.
at_stockpile :: proc(g: ^Game, p: Person) -> bool {
	return in_reach(p.x, p.y, g.stockpile_x, g.stockpile_y)
}

stock_of :: proc(g: ^Game, item: Item) -> int {
	n := 0
	for it in g.ground_items {
		if in_reach(it.x, it.y, g.stockpile_x, g.stockpile_y) && it.item == item {n += 1}
	}
	return n
}

// Take one of an item from the stockpile into a free hand; the person must be standing at it.
take_from_stockpile :: proc(g: ^Game, p: ^Person, item: Item) -> bool {
	return at_stockpile(g, p^) && pick_up(g, p, item)
}

// Go and get an item lying anywhere (usually the stockpile) and pick it up.
fetch :: proc(g: ^Game, p: ^Person, item: Item) -> bool {
	x, y, found := nearest_ground(g, p^, item)
	if !found {return false}
	if in_reach(x, y, p.x, p.y) {return pick_up(g, p, item)}
	if free_hand(p^) < 0 {return false}
	return step_toward(g, p, x, y)
}

// Put the first held thing that matches down on the stockpile.
stash :: proc(g: ^Game, p: ^Person, wanted: proc(item: Item) -> bool) -> bool {
	for h in 0 ..< carry_slots(p^) {
		if p.hands[h] != .None && wanted(p.hands[h]) {return drop_item(g, p, h)}
	}
	return false
}

is_raw_material :: proc(item: Item) -> bool {
	#partial switch item {
	case .Fiber, .Stone, .Stick, .Reed: return true
	}
	return false
}

is_tribe_tool :: proc(item: Item) -> bool {
	#partial switch item {
	case .Net, .Fire_Drill, .Cooking_Stick, .Spear, .Fur_Coat, .Drying_Rack: return true
	}
	return false
}

is_catch :: proc(item: Item) -> bool {
	return item == .Fish || item == .Fish_Filet || item == .Snake_Meat || item == .Rabbit_Corpse || item == .Rabbit_Meat
}

HAUL_URGENT :: 0.25 // under this share of its target, a raw material comes before laying in food

// How much raw material the stockpile should hold before foragers turn to other things.
HAUL_TARGET := #partial [Item]int {
	.Fiber = 14,
	.Stone = 14,
	.Stick = 18,
}

// Foragers fetch whichever raw material the stockpile is shortest of and carry it back.
pursue_forager :: proc(g: ^Game, p: ^Person) -> bool {
	target := HAUL_TARGET
	if free_hand(p^) < 0 || (!at_stockpile(g, p^) && held_raw(p^) > 0 && all_stocked(g)) { // hands full: carry it home
		if at_stockpile(g, p^) {return stash(g, p, is_raw_material) || gather_for_store(g, p)}
		return step_toward(g, p, g.stockpile_x, g.stockpile_y)
	}
	if at_stockpile(g, p^) && held_raw(p^) > 0 {return stash(g, p, is_raw_material)}
	need, worst := Item.None, f32(2)
	for raw in ([?]Item{.Fiber, .Stone, .Stick}) {
		if ratio := f32(stock_of(g, raw)) / f32(target[raw]); ratio < worst && ratio < 1 {need, worst = raw, ratio}
	}
	if worst >= HAUL_URGENT && held_raw(p^) == 0 && store_short(g) && gather_for_store(g, p) {return true} // the winter's food comes before topping up
	if need == .None {
		if held_raw(p^) > 0 {
			if at_stockpile(g, p^) {return stash(g, p, is_raw_material)}
			return step_toward(g, p, g.stockpile_x, g.stockpile_y)
		}
		return gather_for_store(g, p) // nothing to haul: lay in berries for the winter
	}
	if gather_raw(g, p, need) {return true}
	if tx, ty, found := nearest_source(g, p^, need); found {return step_toward(g, p, tx, ty)}
	return false
}

held_raw :: proc(p: Person) -> int {
	n := 0
	for h in 0 ..< carry_slots(p) {
		if is_raw_material(p.hands[h]) {n += 1}
	}
	return n
}

all_stocked :: proc(g: ^Game) -> bool {
	target := HAUL_TARGET
	for raw in ([?]Item{.Fiber, .Stone, .Stick}) {
		if stock_of(g, raw) < target[raw] {return false}
	}
	return true
}

// The toolmaker works at the stockpile, from what lies there: a sharp stone to cut with, then the
// tools the tribe lacks (a net, a fire drill, a cooking stick), each left on the stockpile when done.
pursue_toolmaker :: proc(g: ^Game, p: ^Person) -> bool {
	if !at_stockpile(g, p^) {return step_toward(g, p, g.stockpile_x, g.stockpile_y)}
	if stash(g, p, is_tribe_tool) {return true}
	if !holds(p^, .Sharp_Stone) {
		if take_from_stockpile(g, p, .Sharp_Stone) {return true}
		if craft_sharp_stone(g, p) {return true}
	}
	if skin_rabbit(g, p) {return true}
	if stock_of(g, .Stone) < 2 && !holds(p^, .Sharp_Stone) {return false}
	for want in ([?]Item{.Net, .Fire_Drill, .Cooking_Stick}) {
		if stock_of(g, want) > 0 {continue}
		step := next_step(g, p^, want)
		if step.craft != .None && try_craft(g, p, step.craft) {return true}
	}
	if role_count(g, .Hunter) > 0 && tribe_has(g, .Spear) == 0 { // the hunter keeps theirs, so only one is made
		step := next_step(g, p^, .Spear)
		if step.craft != .None && try_craft(g, p, step.craft) {return true}
	}
	if want_rack(g) {
		step := next_step(g, p^, .Drying_Rack)
		if step.craft != .None && try_craft(g, p, step.craft) {return true}
	}
	if coats_wanted(g) > 0 && have_count(g, p^, .Fur) >= COAT_FUR {
		step := next_step(g, p^, .Fur_Coat)
		if step.craft != .None && try_craft(g, p, step.craft) {return true}
	}
	return false
}

// The fisher takes a net from the stockpile, fishes, and brings each catch back to it.
pursue_fisher :: proc(g: ^Game, p: ^Person) -> bool {
	for h in 0 ..< carry_slots(p^) {
		if is_catch(p.hands[h]) {
			if at_stockpile(g, p^) {return drop_item(g, p, h)}
			return step_toward(g, p, g.stockpile_x, g.stockpile_y)
		}
	}
	if !holds(p^, .Net) {
		return fetch(g, p, .Net) // false until a toolmaker has made one
	}
	if fish_adjacent(g, p) {return true}
	if tx, ty, found := nearest_match(g, p^, pond_with_fish); found {return step_toward(g, p, tx, ty)}
	return false
}

// The firekeeper builds the pit beside the stockpile from the pile there, lights it with a drill from
// the stockpile in the cold, and cooks what the fisher brings, leaving the cooked meals for anyone.
pursue_firekeeper :: proc(g: ^Game, p: ^Person) -> bool {
	if !at_stockpile(g, p^) {return step_toward(g, p, g.stockpile_x, g.stockpile_y)}
	if _, _, has_pit := nearest_match(g, p^, is_fire_pit); !has_pit {
		return build_fire_pit(g, p) // else wait for the foragers to stock enough stone and sticks
	}
	if stick_where(p^, is_cooked) >= 0 { // a meal is ready: put it out for the tribe
		for h in 0 ..< carry_slots(p^) {
			if p.hands[h] == .Cooking_Stick && is_cooked(p.loaded[h]) {return drop_item(g, p, h)}
		}
	}
	_, _, lit := nearest_match(g, p^, lit_pit)
	cold := temperature_c(g.clock, g.cfg) < FIRE_LIGHT_BELOW_C
	meat := stick_where(p^, is_raw_meat) >= 0
	if !lit && cold { // not to cook: sticks are scarce, and a fire burning in warm weather is wood wasted
		if !holds(p^, .Fire_Drill) {
			if fetch(g, p, .Fire_Drill) {return true}
		} else if light_fire(g, p) {
			return true
		}
	}
	if !lit && dry_meat_at_stockpile(g) {return true} // with no fire, meat is dried for the store rather than left to rot
	if lit || meat { // with no fire, the cooking stick stays at the stockpile and the hands are free
		if !holds(p^, .Cooking_Stick) {
			return fetch(g, p, .Cooking_Stick)
		}
		if meat {return cook_on_fire(g, p)}
		if load_stick(g, p) {return true}
	}
	if have_count(g, p^, .Fish) > 0 {
		if holds(p^, .Sharp_Stone) {return fillet_fish(g, p)}
		if take_from_stockpile(g, p, .Sharp_Stone) {return true}
		return craft_sharp_stone(g, p)
	}
	return false
}

// The hunter takes the spear from the stockpile and hunts rabbits, carrying each kill back to the
// stockpile for the toolmaker to skin. With no rabbit near, or no spear yet, they haul like a forager.
pursue_hunter :: proc(g: ^Game, p: ^Person) -> bool {
	for h in 0 ..< carry_slots(p^) {
		if is_catch(p.hands[h]) {
			if at_stockpile(g, p^) {return drop_item(g, p, h)}
			return step_toward(g, p, g.stockpile_x, g.stockpile_y)
		}
	}
	if x, y, found := nearest_ground(g, p^, .Rabbit_Corpse); found && !in_reach(x, y, g.stockpile_x, g.stockpile_y) {
		if in_reach(x, y, p.x, p.y) {return pick_up(g, p, .Rabbit_Corpse)}
		return step_toward(g, p, x, y)
	}
	if !holds(p^, .Spear) {
		if fetch(g, p, .Spear) {return true}
	} else if len(g.rabbits) > rabbit_cap(g, RABBITS_PER_1024_CELLS) && hunt_rabbit(g, p) {
		return true // only rabbits beyond a breeding stock are hunted
	}
	return pursue_forager(g, p)
}

// Whatever a person's specialty has them doing, if there is anything for them to do just now.
pursue_role :: proc(g: ^Game, p: ^Person) -> bool {
	switch p.role {
	case .Forager: return pursue_forager(g, p)
	case .Toolmaker: return pursue_toolmaker(g, p)
	case .Fisher: return pursue_fisher(g, p)
	case .Firekeeper: return pursue_firekeeper(g, p)
	case .Hunter: return pursue_hunter(g, p)
	case .Generalist: return false
	}
	return false
}
