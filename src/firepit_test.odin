#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(private = "file")
camp :: proc(g: ^Game, w, h: int) {
	game_init_rect(g, w, h)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	for &f in g.fiber {f = 0}
	clear(&g.people)
	clear(&g.rabbits)
	append(&g.people, Person{x = 1, y = 1, health = MAX_HEALTH, satiety = MAX_SATIETY, energy = MAX_ENERGY, sleep_hours = 8, hand_count = DEFAULT_HANDS, crafting = MAX_SKILL, foraging = MAX_SKILL, next_move_hours = 1e9})
}

@(private = "file")
pile :: proc(g: ^Game, x, y: int, item: Item, n: int) {
	for _ in 0 ..< n {append(&g.ground_items, Ground_Item{x = x, y = y, item = item})}
}

@(private = "file")
on_ground :: proc(g: ^Game, item: Item) -> int {
	n := 0
	for it in g.ground_items {
		if it.item == item {n += 1}
	}
	return n
}

@(test)
bow_is_a_stick_strung_with_twine :: proc(t: ^testing.T) {
	rand.reset(141)
	g: Game
	camp(&g, 3, 3)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !craft_bow(&g, p), "nothing")
	p.hands[0] = .Stick
	testing.expect(t, !craft_bow(&g, p), "no twine")
	p.hands[1] = .Twine
	testing.expect(t, craft_bow(&g, p), "bow")
	testing.expect(t, holds(p^, .Bow), "holding a bow")
	testing.expect_value(t, held_count(p^), 1)
	testing.expect_value(t, p.craft_levels[.Bow], 1)
}

@(test)
failed_bow_destroys_the_twine_and_only_the_twine :: proc(t: ^testing.T) {
	rand.reset(142)
	failures := 0
	for _ in 0 ..< 60 {
		g: Game
		camp(&g, 3, 3)
		p := &g.people[0]
		p.crafting = 0
		p.hands[0], p.hands[1] = .Stick, .Twine
		testing.expect(t, craft_bow(&g, p), "an attempt is made")
		if !holds(p^, .Bow) {
			failures += 1
			testing.expect(t, holds(p^, .Stick) && !holds(p^, .Twine), "stick kept, twine gone")
		}
		game_destroy(&g)
	}
	testing.expect(t, failures > 0, "some attempts fail")
}

@(test)
stake_is_a_short_stick_worked_with_a_sharp_stone :: proc(t: ^testing.T) {
	rand.reset(143)
	g: Game
	camp(&g, 3, 3)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Short_Stick
	testing.expect(t, !craft_stake(&g, p), "no sharp stone")
	p.hands[1] = .Sharp_Stone
	testing.expect(t, craft_stake(&g, p), "stake")
	testing.expect(t, holds(p^, .Stake) && holds(p^, .Sharp_Stone) && !holds(p^, .Short_Stick), "the sharp stone is kept, the short stick becomes a stake")
	n, _ := uses_left(p^, .Sharp_Stone)
	testing.expect_value(t, n, SHARP_STONE_DURABILITY - 1) // using the sharp stone wears it
	pile(&g, 1, 1, .Short_Stick, 1) // a short stick at the feet works too
	p.hands[0] = .None
	testing.expect(t, craft_stake(&g, p), "stake from the ground")
	testing.expect_value(t, on_ground(&g, .Short_Stick), 0)
}

@(test)
failed_stake_destroys_the_short_stick_but_keeps_the_sharp_stone :: proc(t: ^testing.T) {
	rand.reset(144)
	failures := 0
	for _ in 0 ..< 60 {
		g: Game
		camp(&g, 3, 3)
		p := &g.people[0]
		p.crafting = 0
		p.hands[0], p.hands[1] = .Short_Stick, .Sharp_Stone
		testing.expect(t, craft_stake(&g, p), "an attempt is made")
		if !holds(p^, .Stake) {
			failures += 1
			testing.expect(t, !holds(p^, .Short_Stick) && holds(p^, .Sharp_Stone), "short stick gone, sharp stone kept")
		}
		game_destroy(&g)
	}
	testing.expect(t, failures > 0, "some attempts fail")
}

