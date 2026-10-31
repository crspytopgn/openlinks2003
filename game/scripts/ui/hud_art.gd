class_name HudArt
extends RefCounted
## The original in-play interface pieces from the player's GRAPHICS.LS: the
## chrome info bar (CRSINFO.TGA), the classic swing meter (RIND12.TGA), the
## swing indicator gizmo (SI*.TGA), the PowerStroke panel (PSTROKE1.TGA),
## the lie and wind windows (LIEBOX.TGA, WINDDIR.TGA), the elevation
## pictures (ELEVnn.TGA) and the game's own fonts (.D3F). Null from load_from_game() when the player's files aren't
## there, and the HUD keeps its own plain look.
##
## The rectangles are where each piece sits in its sheet, measured from the
## sheets' alpha. Where the game puts each piece on screen isn't in the files
## (docs/game-shell.md#the-original-interface).

const ARCHIVE_NAMES := ["GRAPHICS.LS"]

## CRSINFO.TGA: a chrome end cap with a black display, and the same bar
## fading out, to lengthen it.
const INFO_BAR := Rect2(2, 90, 254, 63)
const INFO_FADE := Rect2(0, 189, 163, 63)
## Where the black display starts and ends inside INFO_BAR (rows).
const INFO_DISPLAY_LEFT := 72.0
const INFO_DISPLAY_TOP := 6.0
const INFO_DISPLAY_BOTTOM := 31.0

## RIND12.TGA: the meter's chrome end cap, and a plain stretch of its bar
## (between the sheet's own tick marks) to draw the bar from.
const METER_CAP := Rect2(0, 0, 98, 106)
const METER_BAR := Rect2(168, 47, 48, 16)

## SIGR<club>12.TGA: the oval gizmo with the club at the ball, one sheet per
## club kind (DR driver and woods, IR irons and wedges, PT putter).
const GIZMO := Rect2(1, 2, 254, 151)
const GIZMO_KINDS := ["DR", "IR", "PT"]

## PSTROKE1.TGA: the "PowerStroke" title bar, then a row per club kind
## (woods, irons, putter) with the club head in a black display.
const POWERSTROKE_TITLE := Rect2(0, 0, 243, 28)
const POWERSTROKE_ROWS: Array[Rect2] = [Rect2(0, 37, 129, 46), Rect2(0, 96, 129, 46), Rect2(0, 154, 129, 46)]

## LIEBOX.TGA: a large and a small black window with a stone frame.
const BOX_LARGE := Rect2(0, 0, 68, 54)
const BOX_SMALL := Rect2(0, 54, 49, 39)
## Frame width of both windows, in sheet pixels.
const BOX_FRAME := 4.0

## ELEVnn.TGA, 00 to 12: the ball, the aim point (striped pole) and a flag
## on little islands of turf. 06 is level; 00 has the aim point far above
## the ball, 12 far below.
const ELEVATION := Rect2(8, 12, 110, 84)
const ELEVATION_STEPS := 6

## The game's in-play fonts: SPBT14 for 1024 x 768 and up (spbt10 and
## spbt12 are the smaller screen sizes), SMALL for little labels.
const TEXT_FONT := "SPBT14.D3F"
const SMALL_FONT := "SPBT12.D3F"

var info: Texture2D
var meter: Texture2D
## Club kind ("DR", "IR", "PT") -> gizmo sheet.
var gizmos := {}
var powerstroke: Texture2D
var box: Texture2D
var wind_arrow: Texture2D
var elevations: Array[Texture2D] = []
## Null when the archive has no fonts; draw with the theme font then.
var font: Font
var small_font: Font


static func load_from_game() -> HudArt:
	var path := GameFolder.find_file(PackedStringArray(ARCHIVE_NAMES))
	if path.is_empty():
		return null
	var archive := LsArchiveFile.open(path)
	if archive == null:
		return null
	var art := HudArt.new()
	art.info = _texture(archive, "CRSINFO.TGA")
	art.meter = _texture(archive, "RIND12.TGA")
	if art.info == null or art.meter == null:
		return null
	# The rest is optional: each piece the archive lacks keeps the plain look.
	for kind in GIZMO_KINDS:
		var t := _texture(archive, "SIGR%s12.TGA" % kind)
		if t != null:
			art.gizmos[kind] = t
	art.powerstroke = _texture(archive, "PSTROKE1.TGA")
	art.box = _texture(archive, "LIEBOX.TGA")
	art.wind_arrow = _texture(archive, "WINDDIR.TGA")
	for i in ELEVATION_STEPS * 2 + 1:
		var t := _texture(archive, "ELEV%02d.TGA" % i)
		if t == null:
			art.elevations.clear()
			break
		art.elevations.append(t)
	art.font = D3fFont.load_font(archive, TEXT_FONT, ThemeDB.fallback_font)
	art.small_font = D3fFont.load_font(archive, SMALL_FONT, ThemeDB.fallback_font)
	return art


## Which gizmo and PowerStroke row a club uses: 0 woods, 1 irons and
## wedges, 2 the putter.
static func club_kind(club_name: String, putter: bool) -> int:
	if putter:
		return 2
	if club_name.contains("Wood") or club_name.contains("Driver"):
		return 0
	return 1


## The ELEVnn picture for the aim point `rise_m` above the ball. Each step
## is 5 feet (a guess: the game's step size isn't in the files).
static func elevation_index(rise_m: float) -> int:
	return clampi(ELEVATION_STEPS - roundi(rise_m * 3.28084 / 5.0), 0, ELEVATION_STEPS * 2)


## The game's text font, or the theme's default.
func text_font() -> Font:
	return font if font != null else ThemeDB.fallback_font


## Font size that draws `f` pixel for pixel; `fallback_size` for other fonts.
static func font_size(f: Font, fallback_size: int) -> int:
	if f is FontFile and (f as FontFile).fixed_size > 0:
		return (f as FontFile).fixed_size
	return fallback_size


## Draws a stone-framed window from LIEBOX.TGA stretched over `rect`,
## keeping its frame `scale` sheet pixels wide.
func draw_box(ci: CanvasItem, rect: Rect2, large: bool, scale := 1.0) -> void:
	var src := BOX_LARGE if large else BOX_SMALL
	var m := BOX_FRAME
	var d := BOX_FRAME * scale
	# Nine pieces: corners keep their size, edges and the middle stretch.
	var xs := PackedFloat32Array([src.position.x, src.position.x + m, src.end.x - m, src.end.x])
	var ys := PackedFloat32Array([src.position.y, src.position.y + m, src.end.y - m, src.end.y])
	var dx := PackedFloat32Array([rect.position.x, rect.position.x + d, rect.end.x - d, rect.end.x])
	var dy := PackedFloat32Array([rect.position.y, rect.position.y + d, rect.end.y - d, rect.end.y])
	for j in 3:
		for i in 3:
			var s := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			var t := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			ci.draw_texture_rect_region(box, t, s)


static func _texture(archive: LsArchiveFile, entry: String) -> Texture2D:
	var bytes := archive.read(entry)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_tga_from_buffer(bytes) != OK or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
