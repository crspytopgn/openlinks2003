class_name CourseDetector
extends RefCounted
## Finds a hole's real green and bunkers where the map doesn't have them,
## for CourseGuesser:
##
## in the aerial photo, a green is the patch of evenly coloured mown grass
## round the pin, a bunker a compact patch of bright sand cut into grass,
## and a fairway the band of mown grass along the hole's line.
##
## Outlines come back as course points (x, z), simplified, ready for a
## CourseShape. An empty result means nothing convincing was found.

const GREEN_REACH := 26.0  ## metres from the pin a green may reach
const GREEN_AREA := Vector2(150.0, 1200.0)  ## m2, smallest and largest
const GREEN_STEP := 0.005  ## colour distances tried, in steps of this
const GREEN_STEPS := 18
const SAND_AREA := Vector2(15.0, 600.0)  ## m2
const SAND_THICK := 3.0  ## metres; thinner patches are paths and tracks
const SAND_MAX_SIZE := 50.0  ## metres, longest side
const SAND_LEVELS := [0.6, 0.66, 0.72, 0.78, 0.84]  ## brightness tried
const SAND_RIM := 3.0  ## metres out, where the grass round a bunker is read
const SAND_GRASS := 0.5  ## share of that rim that must be green
const SAND_CONTRAST := 0.15  ## how much brighter than the rim a bunker is
const FAIRWAY_STEP := 10.0  ## metres between cross-sections
const FAIRWAY_REACH := 50.0  ## metres either side of the line looked at
const FAIRWAY_WIDTH := Vector2(15.0, 60.0)  ## metres, narrowest and widest
const FAIRWAY_MATCH := 0.07  ## colour distance from the fairway's own colour
const FAIRWAY_NONE := 0.6  ## cost of a cross-section with no fairway
const FAIRWAY_JUMP := 8.0  ## metres an edge may move between cross-sections
const FAIRWAY_JOIN := 2  ## bad cross-sections a fairway may bridge
const FAIRWAY_SHARE := 0.35  ## of the stretch looked at, the least a fairway covers
const FAIRWAY_STEADY := 0.25  ## widest spread of widths along it, over its mean
const FAIRWAY_GAP := 3.0  ## metres of other colour that end a fairway's edge


## Metres per pixel of a course photo across and down.
static func _res(photo: Image, area: Rect2) -> Vector2:
	return Vector2(area.size.x / photo.get_width(), area.size.y / photo.get_height())


## Photo pixel of a course point (the photo's first pixel is the
## north-west, +x +z, corner).
static func _px(photo: Image, area: Rect2, p: Vector2) -> Vector2i:
	var r := _res(photo, area)
	return Vector2i(floori((area.end.x - p.x) / r.x), floori((area.end.y - p.y) / r.y))


static func _pt(photo: Image, area: Rect2, q: Vector2i) -> Vector2:
	var r := _res(photo, area)
	return Vector2(area.end.x - (q.x + 0.5) * r.x, area.end.y - (q.y + 0.5) * r.y)


