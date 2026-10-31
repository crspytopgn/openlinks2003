class_name CaddieNote
extends PanelContainer
## What the caddie says about the shot, in a small card above the controls
## line. Hidden while there is nothing to say.

const WIDTH := 640.0

var _body: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.09, 0.06, 0.78)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var who := Label.new()
	who.text = "CADDIE"
	who.add_theme_font_size_override("font_size", 13)
	who.add_theme_color_override("font_color", Color(0.98, 0.84, 0.35))
	who.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(who)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 17)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = WIDTH - 90.0
	_body.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	row.add_child(_body)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE)
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_bottom = -44.0
	offset_top = -44.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN


func say(words: String) -> void:
	_body.text = words
	visible = not words.is_empty()


func clear() -> void:
	say("")


func text_empty() -> bool:
	return _body.text.is_empty()
