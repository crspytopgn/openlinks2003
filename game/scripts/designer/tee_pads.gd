class_name TeePads
extends RefCounted
## Raised tee pads for a DesignedTerrain, drawn and played at fine detail.
##
## Real tee boxes are built as level platforms a little proud of the ground
## round them, mown right out to a clean shoulder, with banks no steeper
## than about 1 in 3 so they can be mown (USGA construction guidance), tied
## into the ground over a few metres. The course's 2 m height grid can't
## hold a shoulder that sharp: a bank a metre or two wide falls between
## grid points and comes out as a soft hump. So each tee, or each group of
## tees whose banks meet, gets an insert: the grid cells under it are cut
## out of the ground mesh and replaced by a triangulated patch with rings of
## points following the outline, down the bank, at a few tens of
## centimetres. The ball plays on exactly those triangles (height_at()), so
## what is drawn and what the ball rolls on are the same surface.
##
## The insert covers whole grid cells, and its edge points are the grid's
## own vertices beyond the reach of any bank, so it joins the ground mesh
## round it with no step or crack.

const RAISE := 0.45  ## metres the pad sits above the mean ground round its edge
const BANK := 0.25  ## bank rise per metre (1 in 4, gentler than the 1 in 3 limit)
const SHOULDER := 0.4  ## metres over which the shoulder rounds from level to the bank
const TOE := 0.12  ## metres of height over which the bank's foot eases into the ground
const REACH := 6.5  ## metres out from the outline beyond which the ground is untouched
## Offsets of the rings of points from the outline (negative inside).
const RINGS := [-0.7, -0.2, 0.0, 0.1, 0.25, 0.45, 0.7, 1.0, 1.35, 1.75, 2.2, 2.7, 3.25, 3.85, 4.5, 5.2, 6.0, 6.5]
const RING_STEP := 0.6  ## metres between points along a ring
const PAD_STEP := 1.5  ## metres between points on the level top
const BUCKET := 1.0  ## metres per side of the triangle lookup buckets
const MAX_PADS := 254


## One insert: the tees it holds and its triangles.
class Pad:
	var tees: Array[CourseShape] = []
	var levels := PackedFloat32Array()
	var cells := Rect2i()  ## grid cells it replaces (cell (i, j) spans vertices i..i+1, j..j+1)
	var points := PackedVector2Array()
	var heights := PackedFloat32Array()
	var normals := PackedVector3Array()
	var tris := PackedInt32Array()
	var origin := Vector2.ZERO
	var bcols := 0
	var brows := 0
	var buckets: Array[PackedInt32Array] = []

	## Height on the insert's triangles, or NAN off them.
	func height_at(p: Vector2) -> float:
		var bi := floori((p.x - origin.x) / BUCKET)
		var bj := floori((p.y - origin.y) / BUCKET)
		if bi < 0 or bj < 0 or bi >= bcols or bj >= brows:
			return NAN
		for t in buckets[bj * bcols + bi]:
			var a := points[tris[t]]
			var b := points[tris[t + 1]]
			var c := points[tris[t + 2]]
			var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
			if absf(den) < 1e-12:
				continue
			var wa := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / den
			var wb := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / den
			var wc := 1.0 - wa - wb
			if wa >= -1e-6 and wb >= -1e-6 and wc >= -1e-6:
				return wa * heights[tris[t]] + wb * heights[tris[t + 1]] + wc * heights[tris[t + 2]]
		return NAN


var pads: Array[Pad] = []
## Per grid cell ((cols - 1) * (rows - 1)): 0, or the index + 1 of the pad
## that replaces it.
var cell_pad := PackedByteArray()


## The pad's level: the mean ground under its outline, raised.
static func level_of(course: DesignedCourse, s: CourseShape) -> float:
	var sum := 0.0
	var outline := s.outline()
	for p in outline:
		sum += course.base_height(p.x, p.y)
	return sum / maxi(outline.size(), 1) + RAISE


