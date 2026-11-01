class_name TournamentPanel
extends PanelContainer
## The "Tournament" page (Tournament). With no tournament it is the
## tournament creator: the name, the player, the format, each round's course,
## rounds and holes, the field (men, women or mixed, its size and strength),
## the cut, the purse, the weather, tee times and who the person plays with.
## With one it shows the leaderboard (or the draw, or the skins money), the
## players to watch with their strengths and styles, and plays the person's
## next round. Emits play_pressed with that round's setup.

signal play_pressed(setup: RoundSetup)
signal back_pressed

const SIZE_LABEL := "%d players"
const MAX_COURSE_ROWS := 4

var _t: Tournament = null
var _course_keys: Array[String] = []
var _course_names: Array[String] = []
var _new_box: VBoxContainer
var _title: LineEdit
var _player: LineEdit
var _format: OptionButton
var _format_help: Label
var _courses: Array[OptionButton] = []
var _course_labels: Array[Label] = []
var _rounds: OptionButton
var _rounds_label: Label
var _holes: OptionButton
var _field_kind: OptionButton
var _size: OptionButton
var _strength: OptionButton
var _cut: OptionButton
var _cut_label: Label
var _purse: OptionButton
var _weather: OptionButton
var _tee: OptionButton
var _tee_label: Label
var _partners: OptionButton
var _partners_label: Label
var _view_box: VBoxContainer
var _heading: Label
var _next: Label
var _board_title: Label
var _board: Label
var _watch: Label
var _problem: Label
var _play: Button
var _withdraw: Button
var _end: Button
var _back: Button
var _confirm := ""


func _ready() -> void:
	MenuStyle.panel(self)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	outer.add_child(MenuStyle.heading("Tournament", 30))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_build_new(box)
	_build_view(box)
	_problem = _small("", 15)
	_problem.add_theme_color_override("font_color", MenuStyle.WARNING)
	outer.add_child(_problem)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	outer.add_child(buttons)
	_play = MenuStyle.button("Play")
	_play.pressed.connect(_on_play)
	buttons.add_child(_play)
	_withdraw = MenuStyle.button("Withdraw")
	_withdraw.pressed.connect(_on_withdraw)
	buttons.add_child(_withdraw)
	_end = MenuStyle.button("New tournament")
	_end.pressed.connect(_on_end)
	buttons.add_child(_end)
	_back = MenuStyle.button("Back")
	_back.pressed.connect(back_pressed.emit)
	buttons.add_child(_back)
	visible = false


func _build_new(box: VBoxContainer) -> void:
	_new_box = VBoxContainer.new()
	_new_box.add_theme_constant_override("separation", 10)
	box.add_child(_new_box)
	_new_box.add_child(_small("Host your own event. Pick the courses, the format and the field; you play every round "
		+ "with computer golfers from the field, and the rest of the field plays around you, live on the leaderboard.", 15))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	_new_box.add_child(grid)
	_title = _edit(grid, "Name")
	_title.placeholder_text = "(named after the course)"
	_player = _edit(grid, "Player")
	_format = _row(grid, "Format", Tournament.FORMAT_NAMES)
	_format.item_selected.connect(_refresh_form.unbind(1))
	_rounds_label = _label(grid, "Rounds")
	_rounds = _option(grid, ["1 round", "2 rounds", "3 rounds", "4 rounds"])
	_rounds.select(3)
	_rounds.item_selected.connect(_refresh_form.unbind(1))
	for k in MAX_COURSE_ROWS:
		_course_labels.append(_label(grid, "Round %d course" % (k + 1)))
		_courses.append(_option(grid, []))
	_holes = _row(grid, "Holes", ["18 holes", "Front nine (quicker)"])
	_field_kind = _row(grid, "Field", Tournament.FIELD_NAMES)
	_size = _row(grid, "Field size", [])
	_strength = _row(grid, "Field strength", Tournament.STRENGTHS.map(func(s: Dictionary) -> String: return str(s.name)))
	_strength.select(3)
	_cut_label = _label(grid, "Cut")
	_cut = _option(grid, Tournament.CUT_NAMES)
	_cut.select(1)
	_purse = _row(grid, "Purse", Tournament.PURSES.map(func(p: int) -> String: return Career.format_money(p)))
	_purse.select(2)
	_weather = _row(grid, "Weather", Tournament.WEATHER_NAMES)
	_weather.select(1)
	_tee_label = _label(grid, "Tee times")
	_tee = _option(grid, Tournament.TEE_TIME_NAMES)
	_tee.select(2)
	_partners_label = _label(grid, "Playing with")
	_partners = _option(grid, ["Nobody (quickest)", "1 computer golfer", "2 computer golfers", "3 computer golfers"])
	_partners.select(2)
	_format_help = _small("", 15)
	_new_box.add_child(_format_help)


