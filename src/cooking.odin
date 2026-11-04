package gods

COOKED_STOMACH :: 40.0 // a cooked meal fills the stomach twice as much as a berry

is_raw_meat :: proc(item: Item) -> bool {
	return item == .Snake_Meat || item == .Fish_Filet || item == .Rabbit_Meat
}

is_cooked :: proc(item: Item) -> bool {
	return item == .Cooked_Snake_Meat || item == .Cooked_Fish_Filet || item == .Cooked_Rabbit_Meat
}

// One fish, cut with a sharp stone, makes two filets. The stone wears.
fillet_fish :: proc(g: ^Game, p: ^Person) -> bool {
	if !holds(p^, .Sharp_Stone) || !spend(g, p, .Fish, 1) {return false}
	wear_tool(p, .Sharp_Stone)
	give_or_drop(g, p, .Fish_Filet)
	give_or_drop(g, p, .Fish_Filet)
	return true
}

// A stick worked with a sharp stone becomes a cooking stick. The stone wears.
craft_cooking_stick :: proc(g: ^Game, p: ^Person) -> bool {
	if holds(p^, .Cooking_Stick) || !holds(p^, .Sharp_Stone) || !spend(g, p, .Stick, 1) {return false}
	wear_tool(p, .Sharp_Stone)
	craft_credit(p, .Cooking_Stick)
	give_or_drop(g, p, .Cooking_Stick)
	return true
}

// The place holding a cooking stick that has this kind of thing on it (or, for .None, nothing), or -1.
stick_where :: proc(p: Person, on: proc(item: Item) -> bool) -> int {
	for h in 0 ..< carry_slots(p) {
		if p.hands[h] == .Cooking_Stick && on(p.loaded[h]) {return h}
	}
	return -1
}

is_bare :: proc(item: Item) -> bool {return item == .None}

// Skewer raw meat, held or lying at the person's feet, onto an empty cooking stick.
load_stick :: proc(g: ^Game, p: ^Person) -> bool {
	h := stick_where(p^, is_bare)
	if h < 0 {return false}
	for meat in ([?]Item{.Fish_Filet, .Rabbit_Meat, .Snake_Meat}) {
		if spend(g, p, meat, 1) {
			p.loaded[h] = meat
			return true
		}
	}
	return false
}

// Hold the stick over a lit fire beside the person. Cooking is a skill: the check is cooking plus
// experience (one point per meal so far). A success cooks the meat and pays dopamine at a shrinking
// rate; a failure burns it to nothing.
cook_on_fire :: proc(g: ^Game, p: ^Person) -> bool {
	h := stick_where(p^, is_raw_meat)
	if h < 0 {return false}
	if _, _, near := neighbour_where(g, p^, lit_pit); !near {return false}
	if skill_succeeds(p.cooking + f32(p.cook_level)) {
		#partial switch p.loaded[h] {
		case .Snake_Meat: p.loaded[h] = .Cooked_Snake_Meat
		case .Rabbit_Meat: p.loaded[h] = .Cooked_Rabbit_Meat
		case: p.loaded[h] = .Cooked_Fish_Filet
		}
		reward_activity(p, p.cook_level)
		p.cook_level += 1
	} else {
		p.loaded[h] = .None // burnt, and ruined
	}
	return true
}

// A hungry person eats a cooked meal off their stick.
eat_cooked :: proc(p: ^Person) -> bool {
	if p.stomach >= EAT_BELOW_STOMACH || p.satiety >= EAT_BELOW_SATIETY {return false}
	h := stick_where(p^, is_cooked)
	if h < 0 {return false}
	p.loaded[h] = .None
	p.stomach = min(p.stomach + COOKED_STOMACH, MAX_STOMACH)
	return true
}