## The ground `d` metres from a pad's outline (negative inside) at `level`,
## where it was `g`: level on top, then a bank that rounds over at the
## shoulder, runs at BANK until it meets the ground and eases into it. A
## pad on a slope is built up on the low side and cut in on the high side,
## as real ones are.
static func profile(g: float, d: float, level: float) -> float:
	if d <= 0.0:
		return level
	if d >= REACH:
		return g
	var a := BANK * (d * d / (2.0 * SHOULDER) if d < SHOULDER else d - SHOULDER * 0.5)
	var x := g - level
	var k := minf(TOE, a)
	var m := absf(x)
	if k > 1e-6:
		var w := clampf(0.5 + 0.5 * (a - m) / k, 0.0, 1.0)
		m = maxf(0.0, lerpf(a, m, w) - k * w * (1.0 - w))
	else:
		m = minf(m, a)
	var h := level + signf(x) * m
	return lerpf(h, g, smoothstep(REACH - 1.0, REACH, d))


## Rebuilds the pads after a change inside `cells` (grid vertices): `g` is
## the ground before tees, `h` after them (both on the course grid).
func rebuild(course: DesignedCourse, g: PackedFloat32Array, h: PackedFloat32Array, changed: Rect2i) -> void:
	var cols := course.cols
	var rows := course.rows
	var groups: Array = []  # [Rect2i, Array[CourseShape]]
	for s in course.shapes:
		if s.surface != Surface.Type.TEE or not s.is_valid():
			continue
		var r := _cells_for(course, s.bounds().grow(REACH + DesignedCourse.CELL * 0.5))
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		var tees: Array[CourseShape] = [s]
		# Merge with every group it overlaps (and so on, until none does).
		var merged := true
		while merged:
			merged = false
			for gi in groups.size():
				if (groups[gi][0] as Rect2i).intersects(r):
					r = r.merge(groups[gi][0])
					var others: Array[CourseShape] = groups[gi][1]
					others.append_array(tees)
					tees = others
					groups.remove_at(gi)
					merged = true
					break
		groups.append([r, tees])
	var old := pads
	pads = []
	for grp in groups:
		if pads.size() >= MAX_PADS:
			break
		var r: Rect2i = grp[0]
		var tees: Array[CourseShape] = grp[1]
		# Keep the tees in course order, as the grid applies them.
		tees.sort_custom(func(a: CourseShape, b: CourseShape) -> bool:
			return course.shapes.find(a) < course.shapes.find(b))
		var keep: Pad = null
		if not r.grow(1).intersects(changed):
			for p in old:
				if p.cells == r and p.tees == tees:
					keep = p
					break
		pads.append(keep if keep != null else _build(course, g, h, r, tees))
	cell_pad = PackedByteArray()
	cell_pad.resize((cols - 1) * (rows - 1))
	for k in pads.size():
		var r := pads[k].cells
		for j in range(r.position.y, r.end.y):
			for i in range(r.position.x, r.end.x):
				cell_pad[j * (cols - 1) + i] = k + 1


## The pad replacing grid cell (i, j), or null.
func pad_at_cell(cols: int, i: int, j: int) -> Pad:
	if cell_pad.is_empty():
		return null
	var k := cell_pad[j * (cols - 1) + i]
	return pads[k - 1] if k > 0 else null


## Grid cells covering `r`, kept a cell inside the grid's edge so the
## insert's border is always made of grid vertices.
static func _cells_for(course: DesignedCourse, r: Rect2) -> Rect2i:
	var o := course.area.position
	var c := DesignedCourse.CELL
	var lo := Vector2i(maxi(1, floori((r.position.x - o.x) / c)), maxi(1, floori((r.position.y - o.y) / c)))
	var hi := Vector2i(mini(course.cols - 2, ceili((r.end.x - o.x) / c)), mini(course.rows - 2, ceili((r.end.y - o.y) / c)))
	return Rect2i(lo, hi - lo)


static func _bilinear(course: DesignedCourse, g: PackedFloat32Array, p: Vector2) -> float:
	var u := clampf((p.x - course.area.position.x) / DesignedCourse.CELL, 0.0, course.cols - 1.001)
	var v := clampf((p.y - course.area.position.y) / DesignedCourse.CELL, 0.0, course.rows - 1.001)
	var i := int(u)
	var j := int(v)
	var k := j * course.cols + i
	return lerpf(lerpf(g[k], g[k + 1], u - i), lerpf(g[k + course.cols], g[k + course.cols + 1], u - i), v - j)


