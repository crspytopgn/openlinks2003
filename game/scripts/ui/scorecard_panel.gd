class_name ScorecardPanel
extends PanelContainer
## The scorecard: holes across, par and each player's score down, like the
## card in Links, plus the game mode's own rows (points, skins, match, teams).

const INK := Color(0.1, 0.1, 0.1)
const UNDER := Color(0.75, 0.1, 0.1)
const OVER := Color(0.1, 0.2, 0.7)

var _title: Label
var _grid: GridContainer
var _footer: Label


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
	_footer = Label.new()
	_footer.add_theme_color_override("font_color", Color(0.1, 0.25, 0.1))
	_footer.add_theme_font_size_override("font_size", 17)
	box.add_child(_footer)


func show_card(card: Scorecard, course_name: String, footer := "") -> void:
	_title.text = course_name + ("   " + footer if footer != "" else "")
	for child in _grid.get_children():
		child.queue_free()
	_footer.visible = false
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


## Every player's card for a round, with the rows the game mode adds.
func show_round(scoring: RoundScoring, course_name: String, footer := "") -> void:
	_title.text = course_name + ("   " + footer if footer != "" else "")
	for child in _grid.get_children():
		child.queue_free()
	var pars := scoring.cards[0].pars
	var holes := pars.size()
	var mode := scoring.mode
	_grid.columns = holes + 2
	_cell("Hole", true, INK, true)
	for i in holes:
		_cell(str(scoring.numbers[i]) if i < scoring.numbers.size() else str(i + 1), true)
	_cell("Tot", true)
	_cell("Par", true, INK, true)
	var total_par := 0
	for p in pars:
		_cell(str(p), false)
		total_par += p
	_cell(str(total_par), true)
	for n in scoring.player_count():
		var card := scoring.cards[n]
		_score_row(scoring.names[n], card)
		if mode == GameModes.Mode.STABLEFORD:
			_cell("  points", false, INK, true)
			for i in holes:
				var s := card.strokes[i]
				_cell(str(GameModes.stableford_points(s, pars[i])) if s > 0 else "", false)
			_cell(str(GameModes.stableford_total(card)), true)
	match mode:
		GameModes.Mode.BEST_BALL:
			for t in 2:
				_score_row("Team: " + scoring.team_name(t), scoring.team_card(t))
		GameModes.Mode.SKINS:
			var sk := GameModes.skins(scoring.strokes_table())
			_cell("Skin", true, INK, true)
			for i in holes:
				var w: int = sk.hole_winner[i]
				_cell(_initials(scoring.names[w]) if w >= 0 else ("=" if w == -1 else ""), false)
			_cell("", false)
		GameModes.Mode.MATCH:
			_cell("Hole won", true, INK, true)
			var a := scoring.cards[0].strokes
			var b := scoring.cards[1].strokes
			for i in holes:
				if a[i] <= 0 or b[i] <= 0:
					_cell("", false)
				elif a[i] == b[i]:
					_cell("=", false)
				else:
					_cell(_initials(scoring.names[0] if a[i] < b[i] else scoring.names[1]), false)
			_cell("", false)
	_footer.text = scoring.status_text()
	_footer.visible = not _footer.text.is_empty()
	visible = true


func _score_row(label: String, card: Scorecard) -> void:
	_cell(label, true, INK, true)
	for i in card.pars.size():
		var s := card.strokes[i]
		var color := INK
		if s > 0 and s < card.pars[i]:
			color = UNDER
		elif s > card.pars[i]:
			color = OVER
		_cell(str(s) if s > 0 else "-", false, color)
	_cell("%d (%s)" % [card.total_strokes(), Scorecard.format_to_par(card.to_par())] if card.holes_played() > 0 else "-", true)


## "Michael" -> "Mi", so a hole's winner fits in a column.
static func _initials(player_name: String) -> String:
	return player_name.strip_edges().left(2)


func _cell(text: String, bold: bool, color := INK, left := false) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 18 if bold else 17)
	_grid.add_child(l)
