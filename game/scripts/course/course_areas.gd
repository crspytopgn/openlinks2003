class_name CourseAreas
extends RefCounted
## What a course says about its ground beyond the mesh: the full TerrainTypes
## records (surface physics, hazard and free-drop flags) and the outlines that
## set where each hole's ground ends (out of bounds). A GDScript port of
## libs/olcore/src/course_areas.cpp; change both together. See
## docs/formats/crz.md.

const TERRAIN_TYPES_VERSION := 4
const TERRAIN_TYPE_SIZE := 243
const NAME_OFFSET := 0x67
const TYPE_NAME_OFFSET := 0xa7
const NAME_BYTES := 0x40
const SHAPES_VERSION := 1
const SHAPE_HEADER := 37
const NODE_SIZE := 36
## The game tessellates into a buffer of 5,000 points.
const OUTLINE_POINTS := 5000
const MAX_DEPTH := 2
const HAZARD := 1
const FREE_DROP := 8


## `TerrainTypes` entry (version 4): one dictionary per record with "index",
## "values" (PackedFloat32Array of the 20 floats at 0x04 to 0x50; see
## value()), "ground_class", "category", "flags", "name" and "type_name".
## Empty on error. Mirrors olcore::parse_crz_terrain_types.
static func parse_terrain_types(b: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if b.size() < 8 or b.decode_u32(0) != TERRAIN_TYPES_VERSION:
		return out
	var count := b.decode_u32(4)
	if 8 + count * TERRAIN_TYPE_SIZE > b.size():
		return out
	for i in count:
		var o := 8 + i * TERRAIN_TYPE_SIZE
		var values := PackedFloat32Array()
		values.resize(20)
		for k in 20:
			values[k] = b.decode_float(o + 4 + 4 * k)
		out.append({
			"index": b.decode_u32(o),
			"values": values,
			"ground_class": b.decode_u32(o + 0x54),
			"category": b.decode_u32(o + 0x58),
			"flags": b.decode_u32(o + 0x5c),
			"name": _utf16_name(b, o + NAME_OFFSET),
			"type_name": _utf16_name(b, o + TYPE_NAME_OFFSET),
		})
	return out


## The value at a record offset (0x04 LieAngular ... 0x38 Snap).
static func value(t: Dictionary, offset: int) -> float:
	return (t.values as PackedFloat32Array)[(offset - 4) / 4]


## The game refuses drops here and calls it "In Hazard".
static func is_hazard(t: Dictionary) -> bool:
	return (int(t.flags) & HAZARD) != 0


## Cart paths, concrete, asphalt and walls: "In Free Drop Zone".
static func is_free_drop(t: Dictionary) -> bool:
	return (int(t.flags) & FREE_DROP) != 0


## How the ball plays off a record. Greens always take the game's green
## options, as the game replaces every green record with them. Mirrors
## olcore::links_surface(const CrzTerrainType&).
static func links_surface(t: Dictionary) -> LinksGround.Params:
	var c := int(t.ground_class)
	if c < LinksGround.GREEN or c > LinksGround.DEEP_GRASS:
		return LinksGround.surface_for_class(LinksGround.ROUGH)
	if c == LinksGround.GREEN:
		return LinksGround.surface_for_class(LinksGround.GREEN)
	var p := LinksGround.Params.new()
	p.ground_class = c
	p.restitution = value(t, 0x14)
	p.impact_friction = value(t, 0x18)
	p.skid_friction = value(t, 0x1c)
	p.impact_drag = value(t, 0x20)
	p.roll_resistance = value(t, 0x24)
	p.stop_speed = value(t, 0x28)
	p.spin_grip = value(t, 0x2c)
	p.lie_spin = value(t, 0x04)
	p.lie_power = value(t, 0x0c)
	return p


## `Shapes`: a u32 version and three floats, then outlines to the end. Each
## outline: {"id", "closed", "min" (Vector2), "max" (Vector2), "attributes",
## "nodes" (PackedVector2Array: handle in, anchor, handle out per node)}, in
## course feet. Empty on error. Mirrors olcore::parse_shapes.
static func parse_shapes(b: PackedByteArray) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if b.size() < 16 or b.decode_u32(0) != SHAPES_VERSION:
		return none
	return _read_shapes(b, 16)


## `HoleIDShapes`, `OBIDShapes`, `BugIDShapes`: a u32 count before the same.
## Mirrors olcore::parse_id_shapes.
static func parse_id_shapes(b: PackedByteArray) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if b.size() < 20 or b.decode_u32(4) != SHAPES_VERSION:
		return none
	var out := _read_shapes(b, 20)
	if out.size() != b.decode_u32(0):
		return none
	return out


## HoleIDShapes: the hole an outline bounds (1 to 18).
static func shape_hole(s: Dictionary) -> int:
	return int(s.attributes) >> 27


## The polygon the game tests against: every segment cut in eight by halving
## it three times (fewer when the shape has more than 624 segments), starting
## from the last node of a closed shape. Mirrors olcore::shape_outline.
static func shape_outline(s: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var nodes: PackedVector2Array = s.nodes
	var n := nodes.size() / 3
	if n == 0:
		return out
	var depth := MAX_DEPTH
	var fit := (OUTLINE_POINTS - 1) >> (depth + 1)
	while fit < n and depth >= 0:
		depth -= 1
		fit = (OUTLINE_POINTS - 1) >> (depth + 1)
	if n > 1:
		var end := mini(n, fit)
		var prev := n - 1 if s.closed else 0
		for i in range(0 if s.closed else 1, end):
			out.append(nodes[3 * prev + 1])
			if depth >= 0:
				_subdivide(nodes[3 * prev], nodes[3 * prev + 1], nodes[3 * prev + 2], nodes[3 * i], nodes[3 * i + 1], nodes[3 * i + 2], depth, out)
			prev = i
		out.append(nodes[3 * prev + 1])
	return out


## Whether (x, y) is inside, by counting edge crossings to the right.
## Mirrors olcore::outline_contains.
static func outline_contains(o: PackedVector2Array, x: float, y: float) -> bool:
	if o.is_empty():
		return false
	var v0 := o[o.size() - 1]
	var y0 := v0.y >= y
	var inside := false
	for v1 in o:
		var y1 := v1.y >= y
		if y0 != y1:
			var x0 := v0.x >= x
			var x1 := v1.x >= x
			if x0 == x1:
				if x0:
					inside = not inside
			elif v1.x - (v1.y - y) * (v0.x - v1.x) / (v0.y - v1.y) >= x:
				inside = not inside
		y0 = y1
		v0 = v1
	return inside


## Where each hole's ball is in bounds: inside the hole's own outline (if it
## has one) and outside every out-of-bounds area marked for that hole. Course
## feet. Mirrors olcore::HoleBounds; the edges are sorted into bands across y
## so a query only looks at the few that can cross it, which gives the same
## answer as outline_contains().
class HoleBounds:
	var _holes := {}  ## hole number -> Area
	var _ob: Array[Area] = []

	class Area:
		const BANDS := 32
		var lo := Vector2.ZERO
		var hi := Vector2.ZERO
		var mask := 0
		var outline := PackedVector2Array()
		var _band_h := 1.0
		var _bands: Array[PackedInt32Array] = []  ## edge i runs from point i - 1 to point i

		func _init(s: Dictionary, p_mask: int) -> void:
			lo = s.min
			hi = s.max
			mask = p_mask
			outline = CourseAreas.shape_outline(s)
			_band_h = maxf((hi.y - lo.y) / BANDS, 1e-6)
			var lists: Array[PackedInt32Array] = []
			for _b in BANDS:
				lists.append(PackedInt32Array())
			var n := outline.size()
			for i in n:
				var a := outline[(i + n - 1) % n]
				var c := outline[i]
				for band in range(_band(minf(a.y, c.y)), _band(maxf(a.y, c.y)) + 1):
					var l := lists[band]
					l.append(i)
					lists[band] = l
			_bands = lists

		func _band(y: float) -> int:
			return clampi(int(floor((y - lo.y) / _band_h)), 0, BANDS - 1)

		func contains(x: float, y: float) -> bool:
			if x < lo.x or x > hi.x or y < lo.y or y > hi.y:
				return false
			var n := outline.size()
			var inside := false
			for i in _bands[_band(y)]:
				var v0 := outline[(i + n - 1) % n]
				var v1 := outline[i]
				var y0 := v0.y >= y
				if y0 == (v1.y >= y):
					continue
				var x0 := v0.x >= x
				if x0 == (v1.x >= x):
					if x0:
						inside = not inside
				elif v1.x - (v1.y - y) * (v0.x - v1.x) / (v0.y - v1.y) >= x:
					inside = not inside
			return inside

	func _init(hole_shapes: Array[Dictionary], ob_shapes: Array[Dictionary]) -> void:
		for s in hole_shapes:
			var h := CourseAreas.shape_hole(s)
			if h >= 1 and h <= 18:
				_holes[h] = Area.new(s, 1)
		for s in ob_shapes:
			_ob.append(Area.new(s, int(s.attributes)))

	func in_bounds(hole_number: int, x: float, y: float) -> bool:
		if hole_number < 1 or hole_number > 18:
			return true
		var own: Area = _holes.get(hole_number)
		if own != null and not own.contains(x, y):
			return false
		for a in _ob:
			if (a.mask >> (hole_number - 1)) & 1 != 0 and a.contains(x, y):
				return false
		return true


static func _read_shapes(b: PackedByteArray, o: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	while o + SHAPE_HEADER <= b.size():
		var count := b.decode_u32(o + 4)
		var s := {
			"id": b.decode_u32(o),
			"closed": b[o + 8] != 0,
			"min": Vector2(b.decode_float(o + 9), b.decode_float(o + 13)),
			"max": Vector2(b.decode_float(o + 21), b.decode_float(o + 25)),
			"attributes": b.decode_u32(o + 33),
		}
		o += SHAPE_HEADER
		if o + count * NODE_SIZE > b.size():
			out.clear()
			return out
		var nodes := PackedVector2Array()
		nodes.resize(count * 3)
		for k in count * 3:
			nodes[k] = Vector2(b.decode_float(o), b.decode_float(o + 4))
			o += 12
		s.nodes = nodes
		out.append(s)
	return out


## The game's subdivision: split the segment a -> b in half (de Casteljau),
## emit the left half's points, the middle, then the right half's.
static func _subdivide(a_in: Vector2, a_pt: Vector2, a_out: Vector2, b_in: Vector2, b_pt: Vector2, b_out: Vector2, depth: int, out: PackedVector2Array) -> void:
	var handles := (a_out + b_in) * 0.5
	var l_out := (a_pt + a_out) * 0.5
	var r_in := (b_pt + b_in) * 0.5
	var m_in := (l_out + handles) * 0.5
	var m_out := (handles + r_in) * 0.5
	var m_pt := (m_in + m_out) * 0.5
	if depth != 0:
		_subdivide(a_in, a_pt, l_out, m_in, m_pt, m_out, depth - 1, out)
	out.append(m_pt)
	if depth != 0:
		_subdivide(m_in, m_pt, m_out, r_in, b_pt, b_out, depth - 1, out)


static func _utf16_name(b: PackedByteArray, o: int) -> String:
	var s := ""
	for i in range(0, NAME_BYTES - 1, 2):
		var c := b.decode_u16(o + i)
		if c == 0:
			break
		s += char(c)
	return s
