class_name PuttingPanel
extends PanelContainer
## The panel on the right while putting: what the green reads like (its
## speed, the slope under the ball, the read view) and, on the practice
## green, the drill and buttons for everything the keys do, so it works
## with a mouse or a finger too.

signal action(id: StringName)

## Button id, label, key shown in the tooltip.
const PRACTICE_BUTTONS := [
	[&"new_spot", "New spot", "N"], [&"closer", "- ft", "["], [&"further", "+ ft", "]"],
	[&"slope", "Slope", "L"], [&"drill", "Drill", "P"], [&"next_cup", "Next cup", "T"],
	[&"next_green", "Next green", "H"],
]
const WIDTH := 470.0
const READ_BUTTON := [&"read", "Read the green", "V"]

var label: Label
var _buttons: HFlowContainer
var _practice_buttons: Array[Button] = []
var _read: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.03, 0.62)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	label.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	_buttons = HFlowContainer.new()
	_buttons.add_theme_constant_override("h_separation", 6)
	_buttons.add_theme_constant_override("v_separation", 6)
	box.add_child(_buttons)
	for b: Array in PRACTICE_BUTTONS:
		_practice_buttons.append(_button(b))
	_read = _button(READ_BUTTON)
	visible = false


func _button(spec: Array) -> Button:
	var b := Button.new()
	b.text = spec[1]
	b.tooltip_text = "Key: %s" % spec[2]
	b.focus_mode = Control.FOCUS_NONE  # Space swings; it mustn't press these
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(0, 32)
	var id: StringName = spec[0]
	b.pressed.connect(func() -> void: action.emit(id))
	_buttons.add_child(b)
	return b


## Shows `text`, the practice buttons when `practice`, and the read button
## when `can_read`. Hidden when there's nothing to show.
func show_panel(text: String, practice: bool, can_read: bool) -> void:
	label.text = text
	for b in _practice_buttons:
		b.visible = practice
	_read.visible = can_read
	_buttons.visible = practice or can_read
	visible = not text.is_empty() or _buttons.visible
