class_name BallPhysics
extends RefCounted
## Ball flight, bounce and roll: a GDScript port of
## libs/olcore/src/ball_physics.cpp and libs/olcore/src/shot.cpp, so the game
## runs without a compiled extension. Change both together until GDExtension
## replaces this file. See those files for the sources of each formula.
##
## Coordinates: +y up, +z downrange, +x to the golfer's left. SI units.

const MASS := 0.04593
const RADIUS := 0.021335
const AIR_DENSITY := 1.225
const DRAG_COEFFICIENT := 0.24
const DRAG_SPIN_FACTOR := 0.18
const GRAVITY := 9.81
const SPIN_DECAY_PER_S := 0.04
const RPM_TO_RAD_S := TAU / 60.0

# olcore::ShotOptions defaults.
const DT := 0.004
const SAMPLE_EVERY := 4
const MAX_TIME := 60.0
const CUP_RADIUS := 0.054
const MAX_HOLING_SPEED := 1.6
const ROLL_THRESHOLD := 0.4
const STOP_SPEED := 0.03
const MAX_CRATER_DEG := 30.0
const SOLID_RESTITUTION := 0.35  ## normal speed kept off a trunk or wall
const SOLID_FRICTION := 0.75  ## speed along the face kept
const CANOPY_KEEP := 0.2  ## speed kept going into leaves
const CANOPY_BOUNCE := 0.05  ## normal speed kept coming back out
const OBSTACLE_GAP := 0.01  ## m; keeps the ball off the face it hit
const FLAT_TOP := 0.7  ## normal y above which the ball can rest on a solid


## Mirrors olcore::make_launch. Positive azimuth is left of +z; positive
## sidespin curves the ball left.
static func make_launch(speed: float, launch_deg: float, azimuth_deg: float, backspin_rpm: float, sidespin_rpm: float) -> BallState:
	var el := deg_to_rad(launch_deg)
	var az := deg_to_rad(azimuth_deg)
	var dir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
	var horiz := Vector3(dir.x, 0.0, dir.z)
	var right := Vector3(-1.0, 0.0, 0.0)
	if horiz.length() > 0.0:
		right = horiz.normalized().cross(Vector3.UP)
	var spin := right * (backspin_rpm * RPM_TO_RAD_S) + Vector3.UP * (sidespin_rpm * RPM_TO_RAD_S)
	return BallState.new(Vector3.ZERO, dir * speed, spin)


## Mirrors olcore::acceleration: gravity, spin-dependent drag, Magnus lift.
## `wind` is the velocity of the air (olcore::BallParams::wind); drag and lift
## act on the ball's velocity through it.
static func acceleration(vel: Vector3, spin: Vector3, wind := Vector3.ZERO) -> Vector3:
	var a := Vector3(0.0, -GRAVITY, 0.0)
	var air := vel - wind
	var speed := air.length()
	if speed < 1e-9:
		return a
	var area := PI * RADIUS * RADIUS
	var q := 0.5 * AIR_DENSITY * area * speed * speed
	var spin_rate := spin.length()
	var spin_ratio := RADIUS * spin_rate / speed
	var cd := DRAG_COEFFICIENT + DRAG_SPIN_FACTOR * spin_ratio
	a += air * (-q * cd / (MASS * speed))
	var wxv := spin.cross(air)
	var wxv_len := wxv.length()
	if wxv_len > 1e-9 and spin_rate > 1e-9:
		var cl := clampf(-0.05 + sqrt(0.0025 + 0.36 * spin_ratio), 0.0, 0.35)
		a += wxv * (q * cl / (MASS * wxv_len))
	return a


## Mirrors olcore::step_flight (RK4, or the game's own step with `aero`).
static func step_flight(s: BallState, dt: float, wind := Vector3.ZERO, aero: LinksAero = null) -> BallState:
	if aero != null:
		return aero.step_flight(s, dt, wind)
	var v1 := s.velocity
	var a1 := acceleration(v1, s.spin, wind)
	var v2 := s.velocity + a1 * (dt / 2.0)
	var a2 := acceleration(v2, s.spin, wind)
	var v3 := s.velocity + a2 * (dt / 2.0)
	var a3 := acceleration(v3, s.spin, wind)
	var v4 := s.velocity + a3 * dt
	var a4 := acceleration(v4, s.spin, wind)
	var out := BallState.new()
	out.position = s.position + (v1 + v2 * 2.0 + v3 * 2.0 + v4) * (dt / 6.0)
	out.velocity = s.velocity + (a1 + a2 * 2.0 + a3 * 2.0 + a4) * (dt / 6.0)
	out.spin = s.spin * maxf(0.0, 1.0 - SPIN_DECAY_PER_S * dt)
	return out


## Mirrors olcore::turf_restitution.
static func turf_restitution(normal_speed: float) -> float:
	var v := absf(normal_speed)
	if v > 20.0:
		return 0.12
	return 0.510 - 0.0375 * v + 0.000903 * v * v


