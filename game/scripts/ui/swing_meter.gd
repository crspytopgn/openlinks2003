class_name SwingMeter
extends Control
## The classic three-click power meter. In the Broadcast presentation it is
## a slim modern bar on a dark glass panel. In Classic it is drawn as an
## arc in the style of Links or, with the player's own interface art
## (HudArt), as the original's chrome bar. On the bars power runs right
## from the snap line and accuracy left of it.
##
## Click 1 starts the backswing: the marker climbs from the snap line at the
## bottom of the arc towards 100% at the top. Click 2 sets the power and
## starts the downswing: the marker runs back down past the snap line into
## the accuracy zone. Click 3 sets accuracy: on the snap line is straight,
## early (above it) pulls and hooks, late (past it) pushes and slices.

signal backswing_started
signal swing_finished(power: float, accuracy: float)

enum Phase { IDLE, BACKSWING, DOWNSWING, DONE }

const BACKSWING_SPEED := 0.85  ## meter units per second
const DOWNSWING_SPEED := 1.5
const ACCURACY_ZONE := 0.12  ## meter units past the snap line
const PERFECT_WINDOW := 0.012  ## counts as dead on
const RADIUS := 82.0
const WIDTH := 16.0

## Bar layout with the original art: the art is drawn at this scale.
const ART_SCALE := 1.2
const BAR_LENGTH := 330.0

## The modern bar: panel size, and the track's inset from the panel's sides.
const MODERN_SIZE := Vector2(480, 78)
const MODERN_INSET := 28.0
const GLASS := Color(0.03, 0.05, 0.07, 0.62)
const TRACK := Color(1, 1, 1, 0.16)
const SWING := Color(1, 1, 1, 0.92)
const GOLD := Color(0.98, 0.76, 0.28)
const GOOD := Color(0.45, 0.9, 0.55)

var phase: Phase = Phase.IDLE
var value := 0.0  ## marker position: 0 = snap line, 1 = full power
var power := 0.0
var accuracy := 0.0
## The player's interface art; null draws the plain arc.
var art: HudArt
## Draws the modern bar (Broadcast presentation) whatever the art.
var modern := false


func _ready() -> void:
	custom_minimum_size = Vector2(220, 220)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Size the meter needs: the arc, or the bar with the original art.
func wanted_size() -> Vector2:
	if modern:
		return MODERN_SIZE
	if art == null:
		return Vector2(220, 220)
	return Vector2(HudArt.METER_CAP.size.x * ART_SCALE + BAR_LENGTH + 8.0, HudArt.METER_CAP.size.y * ART_SCALE)


func reset() -> void:
	phase = Phase.IDLE
	value = 0.0
	power = 0.0
	accuracy = 0.0
	queue_redraw()


func is_swinging() -> bool:
	return phase == Phase.BACKSWING or phase == Phase.DOWNSWING


## Advances the meter by one click.
func click() -> void:
	match phase:
		Phase.IDLE, Phase.DONE:
			phase = Phase.BACKSWING
			value = 0.0
			power = 0.0
			accuracy = 0.0
			backswing_started.emit()
		Phase.BACKSWING:
			_set_power(value)
		Phase.DOWNSWING:
			_set_accuracy(value)
	queue_redraw()


func _process(delta: float) -> void:
	match phase:
		Phase.BACKSWING:
			value += BACKSWING_SPEED * delta
			if value >= 1.0:
				value = 1.0
				_set_power(1.0)
			queue_redraw()
		Phase.DOWNSWING:
			value -= DOWNSWING_SPEED * delta
			if value <= -ACCURACY_ZONE:
				_set_accuracy(-ACCURACY_ZONE)
			queue_redraw()


func _set_power(p: float) -> void:
	power = clampf(p, 0.02, 1.0)
	phase = Phase.DOWNSWING


func _set_accuracy(v: float) -> void:
	value = v
	if absf(v) <= PERFECT_WINDOW:
		accuracy = 0.0
	else:
		accuracy = clampf(-v / ACCURACY_ZONE, -1.0, 1.0)
	phase = Phase.DONE
	swing_finished.emit(power, accuracy)


## Screen angle of a meter value: 0 at the bottom, 1 at the top, running up
## the left side.
static func _angle(v: float) -> float:
	return PI * 0.5 + v * PI


func _arc(from: float, to: float, color: Color, width: float) -> void:
	var a := _angle(minf(from, to))
	var b := _angle(maxf(from, to))
	var points := maxi(4, int((b - a) * 24.0))
	draw_arc(size * 0.5, RADIUS, a, b, points, color, width, true)


