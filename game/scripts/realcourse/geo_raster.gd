class_name GeoRaster
extends RefCounted
## A grid of heights in latitude and longitude (EPSG:4326), as national
## elevation services return them: a GeoTIFF (WCS or ArcGIS exportImage)
## or a raw float BIL (WMS). Rows run north to south. Pixels are areas: the
## first pixel's north-west corner is at (north, west).

var width := 0
var height := 0
var data := PackedFloat32Array()
var west := 0.0
var north := 0.0
var dlon := 0.0  ## degrees per pixel, east
var dlat := 0.0  ## degrees per pixel, south (positive)
var nodata := NAN


## Covers this latitude and longitude.
func covers(lat: float, lon: float) -> bool:
	return lon >= west and lon < west + width * dlon and lat <= north and lat > north - height * dlat


## Height at a point, bilinear between pixel centres; NAN where the
## service has no data (or outside the raster).
func sample(lat: float, lon: float) -> float:
	if width < 2 or height < 2:
		return NAN
	var u := clampf((lon - west) / dlon - 0.5, 0.0, width - 1.001)
	var v := clampf((north - lat) / dlat - 0.5, 0.0, height - 1.001)
	var i := int(u)
	var j := int(v)
	var k := j * width + i
	var a := data[k]
	var b := data[k + 1]
	var c := data[k + width]
	var d := data[k + width + 1]
	if not (_ok(a) and _ok(b) and _ok(c) and _ok(d)):
		return NAN
	var fu := u - i
	var fv := v - j
	return lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv)


## Share of pixels with data, 0 to 1.
func valid_fraction() -> float:
	if data.is_empty():
		return 0.0
	var step := maxi(1, floori(data.size() / 20000.0))
	var n := 0
	var total := 0
	for k in range(0, data.size(), step):
		total += 1
		if _ok(data[k]):
			n += 1
	return float(n) / total


## Latitude and longitude of the centre of pixel (i, j).
func pixel_lat(j: int) -> float:
	return north - (j + 0.5) * dlat


func pixel_lon(i: int) -> float:
	return west + (i + 0.5) * dlon


func _ok(h: float) -> bool:
	# Services mark gaps with a nodata value, or with huge or tiny numbers.
	return not is_nan(h) and h > -1000.0 and h < 9000.0 and (is_nan(nodata) or not is_equal_approx(h, nodata))


## A raw little-endian float32 BIL covering exactly (south, west, north, east).
static func from_bil(bytes: PackedByteArray, w: int, h: int, box: Array) -> GeoRaster:
	if bytes.size() != w * h * 4:
		return null
	var r := GeoRaster.new()
	r.width = w
	r.height = h
	r.data = bytes.to_float32_array()
	r.west = box[1]
	r.north = box[2]
	r.dlon = (float(box[3]) - float(box[1])) / w
	r.dlat = (float(box[2]) - float(box[0])) / h
	return r


## A Japanese GSI elevation tile (PNG, 256 px, web mercator) covering
## exactly (south, west, north, east). Its colour is the height in
## centimetres, (R << 16 | G << 8 | B), as a signed 24-bit number; 2^23 is
## no data. Over one tile web mercator is as good as linear in latitude
## (well under a pixel), so it is stored as an ordinary grid.
static func from_gsi_png(bytes: PackedByteArray, box: Array) -> GeoRaster:
	var img := Image.new()
	if bytes.size() < 8 or bytes.slice(0, 4) != PackedByteArray([0x89, 0x50, 0x4E, 0x47]):
		return null
	if img.load_png_from_buffer(bytes) != OK or img.get_width() != 256 or img.get_height() != 256:
		return null
	img.convert(Image.FORMAT_RGB8)
	var rgb := img.get_data()
	var r := GeoRaster.new()
	r.width = 256
	r.height = 256
	r.nodata = -9999.0
	r.data.resize(256 * 256)
	for k in 256 * 256:
		var v := (rgb[k * 3] << 16) | (rgb[k * 3 + 1] << 8) | rgb[k * 3 + 2]
		if v == 0x800000:
			r.data[k] = -9999.0
		else:
			r.data[k] = (v - 0x1000000 if v > 0x800000 else v) * 0.01
	r.west = box[1]
	r.north = box[2]
	r.dlon = (float(box[3]) - float(box[1])) / 256.0
	r.dlat = (float(box[2]) - float(box[0])) / 256.0
	return r


