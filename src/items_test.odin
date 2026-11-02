#+build !js
package gods

import "core:math/rand"
import "core:testing"

// A 5x1 grass world with one person at x=2.
item_world :: proc(g: ^Game) {
	game_init_rect(g, 5, 1)
	clear(&g.people)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	append(&g.people, Person{x = 2, y = 0, health = MAX_HEALTH, satiety = 50, stomach = 50, energy = 100, sleep_hours = 8, foraging = MAX_SKILL, crafting = MAX_SKILL, hand_count = DEFAULT_HANDS})
}

@(test)
person_gathers_stone_from_the_field_they_stand_on :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !gather_stone_here(&g, p), "not on a stone field")
	g.cells[2], g.stone[2] = .Stone_Field, 2
	testing.expect(t, gather_stone_here(&g, p), "first")
	testing.expect_value(t, p.hands[0], Item.Stone)
	testing.expect_value(t, g.stone[2], f32(1))
	testing.expect(t, gather_stone_here(&g, p), "second")
	testing.expect_value(t, g.cells[2], Terrain.Dirt) // used up
	testing.expect(t, !gather_stone_here(&g, p), "hands full and field gone")
}

@(test)
dropped_items_land_at_the_persons_feet :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[1] = .Stone
	testing.expect(t, !drop_item(&g, p, 0), "empty hand")
	testing.expect(t, drop_item(&g, p, 1), "drop")
	testing.expect_value(t, p.hands[1], Item.None)
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].item, Item.Stone)
	testing.expect_value(t, g.ground_items[0].x, 2)
}

@(test)
dropped_food_spoils_and_rots_away_but_stone_stays :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0], p.hands[1] = .Food, .Stone
	drop_item(&g, p, 0)
	drop_item(&g, p, 1)
	g.clock.hours += FOOD_SPOIL_HOURS / 2
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 2)
	testing.expect(t, abs(ground_freshness(&g, g.ground_items[0]) - 0.5) < 1e-4, "half fresh")
	g.clock.hours += FOOD_SPOIL_HOURS
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].item, Item.Stone)
}

@(test)
hungry_person_eats_dropped_food_in_proportion_to_freshness :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.stomach = 0
	append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Food, dropped_hours = g.clock.hours})
	g.clock.hours += FOOD_SPOIL_HOURS / 2
	testing.expect(t, eat_from_ground(&g, p), "eats")
	testing.expect(t, abs(p.stomach - FOOD_STOMACH / 2) < 1e-3, "half-spoiled food fills half")
	testing.expect_value(t, len(g.ground_items), 0)
	p.stomach = 80 // not hungry
	append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Food, dropped_hours = g.clock.hours})
	testing.expect(t, !eat_from_ground(&g, p), "not hungry")
}

@(test)
full_hands_beside_a_berry_bush_drop_a_stone :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0], p.hands[1] = .Stone, .Stone
	testing.expect(t, !drop_something(&g, p) || len(g.ground_items) == 1, "only a chance drop without a bush")
	clear(&g.ground_items)
	p.hands[0], p.hands[1] = .Stone, .Stone
	g.cells[3] = .Bush
	g.bushes[3] = Bush{food = 5, max_food = 5}
	testing.expect(t, drop_something(&g, p), "drops to make room")
	testing.expect_value(t, held_count(p^), 1)
	testing.expect(t, gather_adjacent(&g, p), "can now take berries")
}

@(test)
person_gathers_and_drops_plant_fiber :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	g.fiber[2] = 1.5
	testing.expect(t, gather_fiber_here(&g, p), "first")
	testing.expect_value(t, p.hands[0], Item.Fiber)
	testing.expect(t, gather_fiber_here(&g, p), "second takes the rest")
	testing.expect_value(t, g.cells[2], Terrain.Dirt)
	testing.expect(t, !gather_fiber_here(&g, p), "hands full")
	testing.expect(t, drop_item(&g, p, 0), "drop")
	testing.expect_value(t, g.ground_items[0].item, Item.Fiber)
	buf: [80]byte
	testing.expect_value(t, describe_ground_items(&g, 2, 0, buf[:]), "1 fiber")
	g.clock.hours += FIBER_SPOIL_HOURS + 1
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 0) // fiber rots away
}

