class_name RoundCamera
extends Camera3D
## The round's camera, framed the way Links 2003 frames a shot: low behind
## the ball looking down the aim line with the golfer large in the lower
## half; during the shot it holds its place and turns to follow the ball,
## then for longer shots cuts to a view near where the ball comes down,
## watching it land and roll. The next shot cuts straight back behind the
## ball. Distances are by eye from the original (needs data for exact feel).
##
## With `broadcast` set (the Broadcast presentation) a ShotDirector cuts
## between TV-style cameras instead, and each hole opens with a flyover.

## Behind the ball, and how high, for full shots and putts.
const AIM_BACK := 4.2
const AIM_UP := 1.75
const PUTT_BACK := 2.6
const PUTT_UP := 1.2
## The aim view looks at a point this far down the line, this high.
const AIM_LOOK_AHEAD := 70.0
const AIM_LOOK_UP := 2.0
const AIM_MAX_LIFT := 14.0  ## highest the aim camera climbs to see over a rise
const AIM_MAX_BACK_STEPS := 8  ## and how far it backs off (2 m steps) to keep the golfer in view
const PUTT_LOOK_AHEAD := 6.0
## Shots that carry further than this get the landing view.
const LANDING_VIEW_MIN_CARRY := 70.0
## The landing view sits short of the landing point and off to the side,
## and takes over when the ball has this much of its flight left.
const LANDING_SHORT := 30.0
const LANDING_SIDE := 14.0
const LANDING_UP := 4.0
const LANDING_CUT_LEFT := 2.2  ## seconds before the first landing
const KEEP_ABOVE_GROUND := 1.0

var terrain: CourseTerrain
var _look := Vector3.ZERO
var _look_now := Vector3.ZERO
var _shot: ShotResult
var _landing_time := -1.0
var _cut_to_landing := false
## TV-style cameras (ShotDirector) instead of the Links framing.
var broadcast := false
var director: ShotDirector
var _variant := 0
var _aim_pos := Vector3.ZERO
var _aim_look := Vector3.ZERO
## Hole flyover: a path the camera flies before the first shot; empty when
## not flying.
var _fly_path := PackedVector3Array()
var _fly_t := 0.0
var _fly_length := 0.0
var _fly_pin := Vector3.ZERO

const FLYOVER_SPEED := 55.0  ## metres per second along the path
const FLYOVER_MIN_S := 4.5
const FLYOVER_MAX_S := 9.0
const FLYOVER_UP := 38.0


## Snaps behind the ball, looking down the aim line `dir` (flat, unit).
func aim(ball: Vector3, dir: Vector3, putting: bool, reach := 0.0) -> void:
	_shot = null
	var back := PUTT_BACK if putting else AIM_BACK
	var up := PUTT_UP if putting else AIM_UP
	var pos := _above_ground(ball - dir * back + Vector3.UP * up)
	if putting:
		_look = ball + dir * PUTT_LOOK_AHEAD
	else:
		var ahead := ball + dir * AIM_LOOK_AHEAD
		_look = Vector3(ahead.x, maxf(ball.y, _ground(ahead)) + AIM_LOOK_UP, ahead.z)
		# A rise in front can hide where the shot is going: lift the camera
		# until it can see the target, and look at the target.
		if reach > AIM_LOOK_AHEAD and terrain != null:
			var far := ball + dir * reach
			var target := Vector3(far.x, _ground(far) + 1.0, far.z)
			if not sight_clear(terrain, pos, target):
				_aim_over_rise(ball, dir, pos, target)
				return
	_aim_pos = pos
	_aim_look = _look
	if flying():
		return
	position = pos
	_look_now = _look
	look_at(_look_now)


## Stands at `pos` looking at `look`, for reading a putt (GreenRead.View).
func look_from(pos: Vector3, look: Vector3) -> void:
	_shot = null
	if flying():
		end_flyover()
	position = pos
	_look = look
	_look_now = look
	look_at(look)
