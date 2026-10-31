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
	return failures


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _test_scripts_compile() -> void:
	for path in ["res://scripts/realcourse/real_course_fetcher.gd", "res://scripts/realcourse/real_course_dialog.gd"]:
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