@(test)
person_gathers_sticks_from_an_adjacent_tree_until_it_is_bare :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	g.cells[3] = .Tree
	g.sticks[3] = 2
	testing.expect(t, !gather_stick(&g, p, 4, 0), "not adjacent")
	testing.expect(t, gather_stick_adjacent(&g, p), "first")
	testing.expect_value(t, p.hands[0], Item.Stick)
	testing.expect(t, gather_stick_adjacent(&g, p), "second")
	p.hands[0], p.hands[1] = .None, .None
	testing.expect(t, !gather_stick_adjacent(&g, p), "bare")
	testing.expect_value(t, g.cells[3], Terrain.Tree) // the tree stays
	p.hands[0], p.hands[1] = .Stick, .Stick
	testing.expect(t, !gather_stick_adjacent(&g, p), "hands full")
	drop_item(&g, p, 0)
	buf: [80]byte
	testing.expect_value(t, describe_ground_items(&g, 2, 0, buf[:]), "1 stick")
}

@(test)
two_fibers_make_one_twine_which_can_be_dropped :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !craft_twine(p), "nothing in hand")
	p.hands[0] = .Fiber
	testing.expect(t, !craft_twine(p), "one fiber is not enough")
	p.hands[1] = .Stick
	testing.expect(t, !craft_twine(p), "a stick is not fiber")
	p.hands[1] = .Fiber
	testing.expect(t, craft_twine(p), "two fibers")
	testing.expect_value(t, p.hands[0], Item.Twine)
	testing.expect_value(t, p.hands[1], Item.None)
	testing.expect(t, !craft_twine(p), "the fibers are used up")
	testing.expect(t, drop_item(&g, p, 0), "drop twine")
	buf: [80]byte
	testing.expect_value(t, describe_ground_items(&g, 2, 0, buf[:]), "1 twine")
	g.clock.hours += TWINE_SPOIL_HOURS + 1
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 0) // twine rots away
}

@(test)
twine_crafting_works_with_fibers_in_any_hands :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hand_count = 4
	p.hands = {0 = .Stone, 1 = .Fiber, 2 = .Stick, 3 = .Fiber}
	testing.expect(t, craft_twine(p), "craft")
	testing.expect_value(t, p.hands, [MAX_SLOTS]Item{0 = .Stone, 1 = .Twine, 2 = .Stick})
}

@(test)
skill_sets_the_chance_of_success :: proc(t: ^testing.T) {
	rand.reset(12)
	n := 20000
	for skill in ([?]f32{0, 50, 100}) {
		wins := 0
		for _ in 0 ..< n {
			if skill_succeeds(skill) {wins += 1}
		}
		want := f32(SKILL_MIN_SUCCESS) + (1 - SKILL_MIN_SUCCESS) * skill / MAX_SKILL
		testing.expect(t, abs(f32(wins) / f32(n) - want) < 0.02, "success rate matches the skill")
	}
}

@(test)
random_skills_range_over_0_to_100_averaging_50 :: proc(t: ^testing.T) {
	rand.reset(13)
	sum, lo, hi: f32 = 0, 1000, -1
	for _ in 0 ..< 20000 {
		s := random_skill()
		sum += s
		lo, hi = min(lo, s), max(hi, s)
	}
	testing.expect(t, abs(sum / 20000 - 50) < 1, "average 50")
	testing.expect(t, lo >= 0 && lo < 5 && hi <= MAX_SKILL && hi > 95, "spans the range")
}

