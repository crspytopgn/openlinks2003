class_name BuggyDrive
extends RefCounted
## How the golf buggy drives (GolfBuggy): an electric cart's acceleration,
## braking and top speed by the ground under it, kinematic bicycle-model
## steering that tightens less as it goes faster, and hills that slow it
## going up and speed it going down. It won't go onto greens, bunkers or
## water (it stops at the edge, as real course rules ask), and is fastest on
## cart paths. Pure maths on a CourseTerrain, so the tests drive it headless.

const WHEELBASE := 1.65  ## metres between the axles
const MAX_STEER_DEG := 32.0
const HIGH_SPEED_STEER := 0.45  ## the share of the lock left at top speed
const STEER_RATE := 2.5  ## how fast the wheel turns, lock-to-centre per second
const ACCEL := 2.2  ## m/s^2 on the flat
const BRAKE := 5.5
const DRAG := 0.9  ## coasting
const TOP_PATH := 7.2  ## 16 mph, a typical governed cart
const TOP_GRASS := 6.3
const TOP_ROUGH := 4.0
const TOP_DEEP := 2.6
const TOP_REVERSE := 2.5
const HILL := 0.6  ## how much of gravity along the slope the motor doesn't cancel
const PROBE := 1.3  ## metres ahead of the centre checked for ground it won't enter

var position := Vector3.ZERO  ## the centre of the cart, on the ground
var heading_deg := 0.0  ## 0 is +z, 90 is +x (as the round's aim)
var speed := 0.0  ## m/s, negative backing up
var steer := 0.0  ## -1 (full right) to 1 (full left)
var blocked := false  ## stopped at the edge of ground it won't drive on


## Ground the cart stays off.
static func keeps_off(surface: int) -> bool:
	return surface == Surface.Type.GREEN or surface == Surface.Type.SAND or surface == Surface.Type.WATER


## Top speed on the ground at `p`.
static func top_speed(terrain: CourseTerrain, p: Vector3) -> float:
	if terrain.free_drop_at(p.x, p.z):
		return TOP_PATH  # cart paths and other hard ground
	match terrain.surface_at(p.x, p.z):
		Surface.Type.ROUGH, Surface.Type.OUT_OF_BOUNDS:
			return TOP_ROUGH
		Surface.Type.DEEP_ROUGH:
			return TOP_DEEP
	return TOP_GRASS


func forward() -> Vector3:
	var h := deg_to_rad(heading_deg)
	return Vector3(sin(h), 0.0, cos(h))


func place(p: Vector3, heading: float, terrain: CourseTerrain) -> void:
	position = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
	heading_deg = heading
	speed = 0.0
	steer = 0.0
	blocked = false


## One step: `throttle` -1 (brake, then reverse) to 1, `steer_in` -1 (right)
## to 1 (left).
func step(dt: float, throttle: float, steer_in: float, terrain: CourseTerrain) -> void:
	steer = move_toward(steer, clampf(steer_in, -1.0, 1.0), STEER_RATE * dt)
	var top := top_speed(terrain, position)
	var fwd := forward()
	# Gravity along the slope, what the motor doesn't make up.
	var ahead := position + fwd
	var grade := terrain.height_at(ahead.x, ahead.z) - position.y
	var accel := -BallPhysics.GRAVITY * HILL * clampf(grade, -0.5, 0.5)
	if throttle > 0.0:
		accel += (ACCEL if speed >= 0.0 else BRAKE) * throttle
	elif throttle < 0.0:
		accel += (BRAKE if speed > 0.0 else ACCEL) * throttle
	elif absf(speed) > 0.0:
		accel -= signf(speed) * DRAG
	var before := speed
	speed += accel * dt
	if throttle == 0.0 and signf(before) != signf(speed):
		speed = 0.0  # drag stops it, never reverses it
	if speed > top:
		speed = move_toward(speed, top, BRAKE * dt)
	speed = maxf(speed, -TOP_REVERSE)
	# Bicycle model: the lock it has left at this speed sets the turn.
	var lock := deg_to_rad(MAX_STEER_DEG) * steer * lerpf(1.0, HIGH_SPEED_STEER, clampf(absf(speed) / TOP_PATH, 0.0, 1.0))
	var yaw := speed / WHEELBASE * tan(lock)
	var heading := heading_deg + rad_to_deg(yaw * dt)
	var h := deg_to_rad(heading)
	var dir := Vector3(sin(h), 0.0, cos(h))
	var next := position + dir * speed * dt
	var probe := next + dir * PROBE * signf(speed)
	blocked = speed != 0.0 and keeps_off(terrain.surface_at(probe.x, probe.z))
	if blocked:
		speed = 0.0
		heading_deg = heading
		return
	heading_deg = wrapf(heading, -180.0, 180.0)
	position = Vector3(next.x, terrain.height_at(next.x, next.z), next.z)


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
