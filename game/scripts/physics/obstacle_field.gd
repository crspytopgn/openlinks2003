class_name ObstacleField
extends RefCounted
## Things on a course the ball can hit: tree trunks, canopies, buildings and
## fences, in Godot metres. Port of libs/olcore/src/obstacles.cpp; change
## both together.

enum Kind { SOLID = 0, CANOPY = 1 }  ## SOLID bounces the ball off; CANOPY soaks up its speed

const CELL := 10.0  ## metres per side of a grid cell
const CYLINDER_FLOATS := 6  ## x, z, radius, y0, y1, kind
const BOX_FLOATS := 16  ## centre, three axes, half sizes, kind

var _cylinders := PackedFloat32Array()
var _boxes := PackedFloat32Array()
var _origin := Vector2.ZERO
var _cols := 0
var _rows := 0
## Items of cell i are _cell_items[_cell_start[i] .. _cell_start[i + 1]); an
## item k >= 0 is a cylinder, k < 0 is box -k - 1.
var _cell_start := PackedInt32Array()
var _cell_items := PackedInt32Array()


## An upright cylinder: centre (x, z), radius, from y0 up to y1.
func add_cylinder(x: float, z: float, radius: float, y0: float, y1: float, kind: int) -> void:
	_cylinders.append_array(PackedFloat32Array([x, z, radius, y0, y1, kind]))


## A box: centre, orthonormal axes (the columns of `axes`) and the half size
## along each.
func add_box(centre: Vector3, axes: Basis, half: Vector3, kind: int) -> void:
	_boxes.append_array(PackedFloat32Array([centre.x, centre.y, centre.z, axes.x.x, axes.x.y, axes.x.z, axes.y.x, axes.y.y, axes.y.z, axes.z.x, axes.z.y, axes.z.z, half.x, half.y, half.z, kind]))


@warning_ignore("integer_division")
func size() -> int:
	return _cylinders.size() / CYLINDER_FLOATS + _boxes.size() / BOX_FLOATS


## Builds the lookup grid. Call after adding everything.
@warning_ignore("integer_division")
func finalize() -> void:
	var extent := PackedFloat32Array()  # x0, z0, x1, z1 per item
	var ids := PackedInt32Array()
	for i in _cylinders.size() / CYLINDER_FLOATS:
		var o := i * CYLINDER_FLOATS
		var r := _cylinders[o + 2]
		extent.append_array(PackedFloat32Array([_cylinders[o] - r, _cylinders[o + 1] - r, _cylinders[o] + r, _cylinders[o + 1] + r]))
		ids.append(i)
	for i in _boxes.size() / BOX_FLOATS:
		var o := i * BOX_FLOATS
		var rx := 0.0
		var rz := 0.0
		for k in 3:
			var h := _boxes[o + 12 + k]
			rx += absf(_boxes[o + 3 + 3 * k]) * h
			rz += absf(_boxes[o + 5 + 3 * k]) * h
		extent.append_array(PackedFloat32Array([_boxes[o] - rx, _boxes[o + 2] - rz, _boxes[o] + rx, _boxes[o + 2] + rz]))
		ids.append(-i - 1)
	_cols = 0
	_rows = 0
	_cell_start = PackedInt32Array()
	_cell_items = PackedInt32Array()
	if ids.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in ids.size():
		lo = lo.min(Vector2(extent[4 * i], extent[4 * i + 1]))
		hi = hi.max(Vector2(extent[4 * i + 2], extent[4 * i + 3]))
	_origin = lo
	_cols = floori((hi.x - lo.x) / CELL) + 1
	_rows = floori((hi.y - lo.y) / CELL) + 1
	# Two passes: count per cell, then fill.
	var count := PackedInt32Array()
	count.resize(_cols * _rows + 1)
	count.fill(0)
	for i in ids.size():
		var r := _cell_range(extent[4 * i], extent[4 * i + 1], extent[4 * i + 2], extent[4 * i + 3])
		for row in range(r.position.y, r.end.y):
			for col in range(r.position.x, r.end.x):
				count[row * _cols + col + 1] += 1
	for i in range(1, count.size()):
		count[i] += count[i - 1]
	_cell_start = count.duplicate()
	_cell_items.resize(count[count.size() - 1])
	for i in ids.size():
		var r := _cell_range(extent[4 * i], extent[4 * i + 1], extent[4 * i + 2], extent[4 * i + 3])
		for row in range(r.position.y, r.end.y):
			for col in range(r.position.x, r.end.x):
				var c := row * _cols + col
				_cell_items[count[c]] = ids[i]
				count[c] += 1