@(test)
fire_drill_is_a_bow_and_a_stake :: proc(t: ^testing.T) {
	rand.reset(145)
	g: Game
	camp(&g, 3, 3)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Bow
	testing.expect(t, !craft_fire_drill(&g, p), "no stake")
	p.hands[1] = .Stake
	testing.expect(t, craft_fire_drill(&g, p), "fire drill")
	testing.expect(t, holds(p^, .Fire_Drill) && !holds(p^, .Bow) && !holds(p^, .Stake), "both are used up")
}

@(test)
failed_fire_drill_destroys_nothing :: proc(t: ^testing.T) {
	rand.reset(146)
	failures := 0
	for _ in 0 ..< 60 {
		g: Game
		camp(&g, 3, 3)
		p := &g.people[0]
		p.crafting = 0
		p.hands[0], p.hands[1] = .Bow, .Stake
		testing.expect(t, craft_fire_drill(&g, p), "an attempt is made")
		if !holds(p^, .Fire_Drill) {
			failures += 1
			testing.expect(t, holds(p^, .Bow) && holds(p^, .Stake), "both survive")
		}
		game_destroy(&g)
	}
	testing.expect(t, failures > 0, "some attempts fail")
}

@(test)
firepit_takes_eight_stone_and_eight_sticks_and_goes_on_an_empty_neighbour :: proc(t: ^testing.T) {
	rand.reset(147)
	g: Game
	camp(&g, 3, 3)
	defer game_destroy(&g)
	p := &g.people[0]
	pile(&g, 1, 1, .Stone, 8)
	pile(&g, 1, 1, .Stick, 7)
	testing.expect(t, !build_fire_pit(&g, p), "seven sticks are not enough")
	pile(&g, 1, 1, .Stick, 2)
	pile(&g, 1, 1, .Stone, 1)
	testing.expect(t, build_fire_pit(&g, p), "built")
	testing.expect_value(t, on_ground(&g, .Stone), 1) // only eight were used
	testing.expect_value(t, on_ground(&g, .Stick), 1)
	pits := 0
	for d in DIRS {
		if terrain_at(&g, 1 + d.x, 1 + d.y) == .Fire_Pit {
			pits += 1
			fuel, ok := fuel_at(&g, 1 + d.x, 1 + d.y)
			testing.expect(t, ok && fuel == FIRE_PIT_FUEL, "eight sticks of fuel")
		}
	}
	testing.expect_value(t, pits, 1) // beside the builder, not on their own cell
	testing.expect_value(t, terrain_at(&g, 1, 1), Terrain.Grass)
	testing.expect_value(t, p.craft_levels[.Fire_Pit], 1)
}

@(test)
firepit_can_use_things_in_hand_too :: proc(t: ^testing.T) {
	rand.reset(148)
	g: Game
	camp(&g, 3, 3)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0], p.hands[1] = .Stone, .Stick
	pile(&g, 1, 1, .Stone, 7)
	pile(&g, 1, 1, .Stick, 7)
	testing.expect(t, build_fire_pit(&g, p), "7 on the ground plus 1 in hand of each")
	testing.expect_value(t, held_count(p^), 0)
	testing.expect_value(t, len(g.ground_items), 0)
}

