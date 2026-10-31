class_name BuggyDrive
extends RefCounted
## How the golf buggy drives (GolfBuggy): a planar rigid-body model of a
## two-seat electric cart, stepped at 120 Hz.
##
## - Mass 500 kg with the golfer aboard, yaw inertia 300 kg m^2, the centre
##   of gravity behind the middle (the batteries) and 0.55 m up.
## - A 48 V motor driving the rear axle: 1500 N at the wheels from a stand,
##   then limited by 3.7 kW of power, and a speed governor at about 15.5 mph
##   (5.5 mph in reverse) that also holds it back downhill by regenerating.
##   An accelerator and brake pedal that take a moment to press, and the
##   automatic park brake carts have when the pedals are let go.
## - Tyres with a cornering stiffness and grip per surface (cart path best,
##   deep rough worst), saturating smoothly, inside a friction circle per
##   axle, so it understeers, wheelspins and slides like the real thing.
## - Weight moving back under acceleration and forward under braking.
## - Rolling resistance by surface (which is why it is slower in the rough),
##   air drag, and gravity along and across the slope under it.
##
## It won't go onto greens, bunkers or water: it stops at the edge, as real
## course rules ask. Pure maths on a CourseTerrain, so the tests drive it
## headless.

const GRAVITY := 9.81
const MASS := 500.0
const YAW_INERTIA := 300.0
const WHEELBASE := 1.66
const CG_TO_FRONT := 0.9  ## centre of gravity to the front axle
const CG_TO_REAR := WHEELBASE - CG_TO_FRONT
const CG_HEIGHT := 0.55
const TRACK := 0.93  ## between the left and right tyres, on average
const MAX_STEER_DEG := 32.0
const STEER_ASSIST := 0.55  ## the share of the lock left at top speed (keyboard driving)
const STEER_RATE := 2.0  ## lock to centre, per second
const PEDAL_RATE := 4.0
const STALL_FORCE := 1500.0  ## N at the wheels
const MOTOR_POWER := 3700.0  ## W
const GOVERNED := 6.9  ## m/s, about 15.5 mph
const GOVERNED_REVERSE := 2.5
const GOVERNOR_BAND := 0.5  ## the motor fades out over the last 0.5 m/s
const REGEN_FORCE := 1600.0  ## most the governor holds back downhill
const COAST_REGEN := 140.0  ## N of regenerative drag with the pedals up
const BRAKE_FORCE := 4200.0
const BRAKE_FRONT := 0.4  ## share of braking on the front axle
const PARK_SPEED := 0.3  ## the park brake holds below this with the pedals up
const CORNERING := 9000.0  ## N per radian of slip, per axle
const DRAG_AREA := 1.6  ## Cd times frontal area, m^2
const AIR := 1.2
const STEP := 1.0 / 120.0
const MAX_STEPS := 12  ## per call, so a slow frame can't stall the game
const PROBE := 1.3  ## metres ahead of the centre checked for ground it won't enter
## Kept for the round's speed readouts and tests.
const TOP_GRASS := GOVERNED

var position := Vector3.ZERO  ## the centre of the cart, on the ground
var heading_deg := 0.0  ## 0 is +z, 90 is +x (as the round's aim)
var speed := 0.0  ## m/s along the cart, negative backing up
var lateral := 0.0  ## m/s sideways, + to the left (sliding)
var yaw_rate := 0.0  ## rad/s, + turning left
var steer := 0.0  ## -1 (full right) to 1 (full left), where the wheel is now
var pedal := 0.0  ## -1 (brake or reverse) to 1, where the pedals are now
var blocked := false  ## stopped at the edge of ground it won't drive on
var accel_long := 0.0  ## m/s^2, for the suspension and weight transfer
var accel_lat := 0.0
var wheelspin := false  ## the rear tyres are at the limit of grip

var _carry := 0.0


## Ground the cart stays off.
static func keeps_off(surface: int) -> bool:
	return surface == Surface.Type.GREEN or surface == Surface.Type.SAND or surface == Surface.Type.WATER


## Tyre grip (friction coefficient) on the ground at `p`.
static func grip(terrain: CourseTerrain, p: Vector3) -> float:
	if terrain.free_drop_at(p.x, p.z):
		return 0.85  # cart paths and other hard ground
	match terrain.surface_at(p.x, p.z):
		Surface.Type.ROUGH, Surface.Type.OUT_OF_BOUNDS:
			return 0.55
		Surface.Type.DEEP_ROUGH:
			return 0.45
	return 0.62


