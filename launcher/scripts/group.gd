extends VBoxContainer
## A rounded group of rows, like an inset grouped list in Apple's Settings.

const UI := preload("res://scripts/ui.gd")

var _rows: VBoxContainer


func _init(title := "") -> void:
	add_theme_constant_override("separation", 6)
	if not title.is_empty():
		var h := UI.label(title.to_upper(), 11, "SemiBold", UI.TEXT_3)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 14)
		m.add_child(h)
		add_child(m)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(Color(1, 1, 1, 0.055), 14, 0, 2))
	add_child(panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	panel.add_child(_rows)


## A row with a title (and a grey hint under it) and `control` at the right.
func row(title: String, control: Control, hint := "") -> Control:
	if _rows.get_child_count() > 0:
		var line := ColorRect.new()
		line.color = UI.HAIRLINE
		line.custom_minimum_size = Vector2(0, 1)
		var lm := MarginContainer.new()
		lm.add_theme_constant_override("margin_left", 16)
		lm.add_child(line)
		_rows.add_child(lm)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	margin.add_child(h)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 1)
	text.add_child(UI.label(title, 14))
	if not hint.is_empty():
		text.add_child(UI.wrap(UI.label(hint, 12, "Regular", UI.TEXT_2)))
	h.add_child(text)
	if control != null:
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(control)
	_rows.add_child(margin)
	return margin


## A row that is only `control`, full width (a button list, a note).
func wide(control: Control) -> void:
	if _rows.get_child_count() > 0:
		var line := ColorRect.new()
		line.color = UI.HAIRLINE
		line.custom_minimum_size = Vector2(0, 1)
		_rows.add_child(line)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14 if side in ["left", "right"] else 10)
	margin.add_child(control)
	_rows.add_child(margin)