## A single-band GeoTIFF in EPSG:4326: either byte order, 32-bit float or
## 16-bit integer or 8-bit unsigned samples, uncompressed or Deflate, in strips or tiles, with
## its position from ModelPixelScale + ModelTiepoint or ModelTransformation.
## Null for anything else.
static func from_tiff(b: PackedByteArray) -> GeoRaster:
	if b.size() < 16 or not ((b[0] == 0x49 and b[1] == 0x49) or (b[0] == 0x4D and b[1] == 0x4D)):
		return null
	var be := b[0] == 0x4D
	if _u16(b, 2, be) != 42:
		return null
	var ifd := _u32(b, 4, be)
	if ifd + 2 > b.size():
		return null
	var tags := {}
	var n := _u16(b, ifd, be)
	for t in n:
		var e := ifd + 2 + t * 12
		if e + 12 > b.size():
			return null
		tags[_u16(b, e, be)] = _tag_values(b, e, be)
	var w := _first(tags, 256)
	var h := _first(tags, 257)
	var bits := _first(tags, 258, 32)
	var compression := _first(tags, 259, 1)
	var fmt := _first(tags, 339, 1)
	var spp := _first(tags, 277, 1)
	var predictor := _first(tags, 317, 1)
	if w <= 0 or h <= 0 or spp != 1 or not predictor in [1, 3] or not compression in [1, 8, 32946]:
		return null
	var kind := ""
	if bits == 32 and fmt == 3:
		kind = "f32"
	elif bits == 16 and fmt == 2:
		kind = "s16"
	elif bits == 16 and fmt == 1:
		kind = "u16"
	elif bits == 8 and fmt == 1:
		kind = "u8"  # class codes (land cover)
	else:
		return null
	if predictor == 3 and kind != "f32":
		return null
	var r := GeoRaster.new()
	r.width = w
	r.height = h
	r.data.resize(w * h)
	var bpp := bits >> 3
	# Blocks: tiles, or strips as full-width tiles.
	var bw := w
	var bh := _first(tags, 278, h)
	var offsets: Array = tags.get(273, [])
	var counts: Array = tags.get(279, [])
	if tags.has(322):
		bw = _first(tags, 322)
		bh = _first(tags, 323)
		offsets = tags.get(324, [])
		counts = tags.get(325, [])
	if bw <= 0 or bh <= 0 or offsets.is_empty() or offsets.size() != counts.size():
		return null
	var across := ceili(float(w) / bw)
	for k in offsets.size():
		var o: int = offsets[k]
		var c: int = counts[k]
		if o + c > b.size():
			return null
		var block := b.slice(o, o + c)
		if compression != 1:
			block = block.decompress_dynamic(bw * bh * bpp * 2, FileAccess.COMPRESSION_DEFLATE)
		if predictor == 3:
			block = _undo_float_predictor(block, bw, bpp)
		elif be:
			block = _swap(block, bpp)
		var x0 := (k % across) * bw
		var y0 := floori(float(k) / across) * bh
		var rows := mini(bh, h - y0)
		var vals: PackedFloat32Array
		if kind == "f32":
			vals = block.to_float32_array()
		elif kind == "u8":
			vals = PackedFloat32Array()
			vals.resize(block.size())
			for q in block.size():
				vals[q] = block[q]
		else:
			vals = PackedFloat32Array()
			vals.resize(block.size() >> 1)
			for q in vals.size():
				vals[q] = block.decode_s16(q * 2) if kind == "s16" else block.decode_u16(q * 2)
		for y in rows:
			var cols := mini(bw, w - x0)
			var src := y * bw
			if src + cols > vals.size():
				return null
			var dst := (y0 + y) * w + x0
			for x in cols:
				r.data[dst + x] = vals[src + x]
	if tags.has(42113):
		var s := str(tags[42113][0]).strip_edges()
		if s.is_valid_float():
			r.nodata = s.to_float()
	if tags.has(33550) and tags.has(33922):
		var scale: Array = tags[33550]
		var tie: Array = tags[33922]
		r.dlon = scale[0]
		r.dlat = scale[1]
		r.west = float(tie[3]) - float(tie[0]) * r.dlon
		r.north = float(tie[4]) + float(tie[1]) * r.dlat
	elif tags.has(34264):
		var m: Array = tags[34264]
		if absf(m[1]) > 1e-12 or absf(m[4]) > 1e-12:
			return null  # rotated
		r.dlon = m[0]
		r.dlat = -float(m[5])
		r.west = m[3]
		r.north = m[7]
	else:
		return null
	if r.dlon <= 0.0 or r.dlat <= 0.0:
		return null
	return r