## Rolling resistance coefficient on the ground at `p`.
static func rolling(terrain: CourseTerrain, p: Vector3) -> float:
	if terrain.free_drop_at(p.x, p.z):
		return 0.015
	match terrain.surface_at(p.x, p.z):
		Surface.Type.ROUGH, Surface.Type.OUT_OF_BOUNDS:
			return 0.14
		Surface.Type.DEEP_ROUGH:
			return 0.22
	return 0.045


func forward() -> Vector3:
	var h := deg_to_rad(heading_deg)
	return Vector3(sin(h), 0.0, cos(h))


func place(p: Vector3, heading: float, terrain: CourseTerrain) -> void:
	position = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
	heading_deg = heading
	speed = 0.0
	lateral = 0.0
	yaw_rate = 0.0
	steer = 0.0
	pedal = 0.0
	accel_long = 0.0
	accel_lat = 0.0
	blocked = false
	wheelspin = false
	_carry = 0.0


## Advances `dt` seconds: `throttle` -1 (brake, then reverse) to 1,
## `steer_in` -1 (right) to 1 (left).
func step(dt: float, throttle: float, steer_in: float, terrain: CourseTerrain) -> void:
	# The ground under the cart, looked up once a frame.
	var mu := grip(terrain, position)
	var crr := rolling(terrain, position)
	var n := terrain.normal_at(position.x, position.z)
	var g_along_slope := Vector3(0.0, -GRAVITY, 0.0) - n * (-GRAVITY * n.y)
	_carry += dt
	var steps := 0
	blocked = false
	while _carry >= STEP and steps < MAX_STEPS:
		_carry -= STEP
		steps += 1
		_substep(STEP, clampf(throttle, -1.0, 1.0), clampf(steer_in, -1.0, 1.0), terrain, mu, crr, n.y, g_along_slope)
		if blocked:
			break
	if steps >= MAX_STEPS:
		_carry = 0.0


