class_name LinksGround
extends RefCounted
## The bounce and roll of Links 2003: a GDScript port of
## libs/olcore/src/links_ground.cpp; change both together. See
## docs/formats/physics.md.
##
## Like the C++ this works in the game's own frame and units: x to the
## golfer's right, y downrange, z up, feet, seconds, and spin in revolutions
## per second. simulate_shot() converts to and from the game's SI frame.

enum Mode { FLIGHT, SKID, ROLL, REST }

const GREEN := 1
const FAIRWAY := 2
const ROUGH := 3
const SAND := 4
const WATER := 5
const PATH := 6
const DIRT := 7
const BUSHES := 8
const ROCKS := 9
const DEEP_GRASS := 10

const RADIUS := 0.07  ## ft
const GRAVITY := 32.152  ## ft/s^2
const REV_PER_FPS := 2.27364  ## rev/s per ft/s of surface speed
const FRAME_DT := 1.0 / 60.0
const FEET_PER_METRE := 1.0 / 0.3048

# Bounce.
const DRAG_KNEE := 1700.0
const DRAG_KNEE_SLOPE := 0.000352941
const DRAG_KNEE_BASE := 0.4
const ROLLING_SLIP := 0.2
const SLIP_EPSILON := 0.01
const SPIN_PER_IMPULSE := 35.7143
const PLUG_SPEED := 60.0
const ROUGH_SPREAD := 0.13
const ROCKS_SPREAD := 6.28319
# Ground step.
const ACROSS := 0.5625
const ALONG := 0.25
const FAST_ROLL := 30.0
const FAST_ROLL_GROWTH := 0.2
const SKID_SPIN := 5.684105
const TWO_PI_R := 0.439823
const STEEP := 0.6
const LEDGE_PROBES := 12
const LEDGE_HEIGHT := 1.0
const LEAVE_GROUND := 0.1
const CHECKPOINT_TIME := 1.0 + 1e-6
const STUCK_DISTANCE := 0.14
# Rough: random hops.
const HOP_MIN_SPEED := 1.5
const HOP_SPEED_KEPT := 0.9
const HOP_CHANCE := 0.45
const HOP_MAX_SPEED := 40.0
const HOP_LOW := 0.02
const HOP_HIGH := 0.15
# Rocks: kicks.
const KICK_MIN_SPEED := 1.0
const KICK_STOP_CHANCE := 0.5
const KICK_BOOST := 5.0

## class, restitution, impact friction, skid friction, impact drag, roll, stop, spin grip
## (and for rough and deep grass: lie spin, lie power)
const SURFACES := {
	GREEN: [0.23, 0.08, 0.383486, 0.496454, 0.10538, 0.5, 1.219],
	FAIRWAY: [0.266579, 0.1308, 0.132528, 0.441, 0.18, 0.5, 1.00211],
	ROUGH: [0.242881, 0.087621, 0.104659, 0.522788, 0.604758, 1.0, 2.0, 0.406505, 0.927315],
	SAND: [0.2025, 0.05, 0.0714, 0.644842, 0.897139, 0.5, 4.0],
	WATER: [0.3, 0.35, 0.00288, 0.1, 2.0, 2.0, 0.1],
	PATH: [0.75303, 0.45738, 0.45, 0.07597, 0.068172, 2.0, 1.46647],
	DIRT: [0.388524, 0.121495, 0.108, 0.307136, 0.195622, 0.467325, 4.80256],
	BUSHES: [0.404543, 0.209029, 0.203495, 0.19674, 0.2555, 0.5, 3.05625],
	ROCKS: [0.5022, 0.196532, 0.162792, 0.140846, 0.124317, 2.0, 1.15583],
	DEEP_GRASS: [0.24384, 0.07, 0.100116, 0.561193, 0.608475, 0.5, 3.0, 0.1992, 0.836732],
}


## What a ground class does to the ball. Mirrors olcore::LinksSurface.
class Params:
	var ground_class := LinksGround.FAIRWAY
	var restitution := 0.0
	var impact_friction := 0.0
	var skid_friction := 0.0
	var impact_drag := 0.0
	var roll_resistance := 0.0
	var stop_speed := 0.0
	var spin_grip := 0.0
	var lie_spin := 1.0  ## spin kept when striking from this lie
	var lie_power := 1.0  ## ball speed kept when striking from this lie