func _tick(v: float, color: Color, inner: float, outer: float, width: float) -> void:
	var dir := Vector2.from_angle(_angle(v))
	var c := size * 0.5
	draw_line(c + dir * (RADIUS - inner), c + dir * (RADIUS + outer), color, width, true)


func _draw() -> void:
	if modern:
		_draw_modern()
		return
	if art != null:
		_draw_bar()
		return
	_arc(-ACCURACY_ZONE, 1.0, Color(0, 0, 0, 0.55), WIDTH + 6.0)
	_arc(-ACCURACY_ZONE, ACCURACY_ZONE, Color(0.95, 0.85, 0.3, 0.9), WIDTH)
	_arc(ACCURACY_ZONE, 1.0, Color(0.85, 0.85, 0.85, 0.35), WIDTH)
	match phase:
		Phase.BACKSWING:
			_arc(0.0, value, Color(0.3, 0.8, 0.35), WIDTH)
		Phase.DOWNSWING, Phase.DONE:
			_arc(0.0, power, Color(0.95, 0.55, 0.2), WIDTH)
	for quarter in [0.25, 0.5, 0.75, 1.0]:
		_tick(quarter, Color(1, 1, 1, 0.7), WIDTH * 0.5, 4.0, 1.5)
	_tick(0.0, Color.WHITE, WIDTH * 0.5 + 4.0, 8.0, 3.0)
	if phase != Phase.IDLE:
		_tick(value, Color(0.9, 0.1, 0.1), WIDTH * 0.5 + 2.0, 10.0, 4.0)

	var font := ThemeDB.fallback_font
	var c := size * 0.5
	var text := "POWER"
	if phase == Phase.DOWNSWING or phase == Phase.DONE:
		text = "%d%%" % roundi(power * 100.0)
	draw_string(font, c + Vector2(-40, 6), text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 18)
	if phase == Phase.DONE:
		var label := "Perfect"
		if accuracy < 0.0:
			label = "Hook %d%%" % roundi(-accuracy * 100.0)
		elif accuracy > 0.0:
			label = "Slice %d%%" % roundi(accuracy * 100.0)
		draw_string(font, c + Vector2(-50, 28), label, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 14)


# --- The original's bar ----------------------------------------------------------

## Screen x of a meter value along the bar.
func _bar_x(v: float) -> float:
	var left := HudArt.METER_CAP.size.x * ART_SCALE - 4.0
	return left + (v + ACCURACY_ZONE) / (1.0 + ACCURACY_ZONE) * BAR_LENGTH