func _build_view(box: VBoxContainer) -> void:
	_view_box = VBoxContainer.new()
	_view_box.add_theme_constant_override("separation", 8)
	box.add_child(_view_box)
	_heading = _small("", 20)
	_heading.modulate = Color.WHITE
	_view_box.add_child(_heading)
	_next = _small("", 17)
	_next.modulate = Color.WHITE
	_next.add_theme_color_override("font_color", MenuStyle.ACCENT)
	_view_box.add_child(_next)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	_view_box.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	_board_title = _small("Leaderboard", 16, false)
	_board_title.add_theme_color_override("font_color", MenuStyle.ACCENT)
	left.add_child(_board_title)
	_board = _small("", 15, false)
	left.add_child(_board)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var watch_title := _small("Players to watch", 16, false)
	watch_title.add_theme_color_override("font_color", MenuStyle.ACCENT)
	right.add_child(watch_title)
	_watch = _small("", 14, false)
	_watch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_watch.custom_minimum_size = Vector2(380, 0)
	right.add_child(_watch)


## Opens the page; `keys` and `titles` are the courses (the setup page's list
## without the placeholder).
func open(keys: PackedStringArray, titles: PackedStringArray) -> void:
	_course_keys.assign(Array(keys))
	_course_names.assign(Array(titles))
	for o in _courses:
		var was := o.selected
		o.clear()
		if _course_names.is_empty():
			o.add_item(PlaceholderCourseLoader.NAME)
		for n in _course_names:
			o.add_item(n)
		o.select(clampi(was, 0, o.item_count - 1))
	_t = Tournament.load_saved()
	_confirm = ""
	_problem.text = ""
	_fill()
	visible = true
	_play.grab_focus.call_deferred()


func close() -> void:
	visible = false


func set_problem(text: String) -> void:
	_problem.text = text


func _fill() -> void:
	var has := _t != null
	_new_box.visible = not has
	_view_box.visible = has
	_withdraw.visible = has and _t.playing() and _t.rounds_played() > 0
	_end.visible = has
	_withdraw.text = "Sure? Withdraw" if _confirm == "withdraw" else "Withdraw"
	_end.text = "Sure? End it" if _confirm == "end" else "New tournament"
	if not has:
		_play.text = "Start tournament"
		if _player.text.strip_edges().is_empty():
			var saved := RoundSetup.load_saved()
			_player.text = saved.names[0] if not saved.names.is_empty() else "Player 1"
		_refresh_form()
		return
	var t := _t
	_heading.text = "%s   ·   %s, %s field of %d" % [t.title, Tournament.FORMAT_NAMES[t.format],
		str(Tournament.STRENGTHS[t.strength].name).to_lower(), t.names.size()]
	_next.text = t.next_text()
	_play.text = "Done" if t.over() else ("Play the match" if t.format == Tournament.Format.MATCH else "Play round %d" % (t.rounds_played() + 1))
	if not t.playing() and not t.over():
		_play.text = "See it out"
	var board := t.leaderboard_lines(12)
	match t.format:
		Tournament.Format.MATCH:
			_board_title.text = "The draw"
		Tournament.Format.SKINS:
			_board_title.text = "Money won"
		_:
			_board_title.text = "Leaderboard after round %d" % t.rounds_played() if not board.is_empty() else "Leaderboard"
	_board.text = "\n".join(board) if not board.is_empty() else "The first round is still to play."
	_watch.text = "\n".join(_watch_lines(t, 6))


## The best few in the field, with how they play.
func _watch_lines(t: Tournament, n: int) -> Array[String]:
	var out: Array[String] = []
	for i in t.names.size():
		if out.size() >= n * 2:
			break
		var p := t.pro(i)
		if p == null:
			continue
		out.append("%s   %s" % [p.name, Scorecard.format_to_par(roundi(p.scoring_average())) + " avg"])
		out.append("    %s. %s" % [p.profile_text(), p.stats_text()])
	return out