## Mirrors olcore::LinksBall. `position` is the centre.
class Ball:
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var spin := Vector3.ZERO  ## rev/s
	var mode: int = LinksGround.Mode.FLIGHT
	var on_ground_started := false
	var checkpoint_x := 0.0
	var checkpoint_y := 0.0
	var ground_time := 0.0


## The game's random numbers. Mirrors olcore::LinksRandom.
class Rng:
	const MASK := 0xffffffff
	var state := 0x12345678

	func _init(p_seed := 0x12345678) -> void:
		state = p_seed & MASK

	## The seed the game uses for a ball struck from (x, y), in feet.
	static func seed_for(x: float, y: float) -> int:
		var s := ((int(y) & MASK) * (int(x) & MASK)) & MASK
		return s if s != 0 else 0x12345678

	func next_u32() -> int:
		var s := state
		var out := 0
		for _i in 32:
			var x := ((s << 1) ^ s) & MASK
			x = ((x << 1) ^ s) & MASK
			x = ((x << 2) ^ s) & MASK
			x = ((x << 2) ^ s) & MASK
			x = ((x << 25) ^ s) & MASK
			s = (x & 0x80000000) | (s >> 1)
			out = ((out << 1) | (s & 1)) & MASK
		state = s
		return (out << 1) & MASK

	func next_fraction() -> float:
		# The game keeps the fraction as a float.
		return PackedFloat32Array([next_u32() / 4294967296.0])[0]


## The ground in the game's frame. Mirrors olcore::LinksGround.
class Ground:
	func height(_x: float, _y: float) -> float:
		return 0.0

	func normal(_x: float, _y: float) -> Vector3:
		return Vector3(0, 0, 1)

	func surface(_x: float, _y: float) -> LinksGround.Params:
		return LinksGround.surface_for_class(LinksGround.FAIRWAY)


## A CourseTerrain seen in the game's frame.
class TerrainGround extends Ground:
	var terrain: CourseTerrain

	func _init(p_terrain: CourseTerrain) -> void:
		terrain = p_terrain

	func height(x: float, y: float) -> float:
		return terrain.height_at(-x / LinksGround.FEET_PER_METRE, y / LinksGround.FEET_PER_METRE) * LinksGround.FEET_PER_METRE

	func normal(x: float, y: float) -> Vector3:
		var n := terrain.normal_at(-x / LinksGround.FEET_PER_METRE, y / LinksGround.FEET_PER_METRE)
		return Vector3(-n.x, n.z, n.y)

	func surface(x: float, y: float) -> LinksGround.Params:
		var s := terrain.surface_at(-x / LinksGround.FEET_PER_METRE, y / LinksGround.FEET_PER_METRE)
		return LinksGround.surface_for_class(LinksGround.ground_class_for(s))


## What happened during a step. Mirrors olcore::LinksStepInfo.
class StepInfo:
	var landed := false
	var contact := Vector3.ZERO
	var contact_class := 0


static func surface_for_class(ground_class: int) -> Params:
	if ground_class == GREEN and greens != null:
		return greens
	var c := ground_class if SURFACES.has(ground_class) else FAIRWAY
	var v: Array = SURFACES[c]
	var p := Params.new()
	p.ground_class = c
	p.restitution = v[0]
	p.impact_friction = v[1]
	p.skid_friction = v[2]
	p.impact_drag = v[3]
	p.roll_resistance = v[4]
	p.stop_speed = v[5]
	p.spin_grip = v[6]
	if v.size() > 7:
		p.lie_spin = v[7]
		p.lie_power = v[8]
	return p


enum GreenFirmness { SOFT, MEDIUM, FIRM }
enum GreenSpeed { SLOW, NORMAL, FAST }

## The greens every shot uses (set_greens); null is medium and normal.
static var greens: Params = null


