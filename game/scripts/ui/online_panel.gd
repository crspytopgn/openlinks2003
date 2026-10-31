class_name OnlinePanel
extends PanelContainer
## Play online (docs/online-play.md): make a room or join one by its code,
## see who's in, and (the host) pick the course and start. Everyone in the
## room then plays the round in step (OnlineRound). Emits start_pressed with
## the setup, the course's place in the setup page's list and this game's
## OnlineRound.

signal start_pressed(setup: RoundSetup, course_index: int, online_round: OnlineRound)
signal back_pressed

## The course files after the placeholder, as the setup page lists them.
var course_paths: PackedStringArray = []
var link: OnlineLink
var my_seat := -1
var host_id := -1
var my_id := -1
var members: Array = []  ## [{id, name, seat}]

var _name: LineEdit
var _code: LineEdit
var _status: Label
var _who: Label
var _course: OptionButton
var _holes: OptionButton
var _computers: OptionButton
var _host_box: VBoxContainer
var _start: Button
var _create: Button
var _join: Button
var _http: HTTPRequest


func _ready() -> void:
	MenuStyle.panel(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(640, 0)
	add_child(box)
	box.add_child(MenuStyle.heading("Play online", 30))
	_name = LineEdit.new()
	_name.placeholder_text = "Your name"
	_name.max_length = 20
	_name.custom_minimum_size = Vector2(300, 36)
	box.add_child(_name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_create = MenuStyle.button("Make a room")
	_create.pressed.connect(_on_create)
	row.add_child(_create)
	_code = LineEdit.new()
	_code.placeholder_text = "Room code"
	_code.max_length = 4
	_code.custom_minimum_size = Vector2(140, 36)
	_code.text_submitted.connect(_on_join.unbind(1))
	row.add_child(_code)
	_join = MenuStyle.button("Join")
	_join.pressed.connect(_on_join)
	row.add_child(_join)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(600, 0)
	box.add_child(_status)
	_who = Label.new()
	_who.add_theme_font_size_override("font_size", 18)
	box.add_child(_who)
	_host_box = VBoxContainer.new()
	_host_box.visible = false
	box.add_child(_host_box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	_host_box.add_child(grid)
	_course = _row(grid, "Course", [])
	_holes = _row(grid, "Holes", RoundSetup.HOLES_NAMES)
	_computers = _row(grid, "Computer golfers", ["None", "One", "Two"])
	_start = MenuStyle.button("Start the round")
	_start.pressed.connect(_on_start)
	_host_box.add_child(_start)
	var back := MenuStyle.button("Back")
	back.pressed.connect(_on_back)
	box.add_child(back)
	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_created)
	add_child(_http)
	visible = false


## Shows the page with `courses` (the setup page's list) to pick from.
func open(courses: PackedStringArray, player_name: String) -> void:
	_course.clear()
	for c in courses:
		_course.add_item(c)
	_name.text = player_name
	_status.text = "Make a room and send its code to your friends, or type their code and join. Everyone needs the course the host picks."
	_who.text = ""
	_host_box.visible = false
	_set_busy(false)
	visible = true


func _on_create() -> void:
	if _check_name().is_empty():
		return
	_set_busy(true)
	_status.text = "Making a room..."
	if _http.request(OnlineSettings.server() + "/rooms", [], HTTPClient.METHOD_POST, "") != OK:
		_fail("Couldn't reach the server.")


func _on_created(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not d is Dictionary or not d.has("code"):
		_fail("Couldn't make a room (%d)." % code)
		return
	_code.text = str(d.code)
	_connect(str(d.code))


func _on_join() -> void:
	var code := _code.text.strip_edges().to_upper()
	if _check_name().is_empty():
		return
	if code.length() != 4:
		_status.text = "A room code has four letters."
		return
	_set_busy(true)
	_connect(code)


func _connect(code: String) -> void:
	_status.text = "Joining room %s..." % code
	use_link(WebSocketLink.new(OnlineSettings.room_url(OnlineSettings.server(), code), _hello()))


## Starts talking over `l` (the tests pass a LoopbackLink, after sending
## hello themselves).
func use_link(l: OnlineLink) -> void:
	link = l
	set_process(true)


func _hello() -> Dictionary:
	return {"type": "hello", "v": 1, "name": _check_name()}


func _check_name() -> String:
	var n := _name.text.strip_edges()
	if n.is_empty():
		_status.text = "Type your name first."
	return n


func _process(_delta: float) -> void:
	if link == null:
		return
	for msg in link.receive():
		handle(msg)
	if link != null and not link.is_open():
		_fail("Lost the connection to the room.")


## One message from the room.
func handle(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"welcome":
			my_id = int(msg.get("you", -1))
			my_seat = int(msg.get("seat", -1))
			host_id = int(msg.get("host", -1))
			_status.text = "In room %s. Send the code to your friends." % msg.get("code", "")
		"members":
			members = msg.get("members", [])
			host_id = int(msg.get("host", host_id))
			var names: Array[String] = []
			for m: Dictionary in members:
				names.append(str(m.name) + (" (host)" if int(m.id) == host_id else ""))
			_who.text = "Here: " + ", ".join(names)
			_host_box.visible = my_id == host_id
			if my_id != host_id:
				_status.text = "Waiting for the host to start the round."
		"setup":
			_on_setup(msg)
		"error":
			_fail(str(msg.get("reason", "The server said no.")))


## The host: everyone in the room plays, plus the computer golfers chosen.
func host_setup() -> RoundSetup:
	var s := RoundSetup.new()
	s.names.clear()
	s.computer.clear()
	s.teams.clear()
	for m: Dictionary in members:
		s.names.append(str(m.name))
		s.computer.append(RoundSetup.HUMAN)
		s.teams.append(s.teams.size() % 2)
	for i in _computers.selected:
		if s.names.size() >= RoundSetup.MAX_PLAYERS:
			break
		s.names.append(OpponentSkill.LEVEL_NAMES[1] + (" %d" % (i + 1) if _computers.selected > 1 else ""))
		s.computer.append(1)
		s.teams.append(s.teams.size() % 2)
	s.holes = _holes.selected as RoundSetup.Holes
	s.round_seed = (randi() & 0x7fffffff) | 1
	s.wind_level = GraphicsSettings.load_saved().wind
	return s


func _on_start() -> void:
	if my_id != host_id or link == null:
		return
	var s := host_setup()
	var index := _course.selected
	s.course_path = "" if index <= 0 else course_paths[index - 1]
	s.course_key = s.course_path
	s.course_name = _course.get_item_text(index)
	var owners: Array[int] = []
	for m: Dictionary in members:
		owners.append(int(m.seat))
	while owners.size() < s.names.size():
		owners.append(my_seat)
	link.send(OnlineRound.setup_message(s, s.round_seed, s.wind_level, owners, RoundRecord.file_hash(s.course_path)))
	_launch(s, index, owners)


## A guest: the host started. Finds the course here and checks it's the same.
func _on_setup(msg: Dictionary) -> void:
	var s := OnlineRound.setup_from(msg)
	if s == null:
		_fail("The host's round setup didn't make sense.")
		return
	var file := str(msg.get("course_file", ""))
	var index := 0
	if not file.is_empty():
		index = -1
		for i in course_paths.size():
			if course_paths[i].get_file() == file:
				index = i + 1
		if index < 0:
			_fail("The host picked %s, which isn't among your courses." % s.course_name)
			return
		var path := course_paths[index - 1]
		if FileAccess.file_exists(path) and RoundRecord.file_hash(path) != str(msg.get("course_hash", "")):
			_fail("Your copy of %s is different from the host's." % s.course_name)
			return
		s.course_path = path
		s.course_key = path
	_launch(s, index, OnlineRound.owners_from(msg))


func _launch(s: RoundSetup, index: int, owners: Array[int]) -> void:
	var r := OnlineRound.new(link, my_seat, owners)
	r.host_seat = my_seat if my_id == host_id else -1
	set_process(false)
	start_pressed.emit(s, index, r)


func _fail(text: String) -> void:
	_status.text = text
	if link != null:
		link.close()
	link = null
	_host_box.visible = false
	_who.text = ""
	_set_busy(false)


func _set_busy(busy: bool) -> void:
	_create.disabled = busy
	_join.disabled = busy


func _on_back() -> void:
	if link != null:
		link.close()
	link = null
	visible = false
	back_pressed.emit()


func _row(grid: GridContainer, label: String, items: Array) -> OptionButton:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 18)
	grid.add_child(l)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(300, 36)
	for item in items:
		opt.add_item(str(item))
	grid.add_child(opt)
	return opt
