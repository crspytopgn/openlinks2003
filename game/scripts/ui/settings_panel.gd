class_name SettingsPanel
extends PanelContainer
## Graphics options (quality, window mode, v-sync, anti-aliasing, render
## scale, field of view), the wind strength, the presentation (Classic
## Links or Broadcast) and the HD texture pack, and next to them the look: a
## preset plus its effects (lighting, upscaler, dynamic resolution,
## sharpening, bloom, SSAO, depth of field, colour grading, vignette, grain,
## grass, wind in the trees). Picking a look sets all of those; changing one
## makes the look Custom. Changes apply at once and are saved; the HD pack
## applies to textures loaded from then on (HdPack).

signal changed

const FOV_CHOICES := [50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0]

var settings: GraphicsSettings

## The swing skill levels, easiest first (see LinksLaunch.apply_swing).
const SKILL_NAMES := ["Level 1 (forgiving)", "Level 2", "Level 3", "Level 4 (Links 2003's hardest)"]

var _quality: OptionButton
var _window: OptionButton
var _vsync: OptionButton
var _msaa: OptionButton
var _scale: OptionButton
var _fov: OptionButton
var _wind: OptionButton
var _presentation: OptionButton
var _skill: OptionButton
var _firmness: OptionButton
var _speed: OptionButton
var _hd: OptionButton
var _hd_note: Label
var _hd_dialog: FileDialog
var _look: OptionButton
var _lighting: OptionButton
var _upscaler: OptionButton
var _dynamic: OptionButton
var _sharpen: OptionButton
var _bloom: OptionButton
var _ssao: OptionButton
var _dof: OptionButton
var _grade: OptionButton
var _vignette: OptionButton
var _grain: OptionButton
var _grass: OptionButton
var _foliage: OptionButton
var _trees: OptionButton
var _filling := false  ## true while open() sets the controls


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

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	box.add_child(columns)
	var grid := _grid(columns)
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
	_skill = _row(grid, "Swing skill", SKILL_NAMES)
	_firmness = _row(grid, "Green firmness", ["Soft", "Medium", "Firm"])
	_speed = _row(grid, "Green speed", ["Slow", "Normal", "Fast"])
	_add_hd_rows(box, grid)
	_add_look_rows(_grid(columns))

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
	_skill.select(s.skill)
	_firmness.select(s.green_firmness)
	_speed.select(s.green_speed)
	_show_look()
	_show_hd()
	visible = true
	_look.grab_focus()


func close() -> void:
	visible = false


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid


# --- Look and effects ---------------------------------------------------------


func _add_look_rows(grid: GridContainer) -> void:
	_look = _row(grid, "Look", GraphicsSettings.LOOK_NAMES, false)
	_look.item_selected.connect(_on_look_selected)
	_lighting = _row(grid, "Lighting", GraphicsSettings.LIGHTING_NAMES)
	_upscaler = _row(grid, "Upscaler", GraphicsSettings.UPSCALER_NAMES)
	_dynamic = _row(grid, "Dynamic resolution", GraphicsSettings.DYNAMIC_NAMES)
	_sharpen = _row(grid, "Sharpening", GraphicsSettings.LEVEL_NAMES)
	_bloom = _row(grid, "Bloom", GraphicsSettings.LEVEL_NAMES)
	_ssao = _row(grid, "Ambient occlusion", ["Off", "On"])
	_dof = _row(grid, "Depth of field", ["Off", "On"])
	_grade = _row(grid, "Colour grading", GraphicsSettings.GRADE_NAMES)
	_vignette = _row(grid, "Vignette", GraphicsSettings.LEVEL_NAMES)
	_grain = _row(grid, "Film grain", GraphicsSettings.LEVEL_NAMES)
	_grass = _row(grid, "3D grass", GraphicsSettings.LEVEL_NAMES)
	_foliage = _row(grid, "Trees in the wind", ["Still", "Sway"])
	_trees = _row(grid, "Trees", GraphicsSettings.TREE_NAMES)
	_trees.tooltip_text = "Photo-textured 3D trees. Takes effect on the next hole."
	if not GraphicsSettings.is_forward_plus():
		# The browser's renderer can't do these.
		for opt in [_upscaler, _ssao, _dof]:
			opt.disabled = true
			opt.tooltip_text = "Needs the desktop version (Forward+ renderer)."


func _show_look() -> void:
	_filling = true
	var s := settings
	_look.select(s.look)
	_lighting.select(s.lighting)
	_upscaler.select(s.upscaler)
	_dynamic.select(s.dynamic_res)
	_sharpen.select(s.sharpen)
	_bloom.select(s.bloom)
	_ssao.select(1 if s.ssao else 0)
	_dof.select(1 if s.dof else 0)
	_grade.select(s.grade)
	_vignette.select(s.vignette)
	_grain.select(s.grain)
	_grass.select(s.grass)
	_foliage.select(1 if s.foliage_wind else 0)
	_trees.select(s.trees)
	_filling = false


func _on_look_selected(index: int) -> void:
	if settings == null or index == GraphicsSettings.Look.CUSTOM:
		if settings != null:
			settings.look = GraphicsSettings.Look.CUSTOM
			settings.save()
		return
	settings.apply_look(index)
	settings.save()
	open(settings)
	changed.emit()


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


func _row(grid: GridContainer, label: String, items: Array, connect_change := true) -> OptionButton:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var opt := OptionButton.new()
	for item in items:
		opt.add_item(str(item))
	if connect_change:
		opt.item_selected.connect(_on_selected.unbind(1))
	grid.add_child(opt)
	return opt


func _on_selected() -> void:
	if settings == null or _filling:
		return
	var before := _look_values()
	settings.quality = _quality.selected
	settings.fullscreen = _window.selected == 1
	settings.vsync = _vsync.selected == 1
	settings.msaa = GraphicsSettings.MSAA_CHOICES[_msaa.selected]
	settings.render_scale = GraphicsSettings.RENDER_SCALES[_scale.selected]
	settings.fov = FOV_CHOICES[_fov.selected]
	settings.wind = _wind.selected
	settings.presentation = _presentation.selected
	settings.skill = _skill.selected
	settings.green_firmness = _firmness.selected
	settings.green_speed = _speed.selected
	settings.lighting = _lighting.selected
	settings.upscaler = _upscaler.selected
	settings.dynamic_res = _dynamic.selected
	settings.sharpen = _sharpen.selected
	settings.bloom = _bloom.selected
	settings.ssao = _ssao.selected == 1
	settings.dof = _dof.selected == 1
	settings.grade = _grade.selected
	settings.vignette = _vignette.selected
	settings.grain = _grain.selected
	settings.grass = _grass.selected
	settings.foliage_wind = _foliage.selected == 1
	settings.trees = _trees.selected
	if before != _look_values():
		settings.look = GraphicsSettings.Look.CUSTOM
		_look.select(settings.look)
	settings.save()
	changed.emit()


## Everything a look sets, to tell whether a change left the preset.
func _look_values() -> Array:
	return [settings.quality, settings.msaa, settings.render_scale, settings.lighting, settings.upscaler,
		settings.dynamic_res, settings.sharpen, settings.bloom, settings.ssao, settings.dof, settings.grade,
		settings.vignette, settings.grain, settings.grass, settings.foliage_wind, settings.trees]


static func _closest(choices: Array, value: float) -> int:
	var best := 0
	for i in choices.size():
		if absf(float(choices[i]) - value) < absf(float(choices[best]) - value):
			best = i
	return best
