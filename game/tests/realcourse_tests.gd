extends RefCounted
## Checks for the real-course importer (game/scripts/realcourse/) on a small
## made-up map, so they need no network: GeoFrame, TerrainTiles decoding,
## and RealCourseBuilder turning OpenStreetMap-style data into a course.

var failures: Array[String] = []


func run_all() -> Array[String]:
	_test_scripts_compile()
	_test_geo_frame()
	_test_terrain_tiles()
	_test_simplify()
	_test_builder()
	_test_geo_raster()
	_test_national_lidar()
	_test_photo_trees()
	_test_extra_trees()
	_test_photo_ground()
	_test_land_cover()
	_test_guesser()
	_test_detector()
	return failures


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _test_scripts_compile() -> void:
	for path in ["res://scripts/realcourse/real_course_fetcher.gd", "res://scripts/realcourse/real_course_dialog.gd", "res://shaders/aerial_photo.gdshader"]:
		if path.ends_with(".gdshader"):
			check(load(path) is Shader, "%s loads" % path)
			continue
		var script: GDScript = load(path)
		check(script != null and script.can_instantiate(), "%s compiles" % path)


func _test_geo_frame() -> void:
	var f := GeoFrame.new(56.35, -2.81)
	var east := f.to_local(56.35, -2.80)
	var north := f.to_local(56.36, -2.81)
	check(east.x < -600.0 and east.x > -630.0 and absf(east.y) < 0.01, "0.01 deg east at 56 N is about 617 m, on -x: %s" % east)
	check(north.y > 1110.0 and north.y < 1115.0 and absf(north.x) < 0.01, "0.01 deg north is about 1113 m, on +z: %s" % north)
	var p := Vector2(-250.0, 400.0)
	check(f.to_local(f.lat_of(p), f.lon_of(p)).distance_to(p) < 0.001, "GeoFrame round trip")


func _test_terrain_tiles() -> void:
	var t := TerrainTiles.for_box(56.349, -2.812, 56.351, -2.808)
	check(t.zoom == TerrainTiles.MAX_ZOOM and t.count.x * t.count.y <= 4, "a small box needs a few zoom 15 tiles (%d, %s)" % [t.zoom, t.count])
	check(t.urls()[0].ends_with("/15/%d/%d.png" % [t.origin.x, t.origin.y]), "tile url")
	# Height 37.5 m everywhere: 37.5 + 32768 = 32805.5 = 128 * 256 + 37 + 128 / 256.
	var rgb := PackedByteArray()
	for k in TerrainTiles.TILE * TerrainTiles.TILE:
		rgb.append_array(PackedByteArray([128, 37, 128]))
	t.set_tile_rgb(0, rgb)
	check(not t.complete() or t.count == Vector2i.ONE, "one tile in")
	t.fill_missing()
	check(absf(t.height_at(56.35, -2.81) - 37.5) < 0.001, "terrarium decoding: %f" % t.height_at(56.35, -2.81))
	# A real PNG through add_tile.
	var img := Image.create_from_data(TerrainTiles.TILE, TerrainTiles.TILE, false, Image.FORMAT_RGB8, rgb)
	var t2 := TerrainTiles.for_box(56.349, -2.812, 56.351, -2.808)
	check(t2.add_tile(0, img.save_png_to_buffer()), "add_tile reads a PNG")
	check(not t2.add_tile(0, PackedByteArray([1, 2, 3])), "add_tile refuses junk")


func _test_simplify() -> void:
	var circle := PackedVector2Array()
	for i in 400:
		var a := TAU * i / 400.0
		circle.append(Vector2(cos(a), sin(a)) * 30.0)
	var s := RealCourseBuilder.simplify_ring(circle, 0.3)
	check(s.size() >= 8 and s.size() <= RealCourseBuilder.MAX_POINTS, "a 400-point circle simplifies to a few dozen points (%d)" % s.size())
	var line := RealCourseBuilder.simplify_line(PackedVector2Array([Vector2(0, 0), Vector2(5, 0.01), Vector2(10, 0), Vector2(10, 10)]), 0.5)
	check(line.size() == 3, "straight runs collapse (%d)" % line.size())