@(test)
firepit_needs_a_free_neighbour_and_cannot_be_walked_on :: proc(t: ^testing.T) {
	rand.reset(149)
	g: Game
	camp(&g, 3, 3)
	defer game_destroy(&g)
	p := &g.people[0]
	pile(&g, 1, 1, .Stone, 8)
	pile(&g, 1, 1, .Stick, 8)
	g.cells[1] = .Pond // north
	g.cells[3] = .Tree // west
	g.cells[5] = .Bush // east
	g.cells[7] = .Pond // south: nowhere to build
	testing.expect(t, !build_fire_pit(&g, p), "no free square next door")
	testing.expect_value(t, len(g.ground_items), 16)
	g.cells[7] = .Grass
	pile(&g, 1, 2, .Fiber, 1) // a little clutter on the one free square does not stop it
	testing.expect(t, build_fire_pit(&g, p), "now there is room")
	testing.expect(t, !walkable(.Fire_Pit), "no walking on it")
	testing.expect(t, !can_enter(&g, 1, 2), "people cannot step onto the pit")
	testing.expect_value(t, len(g.ground_items), 1) // the clutter was moved aside, not lost
	testing.expect_value(t, have_count(&g, p^, .Fiber), 1)
}

@(test)
fresh_worlds_have_no_firepits_and_no_fuel :: proc(t: ^testing.T) {
	rand.reset(150)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for t_, i in g.cells {
		testing.expect(t, t_ != .Fire_Pit, "none to begin with")
		testing.expect_value(t, g.fuel[i], f32(0))
	}
}

@(test)
a_person_with_a_goal_hauls_materials_to_a_site_and_builds_a_firepit :: proc(t: ^testing.T) {
	rand.reset(151)
	g: Game
	camp(&g, 9, 5)
	defer game_destroy(&g)
	g.cells[4 + 0 * 9] = .Stone_Field // a stone field and a tree, a few steps away
	g.stone[4] = 20
	g.cells[8 + 4 * 9] = .Tree
	g.sticks[8 + 4 * 9] = 20
	p := &g.people[0]
	p.dopamine = 0
	for item in Item {p.craft_levels[item] = 50} // old hat, except...
	p.craft_levels[.Fire_Pit] = 0 // ...the firepit: that is the goal
	built := false
	for _ in 0 ..< 3000 {
		p.dopamine = 0
		pursue_goal(&g, p)
		for t_ in g.cells {
			if t_ == .Fire_Pit {built = true}
		}
		if built {break}
	}
	testing.expect(t, built, "the firepit got built")
	testing.expect_value(t, p.craft_levels[.Fire_Pit], 1)
	testing.expect(t, !p.has_site, "the site is forgotten once the pit stands")
}

@(test)
a_lighter_walks_to_a_drill_lying_on_the_ground :: proc(t: ^testing.T) {
	rand.reset(121)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands = {}
	clear(&g.ground_items)
	append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = .Fire_Drill})
	x, y, ok := nearest_ground(&g, p^, .Fire_Drill)
	testing.expect(t, ok && x == p.x && y == p.y, "found the drill")
	testing.expect(t, pick_up(&g, p, .Fire_Drill), "picked it up")
	testing.expect(t, holds(p^, .Fire_Drill), "in hand")
	testing.expect_value(t, len(g.ground_items), 0)
}

@(test)
a_pit_is_built_even_when_every_free_cell_beside_the_builder_has_clutter :: proc(t: ^testing.T) {
	rand.reset(141)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	p := &g.people[0]
	p.x, p.y = 10, 10
	for i in 1 ..< len(g.people) {g.people[i].x, g.people[i].y = 30 + i % 2, 30 + i / 2}
	for d in DIRS {append(&g.ground_items, Ground_Item{x = 10 + d.x, y = 10 + d.y, item = .Twine})}
	for _ in 0 ..< FIRE_PIT_STONES {append(&g.ground_items, Ground_Item{x = 10, y = 10, item = .Stone})}
	for _ in 0 ..< FIRE_PIT_STICKS {append(&g.ground_items, Ground_Item{x = 10, y = 10, item = .Stick})}
	testing.expect(t, build_fire_pit(&g, p), "built")
	px, py, _ := pit_spot(&g, 10, 10)
	_ = px
	_ = py
	pits := 0
	for tt in g.cells {if tt == .Fire_Pit {pits += 1}}
	testing.expect_value(t, pits, 1)
	for it in g.ground_items {
		testing.expect(t, terrain_at(&g, it.x, it.y) != .Fire_Pit, "nothing is buried in the pit")
	}
}
