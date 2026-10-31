class_name InfoBar
extends Control
## One line of shot information on the original's chrome bar (CRSINFO.TGA
## from the player's GRAPHICS.LS): the end cap, then the bar fading out,
## lettered in the game's own font when the archive has it.

const SCALE := 0.8
const FONT_SIZE := 16
const TEXT := Color(1.0, 0.93, 0.62)

var art: HudArt
var text := "":
	set(value):
		if value != text:
			text = value
			queue_redraw()


func _init(hud_art: HudArt) -> void:
	art = hud_art
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2((HudArt.INFO_BAR.size.x + HudArt.INFO_FADE.size.x) * SCALE, HudArt.INFO_BAR.size.y * SCALE)
	size = custom_minimum_size


func _draw() -> void:
	var font := art.text_font()
	var fs := HudArt.font_size(font, FONT_SIZE)
	var bar := HudArt.INFO_BAR
	var fade := HudArt.INFO_FADE
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# Stretch the plain part of the bar so long lines still fit, then fade.
	var display_left := HudArt.INFO_DISPLAY_LEFT * SCALE
	var body := maxf(bar.size.x * SCALE, display_left + text_w + 24.0)
	var h := bar.size.y * SCALE
	var plain := Rect2(bar.position.x + bar.size.x - 40.0, bar.position.y, 40.0, bar.size.y)
	draw_texture_rect_region(art.info, Rect2(0, 0, bar.size.x * SCALE, h), bar)
	if body > bar.size.x * SCALE:
		draw_texture_rect_region(art.info, Rect2(bar.size.x * SCALE - 1.0, 0, body - bar.size.x * SCALE + 1.0, h), plain)
	draw_texture_rect_region(art.info, Rect2(body - 1.0, 0, fade.size.x * SCALE, h), fade)
	var top := HudArt.INFO_DISPLAY_TOP * SCALE
	var bottom := HudArt.INFO_DISPLAY_BOTTOM * SCALE
	var baseline := (top + bottom) * 0.5 + font.get_ascent(fs) * 0.38
	draw_string(font, Vector2(display_left + 8.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)