## A made-up par 4 running north: tee at the south, green at the north,
## a fairway mapped as a two-part multipolygon, a bunker, a pond, a wood,
## a lone tree, a stream and a cart path, inside a golf course boundary.
func _test_builder() -> void:
	var lat0 := 51.0
	var lon0 := -1.0
	var f := GeoFrame.new(lat0, lon0)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Test Links"}, f, _rect(Vector2(-150, -250), Vector2(150, 250))))
	els.append(_way({"golf": "hole", "ref": "1", "par": "4", "handicap": "7"}, f, [Vector2(0, -200), Vector2(10, 0), Vector2(0, 160)], false))
	els.append(_way({"golf": "tee"}, f, _rect(Vector2(-6, -210), Vector2(6, -195))))
	els.append(_way({"golf": "tee"}, f, _rect(Vector2(-6, -180), Vector2(6, -170))))
	els.append(_way({"golf": "green"}, f, _rect(Vector2(-15, 145), Vector2(15, 175))))
	els.append({"type": "node", "lat": f.lat_of(Vector2(5, 165)), "lon": f.lon_of(Vector2(5, 165)), "tags": {"golf": "pin"}})
	els.append(_way({"golf": "bunker"}, f, _rect(Vector2(20, 120), Vector2(30, 135))))
	els.append(_way({"natural": "water"}, f, _rect(Vector2(-90, -50), Vector2(-60, -10))))
	els.append(_way({"natural": "wood", "leaf_type": "needleleaved"}, f, _rect(Vector2(60, -100), Vector2(120, 100))))
	els.append({"type": "node", "lat": f.lat_of(Vector2(-40, 40)), "lon": f.lon_of(Vector2(-40, 40)), "tags": {"natural": "tree", "height": "21"}})
	els.append(_way({"waterway": "stream"}, f, [Vector2(-150, 60), Vector2(0, 70), Vector2(150, 60)], false))
	els.append(_way({"golf": "cartpath"}, f, [Vector2(-30, -190), Vector2(-30, 140)], false))
	# The fairway as a multipolygon of two open ways that join into one ring.
	var left := [Vector2(-20, -150), Vector2(-20, 130), Vector2(20, 130)]
	var right := [Vector2(20, 130), Vector2(20, -150), Vector2(-20, -150)]
	els.append({"type": "relation", "tags": {"type": "multipolygon", "golf": "fairway"}, "members": [
		{"type": "way", "role": "outer", "geometry": _geom(f, left)},
		{"type": "way", "role": "outer", "geometry": _geom(f, right)},
	]})
	# A second course nearby whose hole must be left out.
	els.append(_way({"golf": "hole", "ref": "1"}, f, [Vector2(600, 0), Vector2(600, 300)], false))
	var b := RealCourseBuilder.new({"elements": els}, lat0, lon0)
	check(b.course_name == "Test Links", "the course takes the boundary's name (%s)" % b.course_name)
	check(b.area.size.x >= 300.0 + 2 * RealCourseBuilder.MARGIN - 4.0 and b.area.size.x <= 300.0 + 2 * RealCourseBuilder.MARGIN + 4.0,
		"area spans the boundary plus margins (%s)" % b.area)
	var gb := b.geo_box()
	check(gb[0] < lat0 and gb[2] > lat0 and gb[1] < lon0 and gb[3] > lon0, "geo box holds the course")
	# Ground rising 1 m per 100 m northwards.
	var c := b.build(func(lat: float, _lon: float) -> float: return 50.0 + (lat - lat0) * 1113.0)
	check(c.holes.size() == 1, "one hole (the other course's is left out): %d" % c.holes.size())
	check(c.credits.contains("OpenStreetMap"), "credits name OpenStreetMap")
	check(str(c.source.get("kind", "")) == "openstreetmap", "source recorded")
	if c.holes.size() == 1:
		var h := c.holes[0]
		var shift := b.frame.to_local(lat0, lon0)  # the course is centred on its boundary
		check(h.par == 4, "par from the tag")
		check(h.stroke_index == 7, "stroke index from the handicap tag")
		check(h.pin.distance_to(Vector2(5, 165) + shift) < 0.5, "pin from the golf=pin node: %s" % (h.pin - shift))
		check(h.tees.size() == 2, "both tee boxes found: %d" % h.tees.size())
		if h.tees.size() == 2:
			check(h.tees[0].distance_to(Vector2(0, -202.5) + shift) < 1.0, "back tee first: %s" % (h.tees[0] - shift))
		check(h.route.size() == 1, "the dogleg point is an aim point (%d)" % h.route.size())
	var counts := {}
	for s in c.shapes:
		if not s.guessed:
			counts[s.surface] = int(counts.get(s.surface, 0)) + 1
	check(counts.get(Surface.Type.FAIRWAY, 0) == 1, "the fairway relation became one area")
	check(counts.get(Surface.Type.GREEN, 0) == 1 and counts.get(Surface.Type.SAND, 0) == 1 and counts.get(Surface.Type.TEE, 0) == 2, "green, bunker, tees")
	check(counts.get(Surface.Type.WATER, 0) >= 2, "pond and stream are water (%d)" % counts.get(Surface.Type.WATER, 0))
	check(c.paths.size() == 1, "one cart path")
	var pines := 0
	var tall := false
	for o in c.objects:
		if o.id == "tree_pine":
			pines += 1
		if o.scale > 1.45:
			tall = true
	check(pines >= 60, "the needleleaved wood is filled with pines (%d)" % pines)
	check(tall, "the 21 m tree is drawn larger")
	# Heights are kept round zero, so the 5 m rise over the course stays.
	var south := c.base_height(0, c.area.position.y + 2)
	var north := c.base_height(0, c.area.end.y - 2)
	check(absf((north - south) - c.area.size.y / 100.0) < 0.1, "heights follow the ground (%f over %f m)" % [north - south, c.area.size.y])
	# It saves, loads and plays.
	var again := DesignedCourse.from_json(c.to_json())
	check(again != null and again.credits == c.credits and again.holes.size() == 1, "real course round trip")
	var data := c.to_course_data()
	check(data.holes.size() == 1 and data.holes[0].terrain.surface_at(data.holes[0].pin.x, data.holes[0].pin.z) == Surface.Type.GREEN, "the pin is on a green")