@(test)
unskilled_foragers_sometimes_fumble_and_take_nothing :: proc(t: ^testing.T) {
	rand.reset(14)
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.foraging = 0
	g.fiber[2] = 5
	fumbles, gains := 0, 0
	for _ in 0 ..< 200 {
		p.hands = {}
		before := g.fiber[2]
		testing.expect(t, gather_fiber_here(&g, p), "an attempt is made")
		if p.hands[0] == .Fiber {gains += 1} else {fumbles += 1; testing.expect_value(t, g.fiber[2], before)}
		g.fiber[2], g.cells[2] = 5, .Grass
	}
	testing.expect(t, fumbles > 100 && gains > 20, "about three in four fumble at skill 0")
}

@(test)
poor_crafting_wastes_a_fiber :: proc(t: ^testing.T) {
	rand.reset(15)
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.crafting = 0
	botched, made := 0, 0
	for _ in 0 ..< 200 {
		p.craft_levels = {} // every attempt is an unpracticed one
		p.hands = {0 = .Fiber, 1 = .Fiber}
		testing.expect(t, craft_twine(p), "an attempt is made")
		if p.hands[0] == .Twine {made += 1} else {botched += 1; testing.expect_value(t, held_count(p^), 1)}
	}
	testing.expect(t, botched > 100 && made > 20, "mostly botched at skill 0")
}

@(test)
things_rot_in_order_food_fiber_twine_sticks_and_stone_never :: proc(t: ^testing.T) {
	testing.expect(t, FOOD_SPOIL_HOURS < FIBER_SPOIL_HOURS, "food before fiber")
	testing.expect(t, FIBER_SPOIL_HOURS < TWINE_SPOIL_HOURS, "fiber before twine")
	testing.expect(t, TWINE_SPOIL_HOURS < STICK_SPOIL_HOURS, "twine before sticks")
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	for item in ([?]Item{.Food, .Fiber, .Twine, .Stick, .Stone}) {
		append(&g.ground_items, Ground_Item{x = 1, y = 0, item = item, dropped_hours = g.clock.hours})
	}
	survivors :: proc(g: ^Game) -> (out: [Item]bool) {
		for it in g.ground_items {out[it.item] = true}
		return
	}
	start := g.clock.hours
	Rot :: struct {
		after: f64,
		item:  Item,
	}
	for r in ([?]Rot{{FOOD_SPOIL_HOURS, .Food}, {FIBER_SPOIL_HOURS, .Fiber}, {TWINE_SPOIL_HOURS, .Twine}, {STICK_SPOIL_HOURS, .Stick}}) {
		g.clock.hours = start + r.after - 0.01
		update_ground_items(&g)
		testing.expect(t, survivors(&g)[r.item], "still there just before its time")
		g.clock.hours = start + r.after + 0.01
		update_ground_items(&g)
		testing.expect(t, !survivors(&g)[r.item], "rotted at its time")
	}
	g.clock.hours = 1e7
	update_ground_items(&g)
	testing.expect(t, survivors(&g)[.Stone], "stone never rots")
	testing.expect_value(t, len(g.ground_items), 1)
}

@(test)
dropped_fiber_loses_freshness_gradually :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	append(&g.ground_items, Ground_Item{x = 1, y = 0, item = .Fiber, dropped_hours = g.clock.hours})
	g.clock.hours += FIBER_SPOIL_HOURS / 4
	testing.expect(t, abs(ground_freshness(&g, g.ground_items[0]) - 0.75) < 1e-4, "three quarters fresh")
}

@(test)
two_stones_make_a_sharp_stone_and_keep_one_stone :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !craft_sharp_stone(p), "nothing in hand")
	p.hands = {0 = .Stone}
	testing.expect(t, !craft_sharp_stone(p), "one stone is not enough")
	p.hands = {0 = .Stone, 1 = .Fiber}
	testing.expect(t, !craft_sharp_stone(p), "a fiber is not a stone")
	p.hands = {0 = .Stone, 1 = .Stone}
	testing.expect(t, craft_sharp_stone(p), "two stones")
	testing.expect_value(t, p.hands[0], Item.Stone)
	testing.expect_value(t, p.hands[1], Item.Sharp_Stone)
	testing.expect(t, !craft_sharp_stone(p), "only one stone is left")
	testing.expect(t, drop_item(&g, p, 1), "drop the sharp stone")
	buf: [80]byte
	testing.expect_value(t, describe_ground_items(&g, 2, 0, buf[:]), "1 sharp stone")
	g.clock.hours += 1e6
	update_ground_items(&g)
	testing.expect_value(t, len(g.ground_items), 1) // sharp stones keep
}

