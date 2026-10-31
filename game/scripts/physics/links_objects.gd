class_name LinksObjects
extends RefCounted
## Links 2003's trees and other billboard objects as the ball meets them, in
## the game's frame (feet, z up; see links_ground.gd). A billboard is a flat
## picture standing on the ground and turned to face the viewer; the ball
## hits it where the picture is opaque. 3D objects (bridges, walls) meet it
## face by face. A GDScript port of
## libs/olcore/src/links_objects.cpp; change both together. See
## docs/formats/physics.md.

const CELL := 64.0
const PARALLEL := 1e-4
const TURN_RANGE := 2.09440565
const CANOPY_KEPT := 0.9
const FLAT_FACE := 1e-5


## What a type does to the ball. Mirrors olcore::LinksObjectType. `mask` is
## the type's picture (any size: only its alpha is read, and u and v are
## fractions of it); the course loader keeps a reduced copy.
class ObjType:
	var collision := 1
	var shape := PackedFloat32Array([1, 1, 0, 0, 1, 1])
	var aspect := 1.0
	var mask: Image

	## Alpha at (x, y) counted from the bottom-left pixel, 0 outside.
	func alpha(x: int, y: int) -> int:
		if mask == null or x < 0 or y < 0 or x >= mask.get_width() or y >= mask.get_height():
			return 0
		return mask.get_pixel(x, mask.get_height() - 1 - y).a8


## A 3D object's mesh as stored: model units, z up, polygons fanned from
## their first corner. Mirrors olcore::LinksMesh.
class Mesh3D:
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()  ## one per corner, v = 0 at the top
	var corners := PackedInt32Array()  ## position index per corner
	var faces := PackedInt32Array()  ## first corner, corner count, texture per face
	## Per texture: the picture of a texture the game marks see-through (its
	## alpha is read), or null for a solid one.
	var holes: Array[Image] = []


class Hit:
	var object := -1  ## the billboard, or for kind 8 the 3D object
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	var kind := 0  ## 1 solid, 2 slowed by the canopy, 8 a 3D object's face
	var factor := 0.0


var types: Array[ObjType] = []
var meshes: Array[Mesh3D] = []
var _base := PackedVector3Array()
var _height := PackedFloat32Array()
var _anchor_x := PackedFloat32Array()
var _anchor_z := PackedFloat32Array()
var _type := PackedInt32Array()
var _cells := {}  ## Vector2i -> PackedInt32Array
var _model_mesh := PackedInt32Array()
var _model_points: Array[PackedVector3Array] = []
var _model_lo := PackedVector3Array()
var _model_hi := PackedVector3Array()
var _model_cells := {}  ## Vector2i -> PackedInt32Array


## A placement's anchors from its `2DPlant` extra fields (-1 when absent).
static func anchor_x(extra_byte: int) -> float:
	if extra_byte < 0:
		return 0.5
	var b := extra_byte if extra_byte < 128 else extra_byte - 256
	return 0.5 + b * 0.0078125


static func anchor_z(extra_word: int) -> float:
	if extra_word < 0:
		return 0.0
	var w := extra_word if extra_word < 32768 else extra_word - 65536
	return w / 256.0


func size() -> int:
	return _base.size()


func type_of(index: int) -> ObjType:
	return types[_type[index]]


func add(base: Vector3, height: float, type: int, p_anchor_x := 0.5, p_anchor_z := 0.0) -> void:
	var index := _base.size()
	_base.append(base)
	_height.append(height)
	_anchor_x.append(p_anchor_x)
	_anchor_z.append(p_anchor_z)
	_type.append(type)
	var aspect := types[type].aspect if type >= 0 and type < types.size() else 1.0
	var reach := height * aspect
	for cx in range(floori((base.x - reach) / CELL), floori((base.x + reach) / CELL) + 1):
		for cy in range(floori((base.y - reach) / CELL), floori((base.y + reach) / CELL) + 1):
			var key := Vector2i(cx, cy)
			var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
			list.append(index)
			_cells[key] = list


## A 3D object: `points` holds its mesh's positions already placed.
func add_model(mesh: int, points: PackedVector3Array) -> void:
	if points.is_empty():
		return
	var lo := points[0]
	var hi := points[0]
	for v in points:
		lo = lo.min(v)
		hi = hi.max(v)
	var index := _model_mesh.size()
	_model_mesh.append(mesh)
	_model_points.append(points)
	_model_lo.append(lo)
	_model_hi.append(hi)
	for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
		for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			var key := Vector2i(cx, cy)
			var list: PackedInt32Array = _model_cells.get(key, PackedInt32Array())
			list.append(index)
			_model_cells[key] = list


