#+build !js
package gods

import "core:testing"

// Clock at the given calendar position (1-based day/month, year 1).
at :: proc(cfg: Calendar_Config, month, day: int, hour: f64) -> Clock {
	days := (month - 1) * cfg.days_per_month + (day - 1)
	return Clock{hours = f64(days * HOURS_PER_DAY) + hour, speed_index = DEFAULT_SPEED_INDEX}
}

@(test)
default_day_takes_24_real_minutes :: proc(t: ^testing.T) {
	cfg := normalize_config(DEFAULT_CALENDAR)
	c := Clock{hours = 0, speed_index = DEFAULT_SPEED_INDEX}
	for _ in 0 ..< 1440 {
		advance_clock(&c, cfg, 1)
	}
	testing.expect(t, abs(c.hours - 24) < 1e-6, "1440 real seconds at 1x is 24 game hours")
	c.speed_index = 3 // 2x
	c.hours = 0
	advance_clock(&c, cfg, 720)
	testing.expect(t, abs(c.hours - 24) < 1e-6, "2x halves it")
	c.paused = true
	advance_clock(&c, cfg, 100)
	testing.expect(t, abs(c.hours - 24) < 1e-6, "paused does not advance")
}

@(test)
months_per_year_is_multiple_of_four :: proc(t: ^testing.T) {
	for pair in ([?][2]int{{4, 0}, {4, 1}, {4, 4}, {8, 5}, {12, 12}, {16, 13}}) {
		c := normalize_config({day_real_seconds = 1, days_per_month = 1, months_per_year = pair[1]})
		testing.expect_value(t, c.months_per_year, pair[0])
	}
}

@(test)
dates_roll_over :: proc(t: ^testing.T) {
	cfg := normalize_config({day_real_seconds = 60, days_per_month = 10, months_per_year = 8, latitude = 40})
	d := date_of(at(cfg, 1, 1, 6.5), cfg)
	testing.expect_value(t, d.year, 1)
	testing.expect_value(t, d.month, 1)
	testing.expect_value(t, d.day, 1)
	testing.expect_value(t, d.hour, 6)
	testing.expect_value(t, d.minute, 30)
	d = date_of(Clock{hours = f64(10 * HOURS_PER_DAY)}, cfg)
	testing.expect_value(t, d.month, 2)
	testing.expect_value(t, d.day, 1)
	d = date_of(Clock{hours = f64(80 * HOURS_PER_DAY)}, cfg)
	testing.expect_value(t, d.year, 2)
	testing.expect_value(t, d.month, 1)
}

@(test)
seasons_follow_quarters_and_hemisphere :: proc(t: ^testing.T) {
	north := normalize_config({day_real_seconds = 60, days_per_month = 10, months_per_year = 8, latitude = 40})
	south := north
	south.latitude = -40
	for want, month in ([?]int{0, 0, 1, 1, 2, 2, 3, 3}) {
		testing.expect_value(t, date_of(at(north, month + 1, 1, 0), north).season, want)
		testing.expect_value(t, date_of(at(south, month + 1, 1, 0), south).season, (want + 2) % 4)
	}
}

@(test)
temperature_swings :: proc(t: ^testing.T) {
	cfg := normalize_config(DEFAULT_CALENDAR)
	summer := at(cfg, 4, 15, 15)
	winter := at(cfg, 10, 15, 15)
	testing.expect(t, temperature_c(summer, cfg) > temperature_c(winter, cfg) + 15, "summer is warmer")
	dawn := at(cfg, 4, 15, 5)
	testing.expect(t, temperature_c(summer, cfg) > temperature_c(dawn, cfg), "afternoon beats dawn")

	south := cfg
	south.latitude = -40
	testing.expect(t, temperature_c(summer, south) < temperature_c(winter, south), "seasons flip in the south")

	equator := cfg
	equator.latitude = 0
	swing_eq := temperature_c(summer, equator) - temperature_c(winter, equator)
	swing_hi := temperature_c(summer, cfg) - temperature_c(winter, cfg)
	testing.expect(t, abs(swing_eq) < abs(swing_hi) / 4, "little seasonal swing at the equator")
}

@(test)
sun_follows_day_and_season :: proc(t: ^testing.T) {
	cfg := normalize_config(DEFAULT_CALENDAR)
	testing.expect(t, sun_sin(at(cfg, 4, 15, 12), cfg) > 0.9, "summer noon is high")
	testing.expect(t, sun_sin(at(cfg, 4, 15, 0), cfg) < 0, "midnight is dark")
	testing.expect(
		t,
		sun_sin(at(cfg, 4, 15, 12), cfg) > sun_sin(at(cfg, 10, 15, 12), cfg),
		"summer sun higher than winter sun",
	)
	testing.expect(t, ambient_overlay(1)[3] == 0, "no tint at noon")
	testing.expect(t, ambient_overlay(-1)[3] > 0.6, "dark at night")
}