## Mirrors olcore::bounce. Updates s.velocity and s.spin in place.
static func bounce(s: BallState, ground_normal: Vector3, surface: int) -> void:
	var n := ground_normal
	if s.velocity.dot(n) >= 0.0:
		return
	var along := s.velocity - n * s.velocity.dot(n)
	var along_len := along.length()
	var speed := s.velocity.length()
	if along_len > 1e-9 and speed > 1e-9:
		var impact_deg := rad_to_deg(asin(minf(1.0, -s.velocity.dot(n) / speed)))
		var tilt_deg := minf(MAX_CRATER_DEG, Surface.softness(surface) * 15.4 * (speed / 18.6) * (impact_deg / 44.4))
		var tilt := deg_to_rad(tilt_deg)
		n = n * cos(tilt) - along * (sin(tilt) / along_len)

	var vn := s.velocity.dot(n)
	if vn >= 0.0:
		return
	var e := turf_restitution(-vn) * Surface.restitution_scale(surface)
	var jn := (1.0 + e) * -vn
	var vt := s.velocity - n * vn
	var vc := vt + s.spin.cross(n * -RADIUS)
	var vc_len := vc.length()
	if vc_len > 1e-9:
		var j := minf(2.0 / 7.0 * vc_len, Surface.friction(surface) * jn)
		var dir := vc / vc_len
		vt -= dir * j
		s.spin += n.cross(dir) * (2.5 * j / RADIUS)
	s.spin -= n * (s.spin.dot(n) * 0.5)
	s.velocity = vt + n * (-e * vn)


## Mirrors olcore::hit_obstacle: a solid sends the ball back with some of its
## speed; a canopy soaks up most of it, so the ball drops. `hit` comes from
## CourseTerrain.obstacle_hit().
static func hit_obstacle(s: BallState, hit: Dictionary) -> void:
	var n: Vector3 = hit.normal
	var vn := s.velocity.dot(n)
	if vn >= 0.0:
		return
	var vt := s.velocity - n * vn
	if int(hit.kind) == ObstacleField.Kind.SOLID:
		s.velocity = vt * SOLID_FRICTION - n * (vn * SOLID_RESTITUTION)
		s.spin *= 0.5
	else:
		s.velocity = vt * CANOPY_KEEP - n * (vn * CANOPY_BOUNCE)
		s.spin *= 0.2