func _build(course: DesignedCourse, g: PackedFloat32Array, h: PackedFloat32Array, r: Rect2i, tees: Array[CourseShape]) -> Pad:
	var pad := Pad.new()
	pad.tees = tees
	pad.cells = r
	for s in tees:
		pad.levels.append(level_of(course, s))
	var cols := course.cols
	var cell := DesignedCourse.CELL
	var lo := course.sample_pos(r.position.x, r.position.y)
	var hi := course.sample_pos(r.end.x, r.end.y)
	var inner := Rect2(lo, hi - lo).grow(-0.3)
	var reach_boxes: Array[Rect2] = []
	for s in tees:
		reach_boxes.append(s.bounds().grow(REACH + 0.3))
	var pts := PackedVector2Array()
	var hs := PackedFloat32Array()
	var fixed := PackedByteArray()  # 1 where the point is a grid vertex on the border

	# Grid vertices: all of the border, and inside wherever no bank reaches.
	for j in range(r.position.y, r.end.y + 1):
		for i in range(r.position.x, r.end.x + 1):
			var p := course.sample_pos(i, j)
			var border := i == r.position.x or j == r.position.y or i == r.end.x or j == r.end.y
			if not border:
				var near := false
				for t in tees.size():
					if reach_boxes[t].has_point(p) and tees[t].signed_distance(p) < REACH + 0.3:
						near = true
						break
				if near:
					continue
			pts.append(p)
			hs.append(g[j * cols + i])
			fixed.append(1 if border else 0)

	# The level tops, sparsely (they are flat).
	for t in tees.size():
		var b := tees[t].bounds()
		var y := b.position.y + PAD_STEP * 0.5
		while y < b.end.y:
			var x := b.position.x + PAD_STEP * 0.5
			while x < b.end.x:
				var p := Vector2(x, y)
				if inner.has_point(p) and tees[t].signed_distance(p) < -1.1:
					pts.append(p)
					hs.append(_height(course, g, tees, pad.levels, reach_boxes, p, t, -1.1))
					fixed.append(0)
				x += PAD_STEP
			y += PAD_STEP

	# Rings round each outline, down the bank and out to the ground.
	for t in tees.size():
		var outline := tees[t].outline()
		for off: float in RINGS:
			var ring := outline
			if absf(off) > 1e-4:
				var rings := Geometry2D.offset_polygon(outline, off, Geometry2D.JOIN_ROUND)
				if rings.is_empty():
					continue
				ring = rings[0]
				for q: PackedVector2Array in rings:
					if q.size() > ring.size():
						ring = q
			for p in _resample(ring, RING_STEP):
				if not inner.has_point(p):
					continue
				# Where another tee's pad covers this ring point, it is not on
				# the bank it was made for; the other tee's rings draw it.
				var hidden := false
				for u in tees.size():
					if u != t and tees[u].bounds().has_point(p) and tees[u].contains(p):
						hidden = off > 0.0
				if hidden:
					continue
				pts.append(p)
				hs.append(_height(course, g, tees, pad.levels, reach_boxes, p, t, off))
				fixed.append(0)

	pad.points = pts
	pad.heights = hs
	var all := Geometry2D.triangulate_delaunay(pts)
	for k in range(0, all.size(), 3):
		var a := pts[all[k]]
		var b := pts[all[k + 1]]
		var c := pts[all[k + 2]]
		var area := (b - a).cross(c - a)
		if absf(area) < 1e-4:
			continue
		# Wound clockwise seen from above (Godot's front faces), as the grid:
		# (b - a) x (c - a) in (x, z) positive.
		if area < 0.0:
			pad.tris.append_array(PackedInt32Array([all[k], all[k + 2], all[k + 1]]))
		else:
			pad.tris.append_array(PackedInt32Array([all[k], all[k + 1], all[k + 2]]))

	# Normals: from the triangles, but the border takes the grid's own
	# (central differences) so the lighting carries on across the join.
	var acc := PackedVector3Array()
	acc.resize(pts.size())
	for k in range(0, pad.tris.size(), 3):
		var ia := pad.tris[k]
		var ib := pad.tris[k + 1]
		var ic := pad.tris[k + 2]
		var va := Vector3(pts[ia].x, hs[ia], pts[ia].y)
		var vb := Vector3(pts[ib].x, hs[ib], pts[ib].y)
		var vc := Vector3(pts[ic].x, hs[ic], pts[ic].y)
		var n := (vc - va).cross(vb - va)
		if n.y < 0.0:
			n = -n
		acc[ia] += n
		acc[ib] += n
		acc[ic] += n
	pad.normals.resize(pts.size())
	for k in pts.size():
		if fixed[k] == 1:
			var gc := course.cell_of(pts[k])
			var i := gc.x
			var j := gc.y
			var hl := h[j * cols + maxi(i - 1, 0)]
			var hr := h[j * cols + mini(i + 1, cols - 1)]
			var hd := h[maxi(j - 1, 0) * cols + i]
			var hu := h[mini(j + 1, course.rows - 1) * cols + i]
			pad.normals[k] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
		else:
			pad.normals[k] = acc[k].normalized() if acc[k].length_squared() > 0.0 else Vector3.UP

	# Buckets for height_at().
	pad.origin = lo
	pad.bcols = ceili((hi.x - lo.x) / BUCKET)
	pad.brows = ceili((hi.y - lo.y) / BUCKET)
	# Gathered in plain arrays (shared by reference), then packed.
	var lists: Array[Array] = []
	lists.resize(pad.bcols * pad.brows)
	for k in lists.size():
		lists[k] = []
	for k in range(0, pad.tris.size(), 3):
		var a := pts[pad.tris[k]]
		var b := pts[pad.tris[k + 1]]
		var c := pts[pad.tris[k + 2]]
		var i0 := clampi(floori((minf(a.x, minf(b.x, c.x)) - lo.x) / BUCKET), 0, pad.bcols - 1)
		var i1 := clampi(floori((maxf(a.x, maxf(b.x, c.x)) - lo.x) / BUCKET), 0, pad.bcols - 1)
		var j0 := clampi(floori((minf(a.y, minf(b.y, c.y)) - lo.y) / BUCKET), 0, pad.brows - 1)
		var j1 := clampi(floori((maxf(a.y, maxf(b.y, c.y)) - lo.y) / BUCKET), 0, pad.brows - 1)
		for bj in range(j0, j1 + 1):
			for bi in range(i0, i1 + 1):
				lists[bj * pad.bcols + bi].append(k)
	for l in lists:
		pad.buckets.append(PackedInt32Array(l))
	return pad


