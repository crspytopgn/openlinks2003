class_name SettingsPanel
extends PanelContainer
## Graphics options (quality, window mode, v-sync, anti-aliasing, render
## scale, field of view), the wind strength, the presentation (Classic
## Links or Broadcast) and the HD texture pack. Changes
## apply at once and are saved; the HD pack applies to textures loaded from
## then on (HdPack).

signal changed

const FOV_CHOICES := [50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0]

var settings: GraphicsSettings

var _quality: OptionButton
var _window: OptionButton
var _vsync: OptionButton
var _msaa: OptionButton
var _scale: OptionButton
var _fov: OptionButton
var _wind: OptionButton
var _presentation: OptionButton
var _hd: OptionButton
var _hd_note: Label
var _hd_dialog: FileDialog


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.09, 0.94)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	_quality = _row(grid, "Quality", GraphicsSettings.QUALITY_NAMES)
	_window = _row(grid, "Display", ["Windowed", "Fullscreen"])
	_vsync = _row(grid, "V-sync", ["Off", "On"])
	_msaa = _row(grid, "Anti-aliasing", ["Off (FXAA)", "MSAA 2x", "MSAA 4x", "MSAA 8x"])
	var scales: Array = []
	for s in GraphicsSettings.RENDER_SCALES:
		scales.append("%d%%" % roundi(s * 100.0))
	_scale = _row(grid, "3D resolution", scales)
	var fovs: Array = []
	for f in FOV_CHOICES:
		fovs.append("%d deg" % roundi(f))
	_fov = _row(grid, "Field of view", fovs)
	_wind = _row(grid, "Wind", Wind.LEVEL_NAMES)
	_presentation = _row(grid, "Presentation", GraphicsSettings.PRESENTATION_NAMES)
	_add_hd_rows(box, grid)

	var hint := Label.new()
	hint.text = "Esc: close    F11: fullscreen"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	visible = false


## Shows the panel with the current values.
func open(s: GraphicsSettings) -> void:
	settings = s
	_quality.select(s.quality)
	_window.select(1 if s.fullscreen else 0)
	_vsync.select(1 if s.vsync else 0)
	_msaa.select(maxi(0, GraphicsSettings.MSAA_CHOICES.find(s.msaa)))
	_scale.select(_closest(GraphicsSettings.RENDER_SCALES, s.render_scale))
	_fov.select(_closest(FOV_CHOICES, s.fov))
	_wind.select(s.wind)
	_presentation.select(s.presentation)
	_show_hd()
	visible = true
	_quality.grab_focus()


func close() -> void:
	visible = false


# --- HD texture pack ----------------------------------------------------------


func _add_hd_rows(box: VBoxContainer, grid: GridContainer) -> void:
	var l := Label.new()
	l.text = "HD textures"
	grid.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	grid.add_child(row)
	_hd = OptionButton.new()
	_hd.add_item("Off")
	_hd.add_item("On")
	_hd.item_selected.connect(_on_hd_selected)
	row.add_child(_hd)
	var choose := Button.new()
	choose.text = "Choose pack..."
	choose.pressed.connect(_choose_hd_pack)
	row.add_child(choose)
	_hd_note = Label.new()
	_hd_note.add_theme_font_size_override("font_size", 14)
	_hd_note.modulate = Color(1, 1, 1, 0.7)
	_hd_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hd_note.custom_minimum_size = Vector2(420, 0)
	box.add_child(_hd_note)
	if OS.has_feature("web"):
		# The browser build can't open a folder on disk yet.
		_hd.disabled = true
		choose.disabled = true
		return
	_hd_dialog = FileDialog.new()
	_hd_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_hd_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_hd_dialog.filters = PackedStringArray(["*.zip ; HD pack (.zip)"])
	_hd_dialog.title = "Choose an HD pack folder or .zip"
	_hd_dialog.dir_selected.connect(_on_hd_picked)
	_hd_dialog.file_selected.connect(_on_hd_picked)
	add_child(_hd_dialog)


func _show_hd() -> void:
	var path := HdPack.saved_path()
	_hd.select(1 if HdPack.saved_enabled() and not path.is_empty() else 0)
	if OS.has_feature("web"):
		_hd_note.text = "HD texture packs work in the desktop version for now."
	elif path.is_empty():
		_hd_note.text = "No HD pack chosen. Make one from your own files: see docs/hd-textures.md."
	else:
		_hd_note.text = "%s (%d textures). Applies from the next course or hole." % [path, HdPack.count_textures(path)]


func _choose_hd_pack() -> void:
	if _hd_dialog == null:
		return
	var path := HdPack.saved_path()
	if not path.is_empty():
		_hd_dialog.current_dir = path if DirAccess.dir_exists_absolute(path) else path.get_base_dir()
	_hd_dialog.popup_centered_ratio(0.6)


func _on_hd_picked(path: String) -> void:
	HdPack.save(path, true)
	_show_hd()


func _on_hd_selected(index: int) -> void:
	var path := HdPack.saved_path()
	if index == 1 and path.is_empty():
		_hd.select(0)
		_choose_hd_pack()
		return
	HdPack.save(path, index == 1)
	_show_hd()


func _row(grid: GridContainer, label: String, items: Array) -> OptionButton:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var opt := OptionButton.new()
	for item in items:
		opt.add_item(str(item))
	opt.item_selected.connect(_on_selected.unbind(1))
	grid.add_child(opt)
	return opt


func _on_selected() -> void:
	if settings == null:
		return
	settings.quality = _quality.selected
	settings.fullscreen = _window.selected == 1
	settings.vsync = _vsync.selected == 1
	settings.msaa = GraphicsSettings.MSAA_CHOICES[_msaa.selected]
	settings.render_scale = GraphicsSettings.RENDER_SCALES[_scale.selected]
	settings.fov = FOV_CHOICES[_fov.selected]
	settings.wind = _wind.selected
	settings.presentation = _presentation.selected
	settings.save()
	changed.emit()


static func _closest(choices: Array, value: float) -> int:
	var best := 0
	for i in choices.size():
		if absf(float(choices[i]) - value) < absf(float(choices[best]) - value):
			best = i
	return best
