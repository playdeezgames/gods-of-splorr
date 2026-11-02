#+build !js
package gods

import "core:math/rand"
import "core:testing"

// A 5x1 strip of grass with nothing on it, so snake behaviour is easy to follow.
@(private = "file")
strip :: proc(g: ^Game) {
	game_init_rect(g, 5, 1)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	clear(&g.people)
}

@(private = "file")
add_person :: proc(g: ^Game, x, y: int) {
	append(&g.people, Person{x = x, y = y, health = MAX_HEALTH, satiety = MAX_SATIETY, stomach = 0, energy = MAX_ENERGY, sleep_hours = 8, hand_count = DEFAULT_HANDS, next_move_hours = 1e9})
}

@(test)
poison_drains_health_for_its_duration_only :: proc(t: ^testing.T) {
	p := Person{health = MAX_HEALTH, satiety = MAX_SATIETY, energy = MAX_ENERGY, sleep_hours = 8}
	poison_person(&p)
	testing.expect_value(t, p.poison_hours, f32(POISON_HOURS_PER_BITE))
	step_vitals(&p, 4)
	testing.expect(t, abs(p.health - (MAX_HEALTH - 4 * POISON_PER_HOUR)) < 1e-3, "4 hours of poison")
	step_vitals(&p, 8) // only the remaining 6 hours hurt
	testing.expect(t, abs(p.health - (MAX_HEALTH - POISON_HOURS_PER_BITE * POISON_PER_HOUR)) < 1e-3, "poison ran out")
	testing.expect_value(t, p.poison_hours, f32(0))
}

@(test)
bites_stack_up_to_a_cap :: proc(t: ^testing.T) {
	p: Person
	for _ in 0 ..< 10 {poison_person(&p)}
	testing.expect_value(t, p.poison_hours, f32(MAX_POISON_HOURS))
}

@(test)
snake_closes_in_and_bites_an_adjacent_person :: proc(t: ^testing.T) {
	rand.reset(31)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 4, 0)
	testing.expect(t, spawn_snake(&g, 0, 0), "spawned")
	for _ in 0 ..< 200 {
		g.clock.hours += 0.05
		update_snakes(&g)
	}
	testing.expect_value(t, g.snakes[0].x, 3) // right next to the person, who blocks the way
	testing.expect(t, g.people[0].poison_hours > 0, "bitten")
}

@(test)
snakes_and_people_never_share_a_cell :: proc(t: ^testing.T) {
	rand.reset(32)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 2, 0)
	testing.expect(t, !spawn_snake(&g, 2, 0), "occupied by a person")
	testing.expect(t, spawn_snake(&g, 1, 0), "free")
	testing.expect(t, !spawn_snake(&g, 1, 0), "occupied by a snake")
	testing.expect(t, !can_enter(&g, 1, 0), "people cannot step onto a snake")
}

@(test)
snake_leaves_after_its_lifetime :: proc(t: ^testing.T) {
	rand.reset(33)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	spawn_snake(&g, 2, 0)
	g.clock.hours += SNAKE_LIFE_HOURS - 1
	update_snakes(&g)
	testing.expect_value(t, len(g.snakes), 1)
	g.clock.hours += 2
	update_snakes(&g)
	testing.expect_value(t, len(g.snakes), 0)
}

@(test)
snake_wanders_when_nobody_is_near :: proc(t: ^testing.T) {
	rand.reset(34)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	spawn_snake(&g, 2, 0)
	moved := false
	for _ in 0 ..< 100 {
		g.clock.hours += 0.2
		update_snakes(&g)
		testing.expect(t, in_bounds(&g, g.snakes[0].x, g.snakes[0].y), "stays in the world")
		if g.snakes[0].x != 2 {moved = true}
	}
	testing.expect(t, moved, "it moved")
}

@(test)
people_step_away_from_a_close_snake :: proc(t: ^testing.T) {
	rand.reset(35)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 2, 0)
	spawn_snake(&g, 1, 0)
	testing.expect(t, flee_snake(&g, &g.people[0]), "snake is close")
	testing.expect_value(t, g.people[0].x, 3)
}