## The ground at `p` with every tee of the pad applied in turn, as the grid
## does; `own` is the tee whose outline `p` is `own_d` metres from (-1 for none).
static func _height(course: DesignedCourse, g: PackedFloat32Array, tees: Array[CourseShape], levels: PackedFloat32Array,
		boxes: Array[Rect2], p: Vector2, own: int, own_d: float) -> float:
	var y := _bilinear(course, g, p)
	for t in tees.size():
		var d := own_d if t == own else (tees[t].signed_distance(p) if boxes[t].has_point(p) else INF)
		if d < REACH:
			y = profile(y, d, levels[t])
	return y


## Points every `step` metres round a closed polyline.
static func _resample(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	if n < 2:
		return out
	var total := 0.0
	for i in n:
		total += poly[i].distance_to(poly[(i + 1) % n])
	var count := maxi(3, ceili(total / step))
	var each := total / count
	var seg := 0
	var seg_start := 0.0
	for k in count:
		var want := k * each
		while seg < n - 1 and seg_start + poly[seg].distance_to(poly[(seg + 1) % n]) < want:
			seg_start += poly[seg].distance_to(poly[(seg + 1) % n])
			seg += 1
		var a := poly[seg]
		var b := poly[(seg + 1) % n]
		var seg_len := a.distance_to(b)
		out.append(a.lerp(b, clampf((want - seg_start) / seg_len, 0.0, 1.0) if seg_len > 1e-6 else 0.0))
	return out
