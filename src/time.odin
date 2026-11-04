package gods

import "core:math"

HOURS_PER_DAY :: 24
SEASONS :: 4
AXIAL_TILT_DEG :: 23.5

SEASON_NAMES := [SEASONS]string{"Spring", "Summer", "Autumn", "Winter"}

// Run-rate multipliers the player can step through. 1x is the configured day length.
SPEEDS := [?]f64{0.25, 0.5, 1, 2, 4, 8, 16, 32}
DEFAULT_SPEED_INDEX :: 2

START_HOUR :: 8.0
START_YEAR_FRACTION :: 1.0 / 6 // a game opens in the last month of spring, when berries are growing

// Game hours in one calendar year, which depends on the configured days and months.
hours_per_year :: proc(cfg: Calendar_Config) -> f64 {
	return f64(HOURS_PER_DAY * cfg.days_per_month * cfg.months_per_year)
}

Calendar_Config :: struct {
	day_real_seconds: f64, // real seconds for one 24-hour day at 1x
	days_per_month:   int,
	months_per_year:  int, // always a multiple of SEASONS
	latitude:         f64, // degrees, -90 (south pole) to 90 (north pole)
}

DEFAULT_CALENDAR := Calendar_Config {
	day_real_seconds = 24 * 60, // 24 hours in 24 minutes
	days_per_month   = 30,
	months_per_year  = 12,
	latitude         = 40,
}

// Force a config into a legal state: months per year rounds up to a multiple of 4.
normalize_config :: proc(c: Calendar_Config) -> Calendar_Config {
	n := c
	n.day_real_seconds = max(n.day_real_seconds, 1)
	n.days_per_month = max(n.days_per_month, 1)
	n.months_per_year = max(n.months_per_year, SEASONS)
	n.months_per_year = (n.months_per_year + SEASONS - 1) / SEASONS * SEASONS
	n.latitude = clamp(n.latitude, -90, 90)
	return n
}

Clock :: struct {
	hours:       f64, // game hours since year 1, month 1, day 1, 00:00
	speed_index: int,
	paused:      bool,
}

clock_init :: proc() -> Clock {
	return Clock{hours = START_HOUR, speed_index = DEFAULT_SPEED_INDEX}
}

advance_clock :: proc(c: ^Clock, cfg: Calendar_Config, dt: f64) {
	if c.paused {return}
	c.hours += dt * f64(HOURS_PER_DAY) / cfg.day_real_seconds * SPEEDS[c.speed_index]
}

change_speed :: proc(c: ^Clock, delta: int) {
	c.speed_index = clamp(c.speed_index + delta, 0, len(SPEEDS) - 1)
}

Date_Time :: struct {
	year, month, day: int, // 1-based
	hour, minute:     int,
	season:           int, // index into SEASON_NAMES
}

date_of :: proc(c: Clock, cfg: Calendar_Config) -> Date_Time {
	days := int(math.floor(c.hours / HOURS_PER_DAY))
	hour_f := c.hours - f64(days * HOURS_PER_DAY)
	days_per_year := cfg.days_per_month * cfg.months_per_year
	day_of_year := days %% days_per_year
	d: Date_Time
	d.year = days / days_per_year + 1
	d.month = day_of_year / cfg.days_per_month + 1
	d.day = day_of_year % cfg.days_per_month + 1
	d.hour = int(hour_f)
	d.minute = int((hour_f - f64(d.hour)) * 60)
	// Year 1 opens at the northern spring equinox; the southern hemisphere is half a year out.
	d.season = (d.month - 1) / (cfg.months_per_year / SEASONS)
	if cfg.latitude < 0 {
		d.season = (d.season + 2) % SEASONS
	}
	return d
}

// How far through the year we are, 0 at the spring equinox, continuous.
year_fraction :: proc(c: Clock, cfg: Calendar_Config) -> f64 {
	days_per_year := f64(cfg.days_per_month * cfg.months_per_year)
	return math.mod(c.hours / HOURS_PER_DAY, days_per_year) / days_per_year
}

hour_of_day :: proc(c: Clock) -> f64 {
	return math.mod(c.hours, HOURS_PER_DAY)
}

// Sine of the sun's elevation: > 0 is daylight. Depends on latitude and season,
// so high latitudes get long summer days, short winter days, even polar day/night.
sun_sin :: proc(c: Clock, cfg: Calendar_Config) -> f64 {
	lat := math.to_radians(cfg.latitude)
	decl := math.to_radians(f64(AXIAL_TILT_DEG)) * math.sin(math.TAU * year_fraction(c, cfg))
	hour_angle := math.TAU * (hour_of_day(c) - 12) / HOURS_PER_DAY
	return math.sin(lat) * math.sin(decl) + math.cos(lat) * math.cos(decl) * math.cos(hour_angle)
}

// Air temperature in °C: a latitude-dependent yearly mean, a seasonal swing that
// grows with latitude (and flips sign in the south) and lags the sun by about three
// weeks of a 365-day year, and a daily swing peaking mid-afternoon.
temperature_c :: proc(c: Clock, cfg: Calendar_Config) -> f64 {
	lat := math.to_radians(cfg.latitude)
	annual_mean := 27 - 45 * math.sin(lat) * math.sin(lat)
	seasonal := 22 * math.sin(lat) * math.sin(math.TAU * (year_fraction(c, cfg) - 0.06))
	daily_amp := 4 + 5 * math.cos(lat)
	daily := daily_amp * math.cos(math.TAU * (hour_of_day(c) - 15) / HOURS_PER_DAY)
	return annual_mean + seasonal + daily
}

// The air temperature averaged over a day: the yearly mean and the season, without the daily swing.
mean_temperature_c :: proc(c: Clock, cfg: Calendar_Config) -> f64 {
	lat := math.to_radians(cfg.latitude)
	annual_mean := 27 - 45 * math.sin(lat) * math.sin(lat)
	return annual_mean + 22 * math.sin(lat) * math.sin(math.TAU * (year_fraction(c, cfg) - 0.06))
}

// Whether the seasons are on the way down: summer has peaked and the daily average is falling,
// through autumn and winter until the spring thaw. Never true at the equator, which has no seasons.
cooling_season :: proc(c: Clock, cfg: Calendar_Config) -> bool {
	lat := math.to_radians(cfg.latitude)
	return math.sin(lat) * math.cos(math.TAU * (year_fraction(c, cfg) - 0.06)) < 0
}

// Overlay colour for the day/night tint: transparent at midday, a warm wash
// at dawn and dusk, deep blue at night. Returns r, g, b, a.
ambient_overlay :: proc(sun: f64) -> [4]f32 {
	dark := clamp((0.2 - sun) / 0.32, 0, 1)
	twilight := max(1 - math.abs(sun - 0.04) / 0.16, 0)
	night := [3]f64{0.02, 0.03, 0.14}
	dusk := [3]f64{0.95, 0.45, 0.15}
	col := dusk + (night - dusk) * dark
	alpha := 0.65 * dark + 0.22 * twilight * (1 - dark)
	return {f32(col.r), f32(col.g), f32(col.b), f32(alpha)}
}
