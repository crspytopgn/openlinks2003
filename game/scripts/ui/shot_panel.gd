class_name ShotPanel
extends Control
## The club side of the original interface, from the player's GRAPHICS.LS:
## the PowerStroke title bar, the row for the club's kind (wood, iron or
## putter) with the club's name and reach in a window beside it, and under
## them the swing indicator gizmo with the club at the ball.

const GIZMO_SCALE := 0.8
const GAP := 4.0
const TEXT_BOX_WIDTH := 170.0
const TEXT := Color(1.0, 0.93, 0.62)
const LABEL := Color(0.75, 0.8, 0.75)

var art: HudArt
var kind := 0
var club_name := ""
var reach_text := ""


func _init(hud_art: HudArt) -> void:
	art = hud_art
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = wanted_size()


func wanted_size() -> Vector2:
	var title := HudArt.POWERSTROKE_TITLE.size
	var row := HudArt.POWERSTROKE_ROWS[0].size
	var gizmo := HudArt.GIZMO.size * GIZMO_SCALE
	return Vector2(maxf(maxf(title.x, gizmo.x), row.x + GAP + TEXT_BOX_WIDTH), title.y + GAP + row.y + GAP + gizmo.y)


func show_club(p_kind: int, p_name: String, p_reach: String) -> void:
	if p_kind == kind and p_name == club_name and p_reach == reach_text:
		return
	kind = p_kind
	club_name = p_name
	reach_text = p_reach
	queue_redraw()


func _draw() -> void:
	var y := 0.0
	if art.powerstroke != null:
		var title := HudArt.POWERSTROKE_TITLE
		draw_texture_rect_region(art.powerstroke, Rect2(Vector2.ZERO, title.size), title)
		y += title.size.y + GAP
		var row := HudArt.POWERSTROKE_ROWS[kind]
		draw_texture_rect_region(art.powerstroke, Rect2(Vector2(0, y), row.size), row)
		var box := Rect2(row.size.x + GAP, y, TEXT_BOX_WIDTH, row.size.y)
		_text_box(box)
		y += row.size.y + GAP
	var kinds := HudArt.GIZMO_KINDS
	var sheet: Texture2D = art.gizmos.get(kinds[kind])
	if sheet != null:
		draw_texture_rect_region(sheet, Rect2(Vector2(0, y), HudArt.GIZMO.size * GIZMO_SCALE), HudArt.GIZMO)


## The club's name and reach in a stone window, or on a shaded strip
## without LIEBOX.TGA.
func _text_box(box: Rect2) -> void:
	if art.box != null:
		art.draw_box(self, box, true)
	else:
		draw_rect(box, Color(0, 0, 0, 0.6))
	var font := art.text_font()
	var fs := HudArt.font_size(font, 16)
	var small: Font = art.small_font if art.small_font != null else font
	var sfs := HudArt.font_size(small, 13)
	var inner := box.grow(-HudArt.BOX_FRAME - 4.0)
	var baseline := inner.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(inner.position.x, baseline), club_name, HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, fs, TEXT)
	draw_string(small, Vector2(inner.position.x, baseline), reach_text, HORIZONTAL_ALIGNMENT_RIGHT, inner.size.x, sfs, LABEL)
