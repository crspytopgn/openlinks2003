class_name AerialPhotos
extends RefCounted
## Openly licensed aerial photos (national orthophotos as web map tiles),
## for two things: a top-down photo under the course designer, to check
## and trace the course against, and finding trees where the map and the
## lidar don't have them. Only services whose licence allows reuse are
## listed (no Google, Bing or Apple imagery). See docs/real-courses.md.

const TILE := 256
const MAX_TILES := 160
const MAX_ZOOM := 17
const PHOTO_MAX := 2048  ## pixels a side of the course photo kept
const PHOTO_RES := 1.0  ## metres per pixel of the course photo, at best

## URL placeholders: {z} {x} {y} (web mercator tile), or {bbox} (the
## tile's web mercator box in metres, for WMS services). Smaller areas come
## first: where boxes overlap, the first service with photos of the course
## is used.
const SOURCES := [
	{
		"id": "vl", "name": "Digitaal Vlaanderen orthophoto, Flanders",
		"boxes": [[50.67, 2.53, 51.51, 5.92]],
		"url": "https://geo.api.vlaanderen.be/omz/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=omzrgb24vl&STYLES=&CRS=EPSG:3857&BBOX={bbox}&WIDTH=256&HEIGHT=256&FORMAT=image/jpeg",
		"credit": "Aerial photo: Digitaal Vlaanderen, Modellicentie Gratis Hergebruik",
	},
	{
		"id": "nrw", "name": "Geobasis NRW orthophoto, North Rhine-Westphalia",
		"boxes": [[50.32, 5.86, 52.53, 9.46]],
		"url": "https://www.wms.nrw.de/geobasis/wms_nw_dop?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=nw_dop_rgb&STYLES=&CRS=EPSG:3857&BBOX={bbox}&WIDTH=256&HEIGHT=256&FORMAT=image/jpeg",
		"credit": "Aerial photo: Geobasis NRW, dl-de/zero-2-0",
	},
	{
		"id": "pdok", "name": "PDOK aerial photo, Netherlands",
		"boxes": [[50.70, 3.20, 53.60, 7.25]],
		"url": "https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857/{z}/{x}/{y}.jpeg",
		"credit": "Aerial photo: Beeldmateriaal Nederland (PDOK), CC BY 4.0",
	},
	{
		"id": "swisstopo", "name": "SWISSIMAGE, Switzerland",
		"boxes": [[45.80, 5.95, 47.81, 10.50]],
		"url": "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.swissimage/default/current/3857/{z}/{x}/{y}.jpeg",
		"credit": "Aerial photo: (c) swisstopo",
	},
	{
		"id": "basemap", "name": "basemap.at orthophoto, Austria",
		"boxes": [[46.37, 9.53, 49.02, 17.17]],
		"url": "https://mapsneu.wien.gv.at/basemap/bmaporthofoto30cm/normal/google3857/{z}/{y}/{x}.jpeg",
		"credit": "Aerial photo: basemap.at, CC BY 4.0",
	},
	{
		"id": "ign", "name": "IGN BD ORTHO, France",
		"boxes": [[41.30, -5.20, 51.15, 9.60]],
		"url": "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg",
		"credit": "Aerial photo: IGN (Geoplateforme), Licence Ouverte 2.0",
	},
	{
		"id": "pnoa", "name": "PNOA aerial photo, Spain",
		"boxes": [[35.9, -9.4, 43.9, 4.4], [27.6, -18.2, 29.5, -13.4]],
		"url": "https://www.ign.es/wmts/pnoa-ma?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=OI.OrthoimageCoverage&STYLE=default&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg",
		"credit": "Aerial photo: PNOA (c) Instituto Geografico Nacional de Espana, CC BY 4.0",
	},
	{
		"id": "gsi", "name": "GSI seamless photo, Japan",
		"boxes": [[24.0, 122.9, 45.6, 146.0]],
		"url": "https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg",
		"credit": "Aerial photo: Geospatial Information Authority of Japan (GSI tiles)",
	},
	{
		"id": "usgs", "name": "USGS/USDA NAIP orthoimagery, United States",
		"boxes": [[24.4, -125.0, 49.5, -66.9], [18.8, -160.4, 22.4, -154.7]],
		"url": "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}",
		"credit": "Aerial photo: USGS The National Map / USDA NAIP, public domain",
	},
]