func model_count() -> int:
	return _model_mesh.size()


## The first billboard or 3D object the path p -> q goes through, skipping
## the billboard `last`; null if none. `facing` is the horizontal unit
## vector from the billboards to the viewer. Mirrors olcore::LinksObjects::hit.
func hit(p: Vector3, q: Vector3, facing: Vector3, last: int) -> Hit:
	var d := q - p
	var length := d.length()
	if not (length > 0.0):
		return null
	var dir := d / length
	var best: Hit = null
	var best_along := 0.0
	var seen := {}
	var seen_models := {}
	for cx in range(floori(minf(p.x, q.x) / CELL), floori(maxf(p.x, q.x) / CELL) + 1):
		for cy in range(floori(minf(p.y, q.y) / CELL), floori(maxf(p.y, q.y) / CELL) + 1):
			var list: PackedInt32Array = _cells.get(Vector2i(cx, cy), PackedInt32Array())
			for i in list:
				if i == last or seen.has(i):
					continue
				seen[i] = true
				var base := _base[i]
				# Only a path that crosses the billboard's plane can hit it.
				if ((p - base).dot(facing) > 0.0) == ((q - base).dot(facing) > 0.0):
					continue
				var h := hit_one(i, p, dir, facing)
				if h == null:
					continue
				var along := (h.point - p).length()
				if best == null or along < best_along:
					best = h
					best_along = along
			# 3D objects: met face by face, and never skipped as the last one hit.
			var models: PackedInt32Array = _model_cells.get(Vector2i(cx, cy), PackedInt32Array())
			for i in models:
				if seen_models.has(i):
					continue
				seen_models[i] = true
				var h := hit_model(i, p, dir, length)
				if h == null:
					continue
				var along := (h.point - p).length()
				if best == null or along < best_along:
					best = h
					best_along = along
	return best


## One 3D object: the nearest face the ray p + t d (d unit) meets within
## `reach` (any distance when negative), through its see-through holes;
## null if none. Faces seen from behind let it through. Mirrors
## olcore::LinksObjects::hit_model.
func hit_model(index: int, p: Vector3, d: Vector3, reach: float) -> Hit:
	var m := _model_mesh[index]
	if m < 0 or m >= meshes.size():
		return null
	var mesh := meshes[m]
	var t_near := _ray_meets_box(p, d, _model_lo[index], _model_hi[index])
	if is_nan(t_near):
		return null
	if reach > 0.0 and not (t_near < reach):
		return null
	var points := _model_points[index]
	var best := -1.0
	var normal := Vector3.ZERO
	@warning_ignore("integer_division")
	for f in mesh.faces.size() / 3:
		var first := mesh.faces[3 * f]
		var count := mesh.faces[3 * f + 1]
		var texture := mesh.faces[3 * f + 2]
		if count < 3 or first + count > mesh.corners.size():
			continue
		var a := _corner(mesh, points, first)
		for k in range(1, count - 1):
			# The fan triangle (corner 0, k + 1, k), Moller and Trumbore's way.
			var b := _corner(mesh, points, first + k + 1)
			var c := _corner(mesh, points, first + k)
			var e1 := b - a
			var e2 := c - a
			var pv := d.cross(e2)
			var det := e1.dot(pv)
			if det > -FLAT_FACE and det < FLAT_FACE:
				continue
			if det < 0.0:
				continue  # the face's back
			var inv := 1.0 / det
			var s := p - a
			var u := s.dot(pv) * inv
			if u < 0.0 or u > 1.0:
				continue
			var qv := s.cross(e1)
			var v := d.dot(qv) * inv
			if v < 0.0 or u + v > 1.0:
				continue
			var t := e2.dot(qv) * inv
			if t < 0.0:
				continue
			if reach >= 0.0 and not (t < reach):
				continue
			if best >= 0.0 and not (t < best):
				continue
			# A see-through texture: the texel there must not be clear. The
			# game takes the uvs of corners 0, k and k + 1 of the whole mesh,
			# not of this face.
			if texture < mesh.holes.size() and mesh.holes[texture] != null:
				var tex := mesh.holes[texture]
				if k + 1 >= mesh.uvs.size():
					continue
				var t0 := mesh.uvs[0]
				var tk := mesh.uvs[k]
				var tk1 := mesh.uvs[k + 1]
				var tu := t0.x + (tk.x - t0.x) * v + (tk1.x - t0.x) * u
				var tv := t0.y + (tk.y - t0.y) * v + (tk1.y - t0.y) * u
				var w := tex.get_width()
				var h := tex.get_height()
				var x := int(tu * w) % w
				var y := int(tv * h) % h
				if x < 0:
					x += w
				if y < 0:
					y += h
				if tex.get_pixel(x, y).a8 == 0:
					continue
			best = t
			normal = e1.cross(e2)
	if not (best >= 0.0):
		return null
	var out := Hit.new()
	out.object = index
	out.point = p + d * best
	out.normal = normal.normalized() if normal.length() > 0.0 else normal
	out.kind = 8
	return out


