extends SceneTree
# bench_view.gd -- slug [first_hole]: 6 holes, photo crops (close-ups when there are) round the pin.
# Left: mapped (green white, sand yellow, fairway blue). Right: found (green cyan, sand red, hollow magenta).
const S := 300  # output pixels per crop side
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var slug := a[0]
	var first := int(a[1]) if a.size() > 1 else 0
	var c := DesignedCourse.load_file("/tmp/bench/%s.olc" % slug)
	var photo := Image.load_from_file("/tmp/bench/%s.photo.jpg" % slug)
	photo.convert(Image.FORMAT_RGB8)
	var keep: Array[CourseShape] = []
	var mapped: Array[CourseShape] = []
	for s in c.shapes:
		if s.guessed:
			continue
		if s.surface in [Surface.Type.GREEN, Surface.Type.SAND, Surface.Type.FAIRWAY]:
			mapped.append(s)
		else:
			keep.append(s)
	c.shapes = keep
	var dets := load_details(slug)
	var added := CourseGuesser.fill(c, 1, photo, dets)
	var n := mini(6, c.holes.size() - first)
	var out := Image.create(S * 2, S * n, false, Image.FORMAT_RGB8)
	for k in n:
		var h := c.holes[first + k]
		var img := photo
		var area := c.area
		for d in dets:
			if (d["area"] as Rect2).grow(-45.0).has_point(h.pin):
				img = d["image"]
				area = d["area"]
		img.convert(Image.FORMAT_RGB8)
		var res := CourseDetector._res(img, area)
		var half := int(55.0 / res.x)
		var q := CourseDetector._px(img, area, h.pin)
		var r := Rect2i(q - Vector2i(half, half), Vector2i(half * 2, half * 2))
		var left: Image = img.get_region(r)
		left.resize(S, S, Image.INTERPOLATE_BILINEAR)
		var right: Image = left.duplicate()
		var f := float(S) / (half * 2)
		for s in mapped:
			var col := Color.WHITE if s.surface == Surface.Type.GREEN else (Color.YELLOW if s.surface == Surface.Type.SAND else Color(0.3, 0.6, 1))
			_draw(left, img, area, s.outline(), r, f, col)
		for s in added:
			if not s.found:
				continue
			var col := Color.CYAN if s.surface == Surface.Type.GREEN else (Color.RED if s.surface == Surface.Type.SAND else Color(0.3, 0.6, 1))
			if s.has_meta("by") and s.get_meta("by") == "lidar":
				col = Color.MAGENTA
			_draw(right, img, area, s.outline(), r, f, col)
		out.blit_rect(left, Rect2i(0, 0, S, S), Vector2i(0, k * S))
		out.blit_rect(right, Rect2i(0, 0, S, S), Vector2i(S, k * S))
	out.save_png("/tmp/bench/view_%s_%d.png" % [slug, first])
	quit()


func _draw(img: Image, photo: Image, area: Rect2, ring: PackedVector2Array, r: Rect2i, f: float, col: Color) -> void:
	for i in ring.size():
		var p0 := ring[i]
		var p1 := ring[(i + 1) % ring.size()]
		var steps := ceili(p0.distance_to(p1) / 0.2) + 1
		for t in steps:
			var pp := Vector2(CourseDetector._px(photo, area, p0.lerp(p1, float(t) / steps)) - r.position) * f
			var pi := Vector2i(pp)
			if Rect2i(0, 0, S - 1, S - 1).has_point(pi):
				img.set_pixelv(pi, col)
				img.set_pixelv(pi + Vector2i(1, 0), col)


static func load_details(slug: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if OS.get_environment("NODETAIL") != "" or not FileAccess.file_exists("/tmp/bench/%s.details.json" % slug):
		return out
	for m in JSON.parse_string(FileAccess.get_file_as_string("/tmp/bench/%s.details.json" % slug)):
		var img := Image.load_from_file("/tmp/bench/%s.d%d.png" % [slug, int(m["k"])])
		out.append({"image": img, "area": Rect2(m["x"], m["y"], m["s"], m["s"])})
	return out
