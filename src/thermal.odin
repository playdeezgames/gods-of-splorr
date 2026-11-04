package gods

// Cold and heat. Below COLD_BELOW_C a person's chill builds; when it is full, hypothermia sets in and
// costs health. Above HOT_ABOVE_C heat builds the same way into heat stress. Chill and heat bleed away in
// comfortable weather; hypothermia and heat stress bleed away more slowly, and while either lingers the
// person tires faster and needs longer asleep to recover (see affliction).
COLD_BELOW_C :: 10.0
HOT_ABOVE_C :: 30.0
MAX_THERMAL :: 100.0 // ceiling of chill, heat, hypothermia and heat stress
THERMAL_PER_DEGREE_HOUR :: 0.5 // heat gained per hour for each degree past the comfortable range
COLD_PER_DEGREE_HOUR :: 0.25 // chill gained per hour for each degree under it: bodies keep warmer than they take heat
BODY_WARMTH_PER_HOUR :: 1.0 // chill the body fights off every hour, so mild cold never builds
SLEEP_WARMTH_PER_HOUR :: 1.0 // and a sleeper, curled up, fights off this much more
THERMAL_RECOVER_PER_HOUR :: 4.0 // chill or heat lost per hour in comfortable weather
STRESS_RISE_PER_HOUR :: 2.0 // hypothermia or heat stress gained per hour while chill or heat is full
STRESS_RECOVER_PER_HOUR :: 0.5 // and lost, much more slowly, once it is not
STRESS_DAMAGE_PER_HOUR :: 3.0 // health lost per hour at full hypothermia or heat stress, in proportion below that
WARM_RANGE :: 2 // a lit fire pit this near (along both axes) warms the air
FIRE_WARMTH_C :: 15.0 // degrees added right beside a lit pit, fading to half that at WARM_RANGE

// Degrees a lit fire adds to the air at (x, y): the strongest of the pits within WARM_RANGE, or 0.
fire_warmth_c :: proc(g: ^Game, x, y: int) -> f64 {
	best := 0.0
	for dy in -WARM_RANGE ..= WARM_RANGE {
		for dx in -WARM_RANGE ..= WARM_RANGE {
			if !fire_lit_at(g, x + dx, y + dy) {continue}
			d := max(abs(dx), abs(dy))
			best = max(best, FIRE_WARMTH_C * f64(WARM_RANGE + 1 - d) / WARM_RANGE)
		}
	}
	return best
}

// 0 (healthy) to 1: how much hypothermia or heat stress holds a person back. Their energy drains
// (1 + affliction) times as fast and refills that much slower, so they need more rest.
affliction :: proc(p: Person) -> f32 {
	return max(p.hypothermia, p.heat_stress) / MAX_THERMAL
}

// One axis (cold or heat): the load builds at `pressure` per hour, or bleeds when there is none, and the
// stress follows it, rising while the load is full and bleeding otherwise. Returns the health lost.
thermal_axis :: proc(load, stress: ^f32, pressure, dt: f32, bleed: f32 = THERMAL_RECOVER_PER_HOUR) -> f32 {
	bleed_time, full_time := dt, f32(0)
	if pressure > 0 {
		bleed_time = min(dt, (MAX_THERMAL - load^) / pressure) // until the load is full
		load^ = min(load^ + pressure * bleed_time, MAX_THERMAL)
		full_time = dt - bleed_time
	} else {
		load^ = max(load^ - bleed * dt, 0)
	}
	integral: f32 // stress-hours, for the damage
	if bleed_time > 0 {
		t := min(bleed_time, stress^ / STRESS_RECOVER_PER_HOUR)
		after := stress^ - STRESS_RECOVER_PER_HOUR * t
		integral += (stress^ + after) / 2 * t
		stress^ = after
	}
	if full_time > 0 {
		after := min(stress^ + STRESS_RISE_PER_HOUR * full_time, MAX_THERMAL)
		integral += (stress^ + after) / 2 * full_time
		stress^ = after
	}
	return STRESS_DAMAGE_PER_HOUR * integral / MAX_THERMAL
}

// Advance one person's body temperature by dt game hours at the given air temperature, warmed by a nearby fire.
step_thermal :: proc(p: ^Person, air_c, fire_c: f64, dt: f32) {
	temp_c := air_c + fire_c // a fire warms the air around it: it keeps the cold off, and adds to the heat
	cold, hot: f32
	cold_bleed := f32(THERMAL_RECOVER_PER_HOUR)
	cold_c := temp_c + (COAT_WARMTH_C if p.coat else 0) // a coat keeps the cold out, but is opened up in the heat
	if cold_c < COLD_BELOW_C { // the body's own warmth offsets part of the cold; what is left builds chill
		warmth := f32(BODY_WARMTH_PER_HOUR + (SLEEP_WARMTH_PER_HOUR if p.asleep else 0))
		raw := f32(COLD_BELOW_C - cold_c) * COLD_PER_DEGREE_HOUR
		cold = max(raw - warmth, 0)
		cold_bleed = min(warmth - raw, THERMAL_RECOVER_PER_HOUR) if raw < warmth else 0
	}
	if temp_c > HOT_ABOVE_C {hot = f32(temp_c - HOT_ABOVE_C) * THERMAL_PER_DEGREE_HOUR}
	cold_loss := thermal_axis(&p.chill, &p.hypothermia, cold, dt, cold_bleed)
	heat_loss := thermal_axis(&p.heat, &p.heat_stress, hot, dt)
	p.harm[.Cold] += cold_loss
	p.harm[.Heat] += heat_loss
	p.health = max(p.health - cold_loss - heat_loss, 0)
}

// A person who is overheating, with a fire's warmth on them, steps to the neighbouring cell where it is cooler.
avoid_fire_heat :: proc(g: ^Game, p: ^Person) -> bool {
	if p.heat < HEAT_AVOID_ABOVE && p.heat_stress <= 0 {return false}
	here := fire_warmth_c(g, p.x, p.y)
	if here <= 0 {return false}
	best, bx, by := here, 0, 0
	for d in DIRS {
		if !can_enter(g, p.x + d.x, p.y + d.y) {continue}
		if w := fire_warmth_c(g, p.x + d.x, p.y + d.y); w < best {best, bx, by = w, d.x, d.y}
	}
	if bx == 0 && by == 0 {return false}
	p.x += bx
	p.y += by
	return true
}
HEAT_AVOID_ABOVE :: 30.0 // heat load at which people move away from a fire

SEEK_WARMTH_CHILL :: 10.0 // chill at which people stop what they are doing and go to a fire
STAY_WARM_CHILL :: 2.0 // they stay by it until the chill is down to this
SLEEPY_ENERGY :: 60.0 // tired people head for the fire early, since sleepers cannot move and the way may be long

// In the cold, a chilled person (or one about to fall asleep) goes to a lit fire and stays within
// reach of its warmth until they are warm again. The firekeeper tends the fire and has no need to.
seek_warmth :: proc(g: ^Game, p: ^Person) -> bool {
	if p.role == .Firekeeper || temperature_c(g.clock, g.cfg) >= COLD_BELOW_C {return false}
	tx, ty, lit := nearest_match(g, p^, lit_pit)
	if !lit {return false}
	warm_here := fire_warmth_c(g, p.x, p.y) > 0
	if warm_here {return p.chill > STAY_WARM_CHILL || p.energy < SLEEPY_ENERGY} // stay put; the fire is doing its work
	if p.chill < SEEK_WARMTH_CHILL && p.energy >= SLEEPY_ENERGY {return false}
	return step_toward(g, p, tx, ty)
}
