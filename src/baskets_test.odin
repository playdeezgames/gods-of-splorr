#+build !js
package gods

import "core:math/rand"
import "core:testing"

// A 5x3 world of grass with a pond in the middle of the top row and nobody in it.
@(private = "file")
pond_world :: proc(g: ^Game) {
	game_init_rect(g, 5, 3)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	g.cells[2] = .Pond
	for &r in g.reeds {r = 0}
	g.reeds[2] = REEDS_PER_POND
	clear(&g.people)
	clear(&g.rabbits)
	append(&g.people, Person{x = 2, y = 1, health = MAX_HEALTH, satiety = MAX_SATIETY, energy = MAX_ENERGY, sleep_hours = 8, hand_count = DEFAULT_HANDS, foraging = MAX_SKILL, crafting = MAX_SKILL, next_move_hours = 1e9})
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
ponds_start_with_a_full_stand_of_reeds :: proc(t: ^testing.T) {
	rand.reset(101)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	ponds := 0
	for t_, i in g.cells {
		if t_ == .Pond {
			ponds += 1
			testing.expect_value(t, g.reeds[i], f32(REEDS_PER_POND))
		} else {
			testing.expect_value(t, g.reeds[i], f32(0))
		}
	}
	testing.expect(t, ponds > 0, "the world has ponds")
}

@(test)
reeds_regrow_slowly_up_to_a_maximum :: proc(t: ^testing.T) {
	rand.reset(102)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	g.reeds[2] = 0
	g.clock.hours += 10
	update_ground(&g)
	testing.expect(t, abs(g.reeds[2] - 10 * REED_REGROW_PER_HOUR) < 1e-4, "ten hours of growth")
	g.clock.hours += 100000
	update_ground(&g)
	testing.expect_value(t, g.reeds[2], f32(REEDS_PER_POND))
}

@(test)
cutting_a_reed_needs_a_sharp_stone_and_a_pond_next_door :: proc(t: ^testing.T) {
	rand.reset(103)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect(t, !gather_reed_adjacent(&g, p), "no sharp stone")
	p.hands[0] = .Sharp_Stone
	testing.expect(t, gather_reed_adjacent(&g, p), "cut a reed")
	testing.expect_value(t, g.reeds[2], f32(REEDS_PER_POND - 1))
	testing.expect(t, holds(p^, .Reed), "holding a reed")
	n, _ := uses_left(p^, .Sharp_Stone)
	testing.expect_value(t, n, SHARP_STONE_DURABILITY - 1) // cutting wears the sharp stone
	p.x, p.y = 0, 2 // far from the pond
	testing.expect(t, !gather_reed_adjacent(&g, p), "too far")
}

@(test)
a_pond_with_less_than_a_whole_reed_gives_nothing :: proc(t: ^testing.T) {
	rand.reset(104)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	g.reeds[2] = 0.9
	g.people[0].hands[0] = .Sharp_Stone
	testing.expect(t, !gather_reed_adjacent(&g, &g.people[0]), "not yet")
}

@(test)
reeds_that_do_not_fit_in_hand_land_at_the_feet :: proc(t: ^testing.T) {
	rand.reset(105)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Sharp_Stone
	for _ in 0 ..< 3 {
		testing.expect(t, gather_reed_adjacent(&g, p), "cut")
	}
	testing.expect_value(t, count_on_ground(&g, .Reed), 2) // one in the free hand, two on the ground
	testing.expect_value(t, g.ground_items[0].x, 2)
	testing.expect_value(t, g.ground_items[0].y, 1)
}

@(test)
the_sharp_stone_breaks_from_cutting_reeds :: proc(t: ^testing.T) {
	rand.reset(106)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Sharp_Stone
	for _ in 0 ..< SHARP_STONE_DURABILITY {
		g.reeds[2] = REEDS_PER_POND
		testing.expect(t, holds(p^, .Sharp_Stone), "sharp stone still there")
		testing.expect(t, gather_reed_adjacent(&g, p), "cut")
		p.hands[1] = .None // keep a hand free
	}
	testing.expect(t, !holds(p^, .Sharp_Stone), "worn out")
}

@(test)
five_reeds_make_a_basket :: proc(t: ^testing.T) {
	rand.reset(107)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.belt = true
	for _ in 0 ..< 4 {append(&g.ground_items, Ground_Item{x = 2, y = 1, item = .Reed})}
	testing.expect(t, !craft_basket(&g, p), "only four reeds")
	p.hands[0] = .Reed // the fifth, in hand
	testing.expect(t, craft_basket(&g, p), "five reeds")
	testing.expect(t, has_basket(p^), "holding a basket")
	testing.expect_value(t, count_on_ground(&g, .Reed), 0)
	testing.expect_value(t, held_count(p^), 1)
}

@(test)
failed_basket_destroys_exactly_one_reed :: proc(t: ^testing.T) {
	rand.reset(108)
	failures := 0
	for _ in 0 ..< 60 {
		g: Game
		pond_world(&g)
		p := &g.people[0]
	p.belt = true
		p.crafting = 0 // 25% success
		for _ in 0 ..< 5 {append(&g.ground_items, Ground_Item{x = 2, y = 1, item = .Reed})}
		testing.expect(t, craft_basket(&g, p), "an attempt is made")
		if !has_basket(p^) {
			failures += 1
			testing.expect_value(t, count_on_ground(&g, .Reed), 4) // one reed lost, four left
		}
		game_destroy(&g)
	}
	testing.expect(t, failures > 0, "some weaves fail")
}

@(test)
only_one_basket_per_person :: proc(t: ^testing.T) {
	rand.reset(109)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Basket
	for _ in 0 ..< 5 {append(&g.ground_items, Ground_Item{x = 2, y = 1, item = .Reed})}
	testing.expect(t, !craft_basket(&g, p), "already carrying one")
}

@(test)
a_basket_takes_a_place_and_holds_three_foods :: proc(t: ^testing.T) {
	rand.reset(110)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	testing.expect_value(t, carry_slots(p^), 2) // a basket adds no places of its own to the person
	p.hands[0] = .Basket
	testing.expect_value(t, carry_slots(p^), 2)
	for _ in 0 ..< BASKET_SLOTS {give_or_drop(&g, p, .Food)}
	testing.expect_value(t, packed_count(p^, .Food), 3)
	testing.expect_value(t, held_count(p^), 1) // only the basket takes a place
	give_or_drop(&g, p, .Food)
	testing.expect_value(t, p.hands[1], Item.Food) // the fourth no longer fits
}

@(test)
only_food_goes_in_a_basket :: proc(t: ^testing.T) {
	rand.reset(113)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Basket
	give_or_drop(&g, p, .Stone)
	testing.expect_value(t, packed_count(p^, .Stone), 0)
	testing.expect_value(t, p.hands[1], Item.Stone)
}

@(test)
a_dropped_basket_keeps_its_food_and_can_be_picked_up :: proc(t: ^testing.T) {
	rand.reset(111)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Basket
	give_or_drop(&g, p, .Food)
	give_or_drop(&g, p, .Fish)
	testing.expect(t, drop_item(&g, p, 0), "dropped the basket")
	testing.expect(t, !has_basket(p^), "no basket")
	testing.expect_value(t, count_on_ground(&g, .Basket), 1)
	testing.expect_value(t, count_on_ground(&g, .Food) + count_on_ground(&g, .Fish), 0) // still inside
	g.clock.hours += 100 // days later the food has not spoiled
	update_ground_items(&g)
	testing.expect_value(t, count_on_ground(&g, .Basket), 1)
	testing.expect(t, take_basket(&g, p), "picked up")
	testing.expect_value(t, packed_count(p^, .Food), 1)
	testing.expect_value(t, packed_count(p^, .Fish), 1)
	testing.expect_value(t, count_on_ground(&g, .Basket), 0)
}

@(test)
a_hungry_person_eats_from_a_basket_on_the_ground :: proc(t: ^testing.T) {
	rand.reset(118)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	append(&g.ground_items, Ground_Item{x = p.x, y = p.y, item = .Basket, pack = {0 = .Food}})
	p.stomach, p.satiety = 0, 10
	testing.expect(t, eat_from_ground(&g, p), "ate")
	testing.expect_value(t, p.stomach, f32(FOOD_STOMACH))
	testing.expect_value(t, g.ground_items[0].pack[0], Item.None)
	testing.expect(t, !edible_on_ground(&g, g.ground_items[0]), "empty now")
}

@(test)
food_in_a_basket_does_not_spoil :: proc(t: ^testing.T) {
	rand.reset(114)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Basket
	give_or_drop(&g, p, .Food)
	p.hands[1] = .Food
	for _ in 0 ..< 200 {spoil_carried(p, 1)}
	testing.expect_value(t, packed_count(p^, .Food), 1)
	testing.expect_value(t, p.hands[1], Item.None) // the one in the open rotted
}

@(test)
people_eat_from_the_basket_and_stow_what_they_hold :: proc(t: ^testing.T) {
	rand.reset(115)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands = {0 = .Basket, 1 = .Food}
	testing.expect(t, stow_held(p), "the berry goes in")
	testing.expect_value(t, p.hands[1], Item.None)
	testing.expect_value(t, packed_count(p^, .Food), 1)
	p.stomach = 0
	testing.expect(t, eat_food(p), "eaten from the basket")
	testing.expect_value(t, packed_count(p^, .Food), 0)
}

@(test)
two_twine_make_a_rope_and_two_ropes_a_belt :: proc(t: ^testing.T) {
	rand.reset(116)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.crafting = 100
	p.hands[0], p.hands[1] = .Twine, .Twine
	testing.expect(t, craft_rope(&g, p), "rope")
	testing.expect_value(t, p.hands[0], Item.Rope)
	testing.expect_value(t, held_count(p^), 1)
	testing.expect(t, !craft_belt(&g, p), "one rope is not enough")
	p.hands[1] = .Rope
	testing.expect(t, craft_belt(&g, p), "belt")
	testing.expect(t, p.belt, "worn")
	testing.expect_value(t, carry_slots(p^), 2 + BELT_SLOTS)
	testing.expect_value(t, held_count(p^), 0) // the belt takes no place
	testing.expect(t, !craft_belt(&g, p), "one belt is plenty")
}

@(test)
failed_rope_and_belt_lose_one_ingredient :: proc(t: ^testing.T) {
	rand.reset(117)
	fails := 0
	for _ in 0 ..< 60 {
		g: Game
		pond_world(&g)
		p := &g.people[0]
		p.crafting = 0
		p.hands[0], p.hands[1] = .Twine, .Twine
		craft_rope(&g, p)
		if p.hands[0] != .Rope {
			fails += 1
			testing.expect_value(t, held_count(p^), 1) // one twine left
		}
		p.hands[0], p.hands[1] = .Rope, .Rope
		craft_belt(&g, p)
		if !p.belt {testing.expect_value(t, held_count(p^), 1)}
		game_destroy(&g)
	}
	testing.expect(t, fails > 0, "some twists fail")
}

@(test)
people_keep_their_baskets_when_they_drop_things :: proc(t: ^testing.T) {
	rand.reset(112)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.hands[0] = .Basket
	for _ in 0 ..< 500 {
		drop_something(&g, p)
	}
	testing.expect(t, has_basket(p^), "the basket stays")
}

@(test)
a_basket_needs_a_belt :: proc(t: ^testing.T) {
	rand.reset(119)
	g: Game
	pond_world(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	for _ in 0 ..< 5 {append(&g.ground_items, Ground_Item{x = 2, y = 1, item = .Reed})}
	testing.expect(t, !craft_basket(&g, p), "no belt, no basket")
	p.belt = true
	testing.expect(t, craft_basket(&g, p), "with a belt")
}
