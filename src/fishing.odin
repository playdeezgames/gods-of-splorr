package gods

// A net is four twine knotted together. A failed attempt ruins two of them. It wears out with use.
NET_TWINE :: 4
NET_TWINE_LOST :: 2
NET_DURABILITY :: 10

craft_net :: proc(g: ^Game, p: ^Person) -> bool {
	if holds(p^, .Net) {return false}
	ingredients: [NET_TWINE]Item
	for &item in ingredients {item = .Twine}
	return craft_recipe(g, p, ingredients[:], .Net, fail_loss = NET_TWINE_LOST)
}

// Fishing is its own skill: the check is the person's fishing skill plus their experience (one point
// for every fish caught so far). Catching a fish pays dopamine at a shrinking rate.
fishing_check :: proc(p: Person) -> bool {
	return skill_succeeds(p.fishing + f32(p.fish_level))
}

// Cast the net into the pond at (px, py): the person must be orthogonally beside it and the pond
// must hold a whole fish. Every cast wears the net; a catch takes a fish from the pond.
fish_pond :: proc(g: ^Game, p: ^Person, px, py: int) -> bool {
	if !holds(p^, .Net) {return false}
	if abs(p.x - px) + abs(p.y - py) != 1 {return false}
	if left, ok := fish_at(g, px, py); !ok || left < 1 {return false}
	wear_tool(p, .Net)
	if !fishing_check(p^) {return true} // the fish got away
	g.fish[py * g.width + px] -= 1
	reward_activity(p, p.fish_level)
	p.fish_level += 1
	give_or_drop(g, p, .Fish)
	return true
}

fish_adjacent :: proc(g: ^Game, p: ^Person) -> bool {
	for d in DIRS {
		if fish_pond(g, p, p.x + d.x, p.y + d.y) {return true}
	}
	return false
}

pond_with_fish :: proc(g: ^Game, x, y: int) -> bool {
	left, ok := fish_at(g, x, y)
	return ok && left >= 1
}
