#+build !js
package gods

import "core:math/rand"
import "core:testing"

@(test)
the_view_starts_fifteen_cells_across :: proc(t: ^testing.T) {
	rand.reset(601)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	testing.expect_value(t, g.view_w, 15)
	testing.expect_value(t, g.view_h, 15)
}

@(test)
zoom_changes_the_view_and_stays_within_limits :: proc(t: ^testing.T) {
	rand.reset(602)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	zoom_view(&g, -3)
	testing.expect_value(t, g.view_w, 12)
	zoom_view(&g, -100)
	testing.expect_value(t, g.view_w, MIN_ZOOM)
	zoom_view(&g, 100)
	testing.expect_value(t, g.view_w, WORLD_SIZE)
	testing.expect_value(t, g.cam_x, 0)
}

@(test)
zoom_keeps_the_middle_of_the_view :: proc(t: ^testing.T) {
	rand.reset(603)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	center_camera(&g, 16, 16)
	zoom_view(&g, -5)
	testing.expect_value(t, g.cam_x + g.view_w / 2, 16)
	testing.expect_value(t, g.cam_y + g.view_h / 2, 16)
}

@(test)
a_small_world_shrinks_the_view_to_fit :: proc(t: ^testing.T) {
	rand.reset(604)
	g: Game
	game_init_rect(&g, 8, 6)
	defer game_destroy(&g)
	testing.expect_value(t, g.view_w, 8)
	testing.expect_value(t, g.view_h, 6)
}

@(test)
centering_crops_at_the_edges_of_the_map :: proc(t: ^testing.T) {
	rand.reset(605)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	center_camera(&g, 0, 0)
	testing.expect_value(t, g.cam_x, 0)
	testing.expect_value(t, g.cam_y, 0)
	center_camera(&g, 31, 31)
	testing.expect_value(t, g.cam_x, WORLD_SIZE - 15)
	center_camera(&g, 16, 16)
	testing.expect_value(t, g.cam_x, 9)
}

@(test)
following_a_person_centres_the_view_on_them :: proc(t: ^testing.T) {
	rand.reset(606)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	p := &g.people[2]
	p.x, p.y = 16, 16
	follow_person(&g, p.id)
	update_follow(&g)
	testing.expect_value(t, g.cam_x, 9)
	p.x = 20
	update_follow(&g)
	testing.expect_value(t, g.cam_x, 13)
}

@(test)
steering_the_cursor_or_panning_drops_the_follow :: proc(t: ^testing.T) {
	rand.reset(607)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	follow_person(&g, g.people[0].id)
	move_cursor(&g, 1, 0)
	testing.expect_value(t, g.following, 0)
	follow_person(&g, g.people[0].id)
	pan_camera(&g, 1, 0)
	testing.expect_value(t, g.following, 0)
}

@(test)
the_follow_ends_when_the_person_dies :: proc(t: ^testing.T) {
	rand.reset(608)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	id := g.people[1].id
	follow_person(&g, id)
	testing.expect(t, followed_index(&g) == 1)
	kill_person(&g, 1)
	testing.expect_value(t, followed_index(&g), -1)
	testing.expect_value(t, g.following, 0)
}

@(test)
people_have_distinct_ids :: proc(t: ^testing.T) {
	rand.reset(609)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	for a, i in g.people {
		testing.expect(t, a.id > 0)
		for b in g.people[i + 1:] {testing.expect(t, a.id != b.id)}
	}
}

@(test)
what_a_person_is_doing_is_recorded :: proc(t: ^testing.T) {
	rand.reset(610)
	g: Game
	game_init_rect(&g, 6, 6)
	defer game_destroy(&g)
	for i in 0 ..< len(g.cells) {g.cells[i] = .Grass}
	p := &g.people[0]
	p.asleep = true
	take_turn(&g, p)
	testing.expect_value(t, p.doing, Activity.Sleeping)
	p.asleep = false
	p.satiety, p.stomach, p.dopamine = 100, 100, 100
	for i in 0 ..< len(g.fiber) {g.fiber[i] = 0}
	for &q in g.people[1:] {q.x, q.y = 5, 5}
	take_turn(&g, p)
	testing.expect_value(t, p.doing, Activity.Wandering)
}

