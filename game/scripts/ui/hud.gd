class_name Hud
extends Control
## On-screen text: hole and shot info, messages, controls, and the meter.

var info: Label
var message: Label
var hint: Label
var meter: SwingMeter
var wind: WindIndicator
var scorecard: ScorecardPanel

var _message_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	info = _label(20)
	info.position = Vector2(16, 12)
	add_child(info)

	message = _label(28)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(message, Control.PRESET_CENTER_TOP, Rect2(-400, 70, 800, 90))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)

	hint = _label(16)
	_place(hint, Control.PRESET_BOTTOM_LEFT, Rect2(16, -34, 900, 26))
	add_child(hint)

	wind = WindIndicator.new()
	_place(wind, Control.PRESET_TOP_RIGHT, Rect2(-106, 12, 90, 112))
	add_child(wind)

	meter = SwingMeter.new()
	_place(meter, Control.PRESET_BOTTOM_RIGHT, Rect2(-240, -240, 220, 220))
	add_child(meter)

	scorecard = ScorecardPanel.new()
	scorecard.visible = false
	add_child(scorecard)


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message.text = ""
	# Keep the card centred as its contents change size.
	if scorecard.visible:
		scorecard.position = (size - scorecard.size) * 0.5


## Shows a message; seconds <= 0 keeps it until the next one.
func show_message(text: String, seconds := 0.0) -> void:
	message.text = text
	_message_time = seconds


## Anchors `c` to a corner or edge, then offsets it by `r` from that anchor.
func _place(c: Control, preset: Control.LayoutPreset, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
