class_name ShotDirector
extends RefCounted
## Broadcast-style camera work for one shot: plans a few cuts the way a TV
## director covers golf (behind the player as the ball leaves, a chase or
## side-on camera through the flight, then a landing or pin camera looking
## back up the hole as it comes down), and gives the camera's place for any
## moment of the shot. `variant` picks between the alternatives, so replays
## and consecutive shots don't look the same. Used by RoundCamera in the
## Broadcast presentation; Classic keeps the Links 2003 framing.

enum Cam { BEHIND, CHASE, SIDE, LANDING, PIN, PUTT }

const CAM_NAMES := ["", "Chase cam", "Side cam", "Landing cam", "Pin cam", ""]
## Shorter shots than this stay on the behind and pin cameras.
const FULL_SHOT_CARRY := 60.0
## Landings this close to the pin cut to the camera behind the green.
const PIN_CAM_RANGE := 45.0
const CHASE_BACK := 16.0
const CHASE_UP := 4.0
const LANDING_BEYOND := 32.0
const LANDING_SIDE := 10.0
const LANDING_UP := 6.0
const PIN_BEYOND := 13.0
const PIN_UP := 2.6
const PUTT_BACK := 2.8
const PUTT_UP := 1.15
const KEEP_ABOVE_GROUND := 1.2

## Cut times (seconds into the shot) and the camera each one switches to.
var cut_times := PackedFloat32Array()
var cut_cams := PackedInt32Array()
## Fixed camera places, by Cam (unused for the tracking cameras).
var fixed := {}

var _shot: ShotResult
var _pin := Vector3.ZERO
var _dir := Vector3.FORWARD
var _right := Vector3.RIGHT
var _terrain: CourseTerrain
var _cut := -1


## Plans the cameras for `shot`. `behind` is where the camera stood at
## address; `putting` keeps a single low tracking camera.
static func plan(shot: ShotResult, pin: Vector3, terrain: CourseTerrain, behind: Vector3, putting: bool, variant: int) -> ShotDirector:
	var d := ShotDirector.new()
	d._shot = shot
	d._pin = pin
	d._terrain = terrain
	var start := shot.points[0] if shot.points.size() > 0 else shot.rest
	var land := shot.first_landing if shot.bounces > 0 else shot.rest
	var flat := Vector3(land.x - start.x, 0.0, land.z - start.z)
	if flat.length() < 0.5:
		flat = Vector3(pin.x - start.x, 0.0, pin.z - start.z)
	d._dir = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	d._right = d._dir.cross(Vector3.UP)
	var side := 1.0 if variant % 2 == 0 else -1.0
	if putting:
		d._add(0.0, Cam.PUTT)
		return d
	d.fixed[Cam.BEHIND] = behind
	d._add(0.0, Cam.BEHIND)
	var t_land := RoundCamera.time_near(shot, land) if shot.bounces > 0 else shot.time_s
	var near_pin := _flat(land, pin) < PIN_CAM_RANGE
	var last_cut := 0.0
	if shot.carry_m >= FULL_SHOT_CARRY:
		var apex_i := 0
		for i in shot.points.size():
			if shot.points[i].y > shot.points[apex_i].y:
				apex_i = i
		var t_apex := shot.times[apex_i] if shot.times.size() > 0 else t_land * 0.5
		var t_mid := clampf(t_apex * 0.45, 0.9, 2.2)
		if t_mid < t_land - 1.5:
			if (variant / 2) % 2 == 0:
				d._add(t_mid, Cam.CHASE)
			else:
				var apex := shot.points[apex_i]
				var reach := clampf(shot.carry_m * 0.5, 30.0, 120.0)
				var p := Vector3(apex.x, 0.0, apex.z) + d._right * side * reach
				p.y = maxf(d._ground(p) + 6.0, start.y + (apex.y - start.y) * 0.5)
				d.fixed[Cam.SIDE] = d._above(p)
				d._add(t_mid, Cam.SIDE)
			last_cut = t_mid
	var t_end := t_land - (1.0 if near_pin else 1.8)
	if t_end > last_cut + 0.8:
		if near_pin:
			var back := Vector3(pin.x - start.x, 0.0, pin.z - start.z).normalized()
			d.fixed[Cam.PIN] = d._above(pin + back * PIN_BEYOND + back.cross(Vector3.UP) * side * 3.0 + Vector3.UP * PIN_UP)
			d._add(t_end, Cam.PIN)
		elif shot.carry_m >= FULL_SHOT_CARRY:
			d.fixed[Cam.LANDING] = d._above(land + d._dir * LANDING_BEYOND + d._right * side * LANDING_SIDE + Vector3.UP * LANDING_UP)
			d._add(t_end, Cam.LANDING)
	return d


## The camera at time `t`: [position, look target, true on a cut]. `from` is
## where the camera is now and `delta` the frame time, for the tracking
## cameras' easing.
func step(t: float, ball: Vector3, from: Vector3, delta: float) -> Array:
	var i := cut_index(t)
	var cut := i != _cut
	_cut = i
	var cam: int = cut_cams[i]
	var pos := from
	var look := ball
	match cam:
		Cam.CHASE:
			var want := _above(ball - _dir * CHASE_BACK + Vector3.UP * CHASE_UP)
			pos = want if cut else from.lerp(want, 1.0 - exp(-delta * 3.5))
		Cam.PUTT:
			var aim := Vector3(_pin.x - ball.x, 0.0, _pin.z - ball.z)
			var back := _dir if aim.length() < 1.0 else aim.normalized()
			var want := _above(ball - back * PUTT_BACK + Vector3.UP * PUTT_UP)
			pos = want if cut else from.lerp(want, 1.0 - exp(-delta * 2.5))
			look = ball.lerp(_pin, 0.25)
		_:
			pos = fixed.get(cam, from)
	return [pos, look, cut]


## Which cut is live at `t`.
func cut_index(t: float) -> int:
	var i := 0
	while i + 1 < cut_times.size() and t >= cut_times[i + 1]:
		i += 1
	return i


## Name of the live camera for the on-screen tag ("" for the plain ones).
func cam_name(t: float) -> String:
	return CAM_NAMES[cut_cams[cut_index(t)]]


func _add(t: float, cam: Cam) -> void:
	cut_times.append(t)
	cut_cams.append(cam)


func _above(p: Vector3) -> Vector3:
	return Vector3(p.x, maxf(p.y, _ground(p) + KEEP_ABOVE_GROUND), p.z)


func _ground(p: Vector3) -> float:
	return _terrain.height_at(p.x, p.z) if _terrain != null else p.y


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