func _substep(h: float, throttle: float, steer_in: float, terrain: CourseTerrain, mu: float, crr: float, cos_slope: float, g_slope: Vector3) -> void:
	steer = move_toward(steer, steer_in, STEER_RATE * h)
	pedal = move_toward(pedal, throttle, PEDAL_RATE * h)
	var fwd := forward()
	var left := Vector3.UP.cross(fwd)
	var u := speed
	var v := lateral
	var r := yaw_rate

	# The park brake: pedals up and nearly stopped, it holds (even on a hill).
	if pedal == 0.0 and absf(u) < PARK_SPEED and absf(v) < PARK_SPEED:
		speed = 0.0
		lateral = 0.0
		yaw_rate = 0.0
		accel_long = 0.0
		accel_lat = 0.0
		wheelspin = false
		return

	# Pedals: drive, brake, or reverse.
	var drive := 0.0
	var brake := 0.0
	if pedal > 0.0:
		if u < -PARK_SPEED:
			brake = BRAKE_FORCE * pedal
		else:
			var f := minf(STALL_FORCE, MOTOR_POWER / maxf(absf(u), 0.1)) * pedal
			drive = f * clampf((GOVERNED - u) / GOVERNOR_BAND, 0.0, 1.0)
	elif pedal < 0.0:
		if u > PARK_SPEED:
			brake = BRAKE_FORCE * -pedal
		else:
			var f := minf(STALL_FORCE, MOTOR_POWER / maxf(absf(u), 0.1)) * -pedal
			drive = -f * clampf((GOVERNED_REVERSE + u) / GOVERNOR_BAND, 0.0, 1.0)
	else:
		brake = COAST_REGEN
	# The governor holds it back downhill.
	if u > GOVERNED:
		brake += minf(REGEN_FORCE, (u - GOVERNED) / GOVERNOR_BAND * REGEN_FORCE)
	elif u < -GOVERNED_REVERSE:
		brake += minf(REGEN_FORCE, (-GOVERNED_REVERSE - u) / GOVERNOR_BAND * REGEN_FORCE)
	var moving := signf(u) if absf(u) > 0.05 else 0.0

	# Axle loads, with the weight moving under acceleration and braking.
	var transfer := MASS * accel_long * CG_HEIGHT / WHEELBASE
	var weight := MASS * GRAVITY * cos_slope
	var n_front := maxf(weight * CG_TO_REAR / WHEELBASE - transfer, 0.1 * weight)
	var n_rear := maxf(weight * CG_TO_FRONT / WHEELBASE + transfer, 0.1 * weight)

	# Front tyres: steered.
	var lock := deg_to_rad(MAX_STEER_DEG) * steer * lerpf(1.0, STEER_ASSIST, clampf(absf(u) / GOVERNED, 0.0, 1.0))
	var c := cos(lock)
	var s := sin(lock)
	var fu := u * c + (v + CG_TO_FRONT * r) * s
	var fv := -u * s + (v + CG_TO_FRONT * r) * c
	var fx_w := -moving * brake * BRAKE_FRONT
	var fy_w := _tyre(-atan(fv / maxf(absf(fu), 1.0)), mu * n_front)
	var front := _circle(Vector2(fx_w, fy_w), mu * n_front)
	var front_x := front.x * c - front.y * s
	var front_y := front.x * s + front.y * c
	# Rear tyres: driven.
	var rv := v - CG_TO_REAR * r
	var rear_x := drive - moving * brake * (1.0 - BRAKE_FRONT)
	var rear_y := _tyre(-atan(rv / maxf(absf(u), 1.0)), mu * n_rear)
	var rear := _circle(Vector2(rear_x, rear_y), mu * n_rear)
	wheelspin = rear.length() >= mu * n_rear * 0.98 and absf(drive) > 0.0

	# Rolling resistance, air, and the slope.
	var fx := front_x + rear.x - moving * crr * weight - AIR * 0.5 * DRAG_AREA * u * absf(u) + MASS * g_slope.dot(fwd)
	var fy := front_y + rear.y + MASS * g_slope.dot(left)
	var mz := CG_TO_FRONT * front_y - CG_TO_REAR * rear.y

	accel_long = fx / MASS
	accel_lat = fy / MASS
	var nu := u + (accel_long + v * r) * h
	var nv := v + (accel_lat - u * r) * h
	var nr := r + mz / YAW_INERTIA * h
	# Rolling resistance and braking stop it; they never push it backwards.
	if drive == 0.0 and moving != 0.0 and signf(nu) != moving and absf(g_slope.dot(fwd)) * MASS < brake + crr * weight:
		nu = 0.0
	var heading := heading_deg + rad_to_deg(nr * h)
	var hr := deg_to_rad(heading)
	var nf := Vector3(sin(hr), 0.0, cos(hr))
	var nl := Vector3.UP.cross(nf)
	var vel := nf * nu + nl * nv
	var next := position + vel * h
	if vel.length_squared() > 0.0:
		var probe := next + vel.normalized() * PROBE
		if keeps_off(terrain.surface_at(probe.x, probe.z)):
			blocked = true
			speed = 0.0
			lateral = 0.0
			yaw_rate = 0.0
			accel_long = 0.0
			accel_lat = 0.0
			return
	speed = nu
	lateral = nv
	yaw_rate = nr
	heading_deg = wrapf(heading, -180.0, 180.0)
	position = Vector3(next.x, terrain.height_at(next.x, next.z), next.z)


## Sideways tyre force for a slip angle: linear at first, then saturating
## smoothly at the grip available.
static func _tyre(slip: float, limit: float) -> float:
	return limit * tanh(CORNERING * slip / maxf(limit, 1.0))


## Keeps a tyre force inside its friction circle.
static func _circle(f: Vector2, limit: float) -> Vector2:
	var l := f.length()
	return f * (limit / l) if l > limit else f


## Somewhere to leave the cart near `ball`, on drivable ground, back from
## the line to `toward`: beside it, off to the right first.
static func parking_spot(terrain: CourseTerrain, ball: Vector3, toward: Vector3) -> Vector3:
	var dir := Vector3(toward.x - ball.x, 0.0, toward.z - ball.z)
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.BACK
	var left := Vector3.UP.cross(dir)
	for d: float in [7.0, 12.0, 20.0, 30.0, 45.0]:
		for off: Vector3 in [-left * d * 0.7 - dir * d * 0.5, left * d * 0.7 - dir * d * 0.5, -dir * d, -left * d, left * d]:
			var p := ball + off
			if not keeps_off(terrain.surface_at(p.x, p.z)) and terrain.in_bounds(p.x, p.z):
				return Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
	return ball - dir * 8.0