static func _rect(a: Vector2, b: Vector2) -> Array:
	return [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]


static func _geom(f: GeoFrame, pts: Array) -> Array:
	var out: Array = []
	for p: Vector2 in pts:
		out.append({"lat": f.lat_of(p), "lon": f.lon_of(p)})
	return out


static func _way(tags: Dictionary, f: GeoFrame, pts: Array, _closed := true) -> Dictionary:
	return {"type": "way", "tags": tags, "geometry": _geom(f, pts)}


## A 4 x 3 float GeoTIFF in strips, in both byte orders, plain and with the
## floating-point predictor and Deflate, as the lidar services send them.
func _test_geo_raster() -> void:
	var heights := PackedFloat32Array([10, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33])
	for be in [false, true]:
		for packed in [false, true]:
			var r := GeoRaster.from_tiff(_tiff(heights, 4, 3, be, packed))
			var what := "%s-endian%s" % ["big" if be else "little", " predictor+deflate" if packed else ""]
			check(r != null, "GeoTIFF reads (%s)" % what)
			if r == null:
				continue
			check(r.width == 4 and r.height == 3 and r.data == heights, "GeoTIFF samples (%s): %s" % [what, r.data])
			check(is_equal_approx(r.west, -1.0) and is_equal_approx(r.north, 51.0) and is_equal_approx(r.dlon, 0.001), "GeoTIFF position (%s)" % what)
			# The centre of pixel (1, 1) is 21 m.
			check(absf(r.sample(51.0 - 0.0015, -1.0 + 0.0015) - 21.0) < 0.001, "GeoTIFF sampling (%s)" % what)
	var bil := GeoRaster.from_bil(heights.to_byte_array(), 4, 3, [50.997, -1.0, 51.0, -0.996])
	check(bil != null and absf(bil.sample(51.0 - 0.0015, -1.0 + 0.0015) - 21.0) < 0.001, "BIL raster")
	var gappy := GeoRaster.from_bil(PackedFloat32Array([1, 2, -99999, 4]).to_byte_array(), 2, 2, [0.0, 0.0, 1.0, 1.0])
	check(is_nan(gappy.sample(0.5, 0.5)) and is_equal_approx(gappy.valid_fraction(), 0.75), "no-data pixels read as NAN")
	check(GeoRaster.from_tiff(PackedByteArray([1, 2, 3])) == null, "junk isn't a GeoTIFF")


