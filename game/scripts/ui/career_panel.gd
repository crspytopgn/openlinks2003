class_name CareerPanel
extends PanelContainer
## The "Career" page (Career). With no career it offers a new one: the
## player, the tour to start on, events per season, rounds per event, full or
## nine-hole rounds and how many computer golfers play in the person's group.
## With a career it shows the season (money list, the event's leaderboard,
## the schedule and results), the person's career and personal records, and
## plays their next round. Emits play_pressed with that round's setup (the
## caller finds its course from course_key).

signal play_pressed(setup: RoundSetup)
signal back_pressed

var _career: Career = null
var _course_keys: Array[String] = []
var _course_names: Array[String] = []
var _new_box: VBoxContainer
var _player: LineEdit
var _tour: OptionButton
var _tour_help: Label
var _season: OptionButton
var _rounds: OptionButton
var _holes: OptionButton
var _partners: OptionButton
var _courses_help: Label
var _view_box: VBoxContainer
var _summary: Label
var _next: Label
var _board_title: Label
var _board: Label
var _money: Label
var _schedule: VBoxContainer
var _problem: Label
var _play: Button
var _withdraw: Button
var _end: Button
var _back: Button
var _confirm := ""  ## "withdraw" or "end" after one press


func _ready() -> void:
	MenuStyle.panel(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(780, 0)
	add_child(box)
	box.add_child(MenuStyle.heading("Career", 30))
	_build_new(box)
	_build_view(box)
	_problem = _small("", 15)
	_problem.add_theme_color_override("font_color", MenuStyle.WARNING)
	box.add_child(_problem)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_play = MenuStyle.button("Play")
	_play.pressed.connect(_on_play)
	buttons.add_child(_play)
	_withdraw = MenuStyle.button("Withdraw")
	_withdraw.pressed.connect(_on_withdraw)
	buttons.add_child(_withdraw)
	_end = MenuStyle.button("End career")
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
	_new_box.add_child(_small("Play a season of tour events against a field of computer golfers. You play every round; "
		+ "the rest of the field plays alongside. Four-round events have a cut after two rounds, and the money list "
		+ "decides who moves up a tour. Your rounds also count on your player profile.", 15))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	_new_box.add_child(grid)
	grid.add_child(_small("Player", 18, false))
	_player = LineEdit.new()
	_player.custom_minimum_size = Vector2(320, 36)
	_player.max_length = 24
	grid.add_child(_player)
	var tours: Array = []
	for t: Dictionary in Career.TOURS:
		tours.append(t.name)
	_tour = _row(grid, "Start on", tours)
	_tour.item_selected.connect(_on_tour_selected.unbind(1))
	_season = _row(grid, "Season", Career.SEASON_LENGTHS.map(func(n: int) -> String: return "%d events" % n))
	_season.select(1)
	_rounds = _row(grid, "Events", ["4 rounds, cut after 2", "2 rounds", "1 round"])
	_holes = _row(grid, "Rounds", ["18 holes", "Front nine (quicker)"])
	_partners = _row(grid, "Playing with", ["2 computer golfers", "1 computer golfer", "Nobody (quickest)"])
	_tour_help = _small("", 15)
	_new_box.add_child(_tour_help)
	_courses_help = _small("", 15)
	_new_box.add_child(_courses_help)


func _build_view(box: VBoxContainer) -> void:
	_view_box = VBoxContainer.new()
	_view_box.add_theme_constant_override("separation", 8)
	box.add_child(_view_box)
	_summary = _small("", 16)
	_summary.modulate = Color.WHITE
	_view_box.add_child(_summary)
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
	var money_title := _small("Money list", 16, false)
	money_title.add_theme_color_override("font_color", MenuStyle.ACCENT)
	right.add_child(money_title)
	_money = _small("", 15, false)
	right.add_child(_money)
	var schedule_title := _small("Schedule", 16, false)
	schedule_title.add_theme_color_override("font_color", MenuStyle.ACCENT)
	_view_box.add_child(schedule_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_view_box.add_child(scroll)
	_schedule = VBoxContainer.new()
	_schedule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_schedule)


## Opens the page; `keys` and `titles` are the courses a new career's events
## are spread over (the setup page's list without the placeholder).
func open(keys: PackedStringArray, titles: PackedStringArray) -> void:
	_course_keys.assign(Array(keys))
	_course_names.assign(Array(titles))
	_career = Career.load_saved()
	_confirm = ""
	_problem.text = ""
	_fill()
	visible = true
	_play.grab_focus.call_deferred()


func close() -> void:
	visible = false


## Shown under the page, e.g. when the next event's course can't be found.
func set_problem(text: String) -> void:
	_problem.text = text


func _fill() -> void:
	var has := _career != null
	_new_box.visible = not has
	_view_box.visible = has
	_withdraw.visible = has and _career.playing_event() and _career.rounds_played() > 0
	_end.visible = has
	_withdraw.text = "Sure? Withdraw" if _confirm == "withdraw" else "Withdraw"
	_end.text = "Sure? End career" if _confirm == "end" else "End career"
	if not has:
		_play.text = "Start career"
		if _player.text.strip_edges().is_empty():
			var saved := RoundSetup.load_saved()
			_player.text = saved.names[0] if not saved.names.is_empty() else "Player 1"
		_on_tour_selected()
		var n := _course_keys.size()
		_courses_help.text = ("Events are spread over your %d course%s." % [n, "" if n == 1 else "s"]) if n > 0 \
			else "With no course files loaded, every event is on the Placeholder Nine."
		return
	var c := _career
	if c.season_over():
		_play.text = "Start season %d" % (c.season + 1)
	elif c.playing_event():
		_play.text = "Play round %d" % (c.rounds_played() + 1)
	else:
		_play.text = "Next event"
	var profiles := PlayerProfiles.load_saved()
	var lines: Array[String] = [c.player + ": " + c.season_text(), "Career: " + c.career_text()]
	var index := profiles.index_of(c.player)
	if index != Handicap.NONE:
		lines.append("Handicap index %s." % Handicap.format(index))
	var rec := PlayerProfiles.records_text(profiles.records(c.player))
	if not rec.is_empty():
		lines.append(rec)
	_summary.text = "\n".join(lines)
	_next.text = c.next_text()
	var board := c.leaderboard_lines(8)
	if board.is_empty() and not c.results.is_empty():
		_board_title.text = "Last event: " + str(c.schedule[c.results.size() - 1].name)
		_board.text = c.result_text(c.results.size() - 1)
	else:
		_board_title.text = "Leaderboard after round %d" % c.rounds_played() if not board.is_empty() else "Leaderboard"
		_board.text = "\n".join(board) if not board.is_empty() else "The first round is still to play."
	_money.text = "\n".join(c.money_lines(8))
	for child in _schedule.get_children():
		child.queue_free()
	for e in c.schedule.size():
		var ev: Dictionary = c.schedule[e]
		var text := "%d.  %s   %s" % [e + 1, c.event_title(e), Career.format_money(int(ev.purse))]
		if e < c.results.size():
			var r: Dictionary = c.results[e]
			var res := str(r.status)
			if res.is_empty():
				res = "%s %s  %s" % [Career.place_text(int(r.pos), r.tied), Scorecard.format_to_par(int(r.to_par)), Career.format_money(int(r.money))]
			text += "    " + res
		elif e == c.event:
			text += "    now"
		var l := _small(text, 15, false)
		if e == c.event:
			l.add_theme_color_override("font_color", MenuStyle.ACCENT)
		elif e < c.results.size() and int(c.results[e].pos) == 1:
			l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		_schedule.add_child(l)


func _on_tour_selected() -> void:
	_tour_help.text = str(Career.TOURS[_tour.selected].about)


func _on_play() -> void:
	_confirm = ""
	_problem.text = ""
	if _career == null:
		var player := _player.text.strip_edges()
		if player.is_empty():
			_problem.text = "Type the player's name."
			return
		_career = Career.create(player, _tour.selected, Career.SEASON_LENGTHS[_season.selected],
			Career.EVENT_ROUNDS[_rounds.selected], _holes.selected == 1, Career.PARTNER_COUNTS[_partners.selected],
			_course_keys, _course_names, randi())
		_career.save()
		_fill()
		return
	if _career.season_over():
		_career.start_next_season()
		_career.save()
		_fill()
		return
	if not _career.playing_event():
		# Shouldn't stay here (a missed cut plays the event out), but move on.
		_career.withdraw()
		_career.save()
		_fill()
		return
	play_pressed.emit(_career.next_setup())


func _on_withdraw() -> void:
	if _career == null or not _career.playing_event():
		return
	if _confirm != "withdraw":
		_confirm = "withdraw"
		_fill()
		return
	_confirm = ""
	_career.withdraw()
	_career.save()
	_fill()


func _on_end() -> void:
	if _confirm != "end":
		_confirm = "end"
		_fill()
		return
	_confirm = ""
	Career.remove()
	_career = null
	_fill()


func _row(grid: GridContainer, label: String, items: Array) -> OptionButton:
	grid.add_child(_small(label, 18, false))
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(320, 36)
	for item: String in items:
		o.add_item(item)
	grid.add_child(o)
	return o


func _small(text: String, font_size: int, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(740, 0)
		l.modulate = Color(1, 1, 1, 0.8)
	return l