@(test)
a_fumbled_forage_hurts_the_bush :: proc(t: ^testing.T) {
	rand.reset(611)
	g: Game
	game_init_rect(&g, 4, 1)
	defer game_destroy(&g)
	for i in 0 ..< 4 {g.cells[i] = .Grass}
	g.cells[1] = .Bush
	g.bushes[1] = Bush{food = 3, max_food = 5, health = BUSH_MAX_HEALTH}
	clear(&g.people)
	clear(&g.rabbits)
	append(&g.people, Person{x = 0, y = 0, foraging = 0, hand_count = DEFAULT_HANDS})
	p := &g.people[0]
	hurt := false
	for _ in 0 ..< 50 { // skill 0 still gets the odd success
		before := g.bushes[1].health
		gather_food(&g, p, 1, 0)
		if g.bushes[1].health < before {hurt = true; break}
		p.hands = {}
	}
	testing.expect(t, hurt, "a fumble damaged the bush")
}

@(test)
a_bush_at_zero_health_is_destroyed_and_drops_its_berries :: proc(t: ^testing.T) {
	rand.reset(612)
	g: Game
	game_init_rect(&g, 4, 1)
	defer game_destroy(&g)
	for i in 0 ..< 4 {g.cells[i] = .Grass}
	g.cells[2] = .Bush
	g.bushes[2] = Bush{food = 3.7, max_food = 5, health = 1}
	damage_bush(&g, 2, 0)
	testing.expect_value(t, g.cells[2], Terrain.Grass)
	berries := 0
	for it in g.ground_items {
		if it.item == .Food && it.x == 2 {berries += 1}
	}
	testing.expect_value(t, berries, 3) // whole berries only
}

@(test)
a_damaged_bush_with_health_left_survives_and_mends :: proc(t: ^testing.T) {
	rand.reset(613)
	g: Game
	game_init_rect(&g, 4, 1)
	defer game_destroy(&g)
	for i in 0 ..< 4 {g.cells[i] = .Grass}
	g.cells[2] = .Bush
	g.bushes[2] = Bush{food = 3, max_food = 5, health = 5}
	damage_bush(&g, 2, 0)
	testing.expect_value(t, g.cells[2], Terrain.Bush)
	testing.expect_value(t, g.bushes[2].health, f32(4))
	g.clock.hours += 20
	update_bushes(&g)
	testing.expect(t, g.bushes[2].health > 4, "mended")
	g.clock.hours += 1000
	update_bushes(&g)
	testing.expect_value(t, g.bushes[2].health, f32(BUSH_MAX_HEALTH))
}

@(test)
the_action_button_follows_casts_and_restarts :: proc(t: ^testing.T) {
	rand.reset(614)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	p := g.people[0]
	g.cursor_x, g.cursor_y = p.x, p.y
	act_at_cursor(&g)
	testing.expect_value(t, g.following, p.id)
	act_at_cursor(&g)
	testing.expect_value(t, g.following, 0) // pressed again: stop following
	g.armed = Power.Smite
	g.faith = MAX_FAITH
	people := len(g.people)
	act_at_cursor(&g)
	testing.expect_value(t, len(g.people), people - 1) // the armed miracle is cast at the cursor
	for len(g.people) > 0 {kill_person(&g, 0, .Smitten)}
	act_at_cursor(&g)
	testing.expect(t, !game_over(&g), "began again")
}

@(test)
following_someone_keeps_the_cursor_on_them :: proc(t: ^testing.T) {
	rand.reset(615)
	g: Game
	game_init(&g, WORLD_SIZE)
	defer game_destroy(&g)
	follow_person(&g, g.people[1].id)
	g.people[1].x = clamp(g.people[1].x + 3, 0, g.width - 1)
	update_follow(&g)
	testing.expect(t, g.cursor_x == g.people[1].x && g.cursor_y == g.people[1].y, "cursor on them")
	act_at_cursor(&g)
	testing.expect_value(t, g.following, 0) // the action button on the one being followed lets them go
}
