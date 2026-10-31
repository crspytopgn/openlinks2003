class_name TerrainTiles
extends RefCounted
## Ground heights from the open "Terrarium" elevation tiles (the Mapzen
## terrain tiles on AWS Open Data). Each tile is a 256 px PNG in web
## mercator whose colour is the height: (R * 256 + G + B / 256) - 32768 m.
## The tiles merge the best open data for each place: national lidar where
## it is open (England, the US, New Zealand, Norway, Austria and others) and
## SRTM or EU-DEM elsewhere. See docs/real-courses.md.
##
## Usage: for_box() picks the tiles a box needs, add_tile() each PNG as it
## arrives, fill_missing() covers any that failed, then height_at() samples
## the mosaic.

const URL := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
const TILE := 256
const MAX_ZOOM := 15  ## the finest level the tiles have
const MAX_TILES := 36

var zoom := MAX_ZOOM
var origin := Vector2i.ZERO  ## the top-left tile
var count := Vector2i.ONE  ## tiles across and down
var loaded := 0
var _h := PackedFloat32Array()
var _have := PackedByteArray()  ## per tile: 1 once its PNG is in


## Tiles covering the box (south, west, north, east in degrees), at the
## finest zoom that needs at most MAX_TILES.
static func for_box(south: float, west: float, north: float, east: float) -> TerrainTiles:
	var t := TerrainTiles.new()
	for z in range(MAX_ZOOM, 9, -1):
		var x0 := int(_tile_x(west, z))
		var y0 := int(_tile_y(north, z))
		var n := Vector2i(int(_tile_x(east, z)) - x0 + 1, int(_tile_y(south, z)) - y0 + 1)
		if n.x * n.y <= MAX_TILES or z == 10:
			t.zoom = z
			t.origin = Vector2i(x0, y0)
			t.count = n
			break
	t._h.resize(t.count.x * t.count.y * TILE * TILE)
	t._have.resize(t.count.x * t.count.y)
	return t


## URLs of every tile, in the order add_tile() takes their index.
func urls() -> PackedStringArray:
	var out := PackedStringArray()
	for j in count.y:
		for i in count.x:
			out.append(URL % [zoom, origin.x + i, origin.y + j])
	return out


## Decodes tile `index` (row by row from the top left) from its PNG bytes.
func add_tile(index: int, png: PackedByteArray) -> bool:
	var img := Image.new()
	if png.size() < 8 or png.slice(0, 4) != PackedByteArray([0x89, 0x50, 0x4E, 0x47]):
		return false
	if img.load_png_from_buffer(png) != OK or img.get_width() != TILE or img.get_height() != TILE:
		return false
	img.convert(Image.FORMAT_RGB8)
	set_tile_rgb(index, img.get_data())
	return true


## Fills tile `index` from raw RGB8 bytes (TILE * TILE * 3).
func set_tile_rgb(index: int, rgb: PackedByteArray) -> void:
	var w := count.x * TILE
	var ox := (index % count.x) * TILE
	var oy := floori(float(index) / count.x) * TILE
	for y in TILE:
		var row := (oy + y) * w + ox
		var src := y * TILE * 3
		for x in TILE:
			var k := src + x * 3
			_h[row + x] = rgb[k] * 256.0 + rgb[k + 1] + rgb[k + 2] / 256.0 - 32768.0
	if _have[index] == 0:
		_have[index] = 1
		loaded += 1


func complete() -> bool:
	return loaded == _have.size()


## Sets tiles that never arrived to the mean of the ones that did, so a
## failed download gives flat ground there instead of a pit.
func fill_missing() -> void:
	if complete():
		return
	var sum := 0.0
	var n := 0
	var w := count.x * TILE
	for index in _have.size():
		if _have[index] == 1:
			var ox := (index % count.x) * TILE
			var oy := floori(float(index) / count.x) * TILE
			for y in range(0, TILE, 16):
				for x in range(0, TILE, 16):
					sum += _h[(oy + y) * w + ox + x]
					n += 1
	var mean := sum / n if n > 0 else 0.0
	for index in _have.size():
		if _have[index] == 0:
			var ox := (index % count.x) * TILE
			var oy := floori(float(index) / count.x) * TILE
			for y in TILE:
				for x in TILE:
					_h[(oy + y) * w + ox + x] = mean


## Height in metres at a latitude and longitude, bilinear between pixels.
## Points outside the tiles read the nearest edge.
func height_at(lat: float, lon: float) -> float:
	var w := count.x * TILE
	var h := count.y * TILE
	# Pixel centres sit at +0.5. (Scalars, not a Vector2: tile coordinates
	# need more than 32-bit precision.)
	var u := clampf((_tile_x(lon, zoom) - origin.x) * TILE - 0.5, 0.0, w - 1.001)
	var v := clampf((_tile_y(lat, zoom) - origin.y) * TILE - 0.5, 0.0, h - 1.001)
	var i := int(u)
	var j := int(v)
	var fu := u - i
	var fv := v - j
	var k := j * w + i
	var a := lerpf(_h[k], _h[k + 1], fu)
	var b := lerpf(_h[k + w], _h[k + w + 1], fu)
	return lerpf(a, b, fv)


## Ground size of one pixel at a latitude, in metres.
func pixel_metres(lat: float) -> float:
	return 40075016.7 * cos(deg_to_rad(lat)) / (TILE * pow(2.0, zoom))


## Fractional tile column (web mercator) of a longitude at a zoom.
static func _tile_x(lon: float, z: int) -> float:
	return (lon + 180.0) / 360.0 * pow(2.0, z)


## Fractional tile row of a latitude at a zoom.
static func _tile_y(lat: float, z: int) -> float:
	var phi := deg_to_rad(clampf(lat, -85.0, 85.0))
	return (1.0 - log(tan(phi) + 1.0 / cos(phi)) / PI) * 0.5 * pow(2.0, z)