## Shows the settings that make sense for the format.
func _refresh_form() -> void:
	var f := _format.selected
	_format_help.text = str(Tournament.FORMAT_HELP[f])
	var stroke := f == Tournament.Format.STROKE or f == Tournament.Format.STABLEFORD
	var sizes: Array = Tournament.FIELD_SIZES
	if f == Tournament.Format.MATCH:
		sizes = Tournament.MATCH_SIZES
	elif f == Tournament.Format.SKINS:
		sizes = [Tournament.SKINS_PLAYERS]
	var was := _size.get_item_text(_size.selected) if _size.selected >= 0 else ""
	_size.clear()
	for n: int in sizes:
		_size.add_item(SIZE_LABEL % n)
	var pick := sizes.find(72) if f != Tournament.Format.MATCH else sizes.find(16)
	for k in _size.item_count:
		if _size.get_item_text(k) == was:
			pick = k
	_size.select(maxi(0, pick))
	_rounds_label.visible = f != Tournament.Format.MATCH
	_rounds.visible = f != Tournament.Format.MATCH
	if f == Tournament.Format.SKINS and _rounds.selected > 1:
		_rounds.select(0)
	var shown := _rounds.selected + 1 if f != Tournament.Format.MATCH else MAX_COURSE_ROWS
	for k in MAX_COURSE_ROWS:
		_courses[k].visible = k < shown
		_course_labels[k].visible = k < shown
		if f == Tournament.Format.MATCH:
			_course_labels[k].text = ["First round course", "Second round course", "Third round course", "Later rounds course"][k]
		else:
			_course_labels[k].text = "Round %d course" % (k + 1)
	_cut.visible = stroke
	_cut_label.visible = stroke
	_tee.visible = stroke
	_tee_label.visible = stroke
	_partners.visible = stroke
	_partners_label.visible = stroke


func _on_play() -> void:
	_confirm = ""
	_problem.text = ""
	if _t == null:
		var player := _player.text.strip_edges()
		if player.is_empty():
			_problem.text = "Type the player's name."
			return
		var f := _format.selected
		var sizes: Array = Tournament.FIELD_SIZES
		if f == Tournament.Format.MATCH:
			sizes = Tournament.MATCH_SIZES
		elif f == Tournament.Format.SKINS:
			sizes = [Tournament.SKINS_PLAYERS]
		var keys: Array[String] = []
		var titles: Array[String] = []
		var count := _rounds.selected + 1 if f != Tournament.Format.MATCH else MAX_COURSE_ROWS
		for k in count:
			var c := _courses[k].selected
			if _course_keys.is_empty():
				keys.append("")
				titles.append(PlaceholderCourseLoader.NAME)
			else:
				keys.append(_course_keys[clampi(c, 0, _course_keys.size() - 1)])
				titles.append(_course_names[clampi(c, 0, _course_names.size() - 1)])
		_t = Tournament.create({
			"title": _title.text, "player": player, "format": f, "rounds": _rounds.selected + 1,
			"short": _holes.selected == 1, "strength": _strength.selected, "field_kind": _field_kind.selected,
			"field_size": sizes[clampi(_size.selected, 0, sizes.size() - 1)], "cut": _cut.selected,
			"purse": Tournament.PURSES[_purse.selected], "weather": _weather.selected, "tee_times": _tee.selected,
			"partners": _partners.selected, "seed": randi(),
		}, keys, titles)
		_t.save()
		_fill()
		return
	if _t.over():
		back_pressed.emit()
		return
	if not _t.playing():
		_t.withdraw()
		_t.save()
		_fill()
		return
	play_pressed.emit(_t.next_setup())


func _on_withdraw() -> void:
	if _t == null or not _t.playing():
		return
	if _confirm != "withdraw":
		_confirm = "withdraw"
		_fill()
		return
	_confirm = ""
	_t.withdraw()
	_t.save()
	_fill()


func _on_end() -> void:
	if _confirm != "end" and _t != null and not _t.over():
		_confirm = "end"
		_fill()
		return
	_confirm = ""
	Tournament.remove()
	_t = null
	_fill()


func _label(grid: GridContainer, text: String) -> Label:
	var l := _small(text, 17, false)
	grid.add_child(l)
	return l


func _option(grid: GridContainer, items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(360, 34)
	for item: String in items:
		o.add_item(item)
	grid.add_child(o)
	return o


func _row(grid: GridContainer, label: String, items: Array) -> OptionButton:
	_label(grid, label)
	return _option(grid, items)


func _edit(grid: GridContainer, label: String) -> LineEdit:
	_label(grid, label)
	var e := LineEdit.new()
	e.custom_minimum_size = Vector2(360, 34)
	e.max_length = 40
	grid.add_child(e)
	return e


func _small(text: String, font_size: int, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(780, 0)
		l.modulate = Color(1, 1, 1, 0.8)
	return l