## Sets the game's green options for every shot. Mirrors olcore::links_green.
static func set_greens(firmness: int, speed: int) -> void:
	greens = green_for(firmness, speed)


## The game's green options. Each firmness is a whole green record (firm
## greens bounce higher and grip spin harder); the speed then sets the rolling
## resistance from the three records' own values. Mirrors olcore::links_green.
static func green_for(firmness: int, speed: int) -> Params:
	var soft := 0.120760001
	var medium := 0.105379999
	var firm := 0.0900000036
	# Each step of speed moves the resistance one record along (past the ends,
	# by the same step again).
	var ladder := [2.0 * soft - medium, soft, medium, firm, 2.0 * firm - medium]
	var p := Params.new()
	var v: Array = SURFACES[GREEN]
	match firmness:
		GreenFirmness.SOFT:
			v = [0.209999993, 0.0900000036, 0.314999998, 0.549284995, soft, 0.5, 0.899999976]
		GreenFirmness.FIRM:
			v = [0.25, 0.100000001, 0.202500001, 0.461228013, firm, 0.5, 1.29999995]
	p.ground_class = GREEN
	p.restitution = v[0]
	p.impact_friction = v[1]
	p.skid_friction = v[2]
	p.impact_drag = v[3]
	p.stop_speed = v[5]
	p.spin_grip = v[6]
	var step := clampi(firmness, 0, 2) + 1 + (clampi(speed, 0, 2) - 1)
	p.roll_resistance = ladder[step]
	return p


## The class used for one of our Surface.Type values.
static func ground_class_for(s: int) -> int:
	match s:
		Surface.Type.GREEN:
			return GREEN
		Surface.Type.ROUGH, Surface.Type.OUT_OF_BOUNDS:
			return ROUGH
		Surface.Type.DEEP_ROUGH:
			return DEEP_GRASS
		Surface.Type.SAND:
			return SAND
		Surface.Type.WATER:
			return WATER
	return FAIRWAY


## Mirrors olcore::links_impact.
static func impact(b: Ball, n: Vector3, s: Params) -> void:
	var v := b.velocity
	var w := b.spin
	if s.ground_class == WATER:
		_rest(b)
		return
	if s.ground_class == SAND and absf(n.dot(v)) > PLUG_SPEED:
		# Plugs one landing in four, picked by where it lands.
		var k := int((b.position.y + b.position.x + b.position.z) * 12)
		if k % 4 == 0:
			_rest(b)
			return
	var side := n.cross(v)
	side = side.normalized() if side.length() > 0.0 else Vector3(1, 0, 0)
	var fwd := side.cross(n)
	var vt := Vector2(fwd.dot(v), side.dot(v)).length()
	var vn := absf(n.dot(v))
	var w0 := side.dot(w) * TAU

	var x := vt * vn
	var drag := sqrt(x) * s.impact_drag
	if x < DRAG_KNEE:
		drag *= x * DRAG_KNEE_SLOPE + DRAG_KNEE_BASE
	drag = minf(drag, vt)

	var rw := w0 * RADIUS
	var slip := vt - rw
	var k := s.restitution + 1.0
	var vt2: float
	var spin: float
	if absf(slip) < ROLLING_SLIP:
		vt2 = vt - drag
		spin = vt2 * REV_PER_FPS
	else:
		var dv := -k * s.impact_friction * vn - drag
		var dw := k * s.spin_grip * s.impact_friction * vn * SPIN_PER_IMPULSE
		if rw > vt:
			dv = -dv
			dw = -dw
		var v1 := vt + dv
		var w1 := w0 + dw
		if (slip > 0.0) == (v1 - w1 * RADIUS > 0.0):
			vt2 = v1
			spin = w1 / TAU
		else:
			# Friction would reverse the slip: stop at rolling instead.
			var d := dv - RADIUS * dw
			vt2 = v1 if absf(d) < SLIP_EPSILON else (-drag - dv) * slip / d - drag + vt
			spin = vt2 * REV_PER_FPS
	var vn2 := vn * s.restitution

	var along := vt2
	var across := 0.0
	if s.ground_class == ROUGH or s.ground_class == ROCKS:
		# A turn picked by where the ball lands.
		var f := float((int(b.position.y) & 0xfff) + (int(b.position.x) & 0xfff)) / 8190.0
		var angle := ROUGH_SPREAD * f - ROUGH_SPREAD * 0.5 if s.ground_class == ROUGH else ROCKS_SPREAD * f
		along = cos(angle) * vt2
		across = -sin(angle) * vt2
	var out := fwd * along + side * across + n * vn2
	b.spin = side * spin
	if out.dot(n) <= 2.0 * s.stop_speed:
		out = fwd * along + side * across
		b.mode = Mode.SKID
		b.on_ground_started = false
	b.velocity = out