var source: Dictionary
var zoom := MAX_ZOOM
var origin := Vector2i.ZERO
var count := Vector2i.ONE
var loaded := 0
var _mosaic: Image


## The first photo service whose box holds a point, or {}.
static func source_for(lat: float, lon: float) -> Dictionary:
	var all := sources_for(lat, lon)
	return all[0] if not all.is_empty() else {}


## Every photo service whose box holds a point, to try in order.
static func sources_for(lat: float, lon: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in SOURCES:
		for b: Array in s["boxes"]:
			if lat >= b[0] and lat <= b[2] and lon >= b[1] and lon <= b[3]:
				out.append(s)
				break
	return out


## Tiles covering `box` (south, west, north, east) at the finest zoom
## needing at most MAX_TILES.
func _init(p_source: Dictionary, box: Array) -> void:
	source = p_source
	for z in range(MAX_ZOOM, 12, -1):
		var x0 := int(TerrainTiles._tile_x(box[1], z))
		var y0 := int(TerrainTiles._tile_y(box[2], z))
		var n := Vector2i(int(TerrainTiles._tile_x(box[3], z)) - x0 + 1, int(TerrainTiles._tile_y(box[0], z)) - y0 + 1)
		zoom = z
		origin = Vector2i(x0, y0)
		count = n
		if n.x * n.y <= MAX_TILES:
			break
	_mosaic = Image.create(count.x * TILE, count.y * TILE, false, Image.FORMAT_RGB8)
	_mosaic.fill(Color(0.3, 0.4, 0.25))


func urls() -> PackedStringArray:
	var out := PackedStringArray()
	# Web mercator metres: the world is 2 pi R across, centred on 0.
	var world := 2.0 * PI * 6378137.0
	var size := world / pow(2.0, zoom)
	for j in count.y:
		for i in count.x:
			var x := origin.x + i
			var y := origin.y + j
			var x0 := x * size - world * 0.5
			var y1 := world * 0.5 - y * size
			var bbox := "%.3f,%.3f,%.3f,%.3f" % [x0, y1 - size, x0 + size, y1]
			out.append(str(source["url"]).format({"z": zoom, "x": x, "y": y, "bbox": bbox}))
	return out


## Puts tile `index` (row by row from the top left) in the mosaic.
func add_tile(index: int, bytes: PackedByteArray) -> bool:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() > 3 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.size() > 3 and bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	if err != OK or img.get_width() != TILE or img.get_height() != TILE:
		return false
	img.convert(Image.FORMAT_RGB8)
	if is_blank(img):
		return false
	var at := Vector2i(index % count.x, floori(float(index) / count.x)) * TILE
	_mosaic.blit_rect(img, Rect2i(0, 0, TILE, TILE), at)
	loaded += 1
	return true


## True for a tile of one flat colour: services answer outside their
## country with white or empty tiles.
static func is_blank(img: Image) -> bool:
	var lo := 1.0
	var hi := 0.0
	for j in range(8, img.get_height(), 16):
		for i in range(8, img.get_width(), 16):
			var l := img.get_pixel(i, j).get_luminance()
			lo = minf(lo, l)
			hi = maxf(hi, l)
	return hi - lo < 0.02


## Photo colour at a latitude and longitude.
func color_at(lat: float, lon: float) -> Color:
	var x := (TerrainTiles._tile_x(lon, zoom) - origin.x) * TILE
	var y := (TerrainTiles._tile_y(lat, zoom) - origin.y) * TILE
	return _mosaic.get_pixel(clampi(int(x), 0, _mosaic.get_width() - 1), clampi(int(y), 0, _mosaic.get_height() - 1))


## A guess at a tree's leaf type from its crown colour: conifers are
## darker and bluer green than broadleaves, and broadleaves are brown in a
## winter photo. "" when the colour doesn't say.
func leaf_at(lat: float, lon: float) -> String:
	var c := color_at(lat, lon)
	var l := c.get_luminance()
	if c.r > c.g * 1.02:
		return "broadleaved"  # leafless or autumn
	if l < 0.16 and c.g >= c.r:
		return "needleleaved"
	if l > 0.24:
		return "broadleaved"
	return ""


## A north-up photo of the course area, at most PHOTO_MAX pixels a side:
## pixel (0, 0) is the north-west corner, which is the area's high x (+x is
## west) and high z. Over a course's few kilometres web mercator is a plain
## scale of the local plane (to well under a metre), so this is a crop and
## a resize of the mosaic.
func course_photo(frame: GeoFrame, area: Rect2) -> Image:
	var res := maxf(PHOTO_RES, maxf(area.size.x, area.size.y) / PHOTO_MAX)
	var w := ceili(area.size.x / res)
	var h := ceili(area.size.y / res)
	var nw := Vector2(area.end.x, area.end.y)
	var se := area.position
	var x0 := (TerrainTiles._tile_x(frame.lon_of(nw), zoom) - origin.x) * TILE
	var y0 := (TerrainTiles._tile_y(frame.lat_of(nw), zoom) - origin.y) * TILE
	var x1 := (TerrainTiles._tile_x(frame.lon_of(se), zoom) - origin.x) * TILE
	var y1 := (TerrainTiles._tile_y(frame.lat_of(se), zoom) - origin.y) * TILE
	var r := Rect2i(Vector2i(floori(x0), floori(y0)), Vector2i(maxi(ceili(x1 - x0), 1), maxi(ceili(y1 - y0), 1)))
	r = r.intersection(Rect2i(Vector2i.ZERO, _mosaic.get_size()))
	if r.size.x < 2 or r.size.y < 2:
		return null
	var img := _mosaic.get_region(r)
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return img


## Tree crowns in a course photo (from course_photo): cells of `cell`
## metres that are mostly dark leafy pixels or deep shade, darker than the
## mown grass (sampled at `grass`, course points on fairways). Returns course
## points (x, z).
static func find_trees(photo: Image, area: Rect2, grass: PackedVector2Array, cell := 5.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	if photo == null or grass.is_empty():
		return out
	var w := photo.get_width()
	var h := photo.get_height()
	var px := PackedByteArray(photo.get_data())
	var to_px := Vector2(w / area.size.x, h / area.size.y)
	var lum := 0.0
	for p in grass:
		lum += _lum_at(px, w, h, (Vector2(area.end.x, area.end.y) - p) * to_px)
	lum /= grass.size()
	var dark := lum * 0.72
	var step := cell / 3.0
	var z := area.position.y + cell * 0.5
	while z < area.end.y:
		var x := area.position.x + cell * 0.5
		while x < area.end.x:
			var hits := 0
			for dj in 3:
				for di in 3:
					var q := (Vector2(area.end.x - x - (di - 1) * step, area.end.y - z - (dj - 1) * step)) * to_px
					var i := clampi(int(q.x), 0, w - 1)
					var j := clampi(int(q.y), 0, h - 1)
					var k := (j * w + i) * 3
					var r := px[k]
					var g := px[k + 1]
					var b := px[k + 2]
					var l := (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
					var leafy := g >= r * 0.95 and g >= b * 0.9
					if (leafy and l < dark) or (l < lum * 0.35 and b <= g * 1.1):
						hits += 1
			if hits >= 7:
				out.append(Vector2(x, z))
			x += cell
		z += cell
	return out


static func _lum_at(px: PackedByteArray, w: int, h: int, q: Vector2) -> float:
	var k := (clampi(int(q.y), 0, h - 1) * w + clampi(int(q.x), 0, w - 1)) * 3
	return (0.2126 * px[k] + 0.7152 * px[k + 1] + 0.0722 * px[k + 2]) / 255.0