## The green round `pin` in the photo: the evenly coloured grass that
## grows out from the pin, with the loosest colour match that doesn't yet
## leak out to GREEN_REACH (into the fringe and fairway, which are much
## the same colour). Empty if none fits.
static func find_green(photo: Image, area: Rect2, pin: Vector2) -> PackedVector2Array:
	if photo == null:
		return PackedVector2Array()
	var res := _res(photo, area)
	var px_area := res.x * res.y
	var seed_px := _px(photo, area, pin)
	var w := photo.get_width()
	var h := photo.get_height()
	if seed_px.x < 1 or seed_px.y < 1 or seed_px.x >= w - 1 or seed_px.y >= h - 1:
		return PackedVector2Array()
	# The green's colour: the middle of the colours within 4 m of the pin
	# (the pin may be mapped a little off, and the flag and cup aren't grass).
	var rs: Array[float] = []
	var gs: Array[float] = []
	var bs: Array[float] = []
	var near := ceili(4.0 / minf(res.x, res.y))
	for dj in range(-near, near + 1):
		for di in range(-near, near + 1):
			var q := seed_px + Vector2i(di, dj)
			if Vector2(di, dj).length() <= near and q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
				var c := photo.get_pixelv(q)
				rs.append(c.r)
				gs.append(c.g)
				bs.append(c.b)
	rs.sort()
	gs.sort()
	bs.sort()
	var seed_col := Color(rs[rs.size() >> 1], gs[gs.size() >> 1], bs[bs.size() >> 1])
	# Mown grass: green the strongest channel. Not on sand, water or a path.
	if seed_col.g <= seed_col.r or seed_col.g <= seed_col.b or seed_col.get_luminance() < 0.12:
		return PackedVector2Array()
	var reach := ceili(GREEN_REACH / minf(res.x, res.y))
	var best := PackedVector2Array()
	for k in range(3, GREEN_STEPS + 1):
		var step := k * GREEN_STEP
		var ok := func(c: Color) -> bool:
			return Vector3(c.r - seed_col.r, c.g - seed_col.g, c.b - seed_col.b).length() < step
		var region := _grow(photo, _seed_ok(photo, seed_px, ok), reach, ok)
		var cells: Array = region["cells"]
		var size := cells.size() * px_area
		# Leaking out into the fringe and fairway shows as reaching GREEN_REACH.
		if int(region["edge"]) > 0 or size > GREEN_AREA.y:
			break
		if size >= GREEN_AREA.x:
			best = _outline(photo, area, cells)
	return best