## Mirrors olcore::simulate_shot: flight, bounces and roll over the terrain
## until the ball stops, drops, or finds water or out of bounds. `wind` acts
## on the flight only, as in olcore. With `aero` the whole shot uses the Links
## 2003 model (olcore::BallParams::links and LinksGround.simulate_shot).
static func simulate_shot(start: BallState, terrain: CourseTerrain, has_cup := false, cup := Vector3.ZERO, wind := Vector3.ZERO, aero: LinksAero = null) -> ShotResult:
	if aero != null:
		return LinksGround.simulate_shot(start, terrain, has_cup, cup, wind, aero)
	var r := ShotResult.new()
	var s := start.copy()
	var t := 0.0
	var step := 0
	var landed := false
	r.add_sample(0.0, s.position)

	var n0 := terrain.normal_at(s.position.x, s.position.z)
	var rolling := s.velocity.dot(n0) < ROLL_THRESHOLD
	if rolling:
		s.velocity -= n0 * s.velocity.dot(n0)
		landed = true
		r.first_landing = s.position

	while t < MAX_TIME:
		if not rolling:
			var nxt := step_flight(s, DT, wind, aero)
			var h0 := s.position.y - terrain.height_at(s.position.x, s.position.z)
			var h1 := nxt.position.y - terrain.height_at(nxt.position.x, nxt.position.z)
			t += DT
			step += 1
			r.apex_m = maxf(r.apex_m, nxt.position.y - start.position.y)

			# An obstacle met before the ground. Time keeps the whole step,
			# so a ball wedged between obstacles still runs out of time.
			var ground := (h0 / (h0 - h1) if h0 > 0.0 else 0.0) if h1 <= 0.0 else 2.0
			var hit := terrain.obstacle_hit(s.position, nxt.position)
			if not hit.is_empty() and float(hit.fraction) < ground:
				var f: float = hit.fraction
				var b := BallState.new(s.position.lerp(nxt.position, f), s.velocity.lerp(nxt.velocity, f), nxt.spin)
				hit_obstacle(b, hit)
				# Just outside a solid, or just inside a canopy, so the same
				# face is not met again.
				var gap := OBSTACLE_GAP if int(hit.kind) == ObstacleField.Kind.SOLID else -OBSTACLE_GAP
				b.position += (hit.normal as Vector3) * gap
				r.obstacle_hits += 1
				r.add_sample(t, b.position)
				# Settled on top of something flat enough (a wall, a bridge).
				var n: Vector3 = hit.normal
				if int(hit.kind) == ObstacleField.Kind.SOLID and n.y > FLAT_TOP and b.velocity.dot(n) < ROLL_THRESHOLD:
					if not landed:
						landed = true
						r.first_landing = b.position
					return _finish(r, ShotResult.Outcome.REST, b.position, t, landed, start, terrain)
				s = b
				continue

			if h1 <= 0.0:
				var frac := h0 / (h0 - h1) if h0 > 0.0 else 0.0
				var pos := s.position.lerp(nxt.position, frac)
				var vel := s.velocity.lerp(nxt.velocity, frac)
				pos.y = terrain.height_at(pos.x, pos.z)
				t = t - DT + DT * frac
				if not landed:
					landed = true
					r.first_landing = pos
				r.add_sample(t, pos)

				var surf := terrain.surface_at(pos.x, pos.z)
				if surf == Surface.Type.WATER:
					return _finish(r, ShotResult.Outcome.WATER, pos, t, landed, start, terrain)
				if surf == Surface.Type.OUT_OF_BOUNDS:
					return _finish(r, ShotResult.Outcome.OUT_OF_BOUNDS, pos, t, landed, start, terrain)
				if has_cup and _distance_xz(pos, cup) < CUP_RADIUS:
					return _finish(r, ShotResult.Outcome.HOLED, cup, t, landed, start, terrain)

				var n := terrain.normal_at(pos.x, pos.z)
				var b := BallState.new(pos, vel, nxt.spin)
				bounce(b, n, surf)
				r.bounces += 1
				s = b
				var vn := b.velocity.dot(n)
				if vn < ROLL_THRESHOLD:
					rolling = true
					s.velocity = b.velocity - n * vn
				continue
			s = nxt
		else:
			var pos := s.position
			var v := s.velocity
			var n := terrain.normal_at(pos.x, pos.z)
			var here := terrain.surface_at(pos.x, pos.z)
			var g := Vector3(0.0, -GRAVITY, 0.0)
			var slope := (g - n * g.dot(n)) * (5.0 / 7.0)
			var resist := Surface.rolling_resistance(here) * GRAVITY * n.y
			var speed := v.length()
			var holds := slope.length() <= resist
			if speed < STOP_SPEED and holds:
				return _finish(r, ShotResult.Outcome.REST, pos, t, landed, start, terrain)
			var a := slope
			if speed > 1e-9:
				a -= v * (resist / speed)
			var nv := v + a * DT
			if speed > 1e-9 and nv.dot(v) < 0.0 and holds:
				return _finish(r, ShotResult.Outcome.REST, pos, t, landed, start, terrain)
			var npos := pos + nv * DT
			npos.y = terrain.height_at(npos.x, npos.z)
			var nn := terrain.normal_at(npos.x, npos.z)
			nv -= nn * nv.dot(nn)
			t += DT
			step += 1

			# Rolling into a trunk or a wall; leaves do not stop a rolling ball.
			var hit := terrain.obstacle_hit(pos, npos)
			if not hit.is_empty() and int(hit.kind) == ObstacleField.Kind.SOLID:
				var hp := pos.lerp(npos, float(hit.fraction)) + (hit.normal as Vector3) * OBSTACLE_GAP
				hp.y = terrain.height_at(hp.x, hp.z)
				var b := BallState.new(hp, nv, s.spin)
				hit_obstacle(b, hit)
				var hn := terrain.normal_at(hp.x, hp.z)
				s.position = hp
				s.velocity = b.velocity - hn * b.velocity.dot(hn)
				s.spin = b.spin
				r.obstacle_hits += 1
				r.add_sample(t, hp)
				continue

			if has_cup and nv.length() < MAX_HOLING_SPEED and _segment_distance_xz(pos, npos, cup) < CUP_RADIUS:
				return _finish(r, ShotResult.Outcome.HOLED, cup, t, landed, start, terrain)
			var surf := terrain.surface_at(npos.x, npos.z)
			if surf == Surface.Type.WATER:
				return _finish(r, ShotResult.Outcome.WATER, npos, t, landed, start, terrain)
			if surf == Surface.Type.OUT_OF_BOUNDS:
				return _finish(r, ShotResult.Outcome.OUT_OF_BOUNDS, npos, t, landed, start, terrain)
			s.position = npos
			s.velocity = nv
		if step % SAMPLE_EVERY == 0:
			r.add_sample(t, s.position)
	return _finish(r, ShotResult.Outcome.TIMED_OUT, s.position, t, landed, start, terrain)


static func _finish(r: ShotResult, outcome: ShotResult.Outcome, pos: Vector3, t: float, landed: bool, start: BallState, terrain: CourseTerrain) -> ShotResult:
	r.outcome = outcome
	r.rest = pos
	r.time_s = t
	r.rest_surface = terrain.surface_at(pos.x, pos.z)
	if not landed:
		r.first_landing = pos
	r.carry_m = _distance_xz(start.position, r.first_landing)
	r.total_m = _distance_xz(start.position, pos)
	if r.times.is_empty() or r.times[r.times.size() - 1] < t:
		r.add_sample(t, pos)
	return r


static func _distance_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _segment_distance_xz(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var len2 := ab.length_squared()
	var f := 0.0 if len2 <= 0.0 else clampf(ac.dot(ab) / len2, 0.0, 1.0)
	return (ab * f - ac).length()