@(test)
cornered_people_stand_still_and_distant_ones_ignore_snakes :: proc(t: ^testing.T) {
	rand.reset(36)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 4, 0)
	spawn_snake(&g, 3, 0)
	testing.expect(t, flee_snake(&g, &g.people[0]), "snake is close")
	testing.expect_value(t, g.people[0].x, 4) // nowhere to go

	clear(&g.snakes)
	spawn_snake(&g, 0, 0) // four cells away is out of range
	testing.expect(t, !flee_snake(&g, &g.people[0]), "too far to care")
	testing.expect_value(t, g.people[0].x, 4)
}

@(test)
fleeing_people_in_the_open_keep_out_of_reach :: proc(t: ^testing.T) {
	rand.reset(37)
	g: Game
	game_init_rect(&g, 9, 9)
	defer game_destroy(&g)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	clear(&g.people)
	add_person(&g, 4, 4)
	g.people[0].next_move_hours = 0
	spawn_snake(&g, 3, 4)
	g.snakes[0].next_move_hours = 1e9 // a snake that stays put
	for _ in 0 ..< 20 {
		g.clock.hours += 0.2
		update_people(&g)
	}
	p := g.people[0]
	testing.expect(t, max(abs(p.x - 3), abs(p.y - 4)) > 1, "never next to the snake")
}

@(private = "file")
count_on_ground :: proc(g: ^Game, item: Item) -> int {
	n := 0
	for it in g.ground_items {
		if it.item == item {n += 1}
	}
	return n
}

@(test)
spear_is_a_sharp_stone_a_stick_and_twine :: proc(t: ^testing.T) {
	rand.reset(41)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 2, 0)
	p := &g.people[0]
	p.crafting = MAX_SKILL
	testing.expect(t, !craft_spear(&g, p), "nothing")
	p.hands[0], p.hands[1] = .Sharp_Stone, .Short_Stick
	testing.expect(t, !craft_spear(&g, p), "a short stick is not enough")
	p.hands[1] = .Stick
	testing.expect(t, !craft_spear(&g, p), "no twine")
	append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Twine}) // twine at the feet counts
	testing.expect(t, craft_spear(&g, p), "craft")
	testing.expect(t, holds(p^, .Spear), "holding a spear")
	testing.expect_value(t, held_count(p^), 1)
	testing.expect_value(t, len(g.ground_items), 0)
}

@(test)
failed_spear_wastes_only_the_twine :: proc(t: ^testing.T) {
	rand.reset(42)
	failures := 0
	for _ in 0 ..< 60 {
		g: Game
		strip(&g)
		add_person(&g, 2, 0)
		p := &g.people[0]
		p.crafting = 0 // 25% success
		p.hands[0], p.hands[1] = .Sharp_Stone, .Stick
		append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Twine})
		testing.expect(t, craft_spear(&g, p), "an attempt is made")
		if !holds(p^, .Spear) {
			failures += 1
			testing.expect(t, holds(p^, .Sharp_Stone) && holds(p^, .Stick), "stone and stick kept")
			testing.expect_value(t, len(g.ground_items), 0) // the twine is gone
		}
		game_destroy(&g)
	}
	testing.expect(t, failures > 0, "some attempts fail")
}

@(test)
nobody_makes_a_second_spear :: proc(t: ^testing.T) {
	rand.reset(43)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 2, 0)
	p := &g.people[0]
	p.hands[0] = .Spear
	append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Sharp_Stone}, Ground_Item{x = 2, y = 0, item = .Stick}, Ground_Item{x = 2, y = 0, item = .Twine})
	testing.expect(t, !craft_spear(&g, p), "already armed")
}

@(test)
person_with_a_spear_hunts_a_snake_and_leaves_a_corpse :: proc(t: ^testing.T) {
	rand.reset(44)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 0, 0)
	g.people[0].hands[0] = .Spear
	spawn_snake(&g, 3, 0)
	g.snakes[0].next_move_hours = 1e9 // a snake that stays put
	g.people[0].ranged, g.snakes[0].dodge = MAX_SKILL, 0
	for _ in 0 ..< 50 {
		if len(g.snakes) == 0 {break}
		testing.expect(t, hunt_snake(&g, &g.people[0]), "hunting")
	}
	testing.expect_value(t, len(g.snakes), 0)
	testing.expect_value(t, count_on_ground(&g, .Snake_Corpse), 1)
	testing.expect_value(t, g.ground_items[0].x, 3)
	testing.expect(t, !hunt_snake(&g, &g.people[0]), "nothing left to hunt")
}