## Bunkers (bright sand) in the photo within `radius` of `centre`.
static func find_sand(photo: Image, area: Rect2, centre: Vector2, radius: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if photo == null:
		return out
	var res := _res(photo, area)
	var c0 := _px(photo, area, centre)
	var reach := ceili(radius / minf(res.x, res.y))
	# A bunker can touch pale ground (winter grass, dunes, paths) that is
	# nearly as bright, so the patch is read at rising brightness until it
	# stands alone. The first brightness at which a patch passes wins.
	var taken := {}
	for level in SAND_LEVELS:
		var ok := func(col: Color) -> bool: return is_sand(col) and col.get_luminance() > level
		for cells in _patches(photo, c0, reach, ok):
			var hit := false
			for q: Vector2i in cells:
				if taken.has(q):
					hit = true
					break
			if hit:
				continue
			var ring := _sand_ring(photo, area, cells, res)
			if ring.is_empty():
				continue
			for q: Vector2i in cells:
				taken[q] = true
			out.append(ring)
	return out


## The connected patches of pixels passing `ok` that start within `reach`
## of `c0`.
static func _patches(photo: Image, c0: Vector2i, reach: int, ok: Callable) -> Array:
	var out := []
	var seen := {}
	var w := photo.get_width()
	var h := photo.get_height()
	for j in range(maxi(c0.y - reach, 0), mini(c0.y + reach + 1, h)):
		for i in range(maxi(c0.x - reach, 0), mini(c0.x + reach + 1, w)):
			var q := Vector2i(i, j)
			if seen.has(q) or (q - c0).length() > reach or not ok.call(photo.get_pixelv(q)):
				continue
			var cells: Array = _grow(photo, q, reach * 2, ok)["cells"]
			for k in cells:
				seen[k] = true
			out.append(cells)
	return out


## The outline of a patch of sand pixels if it looks like a bunker, else
## empty.
static func _sand_ring(photo: Image, area: Rect2, cells: Array, res: Vector2) -> PackedVector2Array:
	var size := cells.size() * res.x * res.y
	if size < SAND_AREA.x or size > SAND_AREA.y:
		return PackedVector2Array()
	var ring := _outline(photo, area, cells)
	if ring.size() < 3:
		return ring
	var b := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		b = b.expand(p)
	# A bunker is compact; paths, roads and roofs are long or square.
	var longest := maxf(b.size.x, b.size.y)
	# Thin in any direction (a path, even a diagonal one) is no bunker.
	if longest > SAND_MAX_SIZE or size < absf(_area_of(ring)) * 0.45 or size / longest < SAND_THICK or min_width(ring) < SAND_THICK:
		return PackedVector2Array()
	# A bunker is cut into grass: clearly brighter than the grass round
	# it. Pale dunes, heather and bare ground aren't.
	if not _in_grass(photo, cells, res):
		return PackedVector2Array()
	return ring


## Whether a patch of pixels sits in grass and stands out from it: most of
## the ground SAND_RIM metres round it is green, and the patch is clearly
## brighter.
static func _in_grass(photo: Image, cells: Array, res: Vector2) -> bool:
	var inside := {}
	var lum := 0.0
	for q: Vector2i in cells:
		inside[q] = true
		lum += photo.get_pixelv(q).get_luminance()
	lum /= maxf(cells.size(), 1.0)
	var step := maxi(1, cells.size() >> 7)
	var rim := Vector2i(maxi(1, roundi(SAND_RIM / res.x)), maxi(1, roundi(SAND_RIM / res.y)))
	var n := 0
	var green := 0
	var around := 0.0
	for k in range(0, cells.size(), step):
		var q: Vector2i = cells[k]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var o: Vector2i = q + d * rim
			if o.x < 0 or o.y < 0 or o.x >= photo.get_width() or o.y >= photo.get_height() or inside.has(o):
				continue
			var c := photo.get_pixelv(o)
			n += 1
			around += c.get_luminance()
			if not is_sand(c) and c.g >= c.r * 0.97 and c.g > c.b * 1.05:
				green += 1
	if n == 0:
		return false
	return green >= n * SAND_GRASS and lum - around / n >= SAND_CONTRAST


## Bright, whitish or pale yellow: sand rather than grass, trees, dead
## bracken or water.
static func is_sand(c: Color) -> bool:
	var lum := c.get_luminance()
	var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	return lum > 0.6 and c.r >= c.g * 0.95 and c.g >= c.b * 0.95 and sat < 0.22


## The fairway along a hole's line in the photo, between `start` and
## `stop` metres along it. Cross-sections every FAIRWAY_STEP metres find the
## bands of mown grass of the line's own colour, of a fairway's width
## (trees, rough and heather end them), within FAIRWAY_REACH of the line;
## one band per section is picked so the fairway keeps near the line and
## runs on smoothly. The longest run of picked bands (bridging a few
## missing ones), at least FAIRWAY_SHARE of the stretch, with steady
## widths, becomes the outline. Empty if none.
static func find_fairway(photo: Image, area: Rect2, line: PackedVector2Array, start: float, stop: float) -> PackedVector2Array:
	if photo == null or stop - start < 4.0 * FAIRWAY_STEP:
		return PackedVector2Array()
	# Work on a softened copy (about 2.5 m a pixel): single pixels of a
	# photo are noisy, and a fairway is wide.
	var res := _res(photo, area)
	var soft: Image = photo.duplicate()
	var shrink := maxf(1.0, 2.5 / minf(res.x, res.y))
	soft.resize(maxi(2, roundi(photo.get_width() / shrink)), maxi(2, roundi(photo.get_height() / shrink)), Image.INTERPOLATE_BILINEAR)
	var step_m := minf(_res(soft, area).x, _res(soft, area).y)
	# The fairway's colour: the middle of the grass colours on the line.
	var rs: Array[float] = []
	var gs: Array[float] = []
	var bs: Array[float] = []
	var d := start
	while d <= stop:
		var c := _color_at(soft, area, CourseGuesser._point_at(line, d))
		if c.g > c.r and c.g > c.b and c.get_luminance() > 0.2:
			rs.append(c.r)
			gs.append(c.g)
			bs.append(c.b)
		d += 2.0
	if rs.size() < 10:
		return PackedVector2Array()
	rs.sort()
	gs.sort()
	bs.sort()
	var ref := Color(rs[rs.size() >> 1], gs[gs.size() >> 1], bs[bs.size() >> 1])
	# Cross-sections: the bands of fairway-coloured grass (gaps of at most
	# FAIRWAY_GAP) of a fairway's width. Mappers' hole lines often cut
	# corners or cross water, so the fairway needn't touch the line.
	var dists: Array[float] = []
	var bands: Array = []  # per section: [Vector2(low, high)] metres along `side`
	var n := ceili(FAIRWAY_REACH / step_m)
	var gap := maxi(1, floori(FAIRWAY_GAP / step_m))
	d = start
	while d <= stop:
		var p := CourseGuesser._point_at(line, d)
		var side := CourseGuesser._dir_at(line, d).orthogonal()
		var hits := PackedByteArray()
		hits.resize(2 * n + 1)
		for k in 2 * n + 1:
			var at := p + side * (k - n) * step_m
			var c := _color_at(soft, area, at)
			hits[k] = 1 if Vector3(c.r - ref.r, c.g - ref.g, c.b - ref.b).length() < FAIRWAY_MATCH else 0
		var here: Array[Vector2] = []
		var k0 := -1
		var last := -100
		for k in 2 * n + 2:
			var hit := k < 2 * n + 1 and hits[k] == 1
			if hit and k0 >= 0 and k - last <= gap + 1:
				last = k
				continue
			if k0 >= 0:
				var band := Vector2((k0 - n - 0.5) * step_m, (last - n + 0.5) * step_m)
				# Bands cut by the edge of the area looked at aren't measured.
				if band.y - band.x >= FAIRWAY_WIDTH.x and band.y - band.x <= FAIRWAY_WIDTH.y and k0 > 0 and last < 2 * n:
					here.append(band)
			k0 = k if hit else -1
			last = k
		dists.append(d)
		bands.append(here)
		d += FAIRWAY_STEP
	# One band per section, or none, so the fairway runs on smoothly:
	# least cost for its distance from the line plus its jumps sideways.
	var count_s := dists.size()
	var cost: Array = []
	var from: Array = []
	for k in count_s:
		var here: Array = bands[k]
		var row := PackedFloat32Array()
		var back := PackedInt32Array()
		row.resize(here.size() + 1)
		back.resize(here.size() + 1)
		for b2 in here.size() + 1:
			var own := FAIRWAY_NONE
			if b2 < here.size():
				var mid: float = (here[b2].x + here[b2].y) * 0.5
				own = absf(mid) / FAIRWAY_REACH * 0.5
			var best_c := 0.0 if k == 0 else INF
			var best_b := -1
			if k > 0:
				var prev: Array = bands[k - 1]
				for a2 in prev.size() + 1:
					var jump := 0.0
					if a2 < prev.size() and b2 < here.size():
						jump = (absf(prev[a2].x - here[b2].x) + absf(prev[a2].y - here[b2].y)) * 0.5 / FAIRWAY_JUMP
						if jump > 1.0:
							continue
					var cc: float = cost[k - 1][a2] + jump
					if cc < best_c:
						best_c = cc
						best_b = a2
			row[b2] = best_c + own
			back[b2] = best_b
		cost.append(row)
		from.append(back)
	var sections: Array[Vector3] = []  # distance, reach along +side, along -side
	var valid := PackedByteArray()
	sections.resize(count_s)
	valid.resize(count_s)
	if count_s > 0:
		var last_row: PackedFloat32Array = cost[count_s - 1]
		var pick := 0
		for b2 in last_row.size():
			if last_row[b2] < last_row[pick]:
				pick = b2
		for k in range(count_s - 1, -1, -1):
			var here: Array = bands[k]
			if pick < here.size():
				sections[k] = Vector3(dists[k], here[pick].y, -here[pick].x)
				valid[k] = 1
			else:
				sections[k] = Vector3(dists[k], 0, 0)
				valid[k] = 0
			pick = from[k][pick]
	# The longest run of good cross-sections, across gaps of up to
	# FAIRWAY_JOIN bad ones (a cross bunker, a path, a shadow), which take
	# their neighbours' edges.
	var run := Vector2i(0, 0)
	var run_start := -1
	var bad := 0
	for k in sections.size() + 1:
		var good := k < sections.size() and valid[k] == 1
		if good:
			if run_start < 0:
				run_start = k
			bad = 0
		elif run_start >= 0:
			bad += 1
			if bad > FAIRWAY_JOIN or k == sections.size():
				var end := k - bad + 1
				if end - run_start > run.y - run.x:
					run = Vector2i(run_start, end)
				run_start = -1
				bad = 0
	if run.y - run.x < maxi(4, ceili(sections.size() * FAIRWAY_SHARE)):
		return PackedVector2Array()
	for k in range(run.x, run.y):
		if valid[k] == 0:
			var a := k - 1
			var b := k + 1
			while valid[b] == 0:
				b += 1
			var t := float(k - a) / (b - a)
			sections[k] = Vector3(sections[k].x, lerpf(sections[a].y, sections[b].y, t), lerpf(sections[a].z, sections[b].z, t))
	# A mown fairway has steady edges; a ragged band is rough, heather or
	# light through trees.
	var sum := 0.0
	var sum2 := 0.0
	for k in range(run.x, run.y):
		var w := sections[k].y + sections[k].z
		sum += w
		sum2 += w * w
	var count := run.y - run.x
	var mean := sum / count
	if sqrt(maxf(sum2 / count - mean * mean, 0.0)) > mean * FAIRWAY_STEADY:
		return PackedVector2Array()
	# Each edge smoothed over its neighbours (a median of three).
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in range(run.x, run.y):
		var a := sections[maxi(k - 1, run.x)]
		var b := sections[k]
		var c := sections[mini(k + 1, run.y - 1)]
		var p := CourseGuesser._point_at(line, b.x)
		var side := CourseGuesser._dir_at(line, b.x).orthogonal()
		left.append(p + side * _median3(a.y, b.y, c.y))
		right.append(p - side * _median3(a.z, b.z, c.z))
	right.reverse()
	left.append_array(right)
	return RealCourseBuilder.simplify_ring(left, 1.0)


static func _median3(a: float, b: float, c: float) -> float:
	return maxf(minf(a, b), minf(maxf(a, b), c))


static func _color_at(photo: Image, area: Rect2, p: Vector2) -> Color:
	var q := _px(photo, area, p)
	if q.x < 0 or q.y < 0 or q.x >= photo.get_width() or q.y >= photo.get_height():
		return Color(0, 0, 0)
	return photo.get_pixelv(q)


## The narrowest width of a convex outline (its smallest extent across any
## of its edges).
static func min_width(ring: PackedVector2Array) -> float:
	var best := INF
	for k in ring.size():
		var a := ring[k]
		var b := ring[(k + 1) % ring.size()]
		var n := (b - a).orthogonal().normalized()
		if n == Vector2.ZERO:
			continue
		var far := 0.0
		for p in ring:
			far = maxf(far, absf((p - a).dot(n)))
		best = minf(best, far)
	return best if best < INF else 0.0


## Pixels 4-connected to `start` that pass `ok`, at most `reach` pixels
## away: {"cells": [Vector2i], "edge": pixels at the reach limit}.
static func _grow(photo: Image, start: Vector2i, reach: int, ok: Callable) -> Dictionary:
	var w := photo.get_width()
	var h := photo.get_height()
	var cells: Array[Vector2i] = []
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	var edge := 0
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		cells.append(p)
		if (p - start).length() >= reach - 1:
			edge += 1
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or seen.has(q):
				continue
			seen[q] = true
			if ok.call(photo.get_pixelv(q)):
				stack.append(q)
	return {"cells": cells, "edge": edge}


## The pixel nearest `start` (within 3) that passes `ok`, to seed a region
## (the pin itself may sit on the cup or flag); `start` if none does.
static func _seed_ok(photo: Image, start: Vector2i, ok: Callable) -> Vector2i:
	for r in 4:
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				var q := start + Vector2i(di, dj)
				if q.x >= 0 and q.y >= 0 and q.x < photo.get_width() and q.y < photo.get_height() and ok.call(photo.get_pixelv(q)):
					return q
	return start


## A simplified outline round photo pixels (their convex hull).
static func _outline(photo: Image, area: Rect2, cells: Array) -> PackedVector2Array:
	var r := _res(photo, area) * 0.5
	var pts := PackedVector2Array()
	for q: Vector2i in cells:
		var p := _pt(photo, area, q)
		pts.append_array([p + Vector2(-r.x, -r.y), p + Vector2(r.x, -r.y), p + Vector2(r.x, r.y), p + Vector2(-r.x, r.y)])
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return RealCourseBuilder.simplify_ring(hull, 0.5) if hull.size() >= 3 else PackedVector2Array()


static func _area_of(ring: PackedVector2Array) -> float:
	var a := 0.0
	for k in ring.size():
		var p := ring[k]
		var q := ring[(k + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5
