extends Control
## A segmented control: a capsule of choices with a sliding lit segment.

signal changed(index: int)

const UI := preload("res://scripts/ui.gd")

var items: PackedStringArray = []
var selected := 0:
	set(v):
		selected = v
		queue_redraw()
var font_size := 14
var _x := -1.0
var _hover := -1


func _init(choices: PackedStringArray, value := 0, height := 34.0) -> void:
	items = choices
	selected = value
	custom_minimum_size = Vector2(0, height)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func _seg_w() -> float:
	return (size.x - 6.0) / maxf(items.size(), 1)


func _index_at(x: float) -> int:
	return clampi(int((x - 3.0) / _seg_w()), 0, items.size() - 1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _index_at((event as InputEventMouseMotion).position.x)
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var i := _index_at(mb.position.x)
		if i != selected:
			selected = i
			changed.emit(i)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		_x = -1.0
		queue_redraw()


func _process(delta: float) -> void:
	var target := 3.0 + selected * _seg_w()
	if _x < 0.0:
		_x = target
		queue_redraw()
	if not is_equal_approx(_x, target):
		_x = move_toward(_x, target, maxf(absf(target - _x) * delta * 14.0, delta * 60.0))
		queue_redraw()


func _draw() -> void:
	var r := int(size.y / 2.0)
	draw_style_box(UI.box(Color(1, 1, 1, 0.07), r), Rect2(Vector2.ZERO, size))
	var w := _seg_w()
	var lit := UI.box(Color(1, 1, 1, 0.17), r - 3)
	lit.shadow_color = Color(0, 0, 0, 0.25)
	lit.shadow_size = 4
	var x := _x if _x >= 0.0 else 3.0 + selected * w
	draw_style_box(lit, Rect2(Vector2(x, 3.0), Vector2(w, size.y - 6.0)))
	var f := UI.font("Medium")
	for i in items.size():
		var tw := f.get_string_size(items[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var col := UI.TEXT if i == selected or i == _hover else UI.TEXT_2
		var pos := Vector2(3.0 + i * w + (w - tw) / 2.0, size.y / 2.0 + font_size * 0.36)
		draw_string(f, pos, items[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
