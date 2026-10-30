class_name HudArt
extends RefCounted
## The original in-play interface pieces from the player's GRAPHICS.LS: the
## chrome info bar (CRSINFO.TGA) and the classic swing meter (RIND12.TGA).
## Null from load_from_game() when the player's files aren't there, and the
## HUD keeps its own plain look.
##
## The rectangles are where each piece sits in its sheet, measured from the
## sheets' alpha.

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

var info: Texture2D
var meter: Texture2D


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
	return art


static func _texture(archive: LsArchiveFile, entry: String) -> Texture2D:
	var bytes := archive.read(entry)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_tga_from_buffer(bytes) != OK or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