## The aim view when a rise hides the target: the camera climbs until it
## sees over, and backs off until the golfer and ball are still in frame
## below the target.
func _aim_over_rise(ball: Vector3, dir: Vector3, start: Vector3, target: Vector3) -> void:
	var half := deg_to_rad(fov) * 0.5
	var feet := ball + Vector3.UP * 0.1
	var pos := start
	var pitch := 0.0
	for k in AIM_MAX_BACK_STEPS + 1:
		pos = _above_ground(start - dir * (2.0 * k))
		var lift := 0.0
		while lift < AIM_MAX_LIFT and not sight_clear(terrain, pos + Vector3.UP * lift, target):
			lift += 1.0
		pos += Vector3.UP * lift
		var down_to_target := _angle_below(pos, target)
		var down_to_feet := _angle_below(pos, feet)
		# Look down just enough to keep the feet inside the bottom edge.
		pitch = maxf(down_to_target, down_to_feet - half * 0.85)
		if pitch - down_to_target < half * 0.8:
			break
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	_look = pos + flat * 100.0 + Vector3.DOWN * tan(pitch) * 100.0
	_aim_pos = pos
	_aim_look = _look
	if flying():
		return
	position = pos
	_look_now = _look
	look_at(_look_now)


## Angle below the horizontal from `from` to `to`, radians.
static func _angle_below(from: Vector3, to: Vector3) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	return atan2(from.y - to.y, flat)


## Starts following a shot. `pin` and `putting` steer the broadcast cameras;
## `variant` picks between their alternatives (replays pass a new one).
func follow(shot: ShotResult, pin := Vector3.ZERO, putting := false, variant := -1) -> void:
	_shot = shot
	_cut_to_landing = false
	_landing_time = -1.0
	end_flyover()
	director = null
	if broadcast:
		if variant < 0:
			_variant += 1
			variant = _variant
		director = ShotDirector.plan(shot, pin, terrain, position, putting, variant)
		return
	if shot.carry_m >= LANDING_VIEW_MIN_CARRY:
		_landing_time = time_near(shot, shot.first_landing)


## Moves the camera for time `t` into the shot (or just eases the view when
## no shot is playing).
func update(delta: float, t: float, ball: Vector3) -> void:
	if flying():
		_update_flyover(delta)
		return
	if _shot != null and director != null:
		var pose := director.step(t, ball, position, delta)
		position = pose[0]
		_look = pose[1]
		if pose[2]:
			_look_now = _look
	elif _shot != null:
		if not _cut_to_landing and _landing_time > 0.0 and t >= _landing_time - LANDING_CUT_LEFT:
			_cut_to_landing = true
			_place_for_landing()
			_look_now = ball
		_look = ball
	_look_now = _look_now.lerp(_look, 1.0 - exp(-delta * 8.0))
	var to_look := _look_now - position
	if to_look.length() > 0.1 and absf(to_look.normalized().y) < 0.99:
		look_at(_look_now)


## Flies over the hole from behind the tee, along its route, down to the
## green, then settles behind the ball (wherever aim() last put it).
func start_flyover(hole: HoleData) -> void:
	_fly_path = PackedVector3Array()
	_fly_pin = hole.pin
	var pts: Array[Vector3] = [hole.tee]
	for r in hole.route:
		pts.append(Vector3(r.x, 0.0, r.y))
	pts.append(hole.pin)
	var first := Vector3(pts[1].x - pts[0].x, 0.0, pts[1].z - pts[0].z).normalized()
	_fly_path.append(_lift(hole.tee - first * 40.0, FLYOVER_UP * 0.8))
	for i in range(0, pts.size() - 1):
		_fly_path.append(_lift(pts[i], FLYOVER_UP))
	var last := Vector3(hole.pin.x - pts[pts.size() - 2].x, 0.0, hole.pin.z - pts[pts.size() - 2].z).normalized()
	_fly_path.append(_lift(hole.pin - last * 30.0, FLYOVER_UP * 0.5))
	_fly_path.append(_lift(hole.pin - last * 14.0 + last.cross(Vector3.UP) * 6.0, 7.0))
	_fly_length = 0.0
	for i in range(1, _fly_path.size()):
		_fly_length += _fly_path[i - 1].distance_to(_fly_path[i])
	_fly_t = 0.0
	position = _fly_path[0]
	_look_now = _fly_look(0.0)
	look_at(_look_now)


