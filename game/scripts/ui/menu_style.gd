class_name MenuStyle
extends RefCounted
## Shared look for the menus: dark green panels, large buttons.

const BACKGROUND := Color(0.07, 0.16, 0.10)
const PANEL := Color(0.08, 0.12, 0.09, 0.94)
const ACCENT := Color(0.95, 0.85, 0.35)
const WARNING := Color(1.0, 0.6, 0.45)


static func panel(p: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", style)


static func heading(text: String, font_size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", ACCENT)
	return l


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 18)
	return b