## Mirrors olcore::links_contact_time.
static func contact_time(v0: Vector3, v1: Vector3, s: float) -> float:
	var m0 := _mask(v0)
	var m1 := _mask(v1)
	var m := m0 & m1
	if m == 0:
		if m0 == 0:
			return s if m1 == 0 else 1.0
		return s if m1 != 0 else 0.0
	var a: float
	if m & 1:
		a = v0.x / v1.x
	elif m & 4:
		a = v0.z / v1.z
	else:
		a = v0.y / v1.y
	if absf(absf(a) - 1.0) < 1e-4:
		return s
	var disc := (1.0 - a) * s * 4.0 + a * a
	var root := sqrt(disc) if disc > 0.0 else 0.0
	var t1 := (root - a) / (2.0 * (1.0 - a))
	var t2 := (a + root) / (2.0 * (1.0 - a))
	return t1 if t1 >= 0.0 and t1 <= 1.0 else t2


## Mirrors olcore::links_step. `wind` is in ft/s before the game's 0.5 factor.
static func step(b: Ball, ground: Ground, aero: LinksAero, wind: Vector3, rng: Rng, dt := FRAME_DT) -> StepInfo:
	match b.mode:
		Mode.FLIGHT:
			return _flight_step(b, ground, aero, wind, dt)
		Mode.SKID, Mode.ROLL:
			return _ground_step(b, ground, aero, wind, rng, dt)
	return StepInfo.new()


