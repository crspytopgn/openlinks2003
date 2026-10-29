class_name Btcv
extends RefCounted
## BTCV textures and DXT5 block runs. See docs/formats/btcv.md; this mirrors
## libs/olcore/src/btcv.cpp. Blocks are assembled into a DXT5 image and
## Image.decompress() turns them into pixels.

const BLOCK_BYTES := 16
const OPAQUE_ALPHA := [0xff, 0, 0, 0, 0, 0, 0, 0]


static func is_btcv(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 20 and bytes.slice(0, 4).get_string_from_ascii() == "BTCV"


## Expands block runs starting at `pos` into `block_count` DXT5 blocks
## appended to `out`. Returns the position after the runs, or -1 on error.
static func decode_runs(bytes: PackedByteArray, pos: int, block_count: int, out: PackedByteArray) -> int:
	var done := 0
	var transparent := PackedByteArray()
	transparent.resize(BLOCK_BYTES)
	var opaque := PackedByteArray(OPAQUE_ALPHA)
	while done < block_count:
		if pos + 2 > bytes.size():
			return -1
		var head := bytes.decode_u16(pos)
		pos += 2
		var n := head & 0xfff
		if n == 0:
			n = 0x1000
		var mode := head >> 12
		if done + n > block_count:
			return -1
		match mode:
			1:
				for i in n:
					out.append_array(transparent)
			2:
				if pos + n * 8 > bytes.size():
					return -1
				for i in n:
					out.append_array(opaque)
					out.append_array(bytes.slice(pos + i * 8, pos + i * 8 + 8))
				pos += n * 8
			3:
				if pos + n * 16 > bytes.size():
					return -1
				out.append_array(bytes.slice(pos, pos + n * 16))
				pos += n * 16
			4:
				if pos + n * 4 > bytes.size():
					return -1
				for i in n:
					var p := pos + i * 4
					# Flat colour as B, G, R, A, rounded to RGB565 like the game does.
					var c := (roundi(bytes[p + 2] * 31 / 255.0) << 11) | (roundi(bytes[p + 1] * 63 / 255.0) << 5) | roundi(bytes[p] * 31 / 255.0)
					out.append_array(opaque)
					out.append_array(PackedByteArray([c & 0xff, c >> 8, 0, 0, 0, 0, 0, 0]))
				pos += n * 4
			_:
				return -1
		done += n
	return pos


## Turns a DXT5 block buffer into an RGBA8 image, cropped to width x height
## from the top-left (crop_top rows skipped first).
static func dxt5_to_image(blocks: PackedByteArray, blocks_wide: int, blocks_high: int, width: int, height: int, crop_top := 0) -> Image:
	var img := Image.create_from_data(blocks_wide * 4, blocks_high * 4, false, Image.FORMAT_DXT5, blocks)
	img.decompress()
	if img.is_compressed():
		push_warning("This build cannot decompress DXT5 textures")
		return null
	img.convert(Image.FORMAT_RGBA8)
	if width != img.get_width() or height != img.get_height():
		img = img.get_region(Rect2i(0, crop_top, width, height))
	return img


## Decodes a whole BTCV texture. Returns null on error.
static func decode(bytes: PackedByteArray) -> Image:
	if not is_btcv(bytes):
		return null
	var width := bytes.decode_u16(4)
	var height := bytes.decode_u16(6)
	var tile_count := bytes.decode_u32(16)
	var bw := (width + 3) / 4
	var bh := (height + 3) / 4
	var row_bytes := bw * BLOCK_BYTES
	var empty_row := PackedByteArray()
	empty_row.resize(row_bytes)
	var rows: Array[PackedByteArray] = []
	for r in bh:
		rows.append(empty_row)
	for t in tile_count:
		var rec := 20 + t * 16
		if rec + 16 > bytes.size():
			return null
		var size := bytes.decode_u16(rec + 2)
		var x := bytes.decode_u16(rec + 4)
		var y := bytes.decode_u16(rec + 6)
		var offset := bytes.decode_u32(rec + 8)
		var tb := size / 4
		var tile := PackedByteArray()
		if decode_runs(bytes, offset, tb * tb, tile) < 0:
			return null
		# Tiles are placed from the bottom left; canvas rows run top down.
		var top := bh - y / 4 - tb
		var left := x / 4
		var cols := mini(tb, bw - left)
		if cols <= 0:
			continue
		for r in tb:
			var row := top + r
			if row < 0 or row >= bh:
				continue
			var src := tile.slice(r * tb * BLOCK_BYTES, (r * tb + cols) * BLOCK_BYTES)
			var line := rows[row]
			var start := left * BLOCK_BYTES
			rows[row] = line.slice(0, start) + src + line.slice(start + src.size())
	var canvas := PackedByteArray()
	for line in rows:
		canvas.append_array(line)
	return dxt5_to_image(canvas, bw, bh, width, height, bh * 4 - height)
