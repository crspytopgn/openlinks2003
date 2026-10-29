extends Control
## First screen: makes sure the game can find the player's own Links 2003
## files, lets the player choose a course, then starts the round. On desktop
## the files come from a folder (asked for once, then remembered). In the
## browser the player picks their disc images or a game folder once; the
## browser keeps them locally and nothing is uploaded. Either way the game can
## be played with placeholder content.

const MAIN_SCENE := "res://scenes/main.tscn"

var _web: WebGameFiles
var _title: Label
var _status: Label
var _bar: ProgressBar
var _buttons: HBoxContainer
var _play: Button
var _course: OptionButton
var _community: VBoxContainer
var _community_hint: Label
var _course_paths: PackedStringArray = []
var _stored := {}  ## browser build: picked relative path -> size
var _busy := false


func _ready() -> void:
	_build_ui()
	if WebGameFiles.is_supported():
		_web = WebGameFiles.new()
		_web.progress.connect(_on_progress)
		_check_stored()
	elif _folder_ok(GameFolder.configured_path()):
		_show_ready(CourseFiles.in_folder(GameFolder.configured_path()), [["Change game folder...", _choose_folder]])
	else:
		_show_desktop_choice()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.16, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(720, 0)
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	_title = Label.new()
	_title.text = "OpenLinks2003"
	_title.add_theme_font_size_override("font_size", 44)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 22)
	_bar.visible = false
	box.add_child(_bar)
	_course = OptionButton.new()
	_course.custom_minimum_size = Vector2(320, 36)
	_course.visible = false
	var course_row := CenterContainer.new()
	course_row.add_child(_course)
	box.add_child(course_row)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 12)
	box.add_child(_buttons)
	_build_community(box)
	var note := Label.new()
	note.text = "OpenLinks2003 contains nothing from the original game. Your files are read on your own computer."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.modulate = Color(1, 1, 1, 0.6)
	box.add_child(note)


## Links to free fan-made courses on Links Corner (CommunityCourses), shown
## with the course picker.
func _build_community(box: VBoxContainer) -> void:
	_community = VBoxContainer.new()
	_community.visible = false
	_community.add_theme_constant_override("separation", 2)
	box.add_child(_community)
	var heading := Label.new()
	heading.text = "Free community courses on Links Corner:"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 16)
	_community.add_child(heading)
	for course: Dictionary in CommunityCourses.COURSES:
		var link := LinkButton.new()
		link.text = CommunityCourses.label(course)
		link.uri = CommunityCourses.page_url(course)
		link.add_theme_font_size_override("font_size", 15)
		var row := CenterContainer.new()
		row.add_child(link)
		_community.add_child(row)
	_community_hint = Label.new()
	_community_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_community_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_community_hint.add_theme_font_size_override("font_size", 14)
	_community_hint.modulate = Color(1, 1, 1, 0.7)
	_community.add_child(_community_hint)


func _set_buttons(items: Array) -> void:
	for child in _buttons.get_children():
		child.queue_free()
	_play = null
	for item: Array in items:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(item[1])
		_buttons.add_child(b)
		if item[0].begins_with("Play"):
			_play = b
	if _play:
		_play.grab_focus.call_deferred()


# --- Browser ----------------------------------------------------------------

func _check_stored() -> void:
	_status.text = "Looking for your game files..."
	_community.visible = false
	_set_buttons([])
	var state: String = await _web.state()
	match state:
		"ready":
			_prepare()
		"reconnect":
			_status.text = "Your browser needs your OK to read your game files again."
			_set_buttons([
				["Use my game files", _reconnect],
				["Load different files...", _pick.bind(false)],
				["Play with placeholders", _start],
			])
		_:
			_ask_for_files()


func _ask_for_files(problem := "") -> void:
	var text := ("To play the real Links 2003 courses, load your own copy of the game from any drive, including "
		+ "an external one: pick your three disc images (BlindWrite .b6i, .iso, .bin, .nrg or .mdf), or the "
		+ "folder that holds them or an installed game. Nothing is copied or uploaded.")
	if not _web.remembers():
		text += " This browser can't remember them, so you'll pick them again next time (it only takes a moment)."
	_status.text = text if problem.is_empty() else problem + "\n\n" + text
	_set_buttons([
		["Load disc images...", _pick.bind(false)],
		["Load a game folder...", _pick.bind(true)],
		["Play with placeholders", _start],
	])


func _reconnect() -> void:
	if _busy:
		return
	_busy = true
	var result: String = await _web.reconnect()
	_busy = false
	if result == "ready":
		_prepare()
	else:
		_ask_for_files("Couldn't open your game files again%s." % (
			"" if result != "error" else " (%s)" % _web.last_error))


