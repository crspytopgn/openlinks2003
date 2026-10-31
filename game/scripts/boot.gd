extends Control
## First screen and main menu: makes sure the game can find the player's own
## Links 2003 files, then offers the main menu (play a round, resume a saved
## round, players, settings) and the round setup page (RoundSetupPanel), then
## starts the round. On desktop
## the files come from a folder (asked for once, then remembered). In the
## browser the player picks their disc images or a game folder once; the
## browser keeps them locally and nothing is uploaded. Either way the game can
## be played with placeholder content.

const MAIN_SCENE := "res://scenes/main.tscn"
const DESIGNER_SCENE := "res://scenes/course_designer.tscn"

var _web: WebGameFiles
var _title: Label
var _status: Label
var _bar: ProgressBar
var _buttons: HBoxContainer
var _play: Button
var _main_box: VBoxContainer
var _setup: RoundSetupPanel
var _settings: SettingsPanel
var _players: PlayersPanel
var _career: CareerPanel
var _graphics: GraphicsSettings
var _community: VBoxContainer
var _community_hint: Label
var _course_paths: PackedStringArray = []
## What the setup page offers after the placeholder: the game's courses, then
## the player's own designs.
var _setup_paths: PackedStringArray = []
var _stored := {}  ## browser build: picked relative path -> size
var _busy := false


func _ready() -> void:
	_graphics = GraphicsSettings.load_saved()
	get_window().content_scale_factor = GraphicsSettings.UI_SCALES[_graphics.ui_scale]
	_build_ui()
	var menu_sounds := MenuSounds.from_game_folder(true)
	if menu_sounds != null:
		add_child(menu_sounds)
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
	_main_box = box
	_setup = RoundSetupPanel.new()
	_setup.start_pressed.connect(_on_setup_start)
	_setup.back_pressed.connect(_close_setup)
	center.add_child(_setup)
	_settings = SettingsPanel.new()
	_settings.changed.connect(func() -> void: _graphics.apply_display(get_viewport()))
	_settings.back_pressed.connect(_close_settings)
	center.add_child(_settings)
	_players = PlayersPanel.new()
	_players.back_pressed.connect(_close_players)
	center.add_child(_players)
	_career = CareerPanel.new()
	_career.back_pressed.connect(_close_career)
	_career.play_pressed.connect(_on_career_play)
	center.add_child(_career)

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
				["Play with placeholders", _play_placeholders],
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
		["Play with placeholders", _play_placeholders],
		["Career", _open_career],
		["Course designer", _open_designer],
		["Players", _open_players],
		["Settings", _open_settings],
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
	_course_paths = PackedStringArray()
	_check_stored()


# --- Ready to play ------------------------------------------------------------

## Shows the main menu: Play a round (the setup page offers the placeholder
## course plus any found in the player's files), `extra` buttons for the game
## files, Settings and Quit.
func _show_ready(courses: PackedStringArray, extra: Array) -> void:
	_course_paths = courses
	if courses.is_empty():
		_status.text = "Your game files are ready. No course files were found among them."
	else:
		_status.text = "Your game files are ready: %d courses." % courses.size()
	if _can_resume():
		_status.text += "
Saved round: %s." % SavedRound.describe()
	var items: Array = [["Play a round", _open_setup]]
	if _can_resume():
		items.append(["Resume round", _resume_round])
	items.append(["Career", _open_career])
	items += extra + [["Players", _open_players], ["Course designer", _open_designer], ["Settings", _open_settings]]
	if not OS.has_feature("web"):
		items.append(["Quit", get_tree().quit])
	_set_buttons(items)
	if _web != null:
		_community_hint.text = "Download a course, then press Add a course and pick the .zip. It's played with your own copy of the game."
	else:
		_community_hint.text = "Download a course and put its .crz in your game folder's Courses folder."
	_community.visible = true
	# Back from a Career round: straight to the Career page.
	if Career.open_on_menu:
		Career.open_on_menu = false
		_open_career()


func _play_placeholders() -> void:
	_course_paths = PackedStringArray()
	_open_setup()


func _open_setup() -> void:
	if _busy:
		return
	var names := PackedStringArray(["Placeholder Nine (built in)"])
	_setup_paths = _all_courses()
	for path in _setup_paths:
		names.append(CourseFiles.display_name(path))
	var saved := RoundSetup.load_saved()
	# The last course played, or the first real one.
	var selected := 0 if _course_paths.is_empty() else 1
	var last := _last_course()
	if not last.is_empty() and _setup_paths.has(last):
		selected = _setup_paths.find(last) + 1
	_main_box.visible = false
	_settings.close()
	_players.close()
	_setup.course_paths = _setup_paths
	_setup.open(names, selected, saved)
	SceneFade.pop_in(_setup)


func _close_setup() -> void:
	_setup.visible = false
	_main_box.visible = true
	SceneFade.pop_in(_main_box)
	if _play:
		_play.grab_focus.call_deferred()


