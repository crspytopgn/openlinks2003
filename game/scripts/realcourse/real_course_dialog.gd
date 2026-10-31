class_name RealCourseDialog
extends ConfirmationDialog
## The course designer's "Real course" window: type a club's name, pick the
## right place from the matches, and RealCourseFetcher builds it from
## OpenStreetMap and open elevation data. While it builds, a progress window
## shows each step, the time taken and a Cancel button; a failure stays on
## screen until it is read.

signal status(text: String)
signal built(course: DesignedCourse, summary: Dictionary)

const SPINNER := ["|", "/", "-", "\\"]

var fetcher: RealCourseFetcher
var query: LineEdit
var results: ItemList
var note: Label
## The window shown while a course builds, and after a failure.
var progress: AcceptDialog
var progress_text: Label
var progress_time: Label
var _places: Array = []
var _started := 0
var _spin := 0
var _step := ""
var _building := false


func _ready() -> void:
	title = "Build a real course"
	ok_button_text = "Build course"
	get_ok_button().disabled = true
	fetcher = RealCourseFetcher.new()
	add_child(fetcher)
	fetcher.found.connect(_on_found)
	fetcher.progress.connect(_on_progress)
	fetcher.failed.connect(_on_failed)
	fetcher.built.connect(_on_built)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 0)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var intro := Label.new()
	intro.text = "Type a golf club or course anywhere in the world. Its holes, greens, bunkers and water come from OpenStreetMap; its ground from national lidar where it is open (England, the Netherlands, Flanders, North Rhine-Westphalia, France, Norway, Japan, the US), else open elevation data; and its trees from the lidar or the country's aerial photos."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label needs a width, or the window sizes itself for one
	# word a line and runs off the bottom of the screen.
	intro.custom_minimum_size = Vector2(480, 0)
	intro.add_theme_font_size_override("font_size", 13)
	box.add_child(intro)
	var row := HBoxContainer.new()
	box.add_child(row)
	query = LineEdit.new()
	query.placeholder_text = "e.g. St Andrews Old Course, Pebble Beach Golf Links"
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query.text_submitted.connect(func(_t: String) -> void: _search())
	row.add_child(query)
	var find := Button.new()
	find.text = "Search"
	find.pressed.connect(_search)
	row.add_child(find)
	results = ItemList.new()
	results.custom_minimum_size = Vector2(0, 150)
	results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results.item_selected.connect(func(_i: int) -> void: get_ok_button().disabled = fetcher.busy)
	results.item_activated.connect(func(_i: int) -> void:
		hide()
		_on_build())
	box.add_child(results)
	note = Label.new()
	note.text = "Map data (c) OpenStreetMap contributors (ODbL). Courses are only as complete as their map: check the holes in the designer after building."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(480, 0)
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(note)
	confirmed.connect(_on_build)

	progress = AcceptDialog.new()
	progress.title = "Building a real course"
	progress.exclusive = true
	progress.dialog_close_on_escape = false
	var pbox := VBoxContainer.new()
	pbox.custom_minimum_size = Vector2(420, 0)
	pbox.add_theme_constant_override("separation", 8)
	progress.add_child(pbox)
	progress_text = Label.new()
	progress_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_text.custom_minimum_size = Vector2(420, 0)
	pbox.add_child(progress_text)
	progress_time = Label.new()
	progress_time.add_theme_font_size_override("font_size", 12)
	progress_time.modulate = Color(1, 1, 1, 0.7)
	pbox.add_child(progress_time)
	progress.confirmed.connect(_on_progress_button)
	progress.canceled.connect(_on_progress_button)
	# A sibling, not a child: a child window hides with this one.
	get_parent().add_child.call_deferred(progress)
	set_process(false)


func open() -> void:
	if fetcher.busy and _building:
		_show_progress()
		return
	popup_centered_clamped(Vector2i(560, 460), 0.9)
	query.grab_focus()


func _search() -> void:
	var q := query.text.strip_edges()
	if q.length() < 3 or fetcher.busy:
		return
	results.clear()
	_places.clear()
	get_ok_button().disabled = true
	results.add_item("Searching...")
	results.set_item_disabled(0, true)
	fetcher.search(q)


func _on_found(found: Array) -> void:
	results.clear()
	_places = found
	for p: Dictionary in found:
		results.add_item(("[golf course]  " if p["golf"] else "") + str(p["label"]))
	if found.is_empty():
		results.add_item("Nothing found. Check the connection, or try the club's full name and its town.")
		results.set_item_disabled(0, true)
	elif found[0]["golf"]:
		results.select(0)
		get_ok_button().disabled = false


func _on_build() -> void:
	var picked := results.get_selected_items()
	if picked.is_empty() or picked[0] >= _places.size() or fetcher.busy:
		return
	_building = true
	_started = Time.get_ticks_msec()
	_step = "Starting..."
	progress.title = "Building %s" % str(_places[picked[0]].get("name", "a real course"))
	progress.ok_button_text = "Cancel"
	_show_progress()
	set_process(true)
	fetcher.build(_places[picked[0]])


func _show_progress() -> void:
	_refresh()
	progress.popup_centered_clamped(Vector2i(460, 160), 0.9)


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if not _building:
		return
	_spin = (_spin + 1) % (SPINNER.size() * 8)
	progress_text.text = _step
	var secs := floori((Time.get_ticks_msec() - _started) / 1000.0)
	progress_time.text = "%s  %d:%02d. Big courses take a few minutes; keep this tab open." % [
		SPINNER[floori(_spin / 8.0)], floori(secs / 60.0), secs % 60]


func _on_progress(text: String) -> void:
	_step = text
	status.emit(text)


func _on_built(c: DesignedCourse, s: Dictionary) -> void:
	_finish()
	progress.hide()
	built.emit(c, s)


func _on_failed(text: String) -> void:
	status.emit(text)
	if not _building:
		return
	_finish()
	if text == "Cancelled.":
		progress.hide()
		return
	# Left on screen until read: a status line is easy to miss.
	progress.title = "Couldn't build the course"
	progress.ok_button_text = "OK"
	progress_text.text = text
	progress_time.text = ""
	if not progress.visible:
		progress.popup_centered_clamped(Vector2i(460, 160), 0.9)


func _finish() -> void:
	_building = false
	set_process(false)


func _on_progress_button() -> void:
	if _building:
		_step = "Cancelling..."
		fetcher.cancel()
		# Keep the window up until the fetcher has stopped.
		_show_progress.call_deferred()