## Copies the few files the game reads before a round into memory, then shows
## the course picker.
func _prepare() -> void:
	var files: Dictionary = await _web.stored_files()
	_status.text = "Preparing your game files..."
	_bar.visible = true
	var ok: bool = await _web.copy_startup_files(files)
	_bar.visible = false
	if not ok:
		_ask_for_files("Couldn't read your game files (%s)." % _web.last_error)
		return
	GameFolder.override_path = WebGameFiles.ROOT
	_stored = files
	_show_ready(CourseFiles.in_list(files.keys()), [
		["Add a course...", _pick_courses],
		["Load different files...", _pick.bind(false)],
		["Forget my files", _forget],
	])


func _pick(folder: bool) -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Choose your files in the dialog."
	_bar.visible = true
	_bar.value = 0
	var n: int = await _web.pick_and_import(folder)
	_bar.visible = false
	_busy = false
	if n < 0:
		_status.text = "That didn't work: %s" % _web.last_error
		return
	if n == 0:
		_check_stored()
		return
	_prepare()


func _pick_courses() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Choose a course's .zip download or its .crz file."
	_bar.visible = true
	_bar.value = 0
	var n: int = await _web.pick_courses()
	_bar.visible = false
	_busy = false
	if n < 0:
		_status.text = "That didn't work: %s" % _web.last_error
		return
	_check_stored()


func _forget() -> void:
	await _web.forget()
	GameFolder.override_path = ""
	_stored = {}
	_course.visible = false
	_check_stored()


# --- Ready to play ------------------------------------------------------------

## Shows the course picker (the placeholder course plus any found in the
## player's files), a Play button and `extra` buttons.
func _show_ready(courses: PackedStringArray, extra: Array) -> void:
	_course_paths = courses
	_course.clear()
	_course.add_item("Placeholder Nine (built in)")
	for path in courses:
		_course.add_item(CourseFiles.display_name(path))
	_course.select(0 if courses.is_empty() else 1)
	_course.visible = true
	if courses.is_empty():
		_status.text = "Your game files are ready. No course files were found among them."
	else:
		_status.text = "Your game files are ready. Choose a course."
	_set_buttons([["Play", _play_chosen]] + extra)
	if _web != null:
		_community_hint.text = "Download a course, then press Add a course and pick the .zip. It's played with your own copy of the game."
	else:
		_community_hint.text = "Download a course and put its .crz in your game folder's Courses folder."
	_community.visible = true


func _play_chosen() -> void:
	if _busy:
		return
	var i := _course.selected
	if i <= 0:
		GolfRound.chosen_course = ""
		_start()
		return
	var path := _course_paths[i - 1]
	if _web != null:
		# In the browser the course is copied into memory only when chosen.
		_busy = true
		_bar.visible = true
		_status.text = "Loading %s..." % CourseFiles.display_name(path)
		for rel: String in _course_files(path):
			if not await _web.copy_file(rel, _stored[rel]):
				_status.text = "Couldn't load the course: %s" % _web.last_error
				_bar.visible = false
				_busy = false
				return
		path = WebGameFiles.ROOT.path_join(path)
	GolfRound.chosen_course = path
	_start()


## The picked files that belong to a course: the course itself and any
## companions with the same base name.
func _course_files(rel: String) -> Array[String]:
	var out: Array[String] = [rel]
	var stem := rel.get_basename().to_lower()
	for other: String in _stored:
		if other.get_basename().to_lower() == stem and other != rel and other.get_extension().to_lower() in CourseFiles.COMPANIONS:
			out.append(other)
	return out


func _on_progress(file_name: String, done: int, total: int) -> void:
	if total > 0:
		_bar.value = 100.0 * done / total
	if not file_name.is_empty():
		_status.text = "%s   (%d of %d MB)" % [file_name, done / 1048576, total / 1048576]


# --- Desktop ----------------------------------------------------------------

func _show_desktop_choice() -> void:
	_status.text = ("To play the real Links 2003 courses, choose the folder of your installed game "
		+ "(or a folder you extracted with tools/cdimage/cdimage.py install).")
	_set_buttons([
		["Choose game folder...", _choose_folder],
		["Play with placeholders", _start],
	])


func _choose_folder() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = "Choose your Links 2003 folder"
	dlg.dir_selected.connect(_on_folder_chosen)
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)


func _on_folder_chosen(path: String) -> void:
	if not _folder_ok(path):
		_status.text = "That folder doesn't look like Links 2003 (no OBJECT.LIB, Courses or GAME folder). Try another."
		return
	var cfg := ConfigFile.new()
	cfg.load(GameFolder.SETTINGS_PATH)
	cfg.set_value("game", "folder", path)
	cfg.save(GameFolder.SETTINGS_PATH)
	_show_ready(CourseFiles.in_folder(path), [["Change game folder...", _choose_folder]])


static func _folder_ok(path: String) -> bool:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return false
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	for entry in dir.get_directories() + dir.get_files():
		if entry.to_lower() in ["game", "courses", "object.lib", "object"]:
			return true
	return false


func _start() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)