func _test_national_lidar() -> void:
	check(str(NationalLidar.source_for(51.4, -0.3).get("id", "")) == "ea", "England uses the Environment Agency")
	check(str(NationalLidar.source_for(52.2, 5.2).get("id", "")) == "ahn", "the Netherlands use AHN")
	check(str(NationalLidar.source_for(36.57, -121.95).get("id", "")) == "3dep", "California uses 3DEP")
	check(NationalLidar.source_for(-33.9, 151.2).is_empty(), "no service for Sydney yet")
	check(str(NationalLidar.source_for(51.3, 4.55).get("id", "")) == "vl", "Flanders uses DHMV")
	check(str(NationalLidar.source_for(51.23, 6.85).get("id", "")) == "nrw", "Duesseldorf uses Geobasis NRW")
	check(str(NationalLidar.source_for(59.93, 10.75).get("id", "")) == "no", "Oslo uses Kartverket")
	check(str(NationalLidar.source_for(35.6, 139.7).get("id", "")) == "gsi", "Tokyo uses the GSI tiles")
	var both := NationalLidar.sources_for(51.4, 3.8)
	check(both.size() == 2 and both[1]["id"] == "ahn", "Zeeland falls back from Flanders to AHN")
	var vl := NationalLidar.new(_lidar_source("vl"), [51.30, 4.55, 51.302, 4.553])
	check(vl.url(vl.chunks[0], false).contains("BBOX=4.5500000,51.3000000,4.5530000,51.3020000"), "WCS 1.0 box is west, south, east, north")
	_test_gsi_tiles()
	var l := NationalLidar.new(NationalLidar.source_for(51.4, -0.3), [51.40, -0.31, 51.42, -0.28])
	# About 2.1 km by 2.2 km at 1 m: 3 x 3 requests of at most 1000 px.
	check(l.chunks.size() == 9, "chunks: %d" % l.chunks.size())
	check(int(l.chunks[0]["cols"]) <= NationalLidar.CHUNK and int(l.chunks[0]["rows"]) <= NationalLidar.CHUNK, "chunk size")
	var u := l.url(l.chunks[0], false)
	check(u.contains("DTM_1m") and u.contains("subset=Lat(51.4000000,"), "WCS url: " + u)
	check(l.url(l.chunks[0], true).contains("FZ_DSM_1m"), "surface model url")
	# Canopy: a 12 m crown on flat ground, and a flat 8 m roof.
	var ground := PackedFloat32Array()
	var top := PackedFloat32Array()
	for j in 40:
		for i in 40:
			ground.append(5.0)
			var crown := maxf(0.0, 12.0 - Vector2(i - 10, j - 10).length() * 2.5)
			var roof := 8.0 if i >= 25 and i < 35 and j >= 25 and j < 35 else 0.0
			top.append(5.0 + maxf(crown, roof))
	var box := [51.0, -1.0, 51.0004, -0.9994]
	var chunk := {"box": box, "cols": 40, "rows": 40}
	var lt := NationalLidar.new(_lidar_source("ign"), box)
	check(lt.add(chunk, ground.to_byte_array(), false) and lt.add(chunk, top.to_byte_array(), true), "BIL chunks load")
	var trees := lt.find_trees()
	check(trees.size() == 1, "one tree found, the roof skipped (%d)" % trees.size())
	if trees.size() == 1:
		check(absf(float(trees[0]["height"]) - 12.0) < 0.01, "tree height from the canopy")


func _lidar_source(id: String) -> Dictionary:
	for s: Dictionary in NationalLidar.SOURCES:
		if s["id"] == id:
			return s
	return {}


## Japan's GSI elevation tiles: chunks per layer, the colour code, and the
## finest layer winning where it has heights.
func _test_gsi_tiles() -> void:
	var box := [35.600, 139.690, 35.610, 139.700]
	var l := NationalLidar.new(_lidar_source("gsi"), box)
	var zooms := {}
	for c in l.chunks:
		zooms[(c["tile"] as Vector3i).z] = true
	check(zooms.has(17) and zooms.has(15) and zooms.has(14), "a chunk per tile of each layer")
	check(l.url(l.chunks[0], false).begins_with("https://cyberjapandata.gsi.go.jp/xyz/dem1a_png/17/"), "finest layer first")
	# One coarse tile with heights 12.34 m and -1.5 m, and a fine tile
	# that is all no data.
	var fine := l.chunks[0]
	var coarse: Dictionary = {}
	var fbox: Array = fine["box"]
	for c in l.chunks:
		var t: Vector3i = c["tile"]
		var b: Array = c["box"]
		var mid_lat := (float(fbox[0]) + float(fbox[2])) * 0.5
		var mid_lon := (float(fbox[1]) + float(fbox[3])) * 0.5
		if t.z == 14 and mid_lat > b[0] and mid_lat < b[2] and mid_lon > b[1] and mid_lon < b[3]:
			coarse = c
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var cm := 1234
	img.fill(Color8((cm >> 16) & 255, (cm >> 8) & 255, cm & 255))
	var neg := 0x1000000 - 150
	img.fill_rect(Rect2i(0, 0, 128, 256), Color8((neg >> 16) & 255, (neg >> 8) & 255, neg & 255))
	check(l.add(coarse, img.save_png_to_buffer(), false), "GSI tile loads")
	var empty := Image.create(256, 256, false, Image.FORMAT_RGB8)
	empty.fill(Color8(128, 0, 0))
	check(l.add(fine, empty.save_png_to_buffer(), false), "an empty fine tile loads")
	var cb: Array = coarse["box"]
	var fb: Array = fine["box"]
	var east := l.ground_at(lerpf(cb[0], cb[2], 0.5), lerpf(cb[1], cb[3], 0.9))
	var west := l.ground_at(lerpf(cb[0], cb[2], 0.5), lerpf(cb[1], cb[3], 0.1))
	check(absf(east - 12.34) < 0.001 and absf(west + 1.5) < 0.001, "GSI heights: %f %f" % [east, west])
	var under := l.ground_at(lerpf(fb[0], fb[2], 0.5), lerpf(fb[1], fb[3], 0.5))
	check(not is_nan(under), "no-data fine tile falls through to the coarse one")
	check(l.coverage() > 0.2, "coverage from the coarse tile: %f" % l.coverage())


