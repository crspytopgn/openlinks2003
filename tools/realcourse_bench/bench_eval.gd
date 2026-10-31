extends SceneTree
# Benchmark: for each course in /tmp/bench, hide the mapped greens, bunkers
# and fairways, run the guesser, and score what it finds against the map.
# Output: one line per course plus totals.

var tot := {}

func _initialize() -> void:
	var only := OS.get_cmdline_user_args()
	var files := DirAccess.get_files_at("/tmp/bench")
	for f in files:
		if not f.ends_with(".olc"):
			continue
		var slug := f.get_basename()
		if not only.is_empty() and not slug in only:
			continue
		_eval(slug)
	print("TOTAL ", _fmt(tot))
	quit()


func _add(k: String, v: float) -> void:
	tot[k] = tot.get(k, 0.0) + v


func _fmt(d: Dictionary) -> String:
	var g: float = d.get("g_mapped", 0.0)
	var s := "greens %d: found %d, good %d, iou %.2f, wrong %d | " % [g, d.get("g_found", 0.0), d.get("g_good", 0.0), d.get("g_iou", 0.0) / maxf(d.get("g_found", 0.0), 1.0), d.get("g_wrong", 0.0)]
	s += "sand %d: found %d, hit %d, false %d, mapped found %d | " % [d.get("s_mapped", 0.0), d.get("s_found", 0.0), d.get("s_hit", 0.0), d.get("s_false", 0.0), d.get("s_recall", 0.0)]
	s += "fairways %d: found %d, iou %.2f, bad %d" % [d.get("f_holes", 0.0), d.get("f_found", 0.0), d.get("f_iou", 0.0) / maxf(d.get("f_found", 0.0), 1.0), d.get("f_bad", 0.0)]
	return s


static func area(r: PackedVector2Array) -> float:
	return absf(CourseDetector._area_of(r))


static func inter(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var t := 0.0
	for p in Geometry2D.intersect_polygons(a, b):
		t += area(p)
	return t


static func iou(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var i := inter(a, b)
	return i / maxf(area(a) + area(b) - i, 1.0)


func _eval(slug: String) -> void:
	var c := DesignedCourse.load_file("/tmp/bench/%s.olc" % slug)
	if c == null:
		return
	var photo: Image = null
	if FileAccess.file_exists("/tmp/bench/%s.photo.jpg" % slug):
		photo = Image.load_from_file("/tmp/bench/%s.photo.jpg" % slug)
	var lidar: bool = FileAccess.get_file_as_string("/tmp/bench/%s.log" % slug).contains("lidar")
	var greens: Array[PackedVector2Array] = []
	var sands: Array[PackedVector2Array] = []
	var fairways: Array[PackedVector2Array] = []
	var keep: Array[CourseShape] = []
	for s in c.shapes:
		if s.guessed:
			continue
		match s.surface:
			Surface.Type.GREEN:
				greens.append(s.outline())
			Surface.Type.SAND:
				sands.append(s.outline())
			Surface.Type.FAIRWAY:
				fairways.append(s.outline())
			_:
				keep.append(s)
	c.shapes = keep
	var d := {}
	# Mapped greens that hold a pin.
	for h in c.holes:
		for g in greens:
			if Geometry2D.is_point_in_polygon(h.pin, g):
				d["g_mapped"] = d.get("g_mapped", 0.0) + 1
				break
	var t0 := Time.get_ticks_msec()
	var added := CourseGuesser.fill(c, 1, photo if OS.get_environment("NOPHOTO") == "" else null, load_details(slug))
	var ms := Time.get_ticks_msec() - t0
	for s in added:
		if not s.found:
			continue
		var o := s.outline()
		match s.surface:
			Surface.Type.GREEN:
				var best := 0.0
				for g in greens:
					best = maxf(best, iou(o, g))
				d["g_found"] = d.get("g_found", 0.0) + 1
				d["g_iou"] = d.get("g_iou", 0.0) + best
				if best >= 0.6:
					d["g_good"] = d.get("g_good", 0.0) + 1
				elif best < 0.2:
					d["g_wrong"] = d.get("g_wrong", 0.0) + 1
			Surface.Type.SAND:
				d["s_found"] = d.get("s_found", 0.0) + 1
				var hit := false
				for g in sands:
					if inter(o, g) > 0.25 * minf(area(o), area(g)):
						hit = true
						break
				d["s_hit" if hit else "s_false"] = d.get("s_hit" if hit else "s_false", 0.0) + 1
			Surface.Type.FAIRWAY:
				var best := 0.0
				var cov := 0.0
				for g in fairways:
					cov += inter(o, g)
				best = cov / maxf(area(o), 1.0)
				d["f_found"] = d.get("f_found", 0.0) + 1
				d["f_iou"] = d.get("f_iou", 0.0) + best
				if best < 0.5:
					d["f_bad"] = d.get("f_bad", 0.0) + 1
	# Mapped bunkers within reach of where the detector looks, and found.
	for g in sands:
		var mid := CourseGuesser._ring_centre(g)
		var near := false
		for h in c.holes:
			if mid.distance_to(h.pin) < 45.0:
				near = true
		if not near:
			continue
		d["s_mapped"] = d.get("s_mapped", 0.0) + 1
		for s in added:
			if s.surface == Surface.Type.SAND and s.found and inter(s.outline(), g) > 0.0:
				d["s_recall"] = d.get("s_recall", 0.0) + 1
				break
	for h in c.holes:
		if h.par >= 4:
			d["f_holes"] = d.get("f_holes", 0.0) + 1
	for k in d:
		_add(k, d[k])
	print("%-14s %s %s %4d ms | %s" % [slug, "photo" if photo else "-----", "lidar" if lidar else "-----", ms, _fmt(d)])


static func load_details(slug: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if OS.get_environment("NODETAIL") != "" or not FileAccess.file_exists("/tmp/bench/%s.details.json" % slug):
		return out
	for m in JSON.parse_string(FileAccess.get_file_as_string("/tmp/bench/%s.details.json" % slug)):
		var img := Image.load_from_file("/tmp/bench/%s.d%d.png" % [slug, int(m["k"])])
		out.append({"image": img, "area": Rect2(m["x"], m["y"], m["s"], m["s"])})
	return out
