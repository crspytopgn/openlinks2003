class_name RealCourseFetcher
extends Node
## Finds a real golf course by name and builds it as a DesignedCourse, all
## from free, open data fetched by the game itself (desktop and browser):
##
## 1. Nominatim (OpenStreetMap's search) turns the name into places.
## 2. The Overpass API returns the course's mapped holes, fairways, greens,
##    tees, bunkers, water, woods, trees and cart paths.
## 3. The Terrain Tiles on AWS give the ground heights (national lidar where
##    it is open, see docs/real-courses.md).
##
## search() emits `found`; build() emits `progress` then `built` or `failed`.

signal found(results: Array)  ## [{"name", "label", "lat", "lon", "box", "golf"}]
signal progress(text: String)
signal built(course: DesignedCourse, summary: Dictionary)
signal failed(text: String)

const NOMINATIM := "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=10&q=%s"
const OVERPASS := [
	"https://overpass-api.de/api/interpreter",
	"https://overpass.private.coffee/api/interpreter",
	"https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]
const USER_AGENT := "OpenLinks2003 course importer (+https://github.com/crspytopgn/openlinks2003)"
## Metres searched round a place that isn't itself a mapped golf course.
const POINT_RADIUS := 1500.0

var busy := false
## Overpass servers, tried in order.
var servers: Array = OVERPASS.duplicate()
var _last_summary := {}


## Looks up places matching `query`, golf courses first.
func search(query: String) -> void:
	if busy:
		return
	busy = true
	var q := query.strip_edges()
	var results := await _search_once(q)
	if not _has_golf(results) and not q.to_lower().contains("golf"):
		var more := await _search_once(q + " golf")
		if _has_golf(more):
			results = more
	busy = false
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["golf"] and not b["golf"])
	found.emit(results)


## Fetches and builds the course at a search result.
func build(place: Dictionary) -> void:
	if busy:
		return
	busy = true
	var course := await _build(place)
	busy = false
	if course != null:
		built.emit(course, _last_summary)



func _build(place: Dictionary) -> DesignedCourse:
	var lat := float(place["lat"])
	var lon := float(place["lon"])
	var box: Array = place.get("box", [])
	var s: float
	var w: float
	var n: float
	var e: float
	if place.get("golf", false) and box.size() == 4:
		# Nominatim boxes are south, north, west, east.
		s = float(box[0]) - 0.002
		n = float(box[1]) + 0.002
		w = float(box[2]) - 0.003
		e = float(box[3]) + 0.003
	else:
		var f := GeoFrame.new(lat, lon)
		# +x is west.
		s = f.lat_of(Vector2(0, -POINT_RADIUS))
		n = f.lat_of(Vector2(0, POINT_RADIUS))
		w = f.lon_of(Vector2(POINT_RADIUS, 0))
		e = f.lon_of(Vector2(-POINT_RADIUS, 0))
	progress.emit("Reading the course map from OpenStreetMap...")
	var data := await _overpass(overpass_query(s, w, n, e))
	if data.is_empty():
		failed.emit("Couldn't reach OpenStreetMap's map server. Check the connection and try again in a minute.")
		return null
	var builder := RealCourseBuilder.new(data, lat, lon, str(place.get("name", "")))
	var gb := builder.geo_box()
	var tiles := TerrainTiles.for_box(gb[0], gb[1], gb[2], gb[3])
	var urls := tiles.urls()
	for i in urls.size():
		progress.emit("Fetching the ground heights (%d of %d)..." % [i + 1, urls.size()])
		var res := await _http_get(urls[i])
		if res[0] == 200:
			tiles.add_tile(i, res[1])
	if tiles.loaded == 0:
		failed.emit("Couldn't fetch the ground heights. Check the connection and try again.")
		return null
	tiles.fill_missing()
	progress.emit("Building %s..." % builder.course_name)
	await get_tree().process_frame
	await get_tree().process_frame
	var course := builder.build(tiles.height_at)
	_last_summary = builder.summary.duplicate()
	_last_summary["missing_tiles"] = urls.size() - tiles.loaded
	_last_summary["metres_per_pixel"] = snappedf(tiles.pixel_metres(lat), 0.1)
	if course.holes.is_empty():
		failed.emit("OpenStreetMap has no holes mapped for %s yet. Try another course, or map it at openstreetmap.org." % builder.course_name)
		return null
	return course


## The Overpass query for everything a course needs in a box.
static func overpass_query(s: float, w: float, n: float, e: float) -> String:
	var bb := "(%.6f,%.6f,%.6f,%.6f)" % [s, w, n, e]
	return ("[out:json][timeout:90];(" +
		"nwr[\"golf\"]%s;" % bb +
		"nwr[\"leisure\"=\"golf_course\"]%s;" % bb +
		"nwr[\"natural\"~\"^(water|wood|scrub|heath)$\"]%s;" % bb +
		"way[\"natural\"=\"tree_row\"]%s;" % bb +
		"nwr[\"landuse\"~\"^(forest|reservoir|basin)$\"]%s;" % bb +
		"node[\"natural\"=\"tree\"]%s;" % bb +
		"way[\"waterway\"~\"^(river|stream|canal|ditch|drain)$\"]%s;" % bb +
		");out geom;")


func _search_once(q: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var res := await _http_get(NOMINATIM % q.uri_encode())
	if res[0] != 200:
		return out
	var parsed: Variant = JSON.parse_string((res[1] as PackedByteArray).get_string_from_utf8())
	if not parsed is Array:
		return out
	for r: Variant in parsed:
		if not r is Dictionary:
			continue
		var golf: bool = str(r.get("type", "")) == "golf_course"
		out.append({
			"name": str(r.get("name", "")),
			"label": str(r.get("display_name", "")),
			"lat": float(r.get("lat", 0)),
			"lon": float(r.get("lon", 0)),
			"box": r.get("boundingbox", []),
			"golf": golf,
		})
	return out


static func _has_golf(results: Array[Dictionary]) -> bool:
	for r in results:
		if r["golf"]:
			return true
	return false


## The Overpass answer, trying each server in turn; {} if none answer.
func _overpass(query: String) -> Dictionary:
	var body := "data=" + query.uri_encode()
	for url: String in servers:
		var res := await _request(url, HTTPClient.METHOD_POST, body, ["Content-Type: application/x-www-form-urlencoded"])
		if res[0] != 200:
			continue
		var parsed: Variant = JSON.parse_string((res[1] as PackedByteArray).get_string_from_utf8())
		if parsed is Dictionary and parsed.get("elements", null) is Array:
			return parsed
	return {}


func _http_get(url: String) -> Array:
	return await _request(url, HTTPClient.METHOD_GET, "", [])


## [status code (0 on failure), body bytes].
func _request(url: String, method: int, body: String, headers: Array) -> Array:
	var req := HTTPRequest.new()
	req.timeout = 120.0
	if not OS.has_feature("web"):
		req.use_threads = true
		headers = headers + ["User-Agent: " + USER_AGENT]
	add_child(req)
	var err := req.request(url, PackedStringArray(headers), method, body)
	if err != OK:
		req.queue_free()
		return [0, PackedByteArray()]
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return [0, PackedByteArray()]
	return [res[1], res[3]]
