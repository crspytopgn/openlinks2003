class_name RoundSetupPanel
extends PanelContainer
## The "Play a round" page: course, tees, holes, game mode and players.
## Emits start_pressed with the chosen RoundSetup and the index of the chosen
## course in the list it was opened with (its course_path is left for the
## caller to fill in).

signal start_pressed(setup: RoundSetup, course_index: int)
signal back_pressed

var _course: OptionButton
var _tees: OptionButton
var _holes: OptionButton
var _mode: OptionButton
var _mode_help: Label
var _count: OptionButton
var _names: Array[LineEdit] = []
var _teams: Array[OptionButton] = []
var _rows: Array[HBoxContainer] = []
var _problem: Label
var _start: Button


func _ready() -> void:
	MenuStyle.panel(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(640, 0)
	add_child(box)
	box.add_child(MenuStyle.heading("Play a round", 30))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	_course = _row(grid, "Course", [])
	_course.custom_minimum_size = Vector2(380, 36)
	_tees = _row(grid, "Tees", RoundSetup.TEES_NAMES)
	_holes = _row(grid, "Holes", RoundSetup.HOLES_NAMES)
	_mode = _row(grid, "Game", GameModes.MODE_NAMES)
	_mode.item_selected.connect(_on_mode_selected.unbind(1))
	_mode_help = Label.new()
	_mode_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_help.custom_minimum_size = Vector2(600, 0)
	_mode_help.add_theme_font_size_override("font_size", 15)
	_mode_help.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_mode_help)

	var players := GridContainer.new()
	players.columns = 2
	players.add_theme_constant_override("h_separation", 24)
	box.add_child(players)
	var counts: Array = []
	for n in RoundSetup.MAX_PLAYERS:
		counts.append("1 player" if n == 0 else "%d players" % (n + 1))
	_count = _row(players, "Players", counts)
	_count.item_selected.connect(_on_count_selected.unbind(1))
	for i in RoundSetup.MAX_PLAYERS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var edit := LineEdit.new()
		edit.max_length = 16
		edit.custom_minimum_size = Vector2(260, 34)
		edit.placeholder_text = RoundSetup.DEFAULT_NAMES[i]
		row.add_child(edit)
		var team := OptionButton.new()
		team.add_item("Team A")
		team.add_item("Team B")
		team.item_selected.connect(_refresh.unbind(1))
		row.add_child(team)
		box.add_child(row)
		_names.append(edit)
		_teams.append(team)
		_rows.append(row)

	_problem = Label.new()
	_problem.add_theme_color_override("font_color", MenuStyle.WARNING)
	box.add_child(_problem)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_start = MenuStyle.button("Start round")
	_start.pressed.connect(_on_start)
	buttons.add_child(_start)
	var back := MenuStyle.button("Back")
	back.pressed.connect(back_pressed.emit)
	buttons.add_child(back)
	visible = false


## Shows the page with `courses` to choose from and `saved` filled in.
func open(courses: PackedStringArray, selected: int, saved: RoundSetup) -> void:
	_course.clear()
	for c in courses:
		_course.add_item(c)
	_course.select(clampi(selected, 0, courses.size() - 1))
	_tees.select(saved.tees)
	_holes.select(saved.holes)
	_mode.select(saved.mode)
	_count.select(saved.player_count() - 1)
	for i in RoundSetup.MAX_PLAYERS:
		var named := i < saved.names.size() and saved.names[i] != RoundSetup.DEFAULT_NAMES[i]
		_names[i].text = saved.names[i] if named else ""
		_teams[i].select(saved.teams[i] if i < saved.teams.size() else i % 2)
	_refresh()
	visible = true
	_start.grab_focus.call_deferred()


## The setup as chosen so far (course_path not set).
func current_setup() -> RoundSetup:
	var s := RoundSetup.new()
	s.tees = _tees.selected as RoundSetup.Tees
	s.holes = _holes.selected as RoundSetup.Holes
	s.mode = _mode.selected as GameModes.Mode
	s.names.clear()
	s.teams.clear()
	for i in _count.selected + 1:
		var n := _names[i].text.strip_edges()
		s.names.append(n if not n.is_empty() else RoundSetup.DEFAULT_NAMES[i])
		s.teams.append(_teams[i].selected)
	return s


## Moves the player count into what the mode allows.
func _on_mode_selected() -> void:
	var r := GameModes.player_range(_mode.selected as GameModes.Mode)
	_count.select(clampi(_count.selected + 1, r.x, r.y) - 1)
	_refresh()


func _on_count_selected() -> void:
	_refresh()


func _refresh() -> void:
	var best_ball := _mode.selected == GameModes.Mode.BEST_BALL
	_mode_help.text = GameModes.MODE_HELP[_mode.selected]
	for i in RoundSetup.MAX_PLAYERS:
		_rows[i].visible = i <= _count.selected
		_teams[i].visible = best_ball
	var problem := current_setup().problem()
	_problem.text = problem
	_problem.visible = not problem.is_empty()
	_start.disabled = not problem.is_empty()


func _on_start() -> void:
	var s := current_setup()
	if s.problem().is_empty():
		start_pressed.emit(s, _course.selected)


func _row(grid: GridContainer, label: String, items: Array) -> OptionButton:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 18)
	grid.add_child(l)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(240, 36)
	for item in items:
		opt.add_item(str(item))
	grid.add_child(opt)
	return opt