func flying() -> bool:
	return _fly_path.size() > 1


## Ends a flyover early (a click) or once it's done, cutting behind the ball.
func end_flyover() -> void:
	if not flying():
		return
	_fly_path = PackedVector3Array()
	position = _aim_pos
	_look = _aim_look
	_look_now = _look
	look_at(_look_now)


func flyover_progress() -> float:
	return clampf(_fly_t / _fly_seconds(), 0.0, 1.0) if flying() else 1.0


func _fly_seconds() -> float:
	return clampf(_fly_length / FLYOVER_SPEED, FLYOVER_MIN_S, FLYOVER_MAX_S)


func _update_flyover(delta: float) -> void:
	_fly_t += delta
	var u := _fly_t / _fly_seconds()
	if u >= 1.0:
		end_flyover()
		return
	# Ease in and out so the start and the arrival at the green are gentle.
	var e := u * u * (3.0 - 2.0 * u)
	position = _above_ground(_fly_point(e))
	_look_now = _look_now.lerp(_fly_look(e), 1.0 - exp(-delta * 4.0))
	var to_look := _look_now - position
	if to_look.length() > 0.1 and absf(to_look.normalized().y) < 0.99:
		look_at(_look_now)


## Point at fraction `u` of the path, Catmull-Rom through its points.
func _fly_point(u: float) -> Vector3:
	var n := _fly_path.size()
	var f := clampf(u, 0.0, 1.0) * (n - 1)
	var i := mini(int(f), n - 2)
	var t := f - i
	var p0 := _fly_path[maxi(i - 1, 0)]
	var p1 := _fly_path[i]
	var p2 := _fly_path[i + 1]
	var p3 := _fly_path[mini(i + 2, n - 1)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


## Looks a little way ahead along the path, and at the pin near the end.
func _fly_look(u: float) -> Vector3:
	var ahead := _fly_point(minf(u + 0.3, 1.0))
	var ground := Vector3(ahead.x, _ground(ahead), ahead.z)
	return ground.lerp(_fly_pin, smoothstep(0.55, 0.95, u))


func _lift(p: Vector3, up: float) -> Vector3:
	return Vector3(p.x, _ground(p) + up, p.z)


func _place_for_landing() -> void:
	var land := _shot.first_landing
	var start := _shot.points[0] if _shot.points.size() > 0 else land
	var dir := Vector3(land.x - start.x, 0.0, land.z - start.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var right := dir.cross(Vector3.UP)
	position = _above_ground(land - dir * LANDING_SHORT + right * LANDING_SIDE + Vector3.UP * LANDING_UP)


## True if no ground lies between `from` and `to`.
static func sight_clear(t: CourseTerrain, from: Vector3, to: Vector3) -> bool:
	const STEPS := 40
	for i in range(2, STEPS):
		var p := from.lerp(to, float(i) / STEPS)
		if t.height_at(p.x, p.z) > p.y:
			return false
	return true


func _above_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, maxf(p.y, _ground(p) + KEEP_ABOVE_GROUND), p.z)


func _ground(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z) if terrain != null else p.y


## Time of the flight sample closest to `p`.
static func time_near(shot: ShotResult, p: Vector3) -> float:
	var best := -1.0
	var best_d := INF
	for i in shot.points.size():
		var d := shot.points[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = shot.times[i]
	return best
