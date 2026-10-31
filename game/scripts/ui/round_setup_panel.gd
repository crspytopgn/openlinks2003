class_name RoundSetupPanel
extends PanelContainer
## The "Play a round" page: course, tees, holes, game mode, handicaps and
## players, each played by a person or by a computer golfer of a chosen level. Each player's handicap index comes from their profile
## (PlayerProfiles); a player with fewer than three rounds can type one in.
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
var _who: Array[OptionButton] = []
var _handicaps: OptionButton
var _indexes: Array[LineEdit] = []
var _records: Array[Label] = []
var _profiles := PlayerProfiles.new()
var _rows: Array[HBoxContainer] = []
var _problem: Label
var _start: Button
## The course files behind the course list after its first entry (the
## placeholder), so a friend's result code can find its course.
var course_paths: PackedStringArray = []
var _code: LineEdit
var _challenge_info: Label
## The friend's round being played against, or null.
var _challenge: RoundRecord = null


func _ready() -> void:
	MenuStyle.panel(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	# No fixed width: the panel fits what is showing (handicap and team
	# columns appear only when needed), so it stays centred on screen.
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
	_handicaps = _row(grid, "Handicaps", ["Off: gross scores", "On: net scores"])
	_handicaps.item_selected.connect(_refresh.unbind(1))
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
		edit.text_changed.connect(func(_text: String) -> void: _on_name_changed(i))
		row.add_child(edit)
		var who := OptionButton.new()
		who.add_item("Human")
		for level_name: String in OpponentSkill.LEVEL_NAMES:
			who.add_item("Computer: " + level_name)
		who.custom_minimum_size = Vector2(230, 34)
		who.item_selected.connect(func(_item: int) -> void: _on_name_changed(i))
		row.add_child(who)
		_who.append(who)
		var index := LineEdit.new()
		index.max_length = 5
		index.custom_minimum_size = Vector2(80, 34)
		index.placeholder_text = "Index"
		index.tooltip_text = "Handicap index, such as 12.3, or +1.4 for a plus handicap. Set by the player's rounds once they have three."
		index.text_changed.connect(_refresh.unbind(1))
		row.add_child(index)
		var record := Label.new()
		record.add_theme_font_size_override("font_size", 15)
		record.modulate = Color(1, 1, 1, 0.75)
		row.add_child(record)
		_indexes.append(index)
		_records.append(record)
		var team := OptionButton.new()
		team.add_item("Team A")
		team.add_item("Team B")
		team.item_selected.connect(_refresh.unbind(1))
		row.add_child(team)
		box.add_child(row)
		_names.append(edit)
		_teams.append(team)
		_rows.append(row)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	box.add_child(code_row)
	_code = LineEdit.new()
	_code.placeholder_text = "A friend's result code (optional): play their course and wind"
	_code.custom_minimum_size = Vector2(560, 36)
	_code.text_submitted.connect(_open_code.unbind(1))
	code_row.add_child(_code)
	var open_code := MenuStyle.button("Open")
	open_code.pressed.connect(_open_code)
	code_row.add_child(open_code)
	var clear_code := MenuStyle.button("Clear")
	clear_code.pressed.connect(_clear_code)
	code_row.add_child(clear_code)
	_challenge_info = Label.new()
	_challenge_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_challenge_info.custom_minimum_size = Vector2(600, 0)
	_challenge_info.add_theme_font_size_override("font_size", 15)
	_challenge_info.visible = false
	box.add_child(_challenge_info)

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
	_handicaps.select(1 if saved.handicaps else 0)
	_profiles = PlayerProfiles.load_saved()
	_count.select(saved.player_count() - 1)
	for i in RoundSetup.MAX_PLAYERS:
		var named: bool = i < saved.names.size() and saved.names[i] != RoundSetup.DEFAULT_NAMES[i] \
				and not (saved.is_computer(i) and saved.names[i].begins_with(OpponentSkill.LEVEL_NAMES[saved.computer_level(i)]))
		_names[i].text = saved.names[i] if named else ""
		_teams[i].select(saved.teams[i] if i < saved.teams.size() else i % 2)
		_who[i].select(saved.computer_level(i) + 1)
		_fill_index(i)
	_clear_code()
	visible = true
	_start.grab_focus.call_deferred()


## The setup as chosen so far (course_path not set).
func current_setup() -> RoundSetup:
	var s := RoundSetup.new()
	s.tees = _tees.selected as RoundSetup.Tees
	s.holes = _holes.selected as RoundSetup.Holes
	s.mode = _mode.selected as GameModes.Mode
	s.handicaps = _handicaps.selected == 1
	s.names.clear()
	s.teams.clear()
	s.computer.clear()
	for i in _count.selected + 1:
		s.names.append(_player_name(i))
		s.teams.append(_teams[i].selected)
		s.computer.append(_who[i].selected - 1)
		s.indexes.append(_index_of(i))
	s.challenge = _challenge
	return s


## A computer golfer left unnamed goes by its level ("Tour pro", or
## "Tour pro 3" when two share it).
func _player_name(i: int) -> String:
	var n := _names[i].text.strip_edges()
	if not n.is_empty():
		return n
	var level := _who[i].selected - 1
	if level == RoundSetup.HUMAN:
		return RoundSetup.DEFAULT_NAMES[i]
	n = OpponentSkill.LEVEL_NAMES[level]
	for j in i:
		if _names[j].text.strip_edges().is_empty() and _who[j].selected == _who[i].selected:
			return "%s %d" % [n, i + 1]
	return n


## A computer golfer's level index, the profile's index once it has a
## record, otherwise what was typed.
func _index_of(i: int) -> int:
	var level := _who[i].selected - 1
	if level != RoundSetup.HUMAN:
		return RoundSetup.computer_index(level)
	var player := _player_name(i)
	if _profiles.has_record(player):
		return _profiles.index_of(player)
	return Handicap.parse(_indexes[i].text)


## Shows player `i`'s index and how many rounds it comes from.
func _fill_index(i: int) -> void:
	var level := _who[i].selected - 1
	if level != RoundSetup.HUMAN:
		_indexes[i].text = Handicap.format(RoundSetup.computer_index(level))
		_indexes[i].editable = false
		_records[i].text = "computer"
		return
	var player := _player_name(i)
	var index := _profiles.index_of(player)
	var played := _profiles.rounds(player).size()
	_indexes[i].text = Handicap.format(index) if index != Handicap.NONE else ""
	_indexes[i].editable = not _profiles.has_record(player)
	if played == 0:
		_records[i].text = "new player" if not _profiles.has_player(player) else "no rounds yet"
	else:
		_records[i].text = "%d round%s" % [played, "" if played == 1 else "s"]


func _on_name_changed(i: int) -> void:
	_fill_index(i)
	_refresh()


## Moves the player count into what the mode allows.
func _on_mode_selected() -> void:
	var r := GameModes.player_range(_mode.selected as GameModes.Mode)
	_count.select(clampi(_count.selected + 1, r.x, r.y) - 1)
	_refresh()


func _on_count_selected() -> void:
	_refresh()


func _refresh() -> void:
	var best_ball := GameModes.is_team(_mode.selected as GameModes.Mode)
	_mode_help.text = GameModes.MODE_HELP[_mode.selected]
	for i in RoundSetup.MAX_PLAYERS:
		_rows[i].visible = i <= _count.selected
		var level := _who[i].selected - 1
		_names[i].placeholder_text = RoundSetup.DEFAULT_NAMES[i] if level == RoundSetup.HUMAN else OpponentSkill.LEVEL_NAMES[level]
		_teams[i].visible = best_ball
		_indexes[i].visible = _handicaps.selected == 1
		_records[i].visible = _handicaps.selected == 1
	var problem := current_setup().problem()
	if problem.is_empty() and _handicaps.selected == 1:
		for i in _count.selected + 1:
			var t := _indexes[i].text.strip_edges()
			if not t.is_empty() and Handicap.parse(t) == Handicap.NONE:
				problem = "%s's handicap index should be a number such as 12.3." % _player_name(i)
				break
	if problem.is_empty() and _challenge != null and _course.selected != _challenge_slot(_challenge):
		problem = "Their round was on %s: pick that course, or clear the code." % _challenge.course_name
	_problem.text = problem
	_problem.visible = not problem.is_empty()
	_start.disabled = not problem.is_empty()


func _on_start() -> void:
	var s := current_setup()
	if _start.disabled or not s.problem().is_empty():
		return
	# A typed index becomes the starting index of a player without a record.
	if s.handicaps:
		for i in s.player_count():
			if not s.is_computer(i) and not _profiles.has_record(s.names[i]):
				_profiles.set_start_index(s.names[i], s.indexes[i])
		_profiles.save()
	start_pressed.emit(s, _course.selected)


## Reads the pasted result code: picks its course, tees and holes, checks the
## round on this machine where it can, and says what was found.
func _open_code() -> void:
	var rec := RoundRecord.from_code(_code.text)
	if rec == null:
		_challenge = null
		_show_info("That isn't a result code. It starts with %s." % RoundRecord.CODE_PREFIX, true)
		return
	var slot := _challenge_slot(rec)
	if slot < 0:
		_challenge = null
		_show_info("%s played %s, which isn't among your courses." % [rec.summary(), rec.course_name], true)
		return
	_challenge = rec
	_course.select(slot)
	_tees.select(rec.tees)
	_holes.select(rec.holes)
	var where := rec.course_name
	var wind: String = Wind.LEVEL_NAMES[clampi(rec.wind_level, 0, Wind.LEVEL_NAMES.size() - 1)]
	var path := "" if slot == 0 else course_paths[slot - 1]
	var checked := ""
	if not rec.finished:
		checked = "The round wasn't finished."
	elif slot > 0 and not FileAccess.file_exists(path):
		checked = "It can't be checked in the browser yet."
	else:
		var answer := RoundReplay.check(rec, path)
		if answer.ok:
			checked = "Checked: every shot plays the same here."
		else:
			var errors: Array = answer.errors
			checked = "Doesn't check out: %s%s" % [errors[0], "" if errors.size() == 1 else " (and %d more)" % (errors.size() - 1)]
	_show_info("%s on %s, %s wind. %s Start to play the same course and wind." % [rec.summary(), where, wind.to_lower(), checked], false)


func _clear_code() -> void:
	_challenge = null
	_code.text = ""
	_challenge_info.visible = false
	_refresh()


func _show_info(text: String, warning: bool) -> void:
	_challenge_info.text = text
	_challenge_info.visible = true
	if warning:
		_challenge_info.add_theme_color_override("font_color", MenuStyle.WARNING)
	else:
		_challenge_info.add_theme_color_override("font_color", MenuStyle.ACCENT)
	_refresh()


## Where a friend's course sits in the course list (0: the placeholder), or
## -1 if this player doesn't have it.
func _challenge_slot(rec: RoundRecord) -> int:
	if rec.course_file.is_empty():
		return 0
	for i in course_paths.size():
		if course_paths[i].get_file() == rec.course_file:
			return i + 1
	return -1


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
