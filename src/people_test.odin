#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(test)
two_people_start_on_grass :: proc(t: ^testing.T) {
	rand.reset(3)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect_value(t, len(g.people), 2)
	testing.expect_value(t, g.people[0].sex, Sex.Male)
	testing.expect_value(t, g.people[1].sex, Sex.Female)
	for p in g.people {
		testing.expect_value(t, terrain_at(&g, p.x, p.y), Terrain.Grass)
	}
	testing.expect(t, g.people[0].x != g.people[1].x || g.people[0].y != g.people[1].y, "distinct cells")
}

@(test)
people_only_ever_walk_on_grass :: proc(t: ^testing.T) {
	rand.reset(11)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	start := [2][2]int{{g.people[0].x, g.people[0].y}, {g.people[1].x, g.people[1].y}}
	moved := false
	for _ in 0 ..< 5000 {
		g.clock.hours += 0.1
		update_people(&g)
		for p in g.people {
			testing.expect(t, in_bounds(&g, p.x, p.y), "in bounds")
			testing.expect_value(t, terrain_at(&g, p.x, p.y), Terrain.Grass)
		}
		testing.expect(t, g.people[0].x != g.people[1].x || g.people[0].y != g.people[1].y, "never share a cell")
	}
	for p, i in g.people {
		if p.x != start[i].x || p.y != start[i].y {moved = true}
	}
	testing.expect(t, moved, "people wander")
}

@(test)
only_grass_is_walkable :: proc(t: ^testing.T) {
	for terrain in Terrain {
		testing.expect_value(t, walkable(terrain), terrain == .Grass)
	}
}

@(test)
cannot_walk_into_blocked_cells :: proc(t: ^testing.T) {
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	g.cells[0] = .Tree
	testing.expect(t, !can_enter(&g, 0, 0), "tree blocks")
	g.cells[1] = .Grass
	g.people[0].x, g.people[0].y = 1, 0
	testing.expect(t, !can_enter(&g, 1, 0), "occupied blocks")
	testing.expect(t, !can_enter(&g, -1, 0), "edge blocks")
}

luminance :: proc(c: [3]f32) -> f32 {
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
}

@(test)
more_melanin_is_darker_and_always_brown :: proc(t: ^testing.T) {
	prev := luminance(skin_color(0))
	for i in 1 ..= 10 {
		c := skin_color(f32(i) / 10)
		testing.expect(t, luminance(c) < prev, "darker with more melanin")
		testing.expect(t, c.r > c.g && c.g > c.b, "always a shade of brown")
		prev = luminance(c)
	}
	testing.expect_value(t, skin_color(-5), skin_color(0))
	testing.expect_value(t, skin_color(5), skin_color(1))
}

@(test)
people_get_melanin_in_range_with_variety :: proc(t: ^testing.T) {
	rand.reset(5)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	lo, hi: f32 = 1, 0
	for _ in 0 ..< 200 {
		m := random_melanin()
		testing.expect(t, m >= 0 && m <= 1, "in range")
		lo, hi = min(lo, m), max(hi, m)
	}
	testing.expect(t, lo < 0.2 && hi > 0.8, "both light and dark occur")
	for p in g.people {
		testing.expect(t, p.melanin >= 0 && p.melanin <= 1, "person melanin in range")
	}
}
