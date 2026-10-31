class_name D3fFont
extends RefCounted
## Bitmap fonts (.D3F) from the player's GRAPHICS.LS, made into Godot fonts
## (docs/formats/d3f.md).
##
## Temporary GDScript port of libs/olcore/src/d3f.cpp; keep the two in sync
## until the C++ library is wired in through GDExtension.

const COVERAGE := 0xb4  ## 8 bits a pixel: glyph coverage
const COLOUR := 0xd4  ## 32 bits a pixel: BGRA
const TABLES := 0x55  ## page, x, y, width, left, right: 256 bytes each
const PAGE_LIST := TABLES + 6 * 256
const MAX_PAGES := 64

## Windows-1252 characters 0x80 to 0x9f; the rest of the codes are Latin-1.
const CP1252 := [0x20ac, 0, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021, 0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017d, 0,
	0, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014, 0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0, 0x017e, 0x0178]

var face := ""
var pixel_height := 0
var italic := false
var weight := 400
var line_height := 0
var colour := false
## Per character code: [page, x, y, width, left, right].
var glyphs: Array[PackedInt32Array] = []
var pages: Array[Image] = []


static func is_d3f(bytes: PackedByteArray) -> bool:
	return bytes.size() > PAGE_LIST and bytes[0] == 0x44 and bytes[1] == 0x33 and bytes[2] == 0x46 \
		and (bytes[3] == COVERAGE or bytes[3] == COLOUR)


## Null if the bytes aren't a D3F font or are damaged.
static func read(bytes: PackedByteArray) -> D3fFont:
	if not is_d3f(bytes):
		return null
	var f := D3fFont.new()
	f.colour = bytes[3] == COLOUR
	var end := 4
	while end < 0x44 and bytes[end] != 0:
		end += 1
	f.face = bytes.slice(4, end).get_string_from_ascii()
	f.pixel_height = absi(bytes.decode_s32(0x44))
	f.italic = bytes[0x48] != 0
	f.weight = bytes.decode_s32(0x49)
	var page_count := bytes.decode_s32(0x4d)
	f.line_height = bytes.decode_s32(0x51)
	if page_count < 1 or page_count > MAX_PAGES or f.line_height < 1 or f.line_height > 255:
		return null
	if PAGE_LIST + page_count * 4 > bytes.size():
		return null
	for c in 256:
		f.glyphs.append(PackedInt32Array([bytes[TABLES + c], bytes[TABLES + 256 + c], bytes[TABLES + 512 + c],
			bytes[TABLES + 768 + c], bytes.decode_s8(TABLES + 1024 + c), bytes.decode_s8(TABLES + 1280 + c)]))
	var bpp := 4 if f.colour else 1
	for i in page_count:
		var at := bytes.decode_s32(PAGE_LIST + i * 4)
		if at < 0 or at + 8 > bytes.size():
			return null
		var side := absi(bytes.decode_s32(at))
		var packed := bytes.decode_s32(at + 4)
		if side < 1 or side > 1024 or packed < 0 or at + 8 + packed > bytes.size():
			return null
		var count := side * side
		# Streams may end early; the rest of the page is empty.
		var px := LsArchiveFile.lzw_decompress(bytes.slice(at + 8, at + 8 + packed), count * bpp)
		px.resize(count * bpp)
		var img: Image
		if f.colour:
			var rgba := PackedByteArray()
			rgba.resize(count * 4)
			for p in count:
				rgba[p * 4] = px[p * 4 + 2]
				rgba[p * 4 + 1] = px[p * 4 + 1]
				rgba[p * 4 + 2] = px[p * 4]
				rgba[p * 4 + 3] = px[p * 4 + 3]
			img = Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, rgba)
		else:
			# White, with the coverage as alpha, so the text takes its colour.
			var rgba := PackedByteArray()
			rgba.resize(count * 4)
			rgba.fill(255)
			for p in count:
				rgba[p * 4 + 3] = px[p]
			img = Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, rgba)
		f.pages.append(img)
	return f


## Pixels from the top of a cell to the baseline: the row under the lowest
## visible pixel of "H" (or of the first capital present).
@warning_ignore("integer_division")
func ascent() -> int:
	for ch in "HIEFTLA":
		var g := glyphs[ch.unicode_at(0)]
		if g[3] == 0 or g[0] >= pages.size():
			continue
		var img := pages[g[0]]
		for row in range(line_height - 1, -1, -1):
			var y := g[2] + row
			if y >= img.get_height():
				continue
			for x in range(g[1], mini(g[1] + g[3], img.get_width())):
				if img.get_pixel(x, y).a8 > 64:
					return row + 1
	return (line_height * 4 + 2) / 5


## The character a code stands for, or 0 for codes with none.
static func char_of(code: int) -> int:
	if code >= 0x80 and code < 0xa0:
		return CP1252[code - 0x80]
	return code


## A Godot font drawing these bitmaps at `pixel_height` (set the font size
## to it for pixel-exact text). Characters the font lacks come from `fallback`.
func to_font(fallback: Font = null) -> FontFile:
	var ff := FontFile.new()
	ff.fixed_size = pixel_height
	ff.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	ff.font_name = face
	ff.font_style = (TextServer.FONT_BOLD if weight >= 600 else 0) | (TextServer.FONT_ITALIC if italic else 0)
	var size := Vector2i(pixel_height, 0)
	var up := ascent()
	ff.set_cache_ascent(0, pixel_height, up)
	ff.set_cache_descent(0, pixel_height, line_height - up)
	for i in pages.size():
		ff.set_texture_image(0, size, i, pages[i])
	for code in range(0x20, 256):
		var g := glyphs[code]
		var ch := char_of(code)
		if g[3] == 0 or ch == 0 or g[0] >= pages.size():
			continue
		ff.set_glyph_advance(0, pixel_height, ch, Vector2(g[4] + g[3] + g[5], 0))
		ff.set_glyph_offset(0, size, ch, Vector2(g[4], -up))
		ff.set_glyph_size(0, size, ch, Vector2(g[3], line_height))
		ff.set_glyph_uv_rect(0, size, ch, Rect2(g[1], g[2], g[3], line_height))
		ff.set_glyph_texture_idx(0, size, ch, g[0])
	if fallback != null:
		var fallbacks: Array[Font] = [fallback]
		ff.fallbacks = fallbacks
	return ff


## Reads `entry` from an archive and makes it a font; null if it isn't there.
static func load_font(archive: LsArchiveFile, entry: String, fallback: Font = null) -> FontFile:
	if archive == null:
		return null
	var f := read(archive.read(entry))
	return null if f == null else f.to_font(fallback)