@(test)
unarmed_people_do_not_hunt_and_armed_ones_do_not_flee :: proc(t: ^testing.T) {
	rand.reset(45)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 2, 0)
	spawn_snake(&g, 4, 0)
	testing.expect(t, !hunt_snake(&g, &g.people[0]), "no spear")
	g.people[0].hands[0] = .Spear
	testing.expect(t, !flee_snake(&g, &g.people[0]), "the armed stand their ground")
}

@(test)
person_with_a_knife_skins_a_snake_corpse :: proc(t: ^testing.T) {
	rand.reset(46)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 0, 0)
	p := &g.people[0]
	p.crafting = MAX_SKILL
	testing.expect(t, !skin_snake(&g, p), "no knife")
	p.hands[0] = .Knife
	testing.expect(t, !skin_snake(&g, p), "no corpse")
	append(&g.ground_items, Ground_Item{x = 3, y = 0, item = .Snake_Corpse})
	for _ in 0 ..< 3 { // walk over
		testing.expect(t, skin_snake(&g, p), "heading for the corpse")
	}
	testing.expect_value(t, p.x, 3)
	testing.expect(t, skin_snake(&g, p), "skinning")
	testing.expect_value(t, count_on_ground(&g, .Snake_Corpse), 0)
	testing.expect_value(t, count_on_ground(&g, .Snake_Meat), 1)
	testing.expect_value(t, count_on_ground(&g, .Snake_Skin), 1)
	testing.expect(t, !skin_snake(&g, p), "nothing more to skin")
}

@(test)
clumsy_skinning_ruins_the_skin_but_not_the_meat :: proc(t: ^testing.T) {
	rand.reset(47)
	ruined := 0
	for _ in 0 ..< 60 {
		g: Game
		strip(&g)
		add_person(&g, 1, 0)
		p := &g.people[0]
		p.crafting = 0
		p.hands[0] = .Knife
		append(&g.ground_items, Ground_Item{x = 1, y = 0, item = .Snake_Corpse})
		testing.expect(t, skin_snake(&g, p), "skinning")
		testing.expect_value(t, count_on_ground(&g, .Snake_Meat), 1)
		if count_on_ground(&g, .Snake_Skin) == 0 {ruined += 1}
		game_destroy(&g)
	}
	testing.expect(t, ruined > 0, "some skins are ruined")
}

@(test)
snake_corpse_rots_like_food :: proc(t: ^testing.T) {
	rand.reset(48)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	append(&g.ground_items, Ground_Item{x = 1, y = 0, item = .Snake_Corpse, dropped_hours = g.clock.hours})
	g.clock.hours += FOOD_SPOIL_HOURS + 1
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 0)
}

@(test)
tools_wear_out_and_break :: proc(t: ^testing.T) {
	p := Person{hand_count = DEFAULT_HANDS}
	p.hands[1] = .Spear
	n, ok := uses_left(p, .Spear)
	testing.expect(t, ok && n == SPEAR_DURABILITY, "a fresh spear")
	for i in 1 ..< SPEAR_DURABILITY {
		testing.expect(t, !wear_tool(&p, .Spear), "still holds together")
		n, _ = uses_left(p, .Spear)
		testing.expect_value(t, n, SPEAR_DURABILITY - i)
	}
	testing.expect(t, wear_tool(&p, .Spear), "the last use breaks it")
	testing.expect(t, !holds(p, .Spear), "gone")
	testing.expect_value(t, p.wear[1], 0)
	testing.expect(t, !wear_tool(&p, .Spear), "nothing to wear")
	testing.expect_value(t, durability_of(.Stone), 0)
}