static func _corner(mesh: Mesh3D, points: PackedVector3Array, c: int) -> Vector3:
	var v := mesh.corners[c]
	return points[v] if v < points.size() else Vector3.ZERO


## Where the ray p + t d enters the box (negative when it starts inside),
## or NAN if it misses: the game's slab test, a ray rather than a segment.
static func _ray_meets_box(p: Vector3, d: Vector3, lo: Vector3, hi: Vector3) -> float:
	var t0 := -3.4028234663852886e38
	var t1 := 3.4028234663852886e38
	for i in 3:
		if d[i] == 0.0:
			if p[i] < lo[i] or p[i] > hi[i]:
				return NAN
			continue
		var a := (lo[i] - p[i]) / d[i]
		var b := (hi[i] - p[i]) / d[i]
		if a > b:
			var swap := a
			a = b
			b = swap
		t0 = maxf(t0, a)
		t1 = minf(t1, b)
		if t0 > t1 or t1 < 0.0:
			return NAN
	return t0


## One billboard: whether the ray p + t d (d unit) meets it.
func hit_one(index: int, p: Vector3, d: Vector3, n: Vector3) -> Hit:
	var t_index := _type[index]
	if t_index < 0 or t_index >= types.size():
		return null
	var type := types[t_index]
	var denom := n.dot(d)
	if not (absf(denom) >= PARALLEL):
		return null
	var base := _base[index]
	var t := (n.dot(base) - n.dot(p)) / denom
	var h := p + d * t
	var tall := _height[index]
	var wide := tall * type.aspect
	var top := base.z + (1.0 - _anchor_z[index]) * tall
	var bottom := base.z - _anchor_z[index] * tall
	if h.z > top or h.z < bottom:
		return null
	var side := Vector3(0, 0, 1).cross(n)
	var left := base - side * (_anchor_x[index] * wide)
	var right := base + side * ((1.0 - _anchor_x[index]) * wide)
	if h.x < minf(left.x, right.x) or h.x > maxf(left.x, right.x):
		return null
	if h.y < minf(left.y, right.y) or h.y > maxf(left.y, right.y):
		return null
	var u := Vector2(h.x - left.x, h.y - left.y).length() / wide
	var v := (h.z - bottom) / tall
	var w := type.mask.get_width() if type.mask != null else 0
	var ht := type.mask.get_height() if type.mask != null else 0
	var px := int(u * w)
	var py := int(v * ht)
	var alpha := type.alpha(px, py)
	if alpha == 0:
		return null
	var s := type.shape
	var core := u > s[2] and u < s[4] and v > s[3] and v < s[5]
	var out := Hit.new()
	out.point = h
	out.normal = n
	if (type.collision & 2) == 0 and (core or _bits_mod10(v) == 0):
		out.kind = 1
		if (type.collision & 1) == 0:
			# Off a trunk the ball turns by where across its width it struck.
			var l := px
			var r := px
			while l >= 0 and type.alpha(l, py) != 0:
				l -= 1
			while r < w and type.alpha(r, py) != 0:
				r += 1
			var across := (u * w - l) / float(r - l)
			out.normal = n.rotated(Vector3(0, 0, 1), (across - 0.5) * TURN_RANGE)
		out.factor = s[0]
	else:
		if not (s[1] * 10.0 > _bits_mod10(u)):
			return null
		out.kind = 2
		out.factor = (alpha / 255.0 * (1.0 - s[0]) + s[0]) * CANOPY_KEPT
	out.object = index
	return out


## The game draws its "random" choices from the bit pattern of a float.
static func _bits_mod10(x: float) -> int:
	var bits := PackedFloat32Array([x]).to_byte_array().decode_s32(0)
	return bits % 10
