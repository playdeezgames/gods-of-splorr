#+build !js
package gods

import "core:math/rand"
import "core:testing"

roles_world :: proc(g: ^Game) {
	game_init(g, WORLD_SIZE)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	for &p in g.people {p.hands = {}}
	g.stockpile_x, g.stockpile_y = 5, 5
	clear(&g.ground_items)
}

@(test)
a_tribe_of_five_splits_into_a_division_of_labour :: proc(t: ^testing.T) {
	rand.reset(130)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect_value(t, len(g.people), 5)
	testing.expect_value(t, role_count(&g, .Forager), 1)
	testing.expect_value(t, role_count(&g, .Toolmaker), 1)
	testing.expect_value(t, role_count(&g, .Fisher), 1)
	testing.expect_value(t, role_count(&g, .Firekeeper), 1)
	testing.expect_value(t, role_count(&g, .Hunter), 1)
	testing.expect_value(t, role_count(&g, .Generalist), 0)
}

@(test)
roles_go_to_the_people_best_suited :: proc(t: ^testing.T) {
	rand.reset(131)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for &p in g.people {p.foraging, p.crafting, p.fishing, p.cooking, p.role = 10, 10, 10, 10, .Generalist}
	g.people[3].fishing = 95
	g.people[1].crafting = 90
	g.people[4].cooking = 80
	assign_roles(&g)
	testing.expect_value(t, g.people[3].role, Role.Fisher)
	testing.expect_value(t, g.people[1].role, Role.Toolmaker)
	testing.expect_value(t, g.people[4].role, Role.Firekeeper)
}

@(test)
a_dead_specialist_is_replaced :: proc(t: ^testing.T) {
	rand.reset(132)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for i in 0 ..< len(g.people) {
		if g.people[i].role == .Firekeeper {kill_person(&g, i); break}
	}
	testing.expect_value(t, len(g.people), 4)
	testing.expect_value(t, role_count(&g, .Firekeeper), 1)
	testing.expect_value(t, role_count(&g, .Generalist), 0)
}

@(test)
a_forager_hauls_raw_material_to_the_stockpile :: proc(t: ^testing.T) {
	rand.reset(133)
	g: Game
	roles_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.role, p.x, p.y = .Forager, 5, 5
	p.hands = {0 = .Stick, 1 = .Fiber}
	testing.expect(t, pursue_forager(&g, p), "drops one")
	testing.expect(t, pursue_forager(&g, p), "drops the other")
	testing.expect_value(t, stock_of(&g, .Stick), 1)
	testing.expect_value(t, stock_of(&g, .Fiber), 1)
}

@(test)
a_toolmaker_makes_a_net_from_the_stockpile_and_leaves_it_there :: proc(t: ^testing.T) {
	rand.reset(134)
	g: Game
	roles_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.role, p.x, p.y, p.crafting = .Toolmaker, 5, 5, MAX_SKILL
	for _ in 0 ..< 10 {append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Fiber})}
	for _ in 0 ..< 4 {append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Stone})}
	for _ in 0 ..< 60 {pursue_toolmaker(&g, p)}
	testing.expect_value(t, stock_of(&g, .Net), 1)
}

@(test)
a_fisher_takes_a_net_and_brings_fish_back :: proc(t: ^testing.T) {
	rand.reset(135)
	g: Game
	roles_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.role, p.x, p.y = .Fisher, 5, 5
	append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Net})
	testing.expect(t, pursue_fisher(&g, p), "takes the net")
	testing.expect(t, holds(p^, .Net), "net in hand")
	p.hands[1] = .Fish
	testing.expect(t, pursue_fisher(&g, p), "leaves the fish")
	testing.expect_value(t, stock_of(&g, .Fish), 1)
}

@(test)
a_cooked_meal_left_on_the_stockpile_feeds_anyone :: proc(t: ^testing.T) {
	rand.reset(136)
	g: Game
	roles_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.x, p.y, p.stomach, p.satiety = 5, 5, 0, 10
	append(&g.ground_items, Ground_Item{x = 5, y = 5, item = .Cooking_Stick, loaded = .Cooked_Fish_Filet})
	testing.expect(t, edible_on_ground(&g, g.ground_items[0]), "food on a stick")
	testing.expect(t, eat_from_ground(&g, p), "ate it")
	testing.expect_value(t, p.stomach, f32(COOKED_STOMACH))
	testing.expect(t, !edible_on_ground(&g, g.ground_items[0]), "the stick is bare")
}

@(test)
things_on_the_cells_around_a_person_are_within_reach :: proc(t: ^testing.T) {
	rand.reset(143)
	g: Game
	roles_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.x, p.y, p.crafting = 5, 5, MAX_SKILL
	append(&g.ground_items, Ground_Item{x = 6, y = 4, item = .Fiber}) // diagonal
	append(&g.ground_items, Ground_Item{x = 4, y = 5, item = .Fiber}) // beside
	append(&g.ground_items, Ground_Item{x = 8, y = 5, item = .Fiber}) // too far
	testing.expect_value(t, have_count(&g, p^, .Fiber), 2)
	testing.expect(t, craft_twine(&g, p), "twine from fibres around the feet")
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].x, 8)
}

@(test)
a_forager_can_stash_beside_a_stockpile_someone_is_standing_on :: proc(t: ^testing.T) {
	rand.reset(144)
	g: Game
	roles_world(&g)
	defer game_destroy(&g)
	g.people[1].x, g.people[1].y = 5, 5 // the toolmaker stands on the stockpile
	p := &g.people[0]
	p.role, p.x, p.y = .Forager, 6, 5
	p.hands = {0 = .Stick, 1 = .Stick}
	testing.expect(t, pursue_forager(&g, p), "drops one beside it")
	testing.expect(t, pursue_forager(&g, p), "and the other")
	testing.expect_value(t, stock_of(&g, .Stick), 2)
}
