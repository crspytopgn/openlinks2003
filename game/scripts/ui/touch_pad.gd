class_name TouchPad
extends Control
## On-screen buttons for phones and tablets, which have no keys: aim left and
## right (held), the next and previous club, and the menu. The swing itself is
## a swipe anywhere else on the screen (see AnalogSwing). Shown only on a
## touch screen.

signal club_pressed(step: int)
signal menu_pressed

const SIZE := 64.0
const GAP := 10.0

var _buttons: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(GAP))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var menu := _button(Vector2.ZERO, column)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	var clubs := _row(column)
	_button(Vector2.UP, clubs).pressed.connect(func() -> void: club_pressed.emit(-1))
	_button(Vector2.DOWN, clubs).pressed.connect(func() -> void: club_pressed.emit(1))
	var aim := _row(column)
	_hold(_button(Vector2.LEFT, aim), &"ui_left")
	_hold(_button(Vector2.RIGHT, aim), &"ui_right")
	custom_minimum_size = Vector2(SIZE * 2 + GAP, SIZE * 3 + GAP * 2)


## Whether a touch at `at` (viewport pixels) lands on one of the buttons, so
## it isn't also taken as a swing.
func covers(at: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	for b in _buttons:
		if b.get_global_rect().grow(GAP * 0.5).has_point(at):
			return true
	return false


## Lets go of the aim buttons (when the pad hides mid press).
func release_all() -> void:
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row


func _button(arrow: Vector2, parent: Control) -> Button:
	var b := PadButton.new()
	b.arrow = arrow
	b.custom_minimum_size = Vector2(SIZE, SIZE)
	b.focus_mode = Control.FOCUS_NONE
	b.modulate = Color(1, 1, 1, 0.75)
	parent.add_child(b)
	_buttons.append(b)
	return b


func _hold(b: Button, action: StringName) -> void:
	b.button_down.connect(func() -> void: Input.action_press(action))
	b.button_up.connect(func() -> void: Input.action_release(action))


## A button showing an arrow (or, with no direction, the menu's three bars),
## drawn so it needs no symbol font.
class PadButton extends Button:
	var arrow := Vector2.ZERO

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.24
		if arrow == Vector2.ZERO:
			for i in 3:
				var y := c.y + (i - 1) * r * 0.75
				draw_line(Vector2(c.x - r, y), Vector2(c.x + r, y), Color.WHITE, 4.0)
			return
		var side := Vector2(-arrow.y, arrow.x)
		var tip := c + arrow * r
		var back := c - arrow * r * 0.8
		draw_colored_polygon(PackedVector2Array([tip, back + side * r, back - side * r]), Color.WHITE)
