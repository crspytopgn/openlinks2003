class_name LaunchMonitorPanel
extends PanelContainer
## The practice range's launch monitor: the last shot's numbers and the
## session so far with that club (LaunchMonitor).

var _title: Label
var _grid: GridContainer
var _summary: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.07, 0.82)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.35))
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 18)
	box.add_child(_grid)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 13)
	_summary.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size.x = 220
	box.add_child(_summary)
	show_waiting("")


## Before the first shot with a club.
func show_waiting(club: String) -> void:
	_title.text = "LAUNCH MONITOR"
	_fill([])
	_summary.text = "Hit a shot to see its numbers." if club.is_empty() else "%s: hit a shot to see its numbers." % club


func show_reading(r: LaunchMonitor.Reading, summary: String) -> void:
	_title.text = "LAUNCH MONITOR  ·  %s" % r.club.to_upper()
	_fill(LaunchMonitor.rows(r))
	_summary.text = summary


func _fill(rows: Array) -> void:
	for c in _grid.get_children():
		c.queue_free()
	for row: Array in rows:
		var name := Label.new()
		name.text = row[0]
		name.add_theme_color_override("font_color", Color(0.75, 0.8, 0.75))
		_grid.add_child(name)
		var value := Label.new()
		value.text = row[1]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 17)
		_grid.add_child(value)
