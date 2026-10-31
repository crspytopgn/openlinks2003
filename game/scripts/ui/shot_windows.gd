class_name ShotWindows
extends Control
## The original's information windows, from the player's GRAPHICS.LS: wind
## (WINDDIR.TGA's arrow), elevation to the aim point (ELEVnn.TGA) and the
## lie, each in a stone-framed window from LIEBOX.TGA, lettered in the
## game's own font.

const WIDTH := 150.0
const WIND_HEIGHT := 58.0
const ELEVATION_HEIGHT := 112.0
const LIE_HEIGHT := 58.0
const GAP := 6.0
const ARROW_SCALE := 2.5
const TEXT := Color(1.0, 0.93, 0.62)
const LABEL := Color(0.75, 0.8, 0.75)

var art: HudArt
var _wind_calm := true
var _wind_mph := 0.0
var _wind_rel_deg := 0.0
var _rise_m := 0.0
var _lie := ""
var _lie_power := 1.0


func _init(hud_art: HudArt) -> void:
	art = hud_art
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = wanted_size()


static func wanted_size() -> Vector2:
	return Vector2(WIDTH, WIND_HEIGHT + GAP + ELEVATION_HEIGHT + GAP + LIE_HEIGHT)


func show_wind(wind: Wind, aim_deg: float) -> void:
	_wind_calm = wind.is_calm()
	_wind_mph = wind.speed_mph()
	_wind_rel_deg = wind.relative_deg(aim_deg)
	queue_redraw()


## `rise_m`: how far the aim point is above the ball. `lie_power`: the share
## of full distance the lie allows.
func show_shot(rise_m: float, lie_name: String, lie_power: float) -> void:
	_rise_m = rise_m
	_lie = lie_name
	_lie_power = lie_power
	queue_redraw()


func _draw() -> void:
	var font := art.text_font()
	var fs := HudArt.font_size(font, 16)
	var small: Font = art.small_font if art.small_font != null else font
	var sfs := HudArt.font_size(small, 13)

	var wind := _window(Rect2(0, 0, WIDTH, WIND_HEIGHT), "Wind", small, sfs)
	var text := "Calm"
	if not _wind_calm:
		text = "%d mph" % roundi(_wind_mph)
		var c := Vector2(wind.position.x + wind.size.y * 0.5, wind.get_center().y)
		if art.wind_arrow != null:
			# The arrow points up the screen (downrange); turn it to the wind.
			var half := art.wind_arrow.get_size() * 0.5
			draw_set_transform(c, -deg_to_rad(_wind_rel_deg), Vector2(ARROW_SCALE, ARROW_SCALE))
			draw_texture(art.wind_arrow, -half)
			draw_set_transform_matrix(Transform2D.IDENTITY)
	_value(wind, text, font, fs)

	var y := WIND_HEIGHT + GAP
	var elev := _window(Rect2(0, y, WIDTH, ELEVATION_HEIGHT), "Elevation", small, sfs)
	if not art.elevations.is_empty():
		var src := HudArt.ELEVATION
		var pic_h := elev.size.y - font.get_height(fs)
		var s := minf(elev.size.x / src.size.x, pic_h / src.size.y)
		var pic := Rect2(elev.position.x + (elev.size.x - src.size.x * s) * 0.5, elev.position.y, src.size.x * s, src.size.y * s)
		draw_texture_rect_region(art.elevations[HudArt.elevation_index(_rise_m)], pic, src)
	var feet := roundi(_rise_m * 3.28084)
	_value(elev, "Level" if feet == 0 else "%+d ft" % feet, font, fs)

	y += ELEVATION_HEIGHT + GAP
	var lie := _window(Rect2(0, y, WIDTH, LIE_HEIGHT), "Lie", small, sfs)
	_value(lie, "%s  %d%%" % [_lie, roundi(_lie_power * 100.0)], font, fs)


## Draws a window with its label; returns the space left inside for content.
func _window(r: Rect2, label: String, small: Font, sfs: int) -> Rect2:
	if art.box != null:
		art.draw_box(self, r, r.size.y > 50.0)
	else:
		draw_rect(r, Color(0, 0, 0, 0.6))
	var inner := r.grow(-HudArt.BOX_FRAME - 3.0)
	draw_string(small, Vector2(inner.position.x, inner.position.y + small.get_ascent(sfs)), label,
		HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, sfs, LABEL)
	var top := small.get_height(sfs)
	return Rect2(inner.position.x, inner.position.y + top, inner.size.x, inner.size.y - top)


## A value along the bottom right of a window's content.
func _value(r: Rect2, text: String, font: Font, fs: int) -> void:
	draw_string(font, Vector2(r.position.x, r.end.y - font.get_descent(fs)), text, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, fs, TEXT)
