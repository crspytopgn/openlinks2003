class_name WindIndicator
extends Control
## A compass-style arrow showing where the wind blows relative to the aim
## (up the screen is downrange), with the speed underneath.

var _relative_deg := 0.0
var _mph := 0.0
var _calm := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_wind(wind: Wind, aim_deg: float) -> void:
	_calm = wind.is_calm()
	_mph = wind.speed_mph()
	_relative_deg = wind.relative_deg(aim_deg)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var r := minf(size.x, size.y - 22.0) * 0.5 - 2.0
	var c := Vector2(size.x * 0.5, r + 2.0)
	draw_circle(c, r, Color(0, 0, 0, 0.35))
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.6), 1.5, true)
	var text := "Calm"
	if not _calm:
		# Towards +x is the golfer's left, which is screen left behind the ball.
		var rel := deg_to_rad(_relative_deg)
		var dir := Vector2(-sin(rel), -cos(rel))
		var side := Vector2(-dir.y, dir.x)
		var tip := c + dir * r * 0.8
		var tail := c - dir * r * 0.7
		var col := Color(1.0, 0.95, 0.6)
		draw_line(tail, tip - dir * r * 0.3, col, 3.0, true)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * r * 0.4 + side * r * 0.25, tip - dir * r * 0.4 - side * r * 0.25]), col)
		text = "%d mph" % roundi(_mph)
	var fs := 16
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(c.x - w * 0.5, c.y + r + 18.0)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
