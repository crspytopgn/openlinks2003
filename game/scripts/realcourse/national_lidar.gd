class_name NationalLidar
extends RefCounted
## Finer ground heights from national lidar services that a browser can
## read directly (they allow cross-site requests and answer in EPSG:4326,
## or as web map tiles):
## the bare ground (DTM) for the course, and where offered the first-return
## surface (DSM), whose height above the ground finds every tree. Where no
## service covers a course, or it has gaps, the Terrain Tiles fill in.
## See docs/real-courses.md for each source and its licence.
##
##     var src := NationalLidar.source_for(lat, lon)
##     var lidar := NationalLidar.new(src, box)
##     for c in lidar.chunks: fetch lidar.url(c, false) ... lidar.add(c, bytes, false)

const CHUNK := 1000  ## pixels a side per request at most
const RES := 1.0  ## metres per pixel asked for
const MAX_TILE_CHUNKS := 256  ## tiles per layer at most, for tile sources

## Each source: the box it may cover (south, west, north, east; gaps
## outside the country come back as no data), how to ask for a box, and
## the credit its licence asks for. URL placeholders: {s} {w} {n} {e}
## (degrees), {cols} {rows} (pixels), {layer} (the DTM or DSM name).
## A "tiles" source lists tile layers instead, finest first, each a URL
## with {z} {x} {y} and its zoom; the finest that has a point wins.
## Smaller areas come first: where boxes overlap, the first service whose
## answer covers the course is used.
const SOURCES := [
	{
		"id": "vl", "name": "Digitaal Hoogtemodel Vlaanderen II, Flanders (1 m)",
		"boxes": [[50.67, 2.53, 51.51, 5.92]],
		"format": "tiff",
		"dtm": "https://geo.api.vlaanderen.be/DHMV/wcs", "dtm_layer": "DHMVII_DTM_1m",
		"dsm": "https://geo.api.vlaanderen.be/DHMV/wcs", "dsm_layer": "DHMVII_DSM_1m",
		"query": "?service=WCS&version=1.0.0&request=GetCoverage&coverage={layer}&format=GeoTIFF&CRS=EPSG:4326&BBOX={w},{s},{e},{n}&WIDTH={cols}&HEIGHT={rows}",
		"credit": "Lidar: Digitaal Hoogtemodel Vlaanderen II (Digitaal Vlaanderen), Modellicentie Gratis Hergebruik",
	},
	{
		"id": "nrw", "name": "Geobasis NRW lidar, North Rhine-Westphalia (1 m)",
		"boxes": [[50.32, 5.86, 52.53, 9.46]],
		"format": "tiff",
		"dtm": "https://www.wcs.nrw.de/geobasis/wcs_nw_dgm", "dtm_layer": "nw_dgm",
		"dsm": "https://www.wcs.nrw.de/geobasis/wcs_nw_dom", "dsm_layer": "nw_dom",
		"query": "?SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage&COVERAGEID={layer}&FORMAT=image/tiff&SUBSET=x({w},{e})&SUBSET=y({s},{n})&SUBSETTINGCRS=http://www.opengis.net/def/crs/EPSG/0/4326&OUTPUTCRS=http://www.opengis.net/def/crs/EPSG/0/4326&SCALESIZE=x({cols}),y({rows})&GEOTIFF:COMPRESSION=DEFLATE",
		"credit": "Lidar: Geobasis NRW, dl-de/zero-2-0",
	},
	{
		"id": "ea", "name": "Environment Agency lidar, England (1 m)",
		"boxes": [[49.85, -6.45, 55.82, 1.80]],
		"format": "tiff",
		"dtm": "https://environment.data.gov.uk/spatialdata/lidar-composite-digital-terrain-model-dtm-1m/wcs",
		"dtm_layer": "13787b9a-26a4-4775-8523-806d13af58fc__Lidar_Composite_Elevation_DTM_1m",
		"dsm": "https://environment.data.gov.uk/spatialdata/lidar-composite-digital-surface-model-first-return-dsm-1m/wcs",
		"dsm_layer": "df4e3ec3-315e-48aa-aaaf-b5ae74d7b2bb__Lidar_Composite_Elevation_FZ_DSM_1m",
		"query": "?service=WCS&version=2.0.1&request=GetCoverage&coverageId={layer}&format=image/tiff&subset=Lat({s},{n})&subset=Long({w},{e})&subsettingCrs=http://www.opengis.net/def/crs/EPSG/0/4326&outputCrs=http://www.opengis.net/def/crs/EPSG/0/4326&scaleSize=i({cols}),j({rows})",
		"credit": "Lidar: Environment Agency, Open Government Licence v3.0",
	},
	{
		"id": "ahn", "name": "AHN lidar, Netherlands (0.5 m)",
		"boxes": [[50.70, 3.20, 53.60, 7.25]],
		"format": "tiff",
		"dtm": "https://service.pdok.nl/rws/ahn/wcs/v1_0", "dtm_layer": "dtm_05m",
		"dsm": "https://service.pdok.nl/rws/ahn/wcs/v1_0", "dsm_layer": "dsm_05m",
		"query": "?SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage&COVERAGEID={layer}&FORMAT=image/tiff&SUBSET=x({w},{e})&SUBSET=y({s},{n})&SUBSETTINGCRS=http://www.opengis.net/def/crs/EPSG/0/4326&OUTPUTCRS=http://www.opengis.net/def/crs/EPSG/0/4326&SCALESIZE=x({cols}),y({rows})",
		"credit": "Lidar: AHN (Rijkswaterstaat, PDOK), CC0",
	},
	{
		"id": "ign", "name": "IGN RGE ALTI and LiDAR HD, France (1 m)",
		"boxes": [[41.30, -5.20, 51.15, 9.60]],
		"format": "bil",
		"dtm": "https://data.geopf.fr/wms-r", "dtm_layer": "ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES",
		"dsm": "https://data.geopf.fr/wms-r", "dsm_layer": "ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES.MNS",
		"query": "?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS={layer}&STYLES=&CRS=EPSG:4326&BBOX={s},{w},{n},{e}&WIDTH={cols}&HEIGHT={rows}&FORMAT=image/x-bil;bits=32",
		"credit": "Lidar: IGN (Geoplateforme), Licence Ouverte 2.0",
	},
	{
		"id": "no", "name": "Kartverket national lidar, Norway (1 m)",
		"boxes": [[57.9, 4.4, 71.3, 31.3]],
		"format": "tiff",
		"dtm": "https://wcs.geonorge.no/skwms1/wcs.hoyde-dtm-nhm-25833", "dtm_layer": "nhm_dtm_topo_25833",
		"dsm": "https://wcs.geonorge.no/skwms1/wcs.hoyde-dom-nhm-25833", "dsm_layer": "nhm_dom_topo_25833",
		"query": "?service=WCS&version=1.0.0&request=GetCoverage&coverage={layer}&format=GeoTIFF&CRS=EPSG:4326&BBOX={w},{s},{e},{n}&WIDTH={cols}&HEIGHT={rows}",
		"credit": "Lidar: Kartverket (Hoydedata), CC BY 4.0",
	},
	{
		"id": "gsi", "name": "GSI elevation tiles, Japan (1 to 10 m)",
		"boxes": [[24.0, 122.9, 45.6, 146.0]],
		"format": "tiles",
		"layers": [
			{"url": "https://cyberjapandata.gsi.go.jp/xyz/dem1a_png/{z}/{x}/{y}.png", "zoom": 17},
			{"url": "https://cyberjapandata.gsi.go.jp/xyz/dem5a_png/{z}/{x}/{y}.png", "zoom": 15},
			{"url": "https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png", "zoom": 14},
		],
		"dtm": "", "dtm_layer": "", "dsm": "", "dsm_layer": "", "query": "",
		"credit": "Elevation: Geospatial Information Authority of Japan (GSI tiles)",
	},
	{
		"id": "3dep", "name": "USGS 3DEP lidar, United States (1 to 10 m)",
		"boxes": [[24.4, -125.0, 49.5, -66.9], [51.0, -170.0, 71.5, -129.9], [18.8, -160.4, 22.4, -154.7], [17.8, -67.4, 18.6, -65.2]],
		"format": "tiff",
		"dtm": "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage", "dtm_layer": "",
		"dsm": "", "dsm_layer": "",
		"query": "?bbox={w},{s},{e},{n}&bboxSR=4326&imageSR=4326&size={cols},{rows}&format=tiff&pixelType=F32&noData=-9999&interpolation=RSP_BilinearInterpolation&f=image",
		"credit": "Lidar: USGS 3D Elevation Program, public domain",
	},
]

