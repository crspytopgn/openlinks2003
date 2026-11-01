extends RefCounted
## The launcher's look: Apple's dark style in the colours of the brand
## (docs/brand/README.md): Inter Display, near-black with green and blue
## glows, frosted "Liquid Glass" panels and capsule buttons. Builds the Theme
## and the few controls Godot doesn't have (a switch, a segmented control,
## a glass panel).

const TEXT := Color("#F5F5F7")
const TEXT_2 := Color("#A1A1A6")
const TEXT_3 := Color("#6E6E73")
const GREEN := Color("#30B94D")
const GREEN_HI := Color("#3FD15E")
const BLUE := Color("#0A84FF")
const RED := Color("#FF6961")
const ORANGE := Color("#FFB340")
const FILL := Color(1, 1, 1, 0.08)
const FILL_HOVER := Color(1, 1, 1, 0.14)
const FILL_PRESSED := Color(1, 1, 1, 0.20)
const HAIRLINE := Color(1, 1, 1, 0.08)

static var _fonts := {}
static var _textures := {}


## Inter Display at `weight` (Light, Regular, Medium, SemiBold). Imported in
## an exported build; read straight from the file when run from source
## without an import (tests, a template binary).
static func font(weight := "Regular") -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var path := "res://assets/fonts/InterDisplay-%s.woff2" % weight
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null:
		var ff := FontFile.new()
		ff.data = FileAccess.get_file_as_bytes(path)
		ff.hinting = TextServer.HINTING_LIGHT
		f = ff
	_fonts[weight] = f
	return f


static func texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null:
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_textures[path] = t
	return t


static func box(color: Color, radius := 12, margin_h := 14.0, margin_v := 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = true
	return s


## A filled circle (or capsule end) image for slider grabbers and the like.
static func _circle(diameter: int, color: Color, shadow := false) -> ImageTexture:
	var pad := 4 if shadow else 0
	var n := diameter + pad * 2
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) / 2.0
	var r := diameter / 2.0
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var px := Color(color, color.a * a)
			if shadow and a < 1.0:
				var sh := clampf(1.0 - (d - r) / pad, 0.0, 1.0) * 0.35
				px = Color(0, 0, 0, sh).blend(px)
			img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)


## A small downward chevron for option buttons.
static func _chevron() -> ImageTexture:
	var img := Image.create(12, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 12:
			var u := x + 0.5
			var v := y + 0.5
			var line := absf(v - (6.5 - absf(u - 6.0))) # distance to the V
			img.set_pixel(x, y, Color(TEXT_2, clampf(1.4 - line, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("Regular")
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)

	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(FILL, 99, 18, 9))
		t.set_stylebox("hover", type, box(FILL_HOVER, 99, 18, 9))
		t.set_stylebox("pressed", type, box(FILL_PRESSED, 99, 18, 9))
		t.set_stylebox("hover_pressed", type, box(FILL_PRESSED, 99, 18, 9))
		t.set_stylebox("disabled", type, box(Color(1, 1, 1, 0.04), 99, 18, 9))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, TEXT_3)
		t.set_font("font", type, font("Medium"))
		t.set_font_size("font_size", type, 14)
	t.set_icon("arrow", "OptionButton", _chevron())
	t.set_constant("arrow_margin", "OptionButton", 12)

	var popup := box(Color(0.11, 0.11, 0.12, 0.98), 12, 6, 6)
	popup.border_color = Color(1, 1, 1, 0.10)
	popup.set_border_width_all(1)
	popup.shadow_color = Color(0, 0, 0, 0.5)
	popup.shadow_size = 18
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(Color(GREEN, 0.85), 7, 8, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", font("Regular"))
	t.set_font_size("font_size", "PopupMenu", 14)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 14)
	t.set_icon("radio_checked", "PopupMenu", _circle(7, TEXT))
	t.set_icon("radio_unchecked", "PopupMenu", ImageTexture.create_from_image(Image.create(7, 7, false, Image.FORMAT_RGBA8)))

	var track := box(Color(1, 1, 1, 0.14), 3, 0, 2)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(GREEN, 3, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GREEN_HI, 3, 0, 2))
	t.set_icon("grabber", "HSlider", _circle(20, Color.WHITE, true))
	t.set_icon("grabber_highlight", "HSlider", _circle(20, Color.WHITE, true))
	t.set_icon("grabber_disabled", "HSlider", _circle(20, Color(1, 1, 1, 0.4), true))

	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0), 3, 3, 0))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.18), 3, 3, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.30), 3, 3, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(Color(1, 1, 1, 0.38), 3, 3, 0))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.12), 99, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(GREEN, 99, 0, 0))
	t.set_font_size("font_size", "ProgressBar", 1)
	t.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))

	var tip := box(Color(0.13, 0.13, 0.14, 0.97), 8, 10, 6)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 13)
	t.set_color("font_color", "LinkButton", BLUE)
	t.set_color("font_hover_color", "LinkButton", Color("#409CFF"))
	t.set_font("font", "LinkButton", font("Medium"))
	t.set_font_size("font_size", "LinkButton", 13)
	return t


static func label(text: String, size := 15, weight := "Regular", color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## The big green capsule (Play, Install).
static func primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 54)
	var n := box(GREEN, 99, 30, 12)
	n.shadow_color = Color(GREEN, 0.35)
	n.shadow_size = 16
	var h := box(GREEN_HI, 99, 30, 12)
	h.shadow_color = Color(GREEN_HI, 0.45)
	h.shadow_size = 22
	var p := box(GREEN.darkened(0.15), 99, 30, 12)
	var d := box(Color(1, 1, 1, 0.10), 99, 30, 12)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_font_override("font", font("SemiBold"))
	b.add_theme_font_size_override("font_size", 19)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", TEXT_2)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## A frosted capsule (Course builder and other second choices).
static func glass_button(text: String, height := 54.0, font_size := 17) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var alpha: float = {"normal": 0.10, "hover": 0.16, "pressed": 0.22, "hover_pressed": 0.22, "disabled": 0.05}[state]
		var s := box(Color(1, 1, 1, alpha), 99, 26, 10)
		s.border_color = Color(1, 1, 1, 0.16 if state != "disabled" else 0.06)
		s.set_border_width_all(1)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_font_override("font", font("Medium"))
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## A small text button in the accent blue.
static func link_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(state, box(Color(0, 0, 0, 0), 6, 0, 2))
	b.add_theme_color_override("font_color", BLUE)
	b.add_theme_color_override("font_hover_color", Color("#409CFF"))
	b.add_theme_color_override("font_pressed_color", Color("#0060DF"))
	b.add_theme_font_override("font", font("Medium"))
	b.add_theme_font_size_override("font_size", 14)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b