@(test)
failed_sharp_stone_crafting_loses_one_stone_but_keeps_the_other :: proc(t: ^testing.T) {
	rand.reset(21)
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.crafting = 0
	made, lost := 0, 0
	for _ in 0 ..< 200 {
		p.craft_levels = {}
		p.hands = {0 = .Stone, 1 = .Stone}
		testing.expect(t, craft_sharp_stone(p), "an attempt is made")
		testing.expect_value(t, p.hands[0], Item.Stone) // always survives
		if p.hands[1] == .Sharp_Stone {made += 1} else {lost += 1; testing.expect_value(t, p.hands[1], Item.None)}
	}
	testing.expect(t, lost > 100 && made > 20, "mostly fails at skill 0")
}

@(test)
sharp_stone_and_stick_make_two_short_sticks :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !craft_short_sticks(&g, p), "nothing in hand")
	p.hands = {0 = .Stone, 1 = .Stick}
	testing.expect(t, !craft_short_sticks(&g, p), "a plain stone is not sharp")
	p.hands = {0 = .Sharp_Stone, 1 = .Fiber}
	testing.expect(t, !craft_short_sticks(&g, p), "needs a stick")
	// two hands: the sharp stone, one short stick, and the other short stick on the ground
	p.hands = {0 = .Sharp_Stone, 1 = .Stick}
	testing.expect(t, craft_short_sticks(&g, p), "craft")
	testing.expect_value(t, p.hands[0], Item.Sharp_Stone)
	testing.expect_value(t, p.hands[1], Item.Short_Stick)
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].item, Item.Short_Stick)
	testing.expect(t, !craft_short_sticks(&g, p), "no stick left")
	// with a free hand both short sticks are carried
	clear(&g.ground_items)
	p.hand_count = 3
	p.hands = {0 = .Stick, 1 = .Sharp_Stone}
	testing.expect(t, craft_short_sticks(&g, p), "craft with a spare hand")
	testing.expect_value(t, p.hands, [MAX_SLOTS]Item{0 = .Short_Stick, 1 = .Sharp_Stone, 2 = .Short_Stick})
	testing.expect_value(t, len(g.ground_items), 0)
	buf: [80]byte
	append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Short_Stick, dropped_hours = g.clock.hours})
	testing.expect_value(t, describe_ground_items(&g, 2, 0, buf[:]), "1 short stick")
}

@(test)
failed_cutting_loses_the_stick_but_keeps_the_sharp_stone :: proc(t: ^testing.T) {
	rand.reset(31)
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.crafting = 0
	made, lost := 0, 0
	for _ in 0 ..< 200 {
		p.craft_levels = {}
		clear(&g.ground_items)
		p.hands = {0 = .Sharp_Stone, 1 = .Stick}
		testing.expect(t, craft_short_sticks(&g, p), "an attempt is made")
		testing.expect_value(t, p.hands[0], Item.Sharp_Stone)
		if p.hands[1] == .Short_Stick {made += 1} else {
			lost += 1
			testing.expect_value(t, p.hands[1], Item.None)
			testing.expect_value(t, len(g.ground_items), 0) // and no short sticks on the ground either
		}
	}
	testing.expect(t, lost > 100 && made > 20, "mostly fails at skill 0")
}

drop_at_feet :: proc(g: ^Game, p: Person, item: Item) {
	append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = item, dropped_hours = g.clock.hours})
}

