class_name MenuStyle
extends RefCounted
## Shared look for the menus: glass panels (Glass), pill buttons
## (GlassTheme), large type.

const BACKGROUND := Color(0.07, 0.16, 0.10)
const PANEL := Color(0.08, 0.12, 0.09, 0.94)
const ACCENT := Color(0.95, 0.85, 0.35)
const WARNING := Color(1.0, 0.6, 0.45)


static func panel(p: PanelContainer) -> void:
	Glass.apply(p, Glass.RADIUS, 22.0)


static func heading(text: String, font_size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_font_override("font", GlassTheme.font(700))
	l.add_theme_color_override("font_color", ACCENT)
	return l


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 18)
	return b
