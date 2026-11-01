extends Control
## An iOS-style switch.

signal toggled(on: bool)

const UI := preload("res://scripts/ui.gd")

var on := false:
	set(v):
		on = v
		queue_redraw()
var _t := 0.0


func _init(value := false) -> void:
	on = value
	_t = 1.0 if value else 0.0
	custom_minimum_size = Vector2(46, 28)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		on = not on
		toggled.emit(on)
		accept_event()


func _process(delta: float) -> void:
	var target := 1.0 if on else 0.0
	if not is_equal_approx(_t, target):
		_t = move_toward(_t, target, delta * 7.0)
		queue_redraw()


func _draw() -> void:
	var h := 28.0
	var w := 46.0
	var y := (size.y - h) / 2.0
	var track := Color(1, 1, 1, 0.16).lerp(UI.GREEN, _t)
	draw_style_box(UI.box(track, 14), Rect2(0, y, w, h))
	var x := lerpf(h / 2.0, w - h / 2.0, _t)
	draw_circle(Vector2(x, y + h / 2.0 + 1.0), h / 2.0 - 1.5, Color(0, 0, 0, 0.25), true, -1.0, true)
	draw_circle(Vector2(x, y + h / 2.0), h / 2.0 - 2.0, Color.WHITE, true, -1.0, true)
