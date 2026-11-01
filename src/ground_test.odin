#+build !js
package gods

import "core:math/rand"
import "core:testing"

blank_world :: proc(g: ^Game) {
	game_init_rect(g, 5, 1)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
}

@(test)
stone_fields_are_weighted_between_pond_and_bush :: proc(t: ^testing.T) {
	w := TERRAIN_WEIGHTS[.Stone_Field]
	testing.expect(t, w > TERRAIN_WEIGHTS[.Pond] && w < TERRAIN_WEIGHTS[.Bush], "between")
	testing.expect_value(t, TERRAIN_WEIGHTS[.Dirt], 0)
}

@(test)
generated_stone_fields_start_full :: proc(t: ^testing.T) {
	rand.reset(5)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	count := 0
	for cell, i in g.cells {
		testing.expect(t, cell != .Dirt, "no dirt at the start")
		if cell == .Stone_Field {
			count += 1
			testing.expect_value(t, g.stone[i], f32(STONE_FIELD_AMOUNT))
		}
	}
	testing.expect(t, count > 0, "world has stone fields")
}

@(test)
people_walk_on_stone_and_dirt_not_trees :: proc(t: ^testing.T) {
	testing.expect(t, walkable(.Stone_Field) && walkable(.Dirt) && walkable(.Grass), "walkable")
	testing.expect(t, !walkable(.Tree) && !walkable(.Pond) && !walkable(.Bush), "blocked")
}

@(test)
depleted_stone_field_becomes_dirt :: proc(t: ^testing.T) {
	g: Game
	blank_world(&g)
	defer game_destroy(&g)
	g.cells[2] = .Stone_Field
	g.stone[2] = 5
	testing.expect_value(t, take_stone(&g, 2, 0, 3), f32(3))
	testing.expect_value(t, g.cells[2], Terrain.Stone_Field)
	testing.expect_value(t, take_stone(&g, 2, 0, 10), f32(2))
	testing.expect_value(t, g.cells[2], Terrain.Dirt)
	testing.expect_value(t, take_stone(&g, 2, 0, 1), f32(0))
}

@(test)
dirt_next_to_grass_becomes_grass_but_isolated_dirt_does_not :: proc(t: ^testing.T) {
	g: Game
	game_init_rect(&g, 5, 5)
	defer game_destroy(&g)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Tree}
	g.cells[0] = .Grass
	g.cells[1] = .Dirt // beside the grass
	g.cells[24] = .Dirt // surrounded by trees
	g.clock.hours += 10000
	update_ground(&g)
	testing.expect_value(t, g.cells[1], Terrain.Grass)
	testing.expect_value(t, g.cells[24], Terrain.Dirt)
}

@(test)
grass_spreads_one_cell_per_update :: proc(t: ^testing.T) {
	g: Game
	blank_world(&g)
	defer game_destroy(&g)
	g.cells[1], g.cells[2], g.cells[3], g.cells[4] = .Dirt, .Dirt, .Dirt, .Dirt
	g.clock.hours += 100000
	update_ground(&g)
	testing.expect_value(t, g.cells[1], Terrain.Grass)
	testing.expect_value(t, g.cells[2], Terrain.Dirt)
}

@(test)
grass_starts_with_fiber_and_regrows_slower_than_berries :: proc(t: ^testing.T) {
	rand.reset(4)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for cell, i in g.cells {
		if cell == .Grass {testing.expect_value(t, g.fiber[i], f32(FIBER_PER_GRASS))}
	}
	testing.expect(t, FIBER_REGROW_PER_HOUR < BUSH_GROWTH_PER_HOUR, "slower than berries")
}

@(test)
taking_all_the_fiber_turns_grass_to_dirt :: proc(t: ^testing.T) {
	g: Game
	blank_world(&g)
	defer game_destroy(&g)
	g.fiber[2] = 2.5
	testing.expect_value(t, take_fiber(&g, 2, 0), f32(1))
	testing.expect_value(t, take_fiber(&g, 2, 0), f32(1))
	testing.expect_value(t, g.cells[2], Terrain.Grass)
	testing.expect_value(t, take_fiber(&g, 2, 0), f32(0.5)) // the remainder still counts as one gather
	testing.expect_value(t, g.cells[2], Terrain.Dirt)
	testing.expect_value(t, take_fiber(&g, 2, 0), f32(0))
}

@(test)
partly_gathered_grass_regrows_to_its_cap_and_new_grass_starts_small :: proc(t: ^testing.T) {
	g: Game
	blank_world(&g)
	defer game_destroy(&g)
	g.fiber[1] = 1
	g.fiber[2] = FIBER_PER_GRASS
	g.cells[3] = .Dirt
	g.clock.hours += 10
	update_ground(&g)
	testing.expect(t, abs(g.fiber[1] - (1 + 10 * FIBER_REGROW_PER_HOUR)) < 1e-4, "regrew")
	testing.expect_value(t, g.fiber[2], f32(FIBER_PER_GRASS))
	g.clock.hours += 100000
	update_ground(&g)
	testing.expect_value(t, g.fiber[1], f32(FIBER_PER_GRASS))
	testing.expect_value(t, g.cells[3], Terrain.Grass)
	testing.expect(t, g.fiber[3] >= FIBER_ON_NEW_GRASS, "greened dirt has fiber")
}

@(test)
trees_start_with_sticks_and_regrow_far_slower_than_fiber :: proc(t: ^testing.T) {
	rand.reset(6)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for cell, i in g.cells {
		if cell == .Tree {testing.expect_value(t, g.sticks[i], f32(STICKS_PER_TREE))}
	}
	testing.expect(t, STICK_REGROW_PER_HOUR * 5 < FIBER_REGROW_PER_HOUR, "much slower than fiber")
	g2: Game
	blank_world(&g2)
	defer game_destroy(&g2)
	g2.cells[2] = .Tree
	g2.sticks[2] = 0
	g2.clock.hours += 100
	update_ground(&g2)
	testing.expect(t, abs(g2.sticks[2] - 100 * STICK_REGROW_PER_HOUR) < 1e-4, "regrew")
	g2.clock.hours += 1e6
	update_ground(&g2)
	testing.expect_value(t, g2.sticks[2], f32(STICKS_PER_TREE))
}
