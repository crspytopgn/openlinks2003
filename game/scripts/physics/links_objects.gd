class_name LinksObjects
extends RefCounted
## Links 2003's trees and other billboard objects as the ball meets them, in
## the game's frame (feet, z up; see links_ground.gd). A billboard is a flat
## picture standing on the ground and turned to face the viewer; the ball
## hits it where the picture is opaque. A GDScript port of
## libs/olcore/src/links_objects.cpp; change both together. See
## docs/formats/physics.md.

const CELL := 64.0
const PARALLEL := 1e-4
const TURN_RANGE := 2.09440565
const CANOPY_KEPT := 0.9


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


class Hit:
	var object := -1
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	var kind := 0  ## 1 solid, 2 slowed by the canopy
	var factor := 0.0


var types: Array[ObjType] = []
var _base := PackedVector3Array()
var _height := PackedFloat32Array()
var _anchor_x := PackedFloat32Array()
var _anchor_z := PackedFloat32Array()
var _type := PackedInt32Array()
var _cells := {}  ## Vector2i -> PackedInt32Array


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


## The first billboard the path p -> q goes through, skipping `last`; null
## if none. `facing` is the horizontal unit vector from the billboards to the
## viewer. Mirrors olcore::LinksObjects::hit.
func hit(p: Vector3, q: Vector3, facing: Vector3, last: int) -> Hit:
	var d := q - p
	var length := d.length()
	if not (length > 0.0):
		return null
	var dir := d / length
	var best: Hit = null
	var best_along := 0.0
	var seen := {}
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
	return best


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