func _test_photo_trees() -> void:
	# A 100 x 100 m photo at 1 m: light fairway grass with a dark green
	# 12 m clump of trees in the middle.
	var img := Image.create(100, 100, false, Image.FORMAT_RGB8)
	img.fill(Color(0.55, 0.7, 0.35))
	img.fill_rect(Rect2i(44, 44, 12, 12), Color(0.12, 0.22, 0.1))
	var area := Rect2(-50, -50, 100, 100)
	var found := AerialPhotos.find_trees(img, area, PackedVector2Array([Vector2(-30, -30), Vector2(30, 30)]))
	check(found.size() >= 1 and found.size() <= 9, "the clump is found (%d cells)" % found.size())
	for p in found:
		check(p.length() < 10.0, "tree cells are on the clump: %s" % p)
	check(AerialPhotos.source_for(52.2, 5.2).get("id", "") == "pdok", "Dutch photos from PDOK")
	check(AerialPhotos.source_for(48.2, 16.3).get("id", "") == "basemap", "Vienna photos from basemap.at")
	check(AerialPhotos.source_for(35.6, 139.7).get("id", "") == "gsi", "Tokyo photos from GSI")
	var vl := AerialPhotos.new(AerialPhotos.source_for(51.30, 4.55), [51.300, 4.550, 51.302, 4.553])
	var u := vl.urls()[0]
	var bb := u.get_slice("BBOX=", 1).get_slice("&", 0).split(",")
	check(bb.size() == 4 and absf(float(bb[2]) - float(bb[0]) - 305.748) < 0.01, "WMS tile box in web mercator metres: " + u)
	var white := Image.create(256, 256, false, Image.FORMAT_RGB8)
	white.fill(Color.WHITE)
	check(AerialPhotos.is_blank(white) and not vl.add_tile(0, white.save_jpg_to_buffer()), "white tiles from outside the country don't count")
	var grass := Image.create(256, 256, false, Image.FORMAT_RGB8)
	grass.fill(Color(0.3, 0.45, 0.2))
	grass.fill_rect(Rect2i(0, 0, 100, 100), Color(0.15, 0.25, 0.1))
	check(not AerialPhotos.is_blank(grass), "a photo with a wood in it isn't blank")