## Mirrors olcore::simulate_links_shot: a whole shot with the Links 2003
## flight, bounce and roll, and our own trees, cup, water and out of bounds.
static func simulate_shot(start: BallState, terrain: CourseTerrain, has_cup: bool, cup: Vector3, wind_mps: Vector3, aero: LinksAero) -> ShotResult:
	var dt := FRAME_DT
	var radius_m := RADIUS / FEET_PER_METRE
	var ground := TerrainGround.new(terrain)
	var r := ShotResult.new()
	var landed := false
	var t := 0.0
	var n_steps := 0

	# The game always starts the ball in flight with its centre one radius up.
	var b := Ball.new()
	b.position = _to_game(start.position) + Vector3(0, 0, RADIUS)
	b.velocity = _to_game(start.velocity)
	b.spin = _spin_to_game(start.spin)
	var rng := Rng.new(Rng.seed_for(b.position.x, b.position.y))
	var wind := _to_game(wind_mps)
	r.add_sample(0.0, start.position)

	while t < BallPhysics.MAX_TIME:
		var before := _from_game(b.position) - Vector3(0, radius_m, 0)
		var before_velocity := _from_game(b.velocity)
		var before_spin := _spin_from_game(b.spin)
		var was_flying := b.mode == Mode.FLIGHT
		var info := step(b, ground, aero, wind, rng, dt)
		t += dt
		n_steps += 1
		var after := _from_game(b.position) - Vector3(0, radius_m, 0)
		r.apex_m = maxf(r.apex_m, after.y - start.position.y)

		# Trees and walls: our own handling, as in BallPhysics.simulate_shot.
		var hit := terrain.obstacle_hit(before, after)
		if not hit.is_empty() and (was_flying or int(hit.kind) == ObstacleField.Kind.SOLID):
			var solid := int(hit.kind) == ObstacleField.Kind.SOLID
			var hb := BallState.new(before.lerp(after, float(hit.fraction)), before_velocity, before_spin)
			BallPhysics.hit_obstacle(hb, hit)
			hb.position += (hit.normal as Vector3) * (BallPhysics.OBSTACLE_GAP if solid else -BallPhysics.OBSTACLE_GAP)
			r.obstacle_hits += 1
			r.add_sample(t, hb.position)
			b.position = _to_game(hb.position) + Vector3(0, 0, RADIUS)
			b.velocity = _to_game(hb.velocity)
			b.spin = _spin_to_game(hb.spin)
			b.mode = Mode.FLIGHT
			continue

		if info.landed:
			var contact := _from_game(info.contact)
			if not landed:
				landed = true
				r.first_landing = contact
			r.bounces += 1
			r.add_sample(t, contact)
			var surf := terrain.surface_at(contact.x, contact.z)
			if surf == Surface.Type.WATER:
				return _finish(r, ShotResult.Outcome.WATER, contact, t, landed, start, terrain)
			if surf == Surface.Type.OUT_OF_BOUNDS:
				return _finish(r, ShotResult.Outcome.OUT_OF_BOUNDS, contact, t, landed, start, terrain)
			if has_cup and BallPhysics._distance_xz(contact, cup) < BallPhysics.CUP_RADIUS:
				return _finish(r, ShotResult.Outcome.HOLED, cup, t, landed, start, terrain)
		elif not was_flying:
			if has_cup and _from_game(b.velocity).length() < BallPhysics.MAX_HOLING_SPEED and BallPhysics._segment_distance_xz(before, after, cup) < BallPhysics.CUP_RADIUS:
				return _finish(r, ShotResult.Outcome.HOLED, cup, t, landed, start, terrain)
			var here := terrain.surface_at(after.x, after.z)
			if here == Surface.Type.WATER:
				return _finish(r, ShotResult.Outcome.WATER, after, t, landed, start, terrain)
			if here == Surface.Type.OUT_OF_BOUNDS:
				return _finish(r, ShotResult.Outcome.OUT_OF_BOUNDS, after, t, landed, start, terrain)
		if b.mode == Mode.REST:
			return _finish(r, ShotResult.Outcome.REST, after, t, landed, start, terrain)
		if n_steps % BallPhysics.SAMPLE_EVERY == 0:
			r.add_sample(t, after)
	return _finish(r, ShotResult.Outcome.TIMED_OUT, _from_game(b.position) - Vector3(0, radius_m, 0), t, landed, start, terrain)


static func _finish(r: ShotResult, outcome: ShotResult.Outcome, pos: Vector3, t: float, landed: bool, start: BallState, terrain: CourseTerrain) -> ShotResult:
	return BallPhysics._finish(r, outcome, pos, t, landed, start, terrain)


static func _mask(v: Vector3) -> int:
	return (1 if v.x != 0.0 else 0) | (2 if v.y != 0.0 else 0) | (4 if v.z != 0.0 else 0)


static func _unit_or_zero(v: Vector3) -> Vector3:
	return v.normalized() if v.length() > 0.0 else v


static func _rest(b: Ball) -> void:
	b.velocity = Vector3.ZERO
	b.spin = Vector3.ZERO
	b.mode = Mode.REST


# Our frame (SI, y up, x to the golfer's left) to the game's (feet, z up, x to
# the golfer's right): a rotation, so cross products carry over.
static func _to_game(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.z, v.y) * FEET_PER_METRE


static func _from_game(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.z, v.y) / FEET_PER_METRE


static func _spin_to_game(w: Vector3) -> Vector3:
	return Vector3(-w.x, w.z, w.y) / TAU


static func _spin_from_game(w: Vector3) -> Vector3:
	return Vector3(-w.x, w.z, w.y) * TAU


# Straight path p -> q: fraction where the centre first meets the ground, or
# a negative number if it stays above.
static func _ground_crossing(g: Ground, p: Vector3, q: Vector3) -> float:
	if _height_above(g, p, q, 0.0) <= 0.0:
		return 0.0
	var samples := 16
	var t0 := 0.0
	var t1 := -1.0
	for k in range(1, samples + 1):
		var t := float(k) / samples
		if _height_above(g, p, q, t) <= 0.0:
			t0 = float(k - 1) / samples
			t1 = t
			break
	if t1 < 0.0:
		return -1.0
	for i in 50:
		var m := 0.5 * (t0 + t1)
		if _height_above(g, p, q, m) <= 0.0:
			t1 = m
		else:
			t0 = m
	return t1