## TIFF predictor 3 (floating point): each row's bytes are differenced,
## then split into planes, most significant byte first whatever the file's
## byte order, so the result is always little-endian.
static func _undo_float_predictor(block: PackedByteArray, w: int, bpp: int) -> PackedByteArray:
	var row_bytes := w * bpp
	var out := PackedByteArray()
	out.resize(block.size())
	var rows := floori(float(block.size()) / row_bytes)
	for y in rows:
		var o := y * row_bytes
		var acc := 0
		for k in row_bytes:
			acc = (acc + block[o + k]) & 0xFF
			block[o + k] = acc
		for x in w:
			for b in bpp:
				out[o + x * bpp + b] = block[o + (bpp - b - 1) * w + x]
	return out


## Byte-swaps every `size`-byte value (big-endian samples to little).
static func _swap(block: PackedByteArray, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(block.size())
	for k in range(0, block.size() - size + 1, size):
		for q in size:
			out[k + q] = block[k + size - 1 - q]
	return out


static func _u16(b: PackedByteArray, o: int, be: bool) -> int:
	return (b[o] << 8 | b[o + 1]) if be else b.decode_u16(o)


static func _u32(b: PackedByteArray, o: int, be: bool) -> int:
	return (b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3]) if be else b.decode_u32(o)


## A little-endian copy of `size` bytes at `o`, for decode_*.
static func _le(b: PackedByteArray, o: int, size: int, be: bool) -> PackedByteArray:
	var s := b.slice(o, o + size)
	if be:
		s.reverse()
	return s


static func _first(tags: Dictionary, tag: int, default := 0) -> int:
	var v: Array = tags.get(tag, [])
	return int(v[0]) if not v.is_empty() else default


## The values of the IFD entry at `e` (offset into `b`).
static func _tag_values(b: PackedByteArray, e: int, be: bool) -> Array:
	var type := _u16(b, e + 2, be)
	var count := _u32(b, e + 4, be)
	var size: int = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 11: 4, 12: 8, 16: 8}.get(type, 1)
	var at := e + 8 if size * count <= 4 else _u32(b, e + 8, be)
	if at + size * count > b.size() or count > 1 << 20:
		return []
	if type == 2:
		return [b.slice(at, at + count).get_string_from_ascii()]
	var out: Array = []
	for k in count:
		var p := at + k * size
		match type:
			3:
				out.append(_u16(b, p, be))
			4:
				out.append(_u32(b, p, be))
			5:
				out.append(float(_u32(b, p, be)) / maxf(_u32(b, p + 4, be), 1.0))
			11:
				out.append(_le(b, p, 4, be).decode_float(0))
			12:
				out.append(_le(b, p, 8, be).decode_double(0))
			16:
				out.append(_le(b, p, 8, be).decode_u64(0))
			_:
				out.append(b[p])
	return out
