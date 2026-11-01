class_name GlassTheme
extends RefCounted
## The theme every menu and dialog uses (installed as the default at boot):
## Inter type, pill-shaped buttons and lists, rounded fields and glass
## panels (Glass). Inter is an open font (SIL OFL, assets/fonts).

const FONT_PATH := "res://assets/fonts/InterVariable.woff2"
const TEXT := Color(0.96, 0.97, 0.98)
const TEXT_DIM := Color(0.96, 0.97, 0.98, 0.62)
const FILL := Color(1, 1, 1, 0.1)
const FILL_HOVER := Color(1, 1, 1, 0.18)
const FILL_PRESSED := Color(1, 1, 1, 0.28)
const FILL_DISABLED := Color(1, 1, 1, 0.05)
const FOCUS := Color(1, 1, 1, 0.7)
const FONT_SIZE := 17

static var _theme: Theme
static var _fonts := {}


## Inter at `weight` (400 regular, 600 semibold, 700 bold); the default font
## if the file is missing.
static func font(weight := 400) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var f: Font = ThemeDB.fallback_font
	if ResourceLoader.exists(FONT_PATH):
		var base := load(FONT_PATH) as Font
		if base != null:
			var v := FontVariation.new()
			v.base_font = base
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
			f = v
	_fonts[weight] = f
	return f


## Makes the glass theme the default for every control, including those
## under a CanvasLayer (the HUD), which a window's theme doesn't reach.
static func install() -> void:
	var t := build()
	var d := ThemeDB.get_default_theme()
	if d.has_meta(&"glass"):
		return
	d.merge_with(t)
	d.default_font = t.default_font
	d.default_font_size = t.default_font_size
	d.set_meta(&"glass", true)


static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = FONT_SIZE
	for type in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, _pill(FILL))
		t.set_stylebox("hover", type, _pill(FILL_HOVER))
		t.set_stylebox("pressed", type, _pill(FILL_PRESSED))
		t.set_stylebox("hover_pressed", type, _pill(FILL_PRESSED))
		t.set_stylebox("disabled", type, _pill(FILL_DISABLED))
		t.set_stylebox("focus", type, _focus())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(TEXT, 0.35))
	for type in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, _pill(Color(0, 0, 0, 0)))
	t.set_stylebox("panel", "PanelContainer", Glass.panel_style())
	t.set_stylebox("panel", "Panel", Glass.panel_style())
	var popup := Glass.panel_style(16, 8)
	popup.bg_color = Color(Glass.TINT, 0.94)
	popup.border_color = Glass.RIM
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "TooltipPanel", popup)
	t.set_stylebox("hover", "PopupMenu", _pill(FILL_HOVER, 10, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 8)
	var field := _pill(Color(1, 1, 1, 0.08), 12, 10)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", _focus(12))
	t.set_stylebox("read_only", "LineEdit", _pill(Color(1, 1, 1, 0.04), 12, 10))
	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", _focus(12))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("font_color", "Label", TEXT)
	# Thin rounded scroll bars and sliders.
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _pill(Color(1, 1, 1, 0.05), 6, 0))
		t.set_stylebox("grabber", type, _pill(Color(1, 1, 1, 0.32), 6, 3))
		t.set_stylebox("grabber_highlight", type, _pill(Color(1, 1, 1, 0.5), 6, 3))
		t.set_stylebox("grabber_pressed", type, _pill(Color(1, 1, 1, 0.62), 6, 3))
	for type in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", type, _pill(Color(1, 1, 1, 0.16), 4, 2))
		t.set_stylebox("grabber_area", type, _pill(Color(1, 1, 1, 0.55), 4, 2))
		t.set_stylebox("grabber_area_highlight", type, _pill(Color(1, 1, 1, 0.75), 4, 2))
	var bar := _pill(Color(1, 1, 1, 0.1), 8, 0)
	t.set_stylebox("background", "ProgressBar", bar)
	t.set_stylebox("fill", "ProgressBar", _pill(Color(1, 1, 1, 0.75), 8, 0))
	t.set_stylebox("panel", "TabContainer", Glass.panel_style())
	t.set_stylebox("tab_selected", "TabContainer", _pill(FILL_PRESSED, 14, 8))
	t.set_stylebox("tab_unselected", "TabContainer", _pill(Color(0, 0, 0, 0), 14, 8))
	t.set_stylebox("tab_hovered", "TabContainer", _pill(FILL_HOVER, 14, 8))
	_theme = t
	return t


## A rounded fill: a pill for a button (the radius caps at half its height).
static func _pill(fill: Color, radius := 999, margin_v := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.content_margin_left = 18 if radius > 20 else 12
	s.content_margin_right = s.content_margin_left
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = true
	return s


## The keyboard and pad focus ring: a light outline round the pill.
static func _focus(radius := 999) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = FOCUS
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.anti_aliasing = true
	return s
