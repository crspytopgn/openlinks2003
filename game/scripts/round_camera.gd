class_name RoundCamera
extends Camera3D
## The round's camera, framed the way Links 2003 frames a shot: low behind
## the ball looking down the aim line with the golfer large in the lower
## half; during the shot it holds its place and turns to follow the ball,
## then for longer shots cuts to a view near where the ball comes down,
## watching it land and roll. The next shot cuts straight back behind the
## ball. Distances are by eye from the original (needs data for exact feel).

## Behind the ball, and how high, for full shots and putts.
const AIM_BACK := 4.2
const AIM_UP := 1.75
const PUTT_BACK := 2.6
const PUTT_UP := 1.2
## The aim view looks at a point this far down the line, this high.
const AIM_LOOK_AHEAD := 70.0
const AIM_LOOK_UP := 2.0
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


## Snaps behind the ball, looking down the aim line `dir` (flat, unit).
func aim(ball: Vector3, dir: Vector3, putting: bool) -> void:
	_shot = null
	var back := PUTT_BACK if putting else AIM_BACK
	var up := PUTT_UP if putting else AIM_UP
	position = _above_ground(ball - dir * back + Vector3.UP * up)
	if putting:
		_look = ball + dir * PUTT_LOOK_AHEAD
	else:
		var ahead := ball + dir * AIM_LOOK_AHEAD
		_look = Vector3(ahead.x, maxf(ball.y, _ground(ahead)) + AIM_LOOK_UP, ahead.z)
	_look_now = _look
	look_at(_look_now)


## Starts following a shot.
func follow(shot: ShotResult) -> void:
	_shot = shot
	_cut_to_landing = false
	_landing_time = -1.0
	if shot.carry_m >= LANDING_VIEW_MIN_CARRY:
		_landing_time = time_near(shot, shot.first_landing)


## Moves the camera for time `t` into the shot (or just eases the view when
## no shot is playing).
func update(delta: float, t: float, ball: Vector3) -> void:
	if _shot != null:
		if not _cut_to_landing and _landing_time > 0.0 and t >= _landing_time - LANDING_CUT_LEFT:
			_cut_to_landing = true
			_place_for_landing()
			_look_now = ball
		_look = ball
	_look_now = _look_now.lerp(_look, 1.0 - exp(-delta * 8.0))
	var to_look := _look_now - position
	if to_look.length() > 0.1 and absf(to_look.normalized().y) < 0.99:
		look_at(_look_now)


func _place_for_landing() -> void:
	var land := _shot.first_landing
	var start := _shot.points[0] if _shot.points.size() > 0 else land
	var dir := Vector3(land.x - start.x, 0.0, land.z - start.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var right := dir.cross(Vector3.UP)
	position = _above_ground(land - dir * LANDING_SHORT + right * LANDING_SIDE + Vector3.UP * LANDING_UP)


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
