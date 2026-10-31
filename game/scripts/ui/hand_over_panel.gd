class_name HandOverPanel
extends Control
## Hot seat: between two people sharing the keyboard, the screen dims and
## names who plays next, so the last player can step away before the next one
## takes the mouse. Any swing press (Space, Enter, a click) dismisses it.

var _name: Label
var _detail: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Clicks go on to the round, which dismisses the panel.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(_centred("Pass the controls to", 22, Color(1, 1, 1, 0.85)))
	_name = _centred("", 54, MenuStyle.ACCENT)
	box.add_child(_name)
	_detail = _centred("", 20, Color.WHITE)
	box.add_child(_detail)
	box.add_child(_centred("Space or click when ready", 18, Color(1, 1, 1, 0.7)))
	visible = false


## Shows the panel for `player_name`, with a line about their shot.
func open(player_name: String, detail: String) -> void:
	_name.text = player_name
	_detail.text = detail
	visible = true
	SceneFade.pop_in(self)


func close() -> void:
	visible = false


func _centred(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