var source: Dictionary
## The requests: {"box": [s, w, n, e], "cols", "rows"}.
var chunks: Array[Dictionary] = []
var dtm: Array[GeoRaster] = []
var dsm: Array[GeoRaster] = []
var _box: Array = []
var _tiles := {}  ## tile sources: Vector3i(x, y, zoom) -> GeoRaster


## The first service whose box holds a point, or {}.
static func source_for(lat: float, lon: float) -> Dictionary:
	var all := sources_for(lat, lon)
	return all[0] if not all.is_empty() else {}


## Every service whose box holds a point, to try in order.
static func sources_for(lat: float, lon: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in SOURCES:
		for b: Array in s["boxes"]:
			if lat >= b[0] and lat <= b[2] and lon >= b[1] and lon <= b[3]:
				out.append(s)
				break
	return out


## Requests for `box` (south, west, north, east) at about RES metres.
func _init(p_source: Dictionary, box: Array) -> void:
	source = p_source
	_box = box
	if source["format"] == "tiles":
		_tile_chunks(box)
		return
	var mid := (float(box[0]) + float(box[2])) * 0.5
	var f := GeoFrame.new(mid, (float(box[1]) + float(box[3])) * 0.5)
	var m_lat := f.to_local(mid + 0.001, f.lon0).y * 1000.0
	var m_lon := absf(f.to_local(mid, f.lon0 + 0.001).x) * 1000.0
	var cols_total := ceili((float(box[3]) - float(box[1])) * m_lon / RES)
	var rows_total := ceili((float(box[2]) - float(box[0])) * m_lat / RES)
	var nx := ceili(float(cols_total) / CHUNK)
	var ny := ceili(float(rows_total) / CHUNK)
	var dw := (float(box[3]) - float(box[1])) / nx
	var dn := (float(box[2]) - float(box[0])) / ny
	for j in ny:
		for i in nx:
			var s := float(box[0]) + j * dn
			var w := float(box[1]) + i * dw
			chunks.append({"box": [s, w, s + dn, w + dw], "cols": ceili(float(cols_total) / nx), "rows": ceili(float(rows_total) / ny)})


## One chunk per web map tile of each layer (layers with too many tiles
## for the box are left out).
func _tile_chunks(box: Array) -> void:
	for layer: Dictionary in source["layers"]:
		var z := int(layer["zoom"])
		var x0 := int(TerrainTiles._tile_x(box[1], z))
		var x1 := int(TerrainTiles._tile_x(box[3], z))
		var y0 := int(TerrainTiles._tile_y(box[2], z))
		var y1 := int(TerrainTiles._tile_y(box[0], z))
		if (x1 - x0 + 1) * (y1 - y0 + 1) > MAX_TILE_CHUNKS:
			continue
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				chunks.append({
					"box": [TerrainTiles.tile_lat(y + 1, z), TerrainTiles.tile_lon(x, z), TerrainTiles.tile_lat(y, z), TerrainTiles.tile_lon(x + 1, z)],
					"cols": 256, "rows": 256, "tile": Vector3i(x, y, z),
					"url": str(layer["url"]).format({"z": z, "x": x, "y": y}),
				})


func has_dsm() -> bool:
	return not str(source.get("dsm", "")).is_empty()


func url(chunk: Dictionary, surface: bool) -> String:
	if chunk.has("url"):
		return chunk["url"]
	var b: Array = chunk["box"]
	var q := str(source["query"]).format({
		"s": "%.7f" % b[0], "w": "%.7f" % b[1], "n": "%.7f" % b[2], "e": "%.7f" % b[3],
		"cols": chunk["cols"], "rows": chunk["rows"],
		"layer": source["dsm_layer" if surface else "dtm_layer"],
	})
	return str(source["dsm" if surface else "dtm"]) + q


## Reads one answer; false if it isn't a usable raster.
func add(chunk: Dictionary, bytes: PackedByteArray, surface: bool) -> bool:
	var r: GeoRaster
	if source["format"] == "bil":
		r = GeoRaster.from_bil(bytes, chunk["cols"], chunk["rows"], chunk["box"])
	elif source["format"] == "tiles":
		r = GeoRaster.from_gsi_png(bytes, chunk["box"])
	else:
		r = GeoRaster.from_tiff(bytes)
	if r == null:
		return false
	if chunk.has("tile"):
		_tiles[chunk["tile"]] = r
	# Finest first, so sampling prefers it where layers overlap.
	var list := dsm if surface else dtm
	var at := list.size()
	while at > 0 and list[at - 1].dlat > r.dlat * 1.01:
		at -= 1
	list.insert(at, r)
	return true


## Share of the box where the service has ground heights (0 to 1).
func coverage() -> float:
	if dtm.is_empty() or _box.size() != 4:
		return 0.0
	var n := 0
	for j in 24:
		for i in 24:
			var lat := lerpf(float(_box[0]), float(_box[2]), (j + 0.5) / 24.0)
			var lon := lerpf(float(_box[1]), float(_box[3]), (i + 0.5) / 24.0)
			if not is_nan(ground_at(lat, lon)):
				n += 1
	return n / 576.0


## Bare-ground height at a point, NAN where the service has none.
func ground_at(lat: float, lon: float) -> float:
	if not _tiles.is_empty():
		return _tile_sample(lat, lon)
	return _sample(dtm, lat, lon)


## Tile sources: the finest layer with a height at the point.
func _tile_sample(lat: float, lon: float) -> float:
	for layer: Dictionary in source["layers"]:
		var z := int(layer["zoom"])
		var r: GeoRaster = _tiles.get(Vector3i(int(TerrainTiles._tile_x(lon, z)), int(TerrainTiles._tile_y(lat, z)), z))
		if r != null:
			var h := r.sample(lat, lon)
			if not is_nan(h):
				return h
	return NAN


func surface_at(lat: float, lon: float) -> float:
	return _sample(dsm, lat, lon)


static func _sample(rasters: Array[GeoRaster], lat: float, lon: float) -> float:
	for r in rasters:
		if r.covers(lat, lon):
			var h := r.sample(lat, lon)
			if not is_nan(h):
				return h
	return NAN


## Trees from the canopy height (surface minus ground): every local peak at
## least `min_height` tall, one per `spacing` metres at most. Flat peaks
## (roofs) are skipped. Returns [{"lat", "lon", "height"}].
func find_trees(min_height := 3.0, spacing := 4.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var taken := {}
	for top in dsm:
		var ground := _matching(top)
		var w := top.width
		var h := top.height
		var chm := PackedFloat32Array()
		chm.resize(w * h)
		for j in h:
			for i in w:
				var k := j * w + i
				var g := ground.data[k] if ground != null else ground_at(top.pixel_lat(j), top.pixel_lon(i))
				var t := top.data[k]
				chm[k] = t - g if (t > -1000.0 and t < 9000.0 and g > -1000.0 and g < 9000.0) else 0.0
		var m_px := maxf(top.dlat * 111000.0, 0.1)
		var r := clampi(roundi(1.5 / m_px), 1, 4)
		for j in range(r, h - r):
			for i in range(r, w - r):
				var c := chm[j * w + i]
				if c < min_height or c > 60.0:
					continue
				var peak := true
				var level := 0
				for dj in range(-r, r + 1):
					for di in range(-r, r + 1):
						var v := chm[(j + dj) * w + i + di]
						if v > c:
							peak = false
						elif absf(v - c) < 0.15:
							level += 1
				# A crown rises to its top; a roof is level (the pixel itself
				# counts once).
				if not peak or level > 3:
					continue
				var lat := top.pixel_lat(j)
				var lon := top.pixel_lon(i)
				var cell := Vector2i(floori(lat * 111000.0 / spacing), floori(lon * 111000.0 * cos(deg_to_rad(lat)) / spacing))
				if taken.has(cell):
					continue
				taken[cell] = true
				out.append({"lat": lat, "lon": lon, "height": c})
	return out


## The ground raster fetched with the same box as `top`, or null.
func _matching(top: GeoRaster) -> GeoRaster:
	for g in dtm:
		if g.width == top.width and g.height == top.height and is_equal_approx(g.west, top.west) and is_equal_approx(g.north, top.north):
			return g
	return null
