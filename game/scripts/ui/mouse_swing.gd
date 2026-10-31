class_name MouseSwingControl
extends Control
## Links 2003's PowerStroke mouse swing. Hold the left button and pull the
## mouse back towards you (down the screen) for the backswing, then push it
## smoothly forward (up) through the snap line and let go of the button as
## you reach it. The speed through the line sets the power, letting go early
## opens the face (slice), late closes it (hook), and a stroke that wanders
## left or right swings the club across the ball. LinksLaunch.mouse_swing
## turns the stroke into the swing.
##
## Distances are in the game's meter units: a 600-unit-high screen. The
## calibration (FULL_SPEED, RELEASE_MS_PER_UNIT) is ours; the original's
## mouse sampling was not decoded.

signal backswing_started
signal stroke_finished(stroke: LinksLaunch.MouseStroke)
signal stroke_cancelled

enum Phase { IDLE, BACK, DOWN, THROUGH, DONE }

## Downswing speed through the snap line, in units per second, for 100%.
const FULL_SPEED := 1300.0
## Each unit of release error is this many milliseconds early or late.
const RELEASE_MS_PER_UNIT := 5.0
## The backswing must be at least this long, in units.
const MIN_BACKSWING := 40.0
## How far the stroke must come back up before it counts as the downswing.
const TURN_UNITS := 6.0
## Speed is averaged over this many seconds before the line.
const SPEED_WINDOW := 0.05

var phase: Phase = Phase.IDLE
var skill := 3
var _start := Vector2.ZERO  ## where the button went down (screen pixels)
var _top := Vector2.ZERO  ## the bottom of the backswing on screen
var _now := Vector2.ZERO
var _cross_x := 0.0
var _speed := 0.0  ## units per second through the line
var _samples: Array[Vector3] = []  ## (x, y, time) in units and seconds
var _result := ""
var _trail: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Screen pixels per meter unit.
func unit_px() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(get_viewport_rect().size.y, 1.0) / 600.0


func is_swinging() -> bool:
	return phase == Phase.BACK or phase == Phase.DOWN or phase == Phase.THROUGH


func reset() -> void:
	phase = Phase.IDLE
	_samples.clear()
	_trail.clear()
	_result = ""
	queue_redraw()


## The button went down at `pos` (screen pixels) at time `t` (seconds).
func begin(pos: Vector2, t: float) -> void:
	reset()
	phase = Phase.BACK
	_start = pos
	_top = pos
	_now = pos
	_add_sample(pos, t)
	backswing_started.emit()


## The mouse moved to `pos` at time `t` with the button held.
func motion(pos: Vector2, t: float) -> void:
	if not is_swinging():
		return
	_now = pos
	_add_sample(pos, t)
	var u := unit_px()
	match phase:
		Phase.BACK:
			if pos.y > _top.y:
				_top = pos
			elif (_top.y - pos.y) / u > TURN_UNITS and (_top.y - _start.y) / u >= MIN_BACKSWING:
				phase = Phase.DOWN
		Phase.DOWN:
			if pos.y <= _start.y:
				_cross(t)
	queue_redraw()


## The button came up at `pos` at time `t`.
func release(pos: Vector2, t: float) -> void:
	if not is_swinging():
		return
	motion(pos, t)
	if phase == Phase.BACK:
		# Let go before the downswing: no shot.
		reset()
		stroke_cancelled.emit()
		return
	var u := unit_px()
	var m := LinksLaunch.MouseStroke.new()
	m.skill = skill
	m.height = maxf((_top.y - _start.y) / u, 1.0)
	# How early or late the button came up: the distance from the line where
	# it did, at the stroke's speed. (Input arrives once a frame, so the
	# position of the release is a better clock than the frame time.)
	if phase != Phase.THROUGH:
		_speed = _recent_speed()
	var past := (_start.y - pos.y) / u
	m.release = past / maxf(_speed, 1.0) * 1000.0 / RELEASE_MS_PER_UNIT
	m.drift = ((_cross_x if phase == Phase.THROUGH else pos.x) - _top.x) / u
	m.power = 100.0 * _speed / FULL_SPEED
	phase = Phase.DONE
	_result = "%d%%" % roundi(m.power)
	if absf(m.release) > 2.0:
		_result += "   %s" % ("late" if m.release > 0.0 else "early")
	queue_redraw()
	stroke_finished.emit(m)


func _cross(_t: float) -> void:
	phase = Phase.THROUGH
	_speed = _recent_speed()
	_cross_x = _now.x


func _add_sample(pos: Vector2, t: float) -> void:
	var u := unit_px()
	_samples.append(Vector3(pos.x / u, pos.y / u, t))
	if _samples.size() > 64:
		_samples.remove_at(0)
	_trail.append(pos)
	if _trail.size() > 256:
		_trail.remove_at(0)


## Upward speed over the last SPEED_WINDOW seconds, units per second.
func _recent_speed() -> float:
	if _samples.size() < 2:
		return 0.0
	var last := _samples[_samples.size() - 1]
	var first := last
	for i in range(_samples.size() - 2, -1, -1):
		first = _samples[i]
		if last.z - first.z >= SPEED_WINDOW:
			break
	var dt := last.z - first.z
	if dt <= 0.0:
		return 0.0
	return maxf(first.y - last.y, 0.0) / dt


func _draw() -> void:
	if phase == Phase.IDLE:
		return
	var u := unit_px()
	var half := 60.0 * u
	# The snap line across the start, and the stroke so far.
	draw_line(_start - Vector2(half, 0), _start + Vector2(half, 0), Color(1, 1, 1, 0.85), 3.0, true)
	draw_line(_start, _start + Vector2(0, 220.0 * u), Color(1, 1, 1, 0.25), 2.0, true)
	if _trail.size() >= 2:
		draw_polyline(_trail, Color(1.0, 0.85, 0.3, 0.8), 3.0, true)
	draw_circle(_now, 6.0 * u, Color(1, 1, 1, 0.9))
	if not _result.is_empty():
		var font := ThemeDB.fallback_font
		var at := _start + Vector2(half + 10.0, 6.0)
		draw_string_outline(font, at, _result, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.8))
		draw_string(font, at, _result, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