func _open_players() -> void:
	_main_box.visible = false
	_players.open()
	SceneFade.pop_in(_players)


func _close_players() -> void:
	_players.close()
	_main_box.visible = true
	SceneFade.pop_in(_main_box)
	if _play:
		_play.grab_focus.call_deferred()


func _open_career() -> void:
	if _busy:
		return
	_setup_paths = _all_courses()
	var titles := PackedStringArray()
	for path in _setup_paths:
		titles.append(CourseFiles.display_name(path))
	_main_box.visible = false
	_settings.close()
	_players.close()
	_career.open(_setup_paths, titles)
	SceneFade.pop_in(_career)


func _close_career() -> void:
	_career.close()
	_main_box.visible = true
	SceneFade.pop_in(_main_box)
	if _play:
		_play.grab_focus.call_deferred()


## Plays the next Career round on its event's course, carrying on with it if
## it was saved part way through.
func _on_career_play(chosen: RoundSetup) -> void:
	if _busy or chosen == null:
		return
	var slot := 0
	if not chosen.course_key.is_empty():
		_setup_paths = _all_courses()
		slot = _setup_paths.find(chosen.course_key) + 1
		if slot <= 0:
			_career.set_problem("%s isn't among your courses now. Load your game files again, or withdraw from this event." % chosen.course_name)
			return
	var saved := SavedRound.load_setup()
	GolfRound.resume = {}
	if saved != null and saved.career == chosen.career:
		chosen = saved
		GolfRound.resume = SavedRound.load_state()
	_career.close()
	_launch(chosen, slot)


## Every course the setup page offers after the placeholder: the game's
## courses, then the player's own designs.
func _all_courses() -> PackedStringArray:
	return _course_paths + DesignedCourse.saved_paths()


## True if there is a saved round and its course is among the player's files
## or designs (or it was on the placeholder course).
func _can_resume() -> bool:
	return _resume_slot() >= 0


## Where the saved round's course sits in the setup list (0: the
## placeholder), or -1 if there's no saved round or its course is gone.
## Fills the setup list, so the menu can resume before the setup page has
## been opened.
func _resume_slot() -> int:
	var s := SavedRound.load_setup()
	if s == null:
		return -1
	if s.course_key.is_empty():
		return 0
	_setup_paths = _all_courses()
	var i := _setup_paths.find(s.course_key)
	return -1 if i < 0 else i + 1


## Carries on with the saved round (SavedRound) from where it stopped.
func _resume_round() -> void:
	if _busy:
		return
	var slot := _resume_slot()
	if slot < 0:
		return
	GolfRound.resume = SavedRound.load_state()
	_launch(SavedRound.load_setup(), slot)


func _open_settings() -> void:
	_main_box.visible = false
	_settings.open(_graphics)
	SceneFade.pop_in(_settings)


func _close_settings() -> void:
	_settings.close()
	_main_box.visible = true
	SceneFade.pop_in(_main_box)
	if _play:
		_play.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if _settings.visible:
			_close_settings()
		elif _setup.visible:
			_close_setup()
		elif _players.visible:
			_close_players()
		elif _career.visible:
			_close_career()


static func _last_course() -> String:
	var cfg := ConfigFile.new()
	cfg.load(GameFolder.SETTINGS_PATH)
	return cfg.get_value("round", "course", "")


func _on_setup_start(chosen: RoundSetup, course_index: int) -> void:
	if _busy:
		return
	chosen.save()
	var cfg := ConfigFile.new()
	cfg.load(GameFolder.SETTINGS_PATH)
	cfg.set_value("round", "course", "" if course_index <= 0 else _setup_paths[course_index - 1])
	cfg.save(GameFolder.SETTINGS_PATH)
	GolfRound.resume = {}
	_launch(chosen, course_index)


## Starts the round in `chosen` on the course at `course_index` in the setup
## page's list (0 is the placeholder), copying the course into memory first in
## the browser.
func _launch(chosen: RoundSetup, course_index: int) -> void:
	chosen.course_key = "" if course_index <= 0 else _setup_paths[course_index - 1]
	GolfRound.setup = chosen
	if course_index <= 0:
		chosen.course_path = ""
		GolfRound.chosen_course = ""
		_start()
		return
	_close_setup()
	var path := _setup_paths[course_index - 1]
	if _web != null and not path.begins_with("user://"):
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
	chosen.course_path = path
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
		["Play with placeholders", _play_placeholders],
		["Career", _open_career],
		["Course designer", _open_designer],
		["Players", _open_players],
		["Settings", _open_settings],
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
	SceneFade.change_scene(get_tree(), MAIN_SCENE)


## Opens the course designer on the last course designed, if any.
func _open_designer() -> void:
	if _busy:
		return
	if CourseDesigner.last_path.is_empty():
		var saved := DesignedCourse.saved_paths()
		var last := _last_course()
		if saved.has(last):
			CourseDesigner.last_path = last
	SceneFade.change_scene(get_tree(), DESIGNER_SCENE)