## Lidar trees replace the guessed wood fill, and keep off buildings.
func _test_extra_trees() -> void:
	var f := GeoFrame.new(51.0, -1.0)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Lidar Links"}, f, _rect(Vector2(-150, -150), Vector2(150, 150))))
	els.append(_way({"golf": "hole", "ref": "1", "par": "3"}, f, [Vector2(0, -80), Vector2(0, 80)], false))
	els.append(_way({"golf": "green"}, f, _rect(Vector2(-10, 70), Vector2(10, 90))))
	els.append(_way({"natural": "wood"}, f, _rect(Vector2(40, -100), Vector2(120, 100))))
	els.append(_way({"building": "yes"}, f, _rect(Vector2(-100, -20), Vector2(-80, 0))))
	var b := RealCourseBuilder.new({"elements": els}, 51.0, -1.0)
	b.lidar_trees = [
		{"lat": b.frame.lat_of(Vector2(60, 0)), "lon": b.frame.lon_of(Vector2(60, 0)), "height": 20.0},
		{"lat": b.frame.lat_of(Vector2(61, 1)), "lon": b.frame.lon_of(Vector2(61, 1)), "height": 18.0},
		{"lat": b.frame.lat_of(Vector2(-90, -10)), "lon": b.frame.lon_of(Vector2(-90, -10)), "height": 9.0},
		{"lat": b.frame.lat_of(Vector2(-50, 40)), "lon": b.frame.lon_of(Vector2(-50, 40)), "height": 11.0},
	]
	b.extra_credits.append("Lidar: test")
	check(b.course_names().is_empty(), "one course: no names to choose from")
	var c := b.build(func(_la: float, _lo: float) -> float: return 10.0)
	check(c.objects.size() == 2, "lidar trees only: the close pair is one tree, none on the building, no wood fill (%d)" % c.objects.size())
	check(c.credits.ends_with("Lidar: test."), "extra credits")
	# Two courses at one club, told apart by golf:course:name.
	var two: Array = [els[0]]
	for n in 18:
		for name in ["Old", "New"]:
			var x := -120.0 + n * 12.0 + (6.0 if name == "New" else 0.0)
			two.append(_way({"golf": "hole", "ref": str(n + 1), "golf:course:name": name}, f, [Vector2(x, -100), Vector2(x, 100)], false))
	var club := RealCourseBuilder.new({"elements": two}, 51.0, -1.0)
	check(Array(club.course_names()) == ["New", "Old"], "both courses named: %s" % club.course_names())
	club.course_filter = "Old"
	var old := club.build(func(_la: float, _lo: float) -> float: return 10.0)
	check(old.holes.size() == 18 and old.course_name == "Old", "the Old course alone (%d holes)" % old.holes.size())


## A strip GeoTIFF of float heights, 0.001 degree pixels from (51 N, 1 W).
static func _tiff(v: PackedFloat32Array, w: int, h: int, be: bool, packed: bool, u8 := false) -> PackedByteArray:
	var pixels := v.to_byte_array()
	if u8:
		pixels = PackedByteArray()
		for x in v:
			pixels.append(int(x))
	if packed:
		# Floating-point predictor: per row, bytes split into planes (most
		# significant first), then differenced.
		var out := PackedByteArray()
		for y in h:
			var row := PackedByteArray()
			row.resize(w * 4)
			for x in w:
				for byte in 4:
					var src := pixels[(y * w + x) * 4 + byte]
					# Planes run most significant byte first in either byte order.
					row[(3 - byte) * w + x] = src
			var prev := 0
			for k in row.size():
				var cur := row[k]
				row[k] = (cur - prev) & 0xFF
				prev = cur
			out.append_array(row)
		pixels = out.compress(FileAccess.COMPRESSION_DEFLATE)
	elif be:
		var swapped := PackedByteArray()
		for k in range(0, pixels.size(), 4):
			swapped.append_array([pixels[k + 3], pixels[k + 2], pixels[k + 1], pixels[k]])
		pixels = swapped
	var entries := [
		[256, 3, 1, w], [257, 3, 1, h], [258, 3, 1, 8 if u8 else 32], [259, 3, 1, 8 if packed else 1],
		[273, 4, 1, 0], [277, 3, 1, 1], [278, 3, 1, h], [279, 4, 1, pixels.size()],
		[317, 3, 1, 3 if packed else 1], [339, 3, 1, 1 if u8 else 3],
		[33550, 12, 3, [0.001, 0.001, 0.0]], [33922, 12, 6, [0.0, 0.0, 0.0, -1.0, 51.0, 0.0]],
	]
	var ifd_size := 2 + entries.size() * 12 + 4
	var extra_at := 8 + ifd_size
	var extra := PackedByteArray()
	var data_at := extra_at + 3 * 8 + 6 * 8
	var b := PackedByteArray()
	b.append_array([0x4D, 0x4D] if be else [0x49, 0x49])
	b.append_array(_be_or_le(42, 2, be))
	b.append_array(_be_or_le(8, 4, be))
	b.append_array(_be_or_le(entries.size(), 2, be))
	for e: Array in entries:
		b.append_array(_be_or_le(e[0], 2, be))
		b.append_array(_be_or_le(e[1], 2, be))
		b.append_array(_be_or_le(e[2], 4, be))
		if e[1] == 12:
			b.append_array(_be_or_le(extra_at + extra.size(), 4, be))
			for d: float in e[3]:
				var x := PackedByteArray()
				x.resize(8)
				x.encode_double(0, d)
				if be:
					x.reverse()
				extra.append_array(x)
		elif e[0] == 273:
			b.append_array(_be_or_le(data_at, 4, be))
		elif e[1] == 3:
			b.append_array(_be_or_le(e[3], 2, be) + PackedByteArray([0, 0]))
		else:
			b.append_array(_be_or_le(e[3], 4, be))
	b.append_array(PackedByteArray([0, 0, 0, 0]))
	b.append_array(extra)
	b.append_array(pixels)
	return b