func _draw_bar() -> void:
	var s := ART_SCALE
	var cap := HudArt.METER_CAP
	var bar := HudArt.METER_BAR
	var bar_top := (bar.position.y - cap.position.y) * s
	var bar_h := bar.size.y * s
	var left := cap.size.x * s - 2.0
	var right := _bar_x(1.0) + 4.0
	draw_texture_rect_region(art.meter, Rect2(left, bar_top, right - left, bar_h), bar)
	draw_texture_rect_region(art.meter, Rect2(Vector2.ZERO, cap.size * s), cap)
	var mid := bar_top + bar_h * 0.5
	var band := bar_h * 0.55
	# Accuracy zone, then how far the swing has gone.
	draw_rect(Rect2(_bar_x(-ACCURACY_ZONE), mid - band * 0.5, _bar_x(ACCURACY_ZONE) - _bar_x(-ACCURACY_ZONE), band), Color(1.0, 0.95, 0.5, 0.35))
	match phase:
		Phase.BACKSWING:
			_bar_fill(0.0, value, Color(0.35, 1.0, 0.4, 0.75), mid, band)
		Phase.DOWNSWING, Phase.DONE:
			_bar_fill(0.0, power, Color(1.0, 0.6, 0.15, 0.75), mid, band)
	for quarter in [0.25, 0.5, 0.75, 1.0]:
		var x := _bar_x(quarter)
		draw_line(Vector2(x, mid - bar_h * 0.6), Vector2(x, mid + bar_h * 0.6), Color(1, 1, 1, 0.8), 1.5)
	var snap := _bar_x(0.0)
	draw_line(Vector2(snap, mid - bar_h * 1.4), Vector2(snap, mid + bar_h * 1.4), Color.WHITE, 2.5)
	if phase != Phase.IDLE:
		var x := _bar_x(value)
		draw_line(Vector2(x, mid - bar_h * 1.1), Vector2(x, mid + bar_h * 1.1), Color(0.95, 0.1, 0.1), 4.0)

	var font := ThemeDB.fallback_font
	var text := ""
	if phase == Phase.DOWNSWING or phase == Phase.DONE:
		text = "%d%%" % roundi(power * 100.0)
	if phase == Phase.DONE:
		if accuracy < 0.0:
			text += "   Hook %d%%" % roundi(-accuracy * 100.0)
		elif accuracy > 0.0:
			text += "   Slice %d%%" % roundi(accuracy * 100.0)
		else:
			text += "   Perfect"
	if not text.is_empty():
		draw_string_outline(font, Vector2(snap + 10.0, bar_top - 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(snap + 10.0, bar_top - 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


func _bar_fill(from: float, to: float, color: Color, mid: float, band: float) -> void:
	var a := _bar_x(minf(from, to))
	var b := _bar_x(maxf(from, to))
	draw_rect(Rect2(a, mid - band * 0.5, b - a, band), color)


# --- The modern bar ---------------------------------------------------------------

func _modern_x(v: float) -> float:
	var w := size.x - MODERN_INSET * 2.0
	return MODERN_INSET + (v + ACCURACY_ZONE) / (1.0 + ACCURACY_ZONE) * w


func _capsule(r: Rect2, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.5))
	box.anti_aliasing = true
	draw_style_box(box, r)


func _draw_modern() -> void:
	var glass := StyleBoxFlat.new()
	glass.bg_color = GLASS
	glass.set_corner_radius_all(16)
	glass.border_color = Color(1, 1, 1, 0.1)
	glass.set_border_width_all(1)
	glass.anti_aliasing = true
	draw_style_box(glass, Rect2(Vector2.ZERO, size))
	var mid := size.y * 0.62
	var h := 8.0
	var x0 := _modern_x(-ACCURACY_ZONE)
	var x1 := _modern_x(1.0)
	var snap := _modern_x(0.0)
	_capsule(Rect2(x0, mid - h * 0.5, x1 - x0, h), TRACK)
	# The accuracy zone: brighter, a hair taller, with a gold centre.
	var zone := Rect2(x0, mid - h * 0.75, _modern_x(ACCURACY_ZONE) - x0, h * 1.5)
	_capsule(zone, Color(1, 1, 1, 0.12))
	match phase:
		Phase.BACKSWING:
			_capsule(Rect2(snap, mid - h * 0.5, maxf(_modern_x(value) - snap, h), h), SWING)
		Phase.DOWNSWING, Phase.DONE:
			_capsule(Rect2(snap, mid - h * 0.5, maxf(_modern_x(power) - snap, h), h), GOLD)
	for quarter in [0.25, 0.5, 0.75, 1.0]:
		draw_circle(Vector2(_modern_x(quarter), mid + h + 5.0), 1.6, Color(1, 1, 1, 0.45))
	draw_line(Vector2(snap, mid - h * 1.6), Vector2(snap, mid + h * 1.6), Color(1, 1, 1, 0.85), 2.0, true)
	if phase != Phase.IDLE:
		var x := _modern_x(value)
		_capsule(Rect2(x - 4.0, mid - 13.0, 8.0, 26.0), Color(1, 1, 1, 0.25))
		_capsule(Rect2(x - 2.0, mid - 11.0, 4.0, 22.0), Color.WHITE)

	var font := ThemeDB.fallback_font
	var top := 24.0
	draw_string(font, Vector2(MODERN_INSET, top), "POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
	if phase == Phase.BACKSWING:
		draw_string(font, Vector2(MODERN_INSET + 52.0, top), "%d%%" % roundi(value * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))
	elif phase == Phase.DOWNSWING or phase == Phase.DONE:
		draw_string(font, Vector2(MODERN_INSET + 52.0, top), "%d%%" % roundi(power * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)
	if phase == Phase.DONE:
		var label := "PERFECT"
		var colour := GOOD
		if accuracy < 0.0:
			label = "HOOK %d%%" % roundi(-accuracy * 100.0)
			colour = GOLD
		elif accuracy > 0.0:
			label = "SLICE %d%%" % roundi(accuracy * 100.0)
			colour = GOLD
		draw_string(font, Vector2(0, top), label, HORIZONTAL_ALIGNMENT_RIGHT, size.x - MODERN_INSET, 15, colour)
	elif phase == Phase.IDLE:
		draw_string(font, Vector2(0, top), "CLICK TO SWING", HORIZONTAL_ALIGNMENT_RIGHT, size.x - MODERN_INSET, 12, Color(1, 1, 1, 0.45))
