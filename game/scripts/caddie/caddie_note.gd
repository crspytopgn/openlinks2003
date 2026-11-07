class_name CaddieNote
extends PanelContainer
## What the caddie says about the shot, in a small card above the controls
## line on the left, under Broadcast's lower third. Hidden while there is
## nothing to say. (Centred, it covered the ball at address in the tee view
## and ran under the swing meter on a 1280 px screen.)

const WIDTH := 440.0
const LEFT := 40.0  ## lined up with Broadcast's lower third
const BOTTOM := -44.0  ## its lowest bottom edge (Hud lifts it over wrapped hints)

var _body: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Glass.apply(self, 16, 12.0)
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
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	offset_left = LEFT
	offset_right = LEFT + WIDTH
	offset_bottom = BOTTOM
	offset_top = BOTTOM
	grow_vertical = Control.GROW_DIRECTION_BEGIN


func say(words: String) -> void:
	_body.text = words
	visible = not words.is_empty()


func clear() -> void:
	say("")


func text_empty() -> bool:
	return _body.text.is_empty()