static func _be_or_le(v: int, size: int, be: bool) -> PackedByteArray:
	var out := PackedByteArray()
	for k in size:
		out.append((v >> (8 * k)) & 0xFF)
	if be:
		out.reverse()
	return out


## The aerial photo tints the ground: a lot beyond the course, a little on
## the fairway, and the photo's west (+x) half lands on the west half.
func _test_photo_ground() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	var fairway := CourseShape.new()
	fairway.surface = Surface.Type.FAIRWAY
	fairway.points = PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	c.shapes.append(fairway)
	var plain := DesignedTerrain.new(c)
	var oob := plain.ground_color_at(-90, 0)
	var mown := plain.ground_color_at(0, 0)
	# A dry, brown photo whose west (left, +x) half is lighter.
	var img := Image.create(200, 200, false, Image.FORMAT_RGB8)
	img.fill(Color(0.55, 0.45, 0.3))
	img.fill_rect(Rect2i(0, 0, 100, 200), Color(0.75, 0.65, 0.45))
	c.set_photo(img)
	var tinted := DesignedTerrain.new(c)
	var east := tinted.ground_color_at(-90, 0)
	var west := tinted.ground_color_at(90, 0)
	check(east.r / east.g > oob.r / oob.g + 0.2, "the field beyond the course turns brown: %s" % east)
	check(west.get_luminance() > east.get_luminance(), "the photo's west half is the course's +x half")
	var m := tinted.ground_color_at(0, 0)
	check(m.g > m.r and absf(m.r - mown.r) + absf(m.g - mown.g) + absf(m.b - mown.b) < 0.2, "the fairway stays green: %s" % m)


## Land cover: an 8-bit class GeoTIFF, trees where the class says so, and
## the ground picture in the photo's layout (north-west pixel first).
func _test_land_cover() -> void:
	var v := PackedFloat32Array()
	for j in 20:
		for i in 20:
			v.append(LandCover.TREES if i < 10 else LandCover.CROPS)
	var land := LandCover.new([50.98, -1.0, 51.0, -0.98])
	check(land.url().contains("bbox=-1.0000000,50.9800000,-0.9800000,51.0000000") and land.url().contains("pixelType=U8"), "land cover url")
	check(land.add(_tiff(v, 20, 20, false, false, true)), "8-bit class GeoTIFF loads")
	check(land.class_at(50.99, -0.995) == LandCover.TREES and land.class_at(50.99, -0.985) == LandCover.CROPS, "classes by place")
	check(absf(land.coverage() - 1.0) < 0.001, "coverage")
	var f := GeoFrame.new(50.99, -0.99)
	var area := Rect2(-800, -1200, 1600, 2400)
	var trees := land.tree_points(f, area)
	check(trees.size() == 200, "one tree per tree pixel: %d" % trees.size())
	var west_side := true
	for p in trees:
		west_side = west_side and p.x > 0.0
	check(west_side, "the trees are in the west (+x) half")
	var img := land.ground_image(f, Rect2(-600, -1000, 1200, 2000), 50.0)
	var nw := img.get_pixel(1, 1)
	var ne := img.get_pixel(img.get_width() - 2, 1)
	var want_nw: Color = LandCover.COLORS[LandCover.TREES]
	var want_ne: Color = LandCover.COLORS[LandCover.CROPS]
	check(absf(nw.r - want_nw.r) + absf(nw.g - want_nw.g) < 0.02 and absf(ne.r - want_ne.r) + absf(ne.g - want_ne.g) < 0.02, "ground picture: woods to the north-west, fields to the north-east")