@(test)
spear_breaks_after_enough_thrusts :: proc(t: ^testing.T) {
	rand.reset(51)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 3, 0)
	g.people[0].hands[0] = .Spear
	for _ in 0 ..< SPEAR_DURABILITY { // keep a snake next to the hunter; each thrust wears the spear
		clear(&g.snakes)
		spawn_snake(&g, 4, 0)
		testing.expect(t, hunt_snake(&g, &g.people[0]), "thrust")
	}
	testing.expect(t, !holds(g.people[0], .Spear), "the spear broke")
}

@(test)
knife_breaks_after_enough_skinnings :: proc(t: ^testing.T) {
	rand.reset(52)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 1, 0)
	g.people[0].hands[0] = .Knife
	for i in 0 ..< KNIFE_DURABILITY {
		testing.expect(t, holds(g.people[0], .Knife), "still has the knife")
		append(&g.ground_items, Ground_Item{x = 1, y = 0, item = .Snake_Corpse})
		testing.expect(t, skin_snake(&g, &g.people[0]), "skinning")
		n, _ := uses_left(g.people[0], .Knife)
		if i + 1 < KNIFE_DURABILITY {testing.expect_value(t, n, KNIFE_DURABILITY - i - 1)}
	}
	testing.expect(t, !holds(g.people[0], .Knife), "the knife broke")
}

@(test)
newly_made_tools_start_unworn :: proc(t: ^testing.T) {
	rand.reset(53)
	g: Game
	strip(&g)
	defer game_destroy(&g)
	add_person(&g, 1, 0)
	p := &g.people[0]
	p.wear[0] = 5 // left over from an old tool that broke
	give_or_drop(&g, p, .Knife)
	n, _ := uses_left(p^, .Knife)
	testing.expect_value(t, n, KNIFE_DURABILITY)
}

@(test)
hit_chance_follows_ranged_against_dodge :: proc(t: ^testing.T) {
	testing.expect_value(t, hit_chance(50, 50), f32(0.5))
	testing.expect_value(t, hit_chance(0, 0), f32(0.5))
	testing.expect(t, abs(hit_chance(100, 0) - 0.95) < 1e-6, "a master against a sitting duck")
	testing.expect(t, abs(hit_chance(0, 100) - 0.05) < 1e-6, "a novice against a slippery snake")
	testing.expect(t, hit_chance(70, 40) > hit_chance(50, 40), "more ranged skill helps")
	testing.expect(t, hit_chance(50, 70) < hit_chance(50, 40), "more dodge hurts")
	testing.expect(t, hit_chance(-50, 200) >= MIN_HIT_CHANCE, "never below the floor")
	testing.expect(t, hit_chance(200, -50) <= MAX_HIT_CHANCE, "never above the ceiling")
}

@(private = "file")
kill_rate :: proc(ranged, dodge: f32) -> int {
	kills := 0
	for _ in 0 ..< 400 {
		g: Game
		strip(&g)
		add_person(&g, 3, 0)
		g.people[0].hands[0] = .Spear
		g.people[0].ranged = ranged
		spawn_snake(&g, 4, 0)
		g.snakes[0].dodge = dodge
		hunt_snake(&g, &g.people[0])
		if len(g.snakes) == 0 {kills += 1}
		game_destroy(&g)
	}
	return kills
}

@(test)
skilled_hunters_kill_more_and_dodgy_snakes_survive_more :: proc(t: ^testing.T) {
	rand.reset(61)
	good, bad, slippery := kill_rate(100, 0), kill_rate(0, 100), kill_rate(100, 100)
	testing.expect(t, good > 330, "a master hits nearly always")
	testing.expect(t, bad < 70, "a novice against a slippery snake rarely does")
	testing.expect(t, slippery > bad && slippery < good, "dodge cancels skill")
}

@(test)
snakes_and_people_get_their_stats_at_birth :: proc(t: ^testing.T) {
	rand.reset(62)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for p in g.people {
		testing.expect(t, p.ranged >= 0 && p.ranged <= MAX_SKILL, "ranged in range")
	}
	for y in 0 ..< g.height {
		for x in 0 ..< g.width {spawn_snake(&g, x, y)}
	}
	testing.expect(t, len(g.snakes) > 3, "several snakes")
	for s in g.snakes {
		testing.expect(t, s.dodge >= 0 && s.dodge <= MAX_SKILL, "dodge in range")
	}
}