static func _height_above(g: Ground, p: Vector3, q: Vector3, t: float) -> float:
	var x := p + (q - p) * t
	return x.z - g.height(x.x, x.y)


static func _acceleration(v: Vector3, spin: Vector3, aero: LinksAero, wind: Vector3) -> Vector3:
	var a := Vector3(0, 0, -GRAVITY)
	var air := v - wind * LinksAero.WIND_SCALE
	var speed := air.length()
	if speed < 1e-9:
		return a
	var rate := spin.length()
	a -= air * (LinksAero.DRAG_SCALE * LinksAero.coefficient(aero.drag, speed, rate) * speed)
	if rate > 1e-9:
		a += (spin / rate).cross(air) * (LinksAero.LIFT_SCALE * LinksAero.coefficient(aero.lift, speed, rate) * speed)
	return a


static func _flight_step(b: Ball, g: Ground, aero: LinksAero, wind: Vector3, dt: float) -> StepInfo:
	var info := StepInfo.new()
	var p := b.position
	var v := b.velocity
	var w := b.spin
	var v2 := v + _acceleration(v, w, aero, wind) * dt
	var p2 := p + (v + v2) * (0.5 * dt)
	var w2 := w * pow(LinksAero.SPIN_KEPT_PER_FRAME, LinksAero.FRAME_RATE * dt)
	var s := _ground_crossing(g, p, p2)
	if s < 0.0:
		b.position = p2
		b.velocity = v2
		b.spin = w2
		return info
	# The rest of the step is dropped: the step ends at the contact.
	var tau := contact_time(v, v2, s)
	var hit := p + (p2 - p) * s
	hit.z = g.height(hit.x, hit.y)
	var n := g.normal(hit.x, hit.y)
	var surf := g.surface(hit.x, hit.y)
	b.velocity = v * (1.0 - tau) + v2 * tau
	b.spin = w * (1.0 - tau) + w2 * tau
	b.position = hit + n * RADIUS
	impact(b, n, surf)
	info.landed = true
	info.contact = hit
	info.contact_class = surf.ground_class
	return info