## A hole mapped only as a line gets a green, a tee, a fairway and bunkers
## at typical sizes, all marked guessed; a fully mapped hole gets nothing.
func _test_guesser() -> void:
	var c := DesignedCourse.blank(Vector2(600, 600))
	var h := DesignedHole.new()
	h.tees = PackedVector2Array([Vector2(0, -200)])
	h.pin = Vector2(0, 180)
	h.par = 4
	c.holes.append(h)
	var added := CourseGuesser.fill(c, 7)
	var by := {}
	for s in added:
		check(s.guessed, "guessed shapes are marked")
		by[s.surface] = int(by.get(s.surface, 0)) + 1
	check(by.get(Surface.Type.GREEN, 0) == 1 and by.get(Surface.Type.TEE, 0) == 1 and by.get(Surface.Type.FAIRWAY, 0) == 1, "green, tee and fairway: %s" % by)
	check(int(by.get(Surface.Type.SAND, 0)) >= 3, "greenside and fairway bunkers: %s" % by)
	var green: CourseShape = null
	var fairway: CourseShape = null
	for s in added:
		if s.surface == Surface.Type.GREEN:
			green = s
		elif s.surface == Surface.Type.FAIRWAY:
			fairway = s
	if green != null:
		var ring := green.outline()
		var a := absf(_ring_area_of(ring))
		check(a > 380.0 and a < 800.0, "green size: %.0f m2" % a)
		check(Geometry2D.is_point_in_polygon(h.pin, ring), "the pin is on the green")
		check(green.bounds().size.y > green.bounds().size.x, "the green is longer along the approach")
	if fairway != null:
		check(Geometry2D.is_point_in_polygon(Vector2(0, 30), fairway.outline()), "the fairway covers the landing area")
		check(fairway.bounds().size.x > 25.0 and fairway.bounds().size.x < 45.0, "fairway width: %.1f" % fairway.bounds().size.x)
		check(not Geometry2D.is_point_in_polygon(Vector2(0, -190), fairway.outline()), "no fairway at the tee")
	var saved := DesignedCourse.from_json(c.to_json())
	var kept := 0
	for s in saved.shapes:
		if s.guessed:
			kept += 1
	check(kept == added.size(), "the guessed mark is saved")
	check(CourseGuesser.fill(c, 7).is_empty(), "a hole with everything gets nothing more")


static func _ring_area_of(ring: PackedVector2Array) -> float:
	var a := 0.0
	for k in ring.size():
		var p := ring[k]
		var q := ring[(k + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Greens and bunkers found in a photo, and bunkers as lidar hollows, take
## the place of guesses.
func _test_detector() -> void:
	var c := DesignedCourse.blank(Vector2(600, 600))
	var h := DesignedHole.new()
	h.tees = PackedVector2Array([Vector2(0, -150)])
	h.pin = Vector2(0, 180)
	h.par = 4
	c.holes.append(h)
	# 1 m photo: rough, a lighter round green of 13 m radius at the pin
	# (pixel (300 - x, 300 - z)), a bunker to its +x side, and a long sandy
	# track that isn't a bunker.
	var photo := Image.create(600, 600, false, Image.FORMAT_RGB8)
	photo.fill(Color(0.25, 0.4, 0.17))
	for j in 600:
		for i in 600:
			var p := Vector2(300 - i, 300 - j)
			if p.distance_to(h.pin) < 13.0:
				photo.set_pixel(i, j, Color(0.36, 0.6, 0.3))
			elif Rect2(16, 176, 8, 6).has_point(p):
				photo.set_pixel(i, j, Color(0.86, 0.8, 0.64))
	photo.fill_rect(Rect2i(250, 80, 3, 100), Color(0.8, 0.76, 0.66))
	var added := CourseGuesser.fill(c, 5, photo, false)
	var green: CourseShape = null
	var sand: Array[CourseShape] = []
	for s in added:
		if s.surface == Surface.Type.GREEN:
			green = s
		elif s.surface == Surface.Type.SAND:
			sand.append(s)
	check(green != null and green.has_meta("detected"), "the green is found in the photo")
	if green != null:
		var a := absf(_ring_area_of(green.outline()))
		check(a > 420.0 and a < 650.0, "found green size: %.0f m2" % a)
	check(sand.size() == 1 and sand[0].has_meta("detected"), "one bunker found, the track left out (%d)" % sand.size())
	if sand.size() == 1:
		check(sand[0].bounds().get_center().distance_to(Vector2(20, 179)) < 2.0, "bunker in place: %s" % sand[0].bounds().get_center())
	# Lidar: flat ground with a 0.8 m hollow beside the pin, no photo.
	var c2 := DesignedCourse.blank(Vector2(600, 600))
	c2.holes.append(h)
	for j in c2.rows:
		for i in c2.cols:
			var p := c2.sample_pos(i, j)
			c2.heights[j * c2.cols + i] = -0.8 if Rect2(-26, 176, 7, 5).has_point(p) else 0.0
	var sand2: Array[CourseShape] = []
	for s in CourseGuesser.fill(c2, 5, null, true):
		if s.surface == Surface.Type.SAND:
			sand2.append(s)
	check(sand2.size() == 1 and sand2[0].has_meta("detected"), "one bunker found as a lidar hollow (%d)" % sand2.size())
