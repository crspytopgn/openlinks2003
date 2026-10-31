class_name LinksPanorama
extends RefCounted
## Panoramic images: a course's horizon (`Panorama` in the .CRZ, `PanNN.btc`
## in PANSKY.LIB) and the cloud skies (`skyNN.btc`). See
## docs/formats/panorama.md; this mirrors libs/olcore/src/panorama.cpp.

const HEADER_BYTES := 20
const TILE_EMPTY := "tpme"
const TILE_USED := "desu"


static func is_panorama(bytes: PackedByteArray) -> bool:
	if bytes.size() < HEADER_BYTES:
		return false
	var tag := bytes.slice(0, 4).get_string_from_ascii()
	return tag == "nap" or tag == "yks"


## True for a cloud sky, false for a horizon.
static func is_sky(bytes: PackedByteArray) -> bool:
	return is_panorama(bytes) and bytes[0] == 0x79  # 'y'


## Edge in pixels of each tile row, top to bottom.
static func row_sizes(height: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var left := height
	while left > 0:
		var s := 256
		if left < 256:
			s = 4
			while s < left:
				s *= 2
		out.append(s)
		left -= mini(left, s)
	return out


## Decodes a whole panorama to RGBA8. Returns null on malformed input.
static func decode(bytes: PackedByteArray) -> Image:
	if not is_panorama(bytes):
		return null
	var width := bytes.decode_u32(4)
	var height := bytes.decode_u32(8)
	var sizes := row_sizes(height)
	if width <= 0 or height <= 0 or width > 32768 or height > 8192 or sizes.size() != bytes.decode_u32(16):
		return null
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var pos := HEADER_BYTES
	var top := 0
	for edge in sizes:
		var across := (width + edge - 1) / edge
		var tb := edge / 4
		for c in across:
			if pos + 4 > bytes.size():
				return null
			var tag := bytes.slice(pos, pos + 4).get_string_from_ascii()
			if tag == TILE_EMPTY:
				pos += 4
				continue
			if tag != TILE_USED or pos + 8 > bytes.size():
				return null
			var length := bytes.decode_u32(pos + 4)
			pos += 8
			if length > bytes.size() - pos:
				return null
			var blocks := PackedByteArray()
			if Btcv.decode_runs(bytes, pos, tb * tb, blocks) != pos + length:
				return null
			pos += length
			var tile := Btcv.dxt5_to_image(blocks, tb, tb, edge, edge)
			if tile == null:
				return null
			# The last tile row is cropped at the bottom, the last column on the right.
			var w := mini(edge, width - c * edge)
			var h := mini(edge, height - top)
			img.blit_rect(tile, Rect2i(0, 0, w, h), Vector2i(c * edge, top))
		top += edge
	if pos != bytes.size():
		return null
	return img


## A custom sky from the 1.07 patch (`skies/<name>.sky`, an ARC0 archive of
## square TGA tiles `_s_k_y_1.tga`, `_s_k_y_2.tga`, ... laid out like a sky
## panorama's), assembled to RGBA8: as tall as its tile rows and as wide as
## the narrowest row. Mirrors olcore::decode_sky_archive. Null on error.
static func decode_sky_archive(sky: Arc0) -> Image:
	if sky == null:
		return null
	var tiles: Array[Image] = []
	while true:
		var entry := "_s_k_y_%d.tga" % (tiles.size() + 1)
		if sky.find(entry) < 0:
			break
		var tile := Image.new()
		if tile.load_tga_from_buffer(sky.read_named(entry)) != OK or tile.get_width() != tile.get_height() or tile.get_width() < 4:
			return null
		tile.convert(Image.FORMAT_RGBA8)
		tiles.append(tile)
	if tiles.is_empty():
		return null
	# Rows: runs of tiles with the same edge, as [first, count, edge].
	var rows: Array[PackedInt32Array] = []
	for i in tiles.size():
		var edge := tiles[i].get_width()
		if rows.is_empty() or rows.back()[2] != edge:
			rows.append(PackedInt32Array([i, 0, edge]))
		rows.back()[1] += 1
	var width := 0
	var height := 0
	for r in rows:
		width = r[1] * r[2] if width == 0 else mini(width, r[1] * r[2])
		height += r[2]
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var top := 0
	for r in rows:
		for c in r[1]:
			var x := c * r[2]
			if x < width:
				img.blit_rect(tiles[r[0] + c], Rect2i(0, 0, mini(r[2], width - x), r[2]), Vector2i(x, top))
		top += r[2]
	return img
