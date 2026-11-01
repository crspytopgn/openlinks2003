class_name WindIndicator
extends Control
## A compass-style arrow showing where the wind blows relative to the aim
## (up the screen is downrange), with the speed underneath. In the
## Broadcast presentation (`modern`) it is a glass disc (Glass) with a
## compass ring and the speed in a glass pill.

const ARROW := Color(1.0, 0.95, 0.6)
const PILL_H := 24.0

## The glass disc and speed pill (Broadcast presentation).
var modern := false:
	set(v):
		modern = v
		queue_redraw()

var _relative_deg := 0.0
var _mph := 0.0
var _calm := true
var _glass: FrostedGlass


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass = FrostedGlass.new()
	add_child(_glass)


func show_wind(wind: Wind, aim_deg: float) -> void:
	_calm = wind.is_calm()
	_mph = wind.speed_mph()
	_relative_deg = wind.relative_deg(aim_deg)
	queue_redraw()


## Lists the glass behind the disc and pill (none in Classic).
func update_glass() -> void:
	_glass.begin()
	if modern:
		for r in _modern_shapes():
			_glass.add(r, 1.0, Vector4.ONE * minf(r.size.x, r.size.y) * 0.5)
	_glass.commit()


func _draw() -> void:
	update_glass()
	if modern:
		_draw_modern()
		return
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


## The disc and the speed pill under it, in this control's coordinates.
func _modern_shapes() -> Array[Rect2]:
	var d := minf(size.x, size.y - PILL_H - 8.0)
	var disc := Rect2((size.x - d) * 0.5, 0.0, d, d)
	var pill_w := minf(size.x, 76.0)
	var pill := Rect2((size.x - pill_w) * 0.5, d + 8.0, pill_w, PILL_H)
	return [disc, pill]


func _draw_modern() -> void:
	var shapes := _modern_shapes()
	var disc: Rect2 = shapes[0]
	var pill: Rect2 = shapes[1]
	var tint := Color(Glass.TINT, Glass.TINT_ALPHA_BLUR if Glass.blurs() else Glass.TINT_ALPHA_FLAT)
	var c := disc.get_center()
	var r := disc.size.x * 0.5
	draw_circle(c, r, tint)
	_pill(pill, tint)
	if not Glass.blurs():
		draw_arc(c, r - 0.5, 0.0, TAU, 64, Glass.RIM, 1.0, true)
	# A compass ring: a tick every 30 degrees, longer at the four points,
	# and a small notch at the top for downrange.
	for i in 12:
		var a := TAU * i / 12.0
		var dir := Vector2(sin(a), -cos(a))
		var long := i % 3 == 0
		var inner := r - (9.0 if long else 6.0)
		draw_line(c + dir * inner, c + dir * (r - 3.5), Color(1, 1, 1, 0.55 if long else 0.28), 1.5 if long else 1.0, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r + 2.0), c + Vector2(-4.0, -r + 9.0), c + Vector2(4.0, -r + 9.0)]), Color(1, 1, 1, 0.85))
	var font := GlassTheme.font(600)
	var text := "CALM"
	if _calm:
		draw_circle(c, 3.0, Color(1, 1, 1, 0.6))
	else:
		# Towards +x is the golfer's left, which is screen left behind the ball.
		var rel := deg_to_rad(_relative_deg)
		var dir := Vector2(-sin(rel), -cos(rel))
		var side := Vector2(-dir.y, dir.x)
		var tip := c + dir * r * 0.62
		var tail := c - dir * r * 0.5
		var head := tip - dir * r * 0.32
		# A soft dark under-stroke keeps the arrow crisp over a bright sky.
		draw_line(tail, head, Color(0, 0, 0, 0.3), 6.0, true)
		draw_line(tail, head, ARROW, 3.0, true)
		draw_colored_polygon(PackedVector2Array([tip, head + side * r * 0.2, head - side * r * 0.2]), ARROW)
		draw_circle(tail, 2.5, ARROW)
		text = "%d MPH" % roundi(_mph)
	var fs := 13
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(pill.get_center().x - w * 0.5, pill.get_center().y + fs * 0.36)
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))


func _pill(r: Rect2, col: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = col
	box.set_corner_radius_all(int(r.size.y * 0.5))
	box.corner_detail = 12
	box.anti_aliasing = true
	if not Glass.blurs():
		box.border_color = Glass.RIM
		box.set_border_width_all(1)
	draw_style_box(box, r)