static func _ground_step(b: Ball, g: Ground, aero: LinksAero, wind: Vector3, rng: Rng, dt: float) -> StepInfo:
	var p := b.position
	var v0 := b.velocity
	var w := b.spin
	var v := v0
	var speed := v.length()
	var p1 := p + v * dt
	var n1 := g.normal(p1.x, p1.y)
	var surf := g.surface(p1.x, p1.y)
	var cls := surf.ground_class

	# Too steep to hold a ball on grass: look up to a foot ahead for a ledge
	# to drop onto.
	if n1.z < STEEP and (cls == GREEN or cls == FAIRWAY or cls == ROUGH or cls == DEEP_GRASS):
		var ahead := _unit_or_zero(Vector3(v.x, v.y, 0))
		for i in range(1, LEDGE_PROBES + 1):
			var q := p1 + ahead * (float(i) / LEDGE_PROBES)
			var nq := g.normal(q.x, q.y)
			var floor_z := g.height(q.x, q.y)
			if nq.z > STEEP and absf(q.z - floor_z) < LEDGE_HEIGHT:
				b.position = Vector3(q.x, q.y, floor_z)
				return StepInfo.new()
			if nq.z >= STEEP:
				break

	# The pull down the slope, the rolling resistance and, while skidding,
	# friction against the slip of the contact point.
	var normal_force := GRAVITY
	var nh := Vector2(n1.x, n1.y).length()
	var vh := Vector2(v.x, v.y).length()
	var pull: float
	if nh == 0.0 or vh == 0.0:
		pull = 0.5 / n1.z * normal_force
	else:
		var c := (n1.x * v.x + n1.y * v.y) / (vh * nh)
		pull = sqrt((1.0 - c * c) * ACROSS + c * c * ALONG) / n1.z * normal_force
	var slope := Vector3(n1.x * pull, n1.y * pull, normal_force - GRAVITY)
	var support := Vector3(n1.x * pull, n1.y * pull, normal_force).length()
	var resist := support * surf.roll_resistance
	if vh > FAST_ROLL:
		resist *= 1.0 + FAST_ROLL_GROWTH * (vh - FAST_ROLL)
	var friction := Vector3.ZERO
	var now_rolling := false
	if b.mode == Mode.SKID:
		var slip := v + n1.cross(w) * TWO_PI_R
		var grip := support * surf.skid_friction
		var slip_speed := slip.length()
		if grip * dt >= slip_speed:
			now_rolling = true
		else:
			friction = slip * (-grip / slip_speed)
	var a := slope + friction
	if resist * dt >= speed:
		if a.length() <= resist:
			_rest(b)
			return StepInfo.new()
		v = Vector3.ZERO
	elif speed > 0.0:
		a -= v * (resist / speed)
	var v2 := v + a * dt
	var p2 := p + v2 * dt
	var n2 := g.normal(p2.x, p2.y)
	var z2 := g.height(p2.x, p2.y) + RADIUS / n2.z

	# The ground falls away (or rises) too fast to follow: take off.
	if (z2 - p.z) * (z2 - p.z) > LEAVE_GROUND:
		b.mode = Mode.FLIGHT
		b.on_ground_started = false
		return _flight_step(b, g, aero, wind, dt)

	# Keep the speed, along the ground at the new point.
	var side := n2.cross(v2)
	var v3 := _unit_or_zero(side).cross(n2) * v2.length() if side.length() > 0.0 else v2
	var w2: Vector3
	if b.mode == Mode.SKID:
		w2 = w + friction.cross(n1) * (surf.spin_grip * dt * SKID_SPIN)
	else:
		w2 = n1.cross(v2) * REV_PER_FPS
	b.position = Vector3(p2.x, p2.y, z2)
	b.velocity = v3
	b.spin = w2
	if now_rolling:
		b.mode = Mode.ROLL

	# Grass makes a ball hop now and then; rocks kick it about.
	var hop := false
	var hop_velocity := Vector3.ZERO
	if cls == ROUGH:
		var r1 := rng.next_fraction()
		var r2 := rng.next_fraction()
		if speed > HOP_MIN_SPEED:
			var kept := speed * HOP_SPEED_KEPT
			if r1 < HOP_CHANCE:
				var height := (HOP_HIGH - HOP_LOW) / (HOP_MAX_SPEED - HOP_MIN_SPEED) * (kept - HOP_MIN_SPEED) * r2
				if height >= z2 - p.z:
					var target := Vector3(p1.x, p1.y, z2 + HOP_LOW + height)
					hop_velocity = _unit_or_zero(target - p) * kept
					hop = true
	elif cls == ROCKS:
		if speed > KICK_MIN_SPEED:
			hop_velocity = _unit_or_zero(_unit_or_zero(v0) * 0.5 + n1 * 0.5) * (speed * surf.restitution)
			hop = true
		elif rng.next_fraction() <= KICK_STOP_CHANCE:
			_rest(b)
			return StepInfo.new()
		else:
			hop_velocity = v0 + n1 * (speed + speed * KICK_BOOST * rng.next_fraction())
			hop = true

	if not b.on_ground_started:
		b.on_ground_started = true
		b.checkpoint_x = p2.x
		b.checkpoint_y = p2.y
		b.ground_time = 0.0
	else:
		b.ground_time += dt
		if b.ground_time >= CHECKPOINT_TIME:
			if Vector2(p2.x - b.checkpoint_x, p2.y - b.checkpoint_y).length() < STUCK_DISTANCE:
				_rest(b)
				return StepInfo.new()
			b.checkpoint_x = p2.x
			b.checkpoint_y = p2.y
			b.ground_time = 0.0
	if hop:
		b.velocity = hop_velocity
		b.position = p + hop_velocity * dt
		b.mode = Mode.FLIGHT
	return StepInfo.new()