## Cells covering x0..x1, z0..z1 as columns position.x until end.x and rows
## position.y until end.y (empty when outside the grid).
func _cell_range(x0: float, z0: float, x1: float, z1: float) -> Rect2i:
	var c0 := maxi(0, floori((x0 - _origin.x) / CELL))
	var r0 := maxi(0, floori((z0 - _origin.y) / CELL))
	var c1 := mini(_cols - 1, floori((x1 - _origin.x) / CELL))
	var r1 := mini(_rows - 1, floori((z1 - _origin.y) / CELL))
	return Rect2i(c0, r0, maxi(0, c1 - c0 + 1), maxi(0, r1 - r0 + 1))


## The first obstacle the segment from -> to enters from outside:
## {fraction (0 to 1), normal (outward unit normal), kind}, or {} if none. A
## segment that starts inside an obstacle does not hit it.
func segment_hit(from: Vector3, to: Vector3) -> Dictionary:
	if _cols == 0:
		return {}
	var d := to - from
	var r := _cell_range(minf(from.x, to.x), minf(from.z, to.z), maxf(from.x, to.x), maxf(from.z, to.z))
	var best := {}
	for row in range(r.position.y, r.end.y):
		for col in range(r.position.x, r.end.x):
			var c := row * _cols + col
			for i in range(_cell_start[c], _cell_start[c + 1]):
				var k := _cell_items[i]
				var h := _hit_cylinder(k, from, d) if k >= 0 else _hit_box(-k - 1, from, d)
				if not h.is_empty() and (best.is_empty() or float(h.fraction) < float(best.fraction)):
					best = h
	return best


## Where p + d t is between lo and hi, as Vector2(t0, t1); null if never.
static func _slab(p: float, d: float, lo: float, hi: float) -> Variant:
	if absf(d) < 1e-12:
		return Vector2(-INF, INF) if p >= lo and p <= hi else null
	var a := (lo - p) / d
	var b := (hi - p) / d
	return Vector2(minf(a, b), maxf(a, b))


func _hit_cylinder(i: int, from: Vector3, d: Vector3) -> Dictionary:
	var o := i * CYLINDER_FLOATS
	var ty: Variant = _slab(from.y, d.y, _cylinders[o + 3], _cylinders[o + 4])
	if ty == null:
		return {}
	var radius := _cylinders[o + 2]
	var fx := from.x - _cylinders[o]
	var fz := from.z - _cylinders[o + 1]
	var a := d.x * d.x + d.z * d.z
	var cc := fx * fx + fz * fz - radius * radius
	var tc0 := -INF
	var tc1 := INF
	if a < 1e-12:
		if cc > 0.0:
			return {}
	else:
		var b := fx * d.x + fz * d.z
		var disc := b * b - a * cc
		if disc < 0.0:
			return {}
		var sq := sqrt(disc)
		tc0 = (-b - sq) / a
		tc1 = (-b + sq) / a
	var y: Vector2 = ty
	var t0 := maxf(y.x, tc0)
	var t1 := minf(y.y, tc1)
	if t0 > t1 or t0 < 0.0 or t0 > 1.0:
		return {}
	var normal := Vector3(0.0, -1.0 if d.y > 0.0 else 1.0, 0.0)
	if tc0 >= y.x:
		normal = Vector3((fx + d.x * t0) / radius, 0.0, (fz + d.z * t0) / radius)
	return {"fraction": t0, "normal": normal, "kind": int(_cylinders[o + 5])}


func _hit_box(i: int, from: Vector3, d: Vector3) -> Dictionary:
	var o := i * BOX_FLOATS
	var rel := from - Vector3(_boxes[o], _boxes[o + 1], _boxes[o + 2])
	var t0 := -INF
	var t1 := INF
	var face := Vector3.ZERO
	for k in 3:
		var axis := Vector3(_boxes[o + 3 + 3 * k], _boxes[o + 4 + 3 * k], _boxes[o + 5 + 3 * k])
		var dk := d.dot(axis)
		var half := _boxes[o + 12 + k]
		var s: Variant = _slab(rel.dot(axis), dk, -half, half)
		if s == null:
			return {}
		var span: Vector2 = s
		if span.x > t0:
			t0 = span.x
			face = -axis if dk > 0.0 else axis
		t1 = minf(t1, span.y)
	if face == Vector3.ZERO or t0 > t1 or t0 < 0.0 or t0 > 1.0:
		return {}
	return {"fraction": t0, "normal": face, "kind": int(_boxes[o + 15])}
