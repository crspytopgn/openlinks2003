class_name MouseSwingControl
extends Control
## Links 2003's PowerStroke mouse swing. Hold the left button and pull the
## mouse back towards you for the backswing, then push it forward, briskly
## and straight: the club follows on the meter and strikes the ball when it
## comes back down to the ball line. LinksMouse runs the game's own frames
## (60 a second) on the mouse's movement in screen pixels, so the swing feels
## like the original: the club has momentum on full swings, the speed through
## the ball sets the power, how far back you went caps it, and moving the
## mouse sideways hooks, slices or misses. The meter is the game's size for
## this screen width, drawn the same share of the screen's height.

signal backswing_started
signal stroke_finished(stroke: LinksMouse.Stroke)
signal stroke_cancelled

const FRAME := 1.0 / 60.0
## The game's meter is about this share of the screen's height.
const METER_SHARE := 0.46
## Our multiplier on mouse movement (1 is the original's).
var sensitivity := 1.0
var club: LinksMouse.MouseClub = null
var _rng := LinksLaunch.Rand.new(randi())
var _pending := Vector2.ZERO  ## mouse movement not yet given to a frame
var _clock := 0.0
var _started := false
var _result := ""
var _last := LinksMouse.Phase.BACKSWING


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func is_swinging() -> bool:
	return club != null and not club.done()


func reset() -> void:
	club = null
	_result = ""
	_pending = Vector2.ZERO
	_release_mouse()
	queue_redraw()


## The button went down: a swing with `club_number` (LinksMouse.PUTTER for
## the putter) at `skill`.
func begin(club_number: int, skill: int) -> void:
	reset()
	var shot := LinksMouse.Shot.PUTT if club_number >= LinksMouse.PUTTER else LinksMouse.Shot.FULL
	var width := 1920
	if is_inside_tree() and DisplayServer.window_get_size().x > 0:
		width = DisplayServer.window_get_size().x
	club = LinksMouse.MouseClub.new(skill, shot, club_number, LinksMouse.meter_for(width))
	_started = false
	_clock = 0.0
	_last = LinksMouse.Phase.BACKSWING
	if is_inside_tree() and not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_redraw()


## The mouse moved this many screen pixels (right and down) with the button held.
func motion(screen_relative: Vector2) -> void:
	if is_swinging():
		_pending += screen_relative * sensitivity


## The button came up. Before the downswing that calls the swing off; after
## it the club carries on (the game's swing ignores the button).
func release() -> void:
	if is_swinging() and club.phase == LinksMouse.Phase.BACKSWING:
		reset()
		stroke_cancelled.emit()


## Runs the game's frames for `delta` seconds of movement.
func advance(delta: float) -> void:
	if not is_swinging():
		return
	_clock += delta
	var frames := int(_clock / FRAME)
	if frames <= 0:
		return
	_clock -= frames * FRAME
	for i in frames:
		# The mouse's movement shared out over the frames, in whole pixels.
		var share := _pending / float(frames - i)
		var dx := int(share.x)
		var dy := int(share.y)
		_pending -= Vector2(dx, dy)
		club.step(dx, dy, _rng)
		if not _started and club.club_height() > club.meter.ball_line + 0.5:
			_started = true
			backswing_started.emit()
		if club.done():
			break
	queue_redraw()
	if club.phase == LinksMouse.Phase.IMPACT:
		_release_mouse()
		var m := club.stroke
		_result = _describe(m)
		stroke_finished.emit(m)
	elif club.phase == LinksMouse.Phase.FAILED:
		reset()
		stroke_cancelled.emit()


func _process(delta: float) -> void:
	advance(delta)


func _release_mouse() -> void:
	if is_inside_tree() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _describe(m: LinksMouse.Stroke) -> String:
	var x := -m.drift
	if absf(x) > 18.0:
		return "Miss!"
	if absf(x) > 10.0:
		return "Hook" if x > 0.0 else "Slice"
	return "%d%%" % roundi(m.backswing * 100.0)


## The meter's rectangle on screen and its pixels per game meter pixel.
func meter_rect() -> Rect2:
	var vh := get_viewport_rect().size.y if is_inside_tree() else 600.0
	var vw := get_viewport_rect().size.x if is_inside_tree() else 800.0
	var h := vh * METER_SHARE
	var w := h * 0.12
	return Rect2(vw - w - vw * 0.06, (vh - h) * 0.5, w, h)


func _draw() -> void:
	if club == null:
		return
	var r := meter_rect()
	var px := r.size.y / club.meter.height
	var y_of := func(meter_px: float) -> float: return r.end.y - meter_px * px
	draw_rect(r.grow(3), Color(0, 0, 0, 0.45))
	draw_rect(r, Color(1, 1, 1, 0.12))
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	var ball_y: float = y_of.call(club.meter.ball_line)
	var top_y: float = y_of.call(club.meter.height - 10)
	var club_y: float = y_of.call(club.club_height())
	# The backswing so far, from the ball line up to the club.
	var fill_top := minf(club_y, ball_y)
	draw_rect(Rect2(r.position.x, fill_top, r.size.x, ball_y - fill_top), Color(1.0, 0.82, 0.25, 0.55))
	draw_line(Vector2(r.position.x - 6, top_y), Vector2(r.end.x + 6, top_y), Color(1, 1, 1, 0.5), 1.5)
	draw_line(Vector2(r.position.x - 10, ball_y), Vector2(r.end.x + 10, ball_y), Color.WHITE, 3.0)
	# The club, shifted by the sideways drift (red past the hook and slice line).
	var x := -club.drift()
	var off := clampf(x / 18.0, -1.0, 1.0) * r.size.x * 1.5
	var colour := Color(1, 0.3, 0.25) if absf(x) > 10.0 else Color.WHITE
	draw_rect(Rect2(r.position.x - 4 + off, club_y - 3, r.size.x + 8, 6), colour)
	var font := ThemeDB.fallback_font
	var text := _result if not _result.is_empty() else "%d%%" % roundi(club.backswing_percent())
	var at := Vector2(r.position.x - 4, r.position.y - 12)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
