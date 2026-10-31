class_name LandCover
extends RefCounted
## What covers the ground everywhere in the world, at 10 m: the Impact
## Observatory / Microsoft / Esri Sentinel-2 land cover (CC BY 4.0), read
## from Esri's image service, which a browser may call. It fills in where
## the map and the photos are thin: trees the map doesn't have (hedges,
## copses, gardens) and the ground colour round the course (fields, bare
## ground, towns) where there is no open aerial photo. See
## docs/real-courses.md.

const URL := "https://ic.imagery1.arcgis.com/arcgis/rest/services/Sentinel2_10m_LandCover/ImageServer/exportImage?bbox={w},{s},{e},{n}&bboxSR=4326&imageSR=4326&size={cols},{rows}&format=tiff&pixelType=U8&interpolation=RSP_NearestNeighbor&f=image"
const CREDIT := "Land cover: Impact Observatory, Microsoft and Esri (Sentinel-2 10 m), CC BY 4.0"
const RES := 10.0  ## metres per pixel
const MAX_SIZE := 1000

## The classes.
const WATER := 1
const TREES := 2
const FLOODED := 4  ## flooded vegetation, marsh
const CROPS := 5
const BUILT := 7
const BARE := 8
const SNOW := 9
const CLOUDS := 10
const RANGELAND := 11  ## grass and scrub

## A typical colour seen from above for each class (sRGB), for the ground
## where there is no photo. Water and clouds are left to the course's own
## colours (black is skipped by the ground tint).
const COLORS := {
	WATER: Color(0, 0, 0),
	TREES: Color(0.24, 0.32, 0.17),
	FLOODED: Color(0.32, 0.40, 0.24),
	CROPS: Color(0.60, 0.56, 0.36),
	BUILT: Color(0.52, 0.50, 0.47),
	BARE: Color(0.60, 0.50, 0.38),
	SNOW: Color(0.88, 0.89, 0.90),
	CLOUDS: Color(0, 0, 0),
	RANGELAND: Color(0.42, 0.50, 0.28),
}

var box: Array  ## south, west, north, east
var cols := 0
var rows := 0
var raster: GeoRaster


func _init(p_box: Array) -> void:
	box = p_box
	var mid := (float(box[0]) + float(box[2])) * 0.5
	var f := GeoFrame.new(mid, (float(box[1]) + float(box[3])) * 0.5)
	var m_lat := f.to_local(mid + 0.001, f.lon0).y * 1000.0
	var m_lon := absf(f.to_local(mid, f.lon0 + 0.001).x) * 1000.0
	cols = clampi(ceili((float(box[3]) - float(box[1])) * m_lon / RES), 2, MAX_SIZE)
	rows = clampi(ceili((float(box[2]) - float(box[0])) * m_lat / RES), 2, MAX_SIZE)


func url() -> String:
	return URL.format({
		"s": "%.7f" % box[0], "w": "%.7f" % box[1], "n": "%.7f" % box[2], "e": "%.7f" % box[3],
		"cols": cols, "rows": rows,
	})


## Reads the service's answer; false if it isn't a usable raster.
func add(bytes: PackedByteArray) -> bool:
	var r := GeoRaster.from_tiff(bytes)
	if r == null or r.width < 2 or r.height < 2:
		return false
	raster = r
	return true


## The class at a point (0 outside or with no data).
func class_at(lat: float, lon: float) -> int:
	if raster == null or not raster.covers(lat, lon):
		return 0
	var i := clampi(floori((lon - raster.west) / raster.dlon), 0, raster.width - 1)
	var j := clampi(floori((raster.north - lat) / raster.dlat), 0, raster.height - 1)
	return int(raster.data[j * raster.width + i])


## Share of the box with a class (0 to 1).
func coverage() -> float:
	if raster == null:
		return 0.0
	var n := 0
	for v in raster.data:
		if v >= 1.0 and v <= 11.0:
			n += 1
	return float(n) / maxf(raster.data.size(), 1.0)


## A colour picture of the course area in the layout of a course photo
## (north-west pixel first, `res` metres a pixel), for the ground tint.
func ground_image(frame: GeoFrame, area: Rect2, res := 4.0) -> Image:
	var w := maxi(2, ceili(area.size.x / res))
	var h := maxi(2, ceili(area.size.y / res))
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for j in h:
		var z := area.end.y - (j + 0.5) * res
		for i in w:
			var x := area.end.x - (i + 0.5) * res
			var p := Vector2(x, z)
			img.set_pixel(i, j, COLORS.get(class_at(frame.lat_of(p), frame.lon_of(p)), Color(0, 0, 0)))
	return img


## Course points for trees: one per tree pixel, jittered inside it, so a
## hedge or copse the map lacks still stands where it is.
func tree_points(frame: GeoFrame, area: Rect2, seed_value := 1) -> PackedVector2Array:
	var out := PackedVector2Array()
	if raster == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for j in raster.height:
		for i in raster.width:
			if int(raster.data[j * raster.width + i]) != TREES:
				continue
			var lat := raster.pixel_lat(j) + rng.randf_range(-0.4, 0.4) * raster.dlat
			var lon := raster.pixel_lon(i) + rng.randf_range(-0.4, 0.4) * raster.dlon
			var p := frame.to_local(lat, lon)
			if area.has_point(p):
				out.append(p)
	return out
