#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(private = "file")
workshop :: proc(g: ^Game) {
	game_init_rect(g, 5, 1)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	clear(&g.people)
	append(&g.people, Person{x = 2, y = 0, health = MAX_HEALTH, satiety = MAX_SATIETY, energy = MAX_ENERGY, sleep_hours = 8, hand_count = DEFAULT_HANDS, next_move_hours = 1e9})
}

@(test)
a_successful_craft_raises_that_items_level_by_one :: proc(t: ^testing.T) {
	rand.reset(121)
	g: Game
	workshop(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.crafting = MAX_SKILL // never fails
	p.hands[0], p.hands[1] = .Fiber, .Fiber
	testing.expect(t, craft_twine(p), "twine")
	testing.expect_value(t, p.craft_levels[.Twine], 1)
	testing.expect_value(t, p.craft_levels[.Knife], 0) // other items are unaffected
	p.hands[0], p.hands[1] = .Fiber, .Fiber
	craft_twine(p)
	testing.expect_value(t, p.craft_levels[.Twine], 2)
}

@(test)
failed_crafts_do_not_raise_the_level :: proc(t: ^testing.T) {
	p := Person{crafting = -100} // clamps to the 25% floor, so some attempts fail
	rand.reset(122)
	wins := 0
	for _ in 0 ..< 400 {
		if craft_roll(&p, .Knife) {wins += 1}
	}
	testing.expect(t, wins > 0 && wins < 400, "some succeed and some fail")
	testing.expect_value(t, p.craft_levels[.Knife], wins) // exactly one point per success
}

@(test)
level_is_added_to_the_crafting_check :: proc(t: ^testing.T) {
	rand.reset(123)
	novice, trained := Person{crafting = 0}, Person{crafting = 0}
	trained.craft_levels[.Spear] = 100 // skill 0 + level 100 is a sure thing
	trained.craft_levels[.Knife] = 100
	novice_wins := 0
	for _ in 0 ..< 400 {
		if craft_roll(&novice, .Spear) {novice_wins += 1}
		novice.craft_levels[.Spear] = 0 // keep the novice a novice
	}
	for _ in 0 ..< 200 {
		testing.expect(t, craft_roll(&trained, .Knife), "a trained hand never fails")
	}
	testing.expect(t, novice_wins < 200, "an untrained hand with no skill often fails")
	testing.expect(t, trained.craft_levels[.Knife] == 300, "and keeps improving")
}

@(test)
levels_are_per_item_not_shared :: proc(t: ^testing.T) {
	rand.reset(124)
	p := Person{crafting = 0}
	p.craft_levels[.Twine] = 100
	wins := 0
	for _ in 0 ..< 400 {
		if craft_roll(&p, .Basket) {wins += 1}
		p.craft_levels[.Basket] = 0 // stay unpracticed at baskets
	}
	testing.expect(t, wins < 250, "twine practice does not help with baskets")
}

@(test)
every_recipe_trains_its_own_item :: proc(t: ^testing.T) {
	rand.reset(125)
	g: Game
	workshop(&g)
	defer game_destroy(&g)
	p := &g.people[0]
	p.crafting = MAX_SKILL
	p.hands[0], p.hands[1] = .Stone, .Stone
	craft_sharp_stone(p)
	testing.expect_value(t, p.craft_levels[.Sharp_Stone], 1)
	p.hands = {0 = .Sharp_Stone, 1 = .Stick}
	craft_short_sticks(&g, p)
	testing.expect_value(t, p.craft_levels[.Short_Stick], 1)
	clear(&g.ground_items)
	p.hands = {0 = .Sharp_Stone, 1 = .Short_Stick}
	append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Twine})
	craft_knife(&g, p)
	testing.expect_value(t, p.craft_levels[.Knife], 1)
	clear(&g.ground_items)
	p.hands = {0 = .Sharp_Stone, 1 = .Stick}
	append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Twine})
	craft_spear(&g, p)
	testing.expect_value(t, p.craft_levels[.Spear], 1)
	clear(&g.ground_items)
	p.hands = {}
	for _ in 0 ..< BASKET_REEDS {append(&g.ground_items, Ground_Item{x = 2, y = 0, item = .Reed})}
	craft_basket(&g, p)
	testing.expect_value(t, p.craft_levels[.Basket], 1)
}

@(test)
craft_levels_are_described_for_the_details_panel :: proc(t: ^testing.T) {
	p: Person
	testing.expect_value(t, describe_craft_levels(p), "")
	p.craft_levels[.Twine] = 5
	p.craft_levels[.Knife] = 2
	testing.expect_value(t, describe_craft_levels(p), "twine 5, knife 2")
}
