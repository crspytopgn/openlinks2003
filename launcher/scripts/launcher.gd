extends Control
## The OpenLinks2003 launcher: keeps the game up to date from the "latest"
## GitHub release, shows what changed, sets the options worth choosing before
## the game starts, gets the player's own Links 2003 files ready, and starts
## the game or its course designer. See docs/launcher.md.
##
## Nothing from Links 2003 is downloaded or bundled: the player's files are
## read from their own discs, images or install (DiscImport).

const UI := preload("res://scripts/ui.gd")
const Glass := preload("res://scripts/glass.gd")
const Switch := preload("res://scripts/switch.gd")
const Segmented := preload("res://scripts/segmented.gd")
const Group := preload("res://scripts/group.gd")
const Paths := preload("res://scripts/paths.gd")
const ReleaseFeed := preload("res://scripts/release_feed.gd")
const Installer := preload("res://scripts/installer.gd")
const DiscImport := preload("res://scripts/disc_import.gd")
const DiscImage := preload("res://scripts/disc_image.gd")
const GameConfig := preload("res://scripts/game_config.gd")
const BuildInfo := preload("res://scripts/build_info.gd")
const Net := preload("res://scripts/net.gd")

const BG_SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(1180.0, 720.0);
uniform vec2 ball_uv = vec2(0.25, 0.4);

float glow(vec2 uv, vec2 at, vec2 scale, float k) {
	vec2 d = (uv - at) * scale;
	return exp(-dot(d, d) * k);
}

