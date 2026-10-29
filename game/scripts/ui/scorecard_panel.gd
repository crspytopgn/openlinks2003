class_name ScorecardPanel
extends PanelContainer
## The scorecard: holes across, par and score down, like the card in Links.

var _title: Label
var _grid: GridContainer


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.96, 0.9, 0.96)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Color(0.1, 0.25, 0.1))
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 14)
	box.add_child(_grid)


func show_card(card: Scorecard, course_name: String, footer := "") -> void:
	_title.text = course_name + ("   " + footer if footer != "" else "")
	for child in _grid.get_children():
		child.queue_free()
	var holes := card.pars.size()
	_grid.columns = holes + 2
	_cell("Hole", true)
	for i in holes:
		_cell(str(i + 1), true)
	_cell("Tot", true)
	_cell("Par", true)
	for p in card.pars:
		_cell(str(p), false)
	_cell(str(card.total_par()), true)
	_cell("Score", true)
	for i in holes:
		var s := card.strokes[i]
		var color := Color(0.1, 0.1, 0.1)
		if s > 0 and s < card.pars[i]:
			color = Color(0.75, 0.1, 0.1)
		elif s > card.pars[i]:
			color = Color(0.1, 0.2, 0.7)
		_cell(str(s) if s > 0 else "-", false, color)
	var played := card.holes_played()
	_cell("%d (%s)" % [card.total_strokes(), Scorecard.format_to_par(card.to_par())] if played > 0 else "-", true)
	visible = true


func _cell(text: String, bold: bool, color := Color(0.1, 0.1, 0.1)) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 18 if bold else 17)
	_grid.add_child(l)