@(test)
knife_needs_sharp_stone_short_stick_and_twine :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !craft_knife(&g, p), "nothing")
	p.hands = {0 = .Sharp_Stone, 1 = .Short_Stick}
	testing.expect(t, !craft_knife(&g, p), "no twine")
	p.hands = {0 = .Stone, 1 = .Short_Stick}
	drop_at_feet(&g, p^, .Twine)
	testing.expect(t, !craft_knife(&g, p), "a plain stone is not sharp")
	testing.expect_value(t, len(g.ground_items), 1) // nothing was spent
	p.hands = {0 = .Sharp_Stone, 1 = .Stick}
	testing.expect(t, !craft_knife(&g, p), "a long stick is not a handle")
}

@(test)
knife_uses_ingredients_from_hands_and_the_ground :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	// two in hand, the short stick on the ground
	p.hands = {0 = .Sharp_Stone, 1 = .Twine}
	drop_at_feet(&g, p^, .Short_Stick)
	drop_at_feet(&g, p^, .Stick) // unrelated clutter stays
	testing.expect(t, craft_knife(&g, p), "craft")
	testing.expect_value(t, held_count(p^), 1)
	testing.expect(t, p.hands[0] == .Knife || p.hands[1] == .Knife, "holding the knife")
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].item, Item.Stick)
	// all three on the ground: the knife goes to a free hand
	clear(&g.ground_items)
	p.hands = {}
	for item in KNIFE_INGREDIENTS {drop_at_feet(&g, p^, item)}
	drop_at_feet(&g, p^, .Short_Stick) // a spare handle
	testing.expect(t, craft_knife(&g, p), "craft from the ground")
	testing.expect_value(t, p.hands[0], Item.Knife)
	testing.expect_value(t, len(g.ground_items), 1)
	testing.expect_value(t, g.ground_items[0].item, Item.Short_Stick)
	// items on other cells do not count
	p.hands = {0 = .Sharp_Stone, 1 = .Twine}
	clear(&g.ground_items)
	append(&g.ground_items, Ground_Item{x = 4, y = 0, item = .Short_Stick, dropped_hours = g.clock.hours})
	testing.expect(t, !craft_knife(&g, p), "the handle is out of reach")
	// full hands and the knife lands on the ground
	p.hands = {0 = .Sharp_Stone, 1 = .Twine}
	clear(&g.ground_items)
	drop_at_feet(&g, p^, .Short_Stick)
	p.hand_count = 2
	testing.expect(t, craft_knife(&g, p), "craft")
	testing.expect_value(t, held_count(p^), 1)
}

@(test)
failed_knife_crafting_wastes_only_the_twine :: proc(t: ^testing.T) {
	rand.reset(41)
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.crafting = 0
	made, failed := 0, 0
	for _ in 0 ..< 200 {
		p.craft_levels = {}
		clear(&g.ground_items)
		p.hands = {0 = .Sharp_Stone, 1 = .Twine}
		drop_at_feet(&g, p^, .Short_Stick)
		testing.expect(t, craft_knife(&g, p), "an attempt is made")
		knife := p.hands[0] == .Knife || p.hands[1] == .Knife
		if knife {made += 1} else {
			failed += 1
			testing.expect_value(t, p.hands[0], Item.Sharp_Stone)
			testing.expect_value(t, p.hands[1], Item.None)
			testing.expect_value(t, len(g.ground_items), 1) // the short stick is still there
		}
	}
	testing.expect(t, failed > 100 && made > 20, "mostly fails at skill 0")
}

@(test)
describing_a_big_pile_never_overflows_the_text_buffer :: proc(t: ^testing.T) {
	g: Game
	item_world(&g)
	defer game_destroy(&g)
	for item in Item {
		if item == .None {continue}
		for _ in 0 ..< 12 {append(&g.ground_items, Ground_Item{x = 2, y = 0, item = item, dropped_hours = g.clock.hours})}
	}
	buf: [80]byte
	s := describe_ground_items(&g, 2, 0, buf[:])
	testing.expect(t, len(s) > 0 && len(s) <= len(buf), "fits in the buffer")
}