void fragment() {
	float aspect = rect_size.x / max(rect_size.y, 1.0);
	vec2 a = vec2(aspect, 1.0);
	float t = TIME * 0.05;
	vec3 c = vec3(0.0);
	c += vec3(0.07, 0.42, 0.17) * 0.55 * glow(UV, vec2(0.05 + 0.03 * sin(t), 1.08), a, 2.6);
	c += vec3(0.00, 0.22, 0.62) * 0.50 * glow(UV, vec2(0.95, -0.08 + 0.03 * cos(t * 1.3)), a, 3.0);
	c += vec3(0.10, 0.58, 0.26) * 0.30 * glow(UV, ball_uv, a * vec2(1.0, 2.6), 16.0);
	// Dither, so the glows don't band.
	c += (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
	COLOR = vec4(c, 1.0);
}
"""

enum State { CHECKING, NO_GAME, OFFLINE_NO_GAME, UPDATE, DOWNLOADING, INSTALLING, READY, PLAYING }

const TAB_NAMES := ["What's New", "Settings", "Game Files"]
const ON_LAUNCH := ["Keep the launcher open", "Minimise the launcher", "Close the launcher"]
const RENDERERS := ["Automatic", "Forward+ (Vulkan, Metal, D3D12)", "Compatibility (OpenGL)"]
const RENDERER_ARGS := [[], ["--rendering-method", "forward_plus"], ["--rendering-method", "gl_compatibility"]]

var _net: Net
var _cfg: GameConfig
var _lcfg := ConfigFile.new()
var _release := {}
var _installed := {}
var _entries: Array[Dictionary] = []
var _state := State.CHECKING
var _error := ""
var _offline := false
var _launcher_update := ""
var _thread: Thread
var _thread_result := ""
var _import: DiscImport
var _import_thread: Thread
var _game_pid := -1
var _time := 0.0

var _bg: ColorRect
var _ball: TextureRect
var _ball_box: Control
var _chip: Control
var _chip_dot: Label
var _chip_text: Label
var _play: Button
var _builder: Button
var _progress: ProgressBar
var _progress_text: Label
var _sub: Label
var _message: Label
var _tabs: Segmented
var _pages: Array[Control] = []
var _news: VBoxContainer
var _settings: VBoxContainer
var _files: VBoxContainer


func _ready() -> void:
	theme = UI.make_theme()
	get_window().min_size = Vector2i(980, 640)
	get_window().title = "OpenLinks2003"
	_net = Net.new()
	add_child(_net)
	_net.download_progress.connect(_on_download_progress)
	_lcfg.load(Paths.launcher_config())
	_cfg = GameConfig.load_from() as GameConfig
	_installed = Installer.installed()
	_load_cache()
	_build()
	get_window().files_dropped.connect(_on_files_dropped)
	_refresh()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--import="):
			_import_from(PackedStringArray([arg.trim_prefix("--import=")]))
		if arg.begins_with("--tab="):
			_tabs.selected = clampi(int(arg.trim_prefix("--tab=")), 0, TAB_NAMES.size() - 1)
			_show_tab(_tabs.selected)
	_check()


# ---- Layout ------------------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg = ColorRect.new()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BG_SHADER
	mat.shader = sh
	_bg.material = mat
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top := 58 if Paths.platform() == "macos" else 50
	for side: String in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", top)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	margin.add_child(row)
	row.add_child(_build_hero())
	row.add_child(_build_card())
	_build_chip()


func _build_hero() -> Control:
	var hero := VBoxContainer.new()
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.size_flags_stretch_ratio = 0.92
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", 0)

	_ball_box = Control.new()
	_ball_box.custom_minimum_size = Vector2(0, 250)
	hero.add_child(_ball_box)
	var shadow := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.75))
	g.set_color(1, Color(0, 0, 0, 0))
	grad.gradient = g
	shadow.texture = grad
	shadow.name = "Shadow"
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_ball_box.add_child(shadow)
	_ball = TextureRect.new()
	_ball.texture = UI.texture("res://assets/ball.png")
	_ball.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ball.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ball_box.add_child(_ball)

	var words := HBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	words.add_child(UI.label("OpenLinks", 52, "SemiBold", UI.TEXT))
	words.add_child(UI.label("2003", 52, "Light", UI.TEXT_2))
	hero.add_child(words)
	var tag := GradientText.new()
	tag.text = "The classic golf game, rebuilt."
	tag.font = UI.font("SemiBold")
	tag.font_size = 20
	tag.from = UI.GREEN
	tag.to = UI.BLUE
	tag.custom_minimum_size = Vector2(0, 30)
	hero.add_child(tag)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	hero.add_child(gap)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	hero.add_child(buttons)
	_play = UI.primary_button("Play")
	_play.pressed.connect(_on_play)
	buttons.add_child(_play)
	_builder = UI.glass_button("Course builder")
	_builder.custom_minimum_size.x = 180
	_builder.tooltip_text = "Opens the course designer: build your own holes and play them."
	_builder.pressed.connect(_on_builder)
	buttons.add_child(_builder)

	var status := VBoxContainer.new()
	status.custom_minimum_size = Vector2(0, 74)
	status.add_theme_constant_override("separation", 8)
	hero.add_child(status)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	status.add_child(spacer)
	var bar_row := CenterContainer.new()
	status.add_child(bar_row)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(384, 6)
	_progress.max_value = 1.0
	_progress.show_percentage = false
	bar_row.add_child(_progress)
	_progress_text = UI.label("", 13, "Regular", UI.TEXT_2)
	_progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_child(_progress_text)
	_message = UI.wrap(UI.label("", 13, "Regular", UI.ORANGE))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_child(_message)
	_sub = UI.label("", 12, "Regular", UI.TEXT_3)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_child(_sub)
	return hero


func _build_card() -> Control:
	var card := Glass.new(28.0, 18.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.08
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	_tabs = Segmented.new(PackedStringArray(TAB_NAMES), 0, 34.0)
	_tabs.changed.connect(_show_tab)
	v.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	for i in TAB_NAMES.size():
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 16)
		page.visible = i == 0
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_right", 10)
		m.add_child(page)
		m.visible = i == 0
		pages.add_child(m)
		_pages.append(m)
	_news = _pages[0].get_child(0) as VBoxContainer
	_settings = _pages[1].get_child(0) as VBoxContainer
	_files = _pages[2].get_child(0) as VBoxContainer
	_build_settings()
	return card


func _build_chip() -> void:
	var chip := Glass.new(16.0, 0.0)
	chip.tint = Color(0.12, 0.12, 0.13, 0.5)
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.position = Vector2(-40, 8)
	var m := MarginContainer.new()
	for side: String in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 12)
	for side: String in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 5)
	chip.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	m.add_child(h)
	_chip_dot = UI.label("●", 10, "Regular", UI.GREEN)
	h.add_child(_chip_dot)
	_chip_text = UI.label("", 12, "Medium", UI.TEXT_2)
	h.add_child(_chip_text)
	add_child(chip)
	_chip = chip
	# The chip floats over the top-right corner of the card.
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.offset_right = -52.0
	chip.offset_top = 14.0 if Paths.platform() != "macos" else 22.0


func _show_tab(i: int) -> void:
	for p in _pages.size():
		_pages[p].visible = p == i
		_pages[p].get_child(0).visible = p == i
	if i == 2:
		_build_files()


func _process(delta: float) -> void:
	_time += delta
	_layout_ball()
	if _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		_on_installed(_thread_result)
	if _import_thread != null:
		var s: Array = _import.snapshot()
		var total := maxi(int(s[1]), 1)
		_progress.value = float(s[0]) / total
		_progress_text.text = "Copying your Links 2003 files · %s of %s" % [Paths.size_text(int(s[0])), Paths.size_text(int(s[1]))]
		if not _import_thread.is_alive():
			_import_thread.wait_to_finish()
			_import_thread = null
			_on_imported()
	if _state == State.PLAYING and not OS.is_process_running(_game_pid):
		_game_pid = -1
		if get_window().mode == Window.MODE_MINIMIZED:
			get_window().mode = Window.MODE_WINDOWED
		_state = State.READY
		_refresh()


## Floats the ball gently, and keeps its glow in the background under it.
func _layout_ball() -> void:
	if _ball_box == null:
		return
	var box := _ball_box.size
	var d := minf(box.y - 40.0, 210.0)
	var bob := sin(_time * 1.1) * 5.0
	_ball.size = Vector2(d, d)
	_ball.position = Vector2((box.x - d) / 2.0, (box.y - 40.0 - d) / 2.0 + bob)
	var shadow: TextureRect = _ball_box.get_node("Shadow")
	var sw := d * (0.78 - bob * 0.008)
	shadow.size = Vector2(sw, sw * 0.16)
	shadow.position = Vector2((box.x - sw) / 2.0, box.y - 40.0 - sw * 0.02)
	shadow.modulate.a = 0.85 - bob * 0.02
	var vp := get_viewport_rect().size
	var centre := _ball.get_global_rect().get_center()
	var mat := _bg.material as ShaderMaterial
	mat.set_shader_parameter("rect_size", vp)
	mat.set_shader_parameter("ball_uv", Vector2(centre.x / vp.x, (centre.y + d * 0.55) / vp.y))


# ---- Updates -------------------------------------------------------------------

func _load_cache() -> void:
	var rel: Variant = _read_json(Paths.cache_dir().path_join("release.json"))
	_release = ReleaseFeed.parse_release(rel, Paths.game_asset())
	_entries = ReleaseFeed.parse_commits(_read_json(Paths.cache_dir().path_join("commits.json")))


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else null


static func _write_json(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


func _check() -> void:
	if _state in [State.DOWNLOADING, State.INSTALLING, State.PLAYING]:
		return
	_state = State.CHECKING
	_error = ""
	_refresh()
	var r: Dictionary = await _net.get_json(ReleaseFeed.RELEASE_URL)
	_offline = not r.ok
	if r.ok:
		_write_json(Paths.cache_dir().path_join("release.json"), r.data)
		_release = ReleaseFeed.parse_release(r.data, Paths.game_asset())
	var c: Dictionary = await _net.get_json(ReleaseFeed.COMMITS_URL)
	if c.ok:
		_write_json(Paths.cache_dir().path_join("commits.json"), c.data)
		_entries = ReleaseFeed.parse_commits(c.data)
	if BuildInfo.LAUNCHER_TREE != "dev":
		var l: Dictionary = await _net.get_json(ReleaseFeed.CONTENTS_URL)
		if l.ok:
			var tree := ReleaseFeed.launcher_tree(l.data)
			_launcher_update = tree if not tree.is_empty() and tree != BuildInfo.LAUNCHER_TREE else ""
	if not r.ok and _installed.is_empty():
		_error = str(r.get("error", ""))
	_decide()


func _decide() -> void:
	_installed = Installer.installed()
	if _installed.is_empty():
		_state = State.OFFLINE_NO_GAME if _release.is_empty() else State.NO_GAME
		if _state == State.NO_GAME and _auto_update():
			_refresh()
			_download()
			return
	elif not _release.is_empty() and str(_installed.get("commit", "")) != str(_release.commit):
		_state = State.UPDATE
		if _auto_update():
			_refresh()
			_download()
			return
	else:
		_state = State.READY
	_refresh()


func _auto_update() -> bool:
	return bool(_lcfg.get_value("launcher", "auto_update", true))


func _download() -> void:
	if _release.is_empty():
		return
	_state = State.DOWNLOADING
	_error = ""
	_refresh()
	var archive := Paths.downloads_dir().path_join(Paths.game_asset())
	var r: Dictionary = await _net.download(str(_release.url), archive)
	if not r.ok:
		_error = str(r.error)
		_decide_after_failure()
		return
	_state = State.INSTALLING
	_progress_text.text = "Installing..."
	_refresh()
	var release := _release.duplicate()
	_thread = Thread.new()
	_thread.start(func() -> void: _thread_result = Installer.install(archive, release))


func _decide_after_failure() -> void:
	_installed = Installer.installed()
	if _installed.is_empty():
		_state = State.NO_GAME if not _release.is_empty() else State.OFFLINE_NO_GAME
	else:
		_state = State.UPDATE if str(_installed.get("commit", "")) != str(_release.get("commit", "")) else State.READY
	_refresh()


func _on_download_progress(done: int, total: int) -> void:
	if total <= 0:
		total = int(_release.get("size", 0))
	_progress.value = float(done) / maxf(total, 1)
	var what := "Downloading the game" if _installed.is_empty() else "Downloading the update"
	_progress_text.text = "%s · %s of %s" % [what, Paths.size_text(done), Paths.size_text(total)]


func _on_installed(why: String) -> void:
	if why.is_empty():
		_error = ""
		_installed = Installer.installed()
		_state = State.READY
		_refresh()
	else:
		_error = why
		_decide_after_failure()


# ---- Play ------------------------------------------------------------------------

func _on_play() -> void:
	match _state:
		State.NO_GAME, State.UPDATE:
			_download()
		State.OFFLINE_NO_GAME:
			_check()
		State.READY:
			_launch([])


func _on_builder() -> void:
	if _state == State.READY:
		_launch(["--", "--designer"])


func _launch(extra: Array) -> void:
	var exe := Paths.game_executable()
	if exe.is_empty():
		_error = "The game isn't installed."
		_decide()
		return
	_save_settings()
	var args := PackedStringArray(RENDERER_ARGS[_renderer()])
	args.append_array(PackedStringArray(extra))
	_game_pid = OS.create_process(exe, args)
	if _game_pid <= 0:
		_error = "The game didn't start."
		_refresh()
		return
	_state = State.PLAYING
	_error = ""
	_refresh()
	match int(_lcfg.get_value("launcher", "on_launch", 1)):
		1:
			get_window().mode = Window.MODE_MINIMIZED
		2:
			get_tree().quit()


func _renderer() -> int:
	return clampi(int(_lcfg.get_value("launcher", "renderer", 0)), 0, RENDERERS.size() - 1)


# ---- State shown -----------------------------------------------------------------

func _refresh() -> void:
	var busy := _state in [State.DOWNLOADING, State.INSTALLING]
	_progress.get_parent().visible = busy or _import_thread != null
	_progress_text.visible = busy or _import_thread != null
	if not busy and _import_thread == null:
		_progress.value = 0.0
	_play.disabled = busy or _state == State.PLAYING
	_builder.disabled = _state != State.READY
	var dl_size := Paths.size_text(int(_release.get("size", 0)))
	match _state:
		State.CHECKING:
			_play.text = "Play" if not _installed.is_empty() else "Install"
			_play.disabled = true
		State.NO_GAME:
			_play.text = "Install · %s" % dl_size
		State.OFFLINE_NO_GAME:
			_play.text = "Try again"
		State.UPDATE:
			_play.text = "Update · %s" % dl_size
		State.DOWNLOADING:
			_play.text = "Downloading"
		State.INSTALLING:
			_play.text = "Installing"
		State.READY:
			_play.text = "Play"
		State.PLAYING:
			_play.text = "Playing"
	_message.text = _error
	_message.visible = not _error.is_empty()
	_sub.text = _build_line()
	_set_chip()
	_fill_news()


func _build_line() -> String:
	if _installed.is_empty():
		return "Not installed yet. The game is free and contains nothing from Links 2003."
	var commit := str(_installed.get("commit", ""))
	var when := ReleaseFeed.relative_date(str(_installed.get("published", "")))
	if commit.is_empty():
		return "Installed"
	return "Build %s%s" % [ReleaseFeed.short(commit), (" · " + when) if not when.is_empty() else ""]


func _set_chip() -> void:
	var text := ""
	var colour := UI.GREEN
	match _state:
		State.CHECKING:
			text = "Checking for updates"
			colour = UI.TEXT_3
		State.DOWNLOADING, State.INSTALLING:
			text = "Updating"
			colour = UI.BLUE
		State.UPDATE, State.NO_GAME:
			text = "Update available" if _state == State.UPDATE else "Ready to install"
			colour = UI.BLUE
		State.PLAYING:
			text = "Playing"
		_:
			text = "Up to date"
	if _offline and _state != State.CHECKING:
		text = "Offline"
		colour = UI.ORANGE
	if not _launcher_update.is_empty() and _state == State.READY:
		text += " · New launcher available"
	_chip_text.text = text
	_chip_dot.add_theme_color_override("font_color", colour)


# ---- What's New ------------------------------------------------------------------

func _fill_news() -> void:
	for c in _news.get_children():
		c.queue_free()
	var installed_commit := str(_installed.get("commit", ""))
	var fresh := ReleaseFeed.count_new(_entries, installed_commit)
	var head := UI.label("", 13, "Medium", UI.TEXT_2)
	if _entries.is_empty():
		head.text = "The changelog appears here once the launcher has been online."
	elif installed_commit.is_empty():
		head.text = "The latest changes to OpenLinks2003"
	elif fresh == 0:
		head.text = "You have the latest build."
	else:
		head.text = "%d change%s since your build" % [fresh, "" if fresh == 1 else "s"]
		head.add_theme_color_override("font_color", UI.GREEN)
	_news.add_child(head)
	for i in _entries.size():
		_news.add_child(_news_entry(_entries[i], i < fresh))
	if not _entries.is_empty():
		var more := UI.link_button("All changes on GitHub")
		more.pressed.connect(func() -> void: OS.shell_open(Paths.PROJECT_PAGE + "/commits/main"))
		more.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_news.add_child(more)


func _news_entry(e: Dictionary, fresh: bool) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var dot := Label.new()
	dot.text = "●" if fresh else ""
	dot.add_theme_color_override("font_color", UI.GREEN)
	dot.add_theme_font_size_override("font_size", 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dot.custom_minimum_size = Vector2(10, 22)
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(dot)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	v.add_child(UI.wrap(UI.label(str(e.title), 15, "SemiBold")))
	var meta := ReleaseFeed.relative_date(str(e.get("date", "")))
	if int(e.get("pr", 0)) > 0:
		meta = "#%d · %s" % [int(e.pr), meta]
	v.add_child(UI.label(meta, 12, "Regular", UI.TEXT_3))
	var points: PackedStringArray = e.get("points", PackedStringArray())
	if not points.is_empty():
		for p in points.slice(maxi(points.size() - 3, 0)):
			v.add_child(UI.wrap(UI.label("·  " + p, 13, "Regular", UI.TEXT_2)))
	elif not str(e.get("summary", "")).is_empty():
		v.add_child(UI.wrap(UI.label(str(e.summary), 13, "Regular", UI.TEXT_2)))
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 14)
	var line := ColorRect.new()
	line.color = UI.HAIRLINE
	line.custom_minimum_size = Vector2(0, 1)
	wrap.add_child(line)
	wrap.add_child(h)
	return wrap


# ---- Settings --------------------------------------------------------------------

func _option(items: Array, selected: int, on_change: Callable, width := 210.0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(clampi(selected, -1, items.size() - 1))
	o.custom_minimum_size = Vector2(width, 32)
	o.fit_to_longest_item = false
	o.clip_text = true
	o.item_selected.connect(func(i: int) -> void:
		on_change.call(i)
		_save_settings())
	return o


func _switch(value: bool, on_change: Callable) -> Control:
	var s := Switch.new(value)
	s.toggled.connect(func(on: bool) -> void:
		on_change.call(on)
		_save_settings())
	return s


func _slider(value: int, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.value = value
	s.custom_minimum_size = Vector2(150, 22)
	var l := UI.label("%d%%" % value, 13, "Regular", UI.TEXT_2)
	l.custom_minimum_size = Vector2(38, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v: float) -> void:
		l.text = "%d%%" % int(v)
		on_change.call(int(v)))
	s.drag_ended.connect(func(_changed: bool) -> void: _save_settings())
	h.add_child(s)
	h.add_child(l)
	return h


func _build_settings() -> void:
	var c := _cfg
	var graphics := Group.new("Graphics")
	var looks: Array = GameConfig.LOOKS.duplicate()
	var shown: int = c.shown_look()
	if shown == GameConfig.LOOK_CUSTOM:
		looks.append("Custom (set in the game)")
	elif shown < 0:
		looks.append("Picked for this computer")
		shown = looks.size() - 1
	var quality := Segmented.new(PackedStringArray(GameConfig.QUALITIES), c.shown_quality(), 30.0)
	quality.custom_minimum_size.x = 250
	quality.font_size = 13
	var pick_look := func(i: int) -> void:
		if i < GameConfig.LOOKS.size():
			c.choose_look(i)
			quality.selected = c.shown_quality()
	var look := _option(looks, shown, pick_look)
	look.tooltip_text = "\n".join(PackedStringArray(GameConfig.LOOK_HINTS))
	graphics.row("Look", look, "A preset for light, effects and quality. Fine-tune it in the game's Settings.")
	quality.changed.connect(func(i: int) -> void:
		c.choose_quality(i)
		_save_settings())
	graphics.row("Quality", quality)
	var scales: Array = []
	var scale_index := 2
	for i in GameConfig.RENDER_SCALES.size():
		scales.append("%d%%" % roundi(GameConfig.RENDER_SCALES[i] * 100.0))
		if is_equal_approx(GameConfig.RENDER_SCALES[i], c.render_scale):
			scale_index = i
	var set_scale := func(i: int) -> void: c.render_scale = GameConfig.RENDER_SCALES[i]
	graphics.row("3D resolution", _option(scales, scale_index, set_scale, 110.0), "Below 100% is faster and softer.")
	var set_renderer := func(i: int) -> void: _lcfg.set_value("launcher", "renderer", i)
	graphics.row("Renderer", _option(RENDERERS, _renderer(), set_renderer), "Compatibility works on older graphics cards and is lighter.")
	_settings.add_child(graphics)

	var display := Group.new("Display")
	var set_mode := func(i: int) -> void: c.set_display_choice(i)
	display.row("Mode", _option(GameConfig.DISPLAY_MODES, c.display_choice(), set_mode))
	var sizes: Array = ["Default"]
	var size_index := 0
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var offered: Array[Vector2i] = []
	for s: Vector2i in GameConfig.WINDOW_SIZES:
		if s.x <= screen.x and s.y <= screen.y:
			offered.append(s)
	if c.window_size != Vector2i.ZERO and not offered.has(c.window_size):
		offered.append(c.window_size)
	for i in offered.size():
		sizes.append("%d × %d" % [offered[i].x, offered[i].y])
		if offered[i] == c.window_size:
			size_index = i + 1
	var set_size := func(i: int) -> void: c.window_size = Vector2i.ZERO if i == 0 else offered[i - 1]
	display.row("Window size", _option(sizes, size_index, set_size, 150.0), "Fullscreen always uses the screen's own resolution.")
	var set_vsync := func(on: bool) -> void: c.vsync = on
	display.row("Vertical sync", _switch(c.vsync, set_vsync), "Stops tearing; can add a little delay.")
	var set_ui := func(i: int) -> void: c.ui_scale = i
	display.row("Interface size", _option(GameConfig.UI_SCALES, c.ui_scale, set_ui, 130.0))
	_settings.add_child(display)

	var audio := Group.new("Sound")
	var set_master := func(v: int) -> void: c.master = v
	audio.row("Volume", _slider(c.master, set_master))
	var set_music := func(v: int) -> void: c.music = v
	audio.row("Menu music", _slider(c.music, set_music), "Plays from your Links 2003 files.")
	_settings.add_child(audio)

	var controls := Group.new("Controls")
	var set_swing := func(i: int) -> void: c.swing_method = i
	controls.row("Swing", _option(GameConfig.SWINGS, c.swing_method, set_swing),
		"PowerStroke swings with the mouse, as Links 2003 did. Space always uses the meter.")
	var set_skill := func(i: int) -> void: c.skill = i
	controls.row("Swing skill", _option(GameConfig.SKILLS, c.skill, set_skill, 230.0))
	var set_help := func(on: bool) -> void: c.swing_help = on
	controls.row("Swing help", _switch(c.swing_help, set_help), "Links 2003's help for straight mouse swings.")
	var set_monitor := func(on: bool) -> void: c.launch_monitor = on
	controls.row("Launch monitor", _switch(c.launch_monitor, set_monitor), "Take real swings from a launch monitor app (OpenConnect).")
	_settings.add_child(controls)

	var show := Group.new("Presentation")
	var pres := Segmented.new(PackedStringArray(GameConfig.PRESENTATIONS), c.presentation, 30.0)
	pres.custom_minimum_size.x = 270
	pres.font_size = 13
	pres.changed.connect(func(i: int) -> void:
		c.presentation = i
		_save_settings())
	show.row("Style", pres, "Classic Links 2003, a TV broadcast, or Tour graphics.")
	_settings.add_child(show)

	var launcher := Group.new("Launcher")
	var set_auto := func(on: bool) -> void: _lcfg.set_value("launcher", "auto_update", on)
	launcher.row("Update automatically", _switch(_auto_update(), set_auto), "Downloads new builds as soon as they're published.")
	var set_on_launch := func(i: int) -> void: _lcfg.set_value("launcher", "on_launch", i)
	launcher.row("When the game starts", _option(ON_LAUNCH, int(_lcfg.get_value("launcher", "on_launch", 1)), set_on_launch, 220.0))
	var check := UI.glass_button("Check now", 32.0, 13)
	check.pressed.connect(_check)
	launcher.row("Updates", check, "Launcher %s · the game comes from GitHub releases" % ("development build" if BuildInfo.LAUNCHER_TREE == "dev" else ReleaseFeed.short(BuildInfo.LAUNCHER_TREE)))
	var get_new := UI.link_button("Downloads page")
	get_new.pressed.connect(func() -> void: OS.shell_open(Paths.RELEASES_PAGE))
	launcher.row("Launcher updates", get_new, "The game updates itself; a newer launcher is downloaded from the releases page.")
	_settings.add_child(launcher)


func _save_settings() -> void:
	_cfg.save_to()
	DirAccess.make_dir_recursive_absolute(Paths.data_dir())
	_lcfg.save(Paths.launcher_config())


# ---- Game files ------------------------------------------------------------------

func _build_files() -> void:
	for ch in _files.get_children():
		ch.queue_free()
	var folder: String = _cfg.folder
	var kind := DiscImport.folder_kind(folder)
	var status := Group.new("Your Links 2003 files")
	var title := "Ready"
	var hint := ""
	if kind == "install":
		var courses := DiscImport.count_courses(folder)
		hint = "%d course%s · %s" % [courses, "" if courses == 1 else "s", folder]
		var discs := DiscImport.copied_discs()
		if folder == Paths.library_dir() and not discs.has("1"):
			title = "Add disc 1"
		elif folder == Paths.library_dir() and discs.size() < 3:
			title = "Ready, with some courses"
		if folder == Paths.library_dir() and not discs.is_empty():
			var names := PackedStringArray()
			for d in ["1", "2", "3"]:
				names.append("Disc %s %s" % [d, "✓" if discs.has(d) else "–"])
			hint += "\n" + "   ".join(names)
	else:
		title = "Not set up yet"
		hint = "Until it can read your files, the game plays its own placeholder course. Your copy of Links 2003 brings its courses, golfers, sounds and objects."
	var show := UI.glass_button("Show", 30.0, 13)
	show.visible = kind == "install"
	show.pressed.connect(func() -> void: OS.shell_show_in_file_manager(folder))
	status.row(title, show, hint)
	_files.add_child(status)

	var found := DiscImport.detect()
	if not found.is_empty():
		var near := Group.new("Found on this computer")
		for f: Dictionary in found:
			var is_disc: bool = f.kind == "disc"
			var b := UI.glass_button("Copy" if is_disc else "Use", 30.0, 13)
			var path: String = f.path
			b.pressed.connect(func() -> void: _import_from(PackedStringArray([path])))
			near.row(("CD: " if is_disc else "Installed: ") + str(f.label), b, path)
		_files.add_child(near)

	var add := Group.new("Add your files")
	var images := UI.glass_button("Choose...", 30.0, 13)
	images.pressed.connect(_pick_images)
	add.row("Disc images", images, "BlindWrite .b6i, .iso, .bin, .nrg or .mdf. Pick all three discs at once. About 1.4 GB is copied out of them.")
	var drive := UI.glass_button("Choose...", 30.0, 13)
	drive.pressed.connect(_pick_folder.bind("Choose a Links 2003 CD"))
	add.row("CDs", drive, "Put a disc in the drive and choose it. Do this for each of the three discs.")
	var install := UI.glass_button("Choose...", 30.0, 13)
	install.pressed.connect(_pick_folder.bind("Choose your Links 2003 folder"))
	add.row("Installed game", install, "The Links 2003 folder of an installed copy, used where it is. Nothing is copied.")
	_files.add_child(add)

	var note := UI.wrap(UI.label("You can also drop images or folders on this window. OpenLinks2003 contains nothing from Links 2003: your files are read on this computer and never uploaded.", 12, "Regular", UI.TEXT_3))
	_files.add_child(note)


func _pick_images() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = "Choose your Links 2003 disc images"
	dlg.filters = PackedStringArray(["*.b6i, *.b5i, *.bwi, *.iso, *.bin, *.img, *.nrg, *.mdf ; Disc images"])
	dlg.files_selected.connect(func(paths: PackedStringArray) -> void: _import_from(paths))
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)


func _pick_folder(title: String) -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = title
	dlg.dir_selected.connect(func(path: String) -> void: _import_from(PackedStringArray([path])))
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)


func _on_files_dropped(paths: PackedStringArray) -> void:
	_tabs.selected = 2
	_show_tab(2)
	_import_from(paths)


## Uses an installed copy in place, or copies the game's files out of the
## discs, images or CD folders in `sources`.
func _import_from(sources: PackedStringArray) -> void:
	if _import_thread != null or sources.is_empty():
		return
	_error = ""
	if sources.size() == 1 and DiscImport.folder_kind(sources[0]) == "install":
		_cfg.folder = sources[0]
		_save_settings()
		_refresh()
		_build_files()
		return
	var usable := PackedStringArray()
	var descriptors := 0
	for s in sources:
		if DirAccess.dir_exists_absolute(s) or DiscImage.is_image(s):
			usable.append(s)
		elif DiscImage.is_descriptor(s):
			descriptors += 1
	if usable.is_empty():
		_error = ("Those are the small descriptor files (.b6t, .cue). Pick the big image files next to them (.b6i, .bin)."
			if descriptors > 0 else "That isn't a Links 2003 disc, image or folder.")
		_refresh()
		return
	_import = DiscImport.new()
	_import_thread = Thread.new()
	_import_thread.start(_import_job.bind(usable))
	_refresh()


func _import_job(sources: PackedStringArray) -> void:
	var p := DiscImport.plan(sources)
	if (p.entries as Array).is_empty():
		var why := "Couldn't find Links 2003's files there."
		if not (p.unreadable as PackedStringArray).is_empty():
			why = "Couldn't read %s as a CD image." % ", ".join(p.unreadable)
		_import.fail(why)
		return
	_import.copy(p)


func _on_imported() -> void:
	var s: Array = _import.snapshot()
	if not str(s[3]).is_empty():
		_error = str(s[3])
	elif DiscImport.library_ready(Paths.library_dir()):
		_cfg.folder = Paths.library_dir()
		_save_settings()
		var discs := DiscImport.copied_discs()
		var missing := PackedStringArray()
		for d in ["1", "2", "3"]:
			if not discs.has(d):
				missing.append(d)
		_error = "" if missing.is_empty() else "Copied. Add disc%s %s too for every course." % ["" if missing.size() == 1 else "s", " and ".join(missing)]
	else:
		_error = "Copied. Now add the first disc, which holds the game's main files."
	_import = null
	_refresh()
	_build_files()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _thread != null:
			_thread.wait_to_finish()
			_thread = null
		if _import_thread != null:
			_import_thread.wait_to_finish()
			_import_thread = null


## Text drawn with a colour gradient from left to right, like the brand's
## tagline.
class GradientText extends Control:
	var text := ""
	var font: Font
	var font_size := 20
	var from := Color.WHITE
	var to := Color.WHITE

	func _draw() -> void:
		if font == null:
			return
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var x := (size.x - width) / 2.0
		var y := size.y / 2.0 + font_size * 0.36
		var cursor := x
		for i in text.length():
			var t := clampf((cursor - x) / maxf(width, 1.0), 0.0, 1.0)
			cursor += font.draw_char(get_canvas_item(), Vector2(cursor, y), text.unicode_at(i), font_size, from.lerp(to, t))
