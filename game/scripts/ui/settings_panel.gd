class_name SettingsPanel
extends PanelContainer
## Graphics options (quality, window mode, v-sync, anti-aliasing, render
## scale, field of view) and the wind strength. Changes apply at once and are
## saved.

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
	visible = true
	_quality.grab_focus()


func close() -> void:
	visible = false


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
	settings.save()
	changed.emit()


static func _closest(choices: Array, value: float) -> int:
	var best := 0
	for i in choices.size():
		if absf(float(choices[i]) - value) < absf(float(choices[best]) - value):
			best = i
	return best
