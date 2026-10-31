class_name DesignedTerrain
extends CourseTerrain
## The ground of a DesignedCourse, for the round and the designer. Heights
## are the sculpted grid, shaped by the painted areas: tee boxes become level
## pads, bunkers are dug in and ponds are sunk below their water line.
## Surfaces come from a raster of the shapes at RES metres, painted in layer
## order (rough, then fairways, fringes, tees, greens, sand and water on top);
## greens get a fringe ring. Outside the course area is out of bounds.
##
## The designer edits the course in place and calls update_heights() or
## update_surfaces() with the area it changed; meshes are cached per chunk and
## rebuilt only where something changed.

const RES := 0.5  ## metres per surface raster cell
const CHUNK := 32  ## height cells per mesh chunk side
const FRINGE_WIDTH := 1.8
const TEE_RAISE := 0.25
const TEE_BLEND := 3.0
const BUNKER_DEPTH := 0.7
const BUNKER_LIP := 2.0
const WATER_DROP := 0.3  ## water line below the lowest point of the bank
const APRON := 700.0  ## ground drawn beyond the course edge
## Paint order: later layers cover earlier ones.
const LAYERS := [
	Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS, Surface.Type.ROUGH, Surface.Type.FAIRWAY,
	Surface.Type.FRINGE, Surface.Type.TEE, Surface.Type.GREEN, Surface.Type.SAND, Surface.Type.WATER,
]
const COLORS := [
	Color(0.33, 0.62, 0.25),  # tee
	Color(0.30, 0.58, 0.20),  # fairway
	Color(0.32, 0.64, 0.26),  # fringe
	Color(0.36, 0.72, 0.30),  # green
	Color(0.20, 0.43, 0.14),  # rough
	Color(0.15, 0.33, 0.11),  # deep rough
	Color(0.86, 0.80, 0.60),  # sand
	Color(0.12, 0.25, 0.35),  # water
	Color(0.13, 0.27, 0.10),  # out of bounds
]

var course: DesignedCourse

var _h := PackedFloat32Array()  ## heights after the shapes, on the course grid
var _img: Image  ## surface raster (R8 holds the Surface.Type)
var _surf := PackedByteArray()
var _sw := 0
var _sh := 0
var _vc := PackedColorArray()  ## surface colour per grid vertex
var _vw := PackedVector2Array()  ## rough and sand weights per grid vertex
var _water_levels := {}  ## CourseShape -> water line
var _meshes := {}  ## Vector2i chunk -> ArrayMesh


func _init(p_course: DesignedCourse) -> void:
	course = p_course
	rebuild()


## Everything from scratch: after loading, or a change to the course area.
func rebuild() -> void:
	_sw = int(ceil(course.area.size.x / RES))
	_sh = int(ceil(course.area.size.y / RES))
	_img = Image.create_empty(_sw, _sh, false, Image.FORMAT_R8)
	_h = course.heights.duplicate()
	_vc = PackedColorArray()
	_vc.resize(course.cols * course.rows)
	_vw = PackedVector2Array()
	_vw.resize(course.cols * course.rows)
	_meshes.clear()
	var all := Rect2i(0, 0, course.cols, course.rows)
	_raster(Rect2i(0, 0, _sw, _sh))
	_derive(all)
	_vertex_surfaces(all)
	update_objects()


## After sculpting: `cells` is the rect of height samples that changed.
func update_heights(cells: Rect2i) -> void:
	var r := cells.grow(int(ceil(TEE_BLEND / DesignedCourse.CELL)) + 1).intersection(Rect2i(0, 0, course.cols, course.rows))
	# A pond's water line follows its bank, and a tee pad its mean height,
	# so a change near either redoes the whole shape.
	for s in course.shapes:
		if s.surface in [Surface.Type.WATER, Surface.Type.TEE] and _cells_of(s.bounds().grow(TEE_BLEND)).intersects(r):
			r = r.merge(_cells_of(s.bounds().grow(TEE_BLEND + DesignedCourse.CELL)))
	r = r.intersection(Rect2i(0, 0, course.cols, course.rows))
	_derive(r)
	_invalidate(r)


## After adding, moving or removing shapes: `area` (x, z) covers where the
## surfaces may have changed (the old and new outlines).
func update_surfaces(area: Rect2) -> void:
	var grown := area.grow(FRINGE_WIDTH + TEE_BLEND + DesignedCourse.CELL * 2.0)
	var o := course.area.position
	var px := Rect2i(Vector2i(floori((grown.position.x - o.x) / RES), floori((grown.position.y - o.y) / RES)),
		Vector2i(ceili(grown.size.x / RES) + 1, ceili(grown.size.y / RES) + 1)).intersection(Rect2i(0, 0, _sw, _sh))
	_raster(px)
	var cells := _cells_of(grown)
	for s in course.shapes:
		if s.surface in [Surface.Type.WATER, Surface.Type.TEE, Surface.Type.SAND] and _cells_of(s.bounds()).intersects(cells):
			cells = cells.merge(_cells_of(s.bounds().grow(TEE_BLEND + DesignedCourse.CELL)))
	cells = cells.intersection(Rect2i(0, 0, course.cols, course.rows))
	_derive(cells)
	_vertex_surfaces(cells)
	_invalidate(cells)


## After placing or removing trees.
func update_objects() -> void:
	obstacles = ObstacleField.new()
	for o in course.objects:
		var x := o.position.x
		var z := o.position.z
		var y := height_at(x, z)
		var s := o.scale
		match o.id:
			"tree_pine":
				obstacles.add_cylinder(x, z, 0.28 * s, y - 1.0, y + 3.0 * s, ObstacleField.Kind.SOLID)
				obstacles.add_cylinder(x, z, 2.0 * s, y + 2.5 * s, y + 11.5 * s, ObstacleField.Kind.CANOPY)
			"tree_broadleaf":
				obstacles.add_cylinder(x, z, 0.28 * s, y - 1.0, y + 3.5 * s, ObstacleField.Kind.SOLID)
				obstacles.add_cylinder(x, z, 3.2 * s, y + 3.0 * s, y + 10.0 * s, ObstacleField.Kind.CANOPY)
			_:
				obstacles.add_cylinder(x, z, 0.3 * s, y - 1.0, y + 4.0 * s, ObstacleField.Kind.SOLID)
	obstacles.finalize()


func height_at(x: float, z: float) -> float:
	var a := course.area
	var u := clampf((x - a.position.x) / DesignedCourse.CELL, 0.0, course.cols - 1.001)
	var v := clampf((z - a.position.y) / DesignedCourse.CELL, 0.0, course.rows - 1.001)
	var i := int(u)
	var j := int(v)
	var fu := u - i
	var fv := v - j
	var k := j * course.cols + i
	return lerpf(lerpf(_h[k], _h[k + 1], fu), lerpf(_h[k + course.cols], _h[k + course.cols + 1], fu), fv)


func surface_at(x: float, z: float) -> int:
	var a := course.area
	if not a.has_point(Vector2(x, z)):
		return Surface.Type.OUT_OF_BOUNDS
	var c := mini(int((x - a.position.x) / RES), _sw - 1)
	var r := mini(int((z - a.position.y) / RES), _sh - 1)
	return _surf[r * _sw + c]


## The colour the ground is drawn with at the nearest grid vertex.
func ground_color_at(x: float, z: float) -> Color:
	var c := course.cell_of(Vector2(x, z))
	return _vc[c.y * course.cols + c.x]


## The water line of a pond shape (its bank's lowest point, less a little).
func water_level(shape: CourseShape) -> float:
	return _water_levels.get(shape, 0.0)


func chunk_count() -> Vector2i:
	return Vector2i(ceili(float(course.cols - 1) / CHUNK), ceili(float(course.rows - 1) / CHUNK))


## False when the chunk's mesh is out of date (or was never built).
func chunk_built(c: Vector2i) -> bool:
	return _meshes.has(c)


func chunk_mesh(c: Vector2i) -> ArrayMesh:
	if not _meshes.has(c):
		_meshes[c] = _build_chunk(c)
	return _meshes[c]


## The ground, ponds and the land beyond the course edge.
func build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	var n := chunk_count()
	for cj in n.y:
		for ci in n.x:
			var inst := MeshInstance3D.new()
			inst.mesh = chunk_mesh(Vector2i(ci, cj))
			inst.material_override = Materials.terrain()
			root.add_child(inst)
	root.add_child(build_apron())
	root.add_child(build_water())
	return root


func build_water() -> Node3D:
	var root := Node3D.new()
	root.name = "Water"
	for s in course.shapes:
		if s.surface != Surface.Type.WATER:
			continue
		var poly := s.outline()
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			continue
		var level := water_level(s)
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var normals := PackedVector3Array()
		for p in poly:
			verts.append(Vector3(p.x, level, p.y))
			uvs.append(Vector2(0.5, 0.5))
			normals.append(Vector3.UP)
		var indices := PackedInt32Array()
		for t in range(0, tris.size(), 3):
			_add_tri(indices, verts, tris[t], tris[t + 1], tris[t + 2])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = Materials.water_surface()
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(inst)
	return root


## Ground running out from the course edge to the horizon, so the course
## doesn't end in a cliff.
func build_apron() -> MeshInstance3D:
	var a := course.area
	var border := PackedVector2Array()
	var step := 16.0
	var corners := [a.position, Vector2(a.end.x, a.position.y), a.end, Vector2(a.position.x, a.end.y)]
	for c in 4:
		var p0: Vector2 = corners[c]
		var p1: Vector2 = corners[(c + 1) % 4]
		var n := maxi(1, ceili(p0.distance_to(p1) / step))
		for k in n:
			border.append(p0.lerp(p1, float(k) / n))
	var centre := a.get_center()
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var far_color: Color = COLORS[Surface.Type.OUT_OF_BOUNDS]
	for p in border:
		var inner := p.move_toward(centre, 0.01)
		var h := height_at(inner.x, inner.y)
		var out := (p - centre)
		out = Vector2(signf(out.x) if absf(p.x - a.position.x) < 0.1 or absf(p.x - a.end.x) < 0.1 else 0.0,
			signf(out.y) if absf(p.y - a.position.y) < 0.1 or absf(p.y - a.end.y) < 0.1 else 0.0)
		var far := p + out * APRON
		verts.append(Vector3(p.x, h, p.y))
		verts.append(Vector3(far.x, h * 0.3 - 2.0, far.y))
		colors.append(far_color)
		colors.append(far_color.darkened(0.1))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	var indices := PackedInt32Array()
	var count := border.size()
	for k in count:
		var a0 := 2 * k
		var a1 := 2 * ((k + 1) % count)
		_add_tri(indices, verts, a0, a1, a0 + 1)
		_add_tri(indices, verts, a1, a1 + 1, a0 + 1)
	var weights := PackedVector2Array()
	weights.resize(verts.size())
	weights.fill(Materials.terrain_weights(Surface.Type.OUT_OF_BOUNDS))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var inst := MeshInstance3D.new()
	inst.name = "Apron"
	inst.mesh = mesh
	inst.material_override = Materials.terrain()
	return inst


## Adds a triangle wound the way Godot draws front faces seen from above.
static func _add_tri(indices: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int) -> void:
	var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.y > 0.0:
		indices.append_array(PackedInt32Array([a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c]))


# --- Internals ----------------------------------------------------------------

func _cells_of(r: Rect2) -> Rect2i:
	var lo := course.cell_of(r.position)
	var hi := course.cell_of(r.end)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _invalidate(cells: Rect2i) -> void:
	var g := cells.grow(1)
	for c: Vector2i in _meshes.keys():
		var r := Rect2i(c * CHUNK, Vector2i.ONE * (CHUNK + 1))
		if r.intersects(g):
			_meshes.erase(c)


## Paints the surface raster inside `px` (raster cells).
func _raster(px: Rect2i) -> void:
	if px.size.x <= 0 or px.size.y <= 0:
		return
	_img.fill_rect(px, _code(Surface.Type.ROUGH))
	var o := course.area.position
	var world := Rect2(o + Vector2(px.position) * RES, Vector2(px.size) * RES)
	for layer: int in LAYERS:
		for s in course.shapes:
			if s.surface == layer and s.is_valid() and s.bounds().intersects(world):
				_fill(s.outline(), layer, px)
		if layer == Surface.Type.FRINGE:
			# Every green gets a fringe ring under it.
			for s in course.shapes:
				if s.surface == Surface.Type.GREEN and s.is_valid() and s.bounds().grow(FRINGE_WIDTH).intersects(world):
					for ring in Geometry2D.offset_polygon(s.outline(), FRINGE_WIDTH):
						_fill(ring, Surface.Type.FRINGE, px)
	_surf = _img.get_data()


static func _code(surface: int) -> Color:
	return Color(surface / 255.0, 0.0, 0.0)


## Scanline fill of a polygon into the raster, clipped to `px`.
func _fill(poly: PackedVector2Array, surface: int, px: Rect2i) -> void:
	var o := course.area.position
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var r0 := maxi(px.position.y, floori((lo.y - o.y) / RES))
	var r1 := mini(px.end.y - 1, ceili((hi.y - o.y) / RES))
	var color := _code(surface)
	var n := poly.size()
	var xs := PackedFloat32Array()
	for r in range(r0, r1 + 1):
		var y := o.y + (r + 0.5) * RES
		xs.clear()
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			if (a.y <= y) != (b.y <= y):
				xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var c0 := maxi(px.position.x, ceili((xs[k] - o.x) / RES - 0.5))
			var c1 := mini(px.end.x - 1, floori((xs[k + 1] - o.x) / RES - 0.5))
			if c1 >= c0:
				_img.fill_rect(Rect2i(c0, r, c1 - c0 + 1, 1), color)


## Recomputes the shaped heights inside `cells` from the sculpted ones.
func _derive(cells: Rect2i) -> void:
	var cols := course.cols
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			_h[j * cols + i] = course.heights[j * cols + i]
	for s in course.shapes:
		if not s.is_valid():
			continue
		match s.surface:
			Surface.Type.TEE:
				var level := 0.0
				for p in s.points:
					level += course.base_height(p.x, p.y)
				_shape_heights(s, cells, TEE_BLEND, func(h: float, d: float) -> float:
					return lerpf(level / s.points.size() + TEE_RAISE, h, smoothstep(0.0, TEE_BLEND, d)))
	for s in course.shapes:
		if s.is_valid() and s.surface == Surface.Type.SAND:
			_shape_heights(s, cells, 0.0, func(h: float, d: float) -> float:
				return h - BUNKER_DEPTH * smoothstep(0.0, BUNKER_LIP, -d))
	for s in course.shapes:
		if s.is_valid() and s.surface == Surface.Type.WATER:
			var lowest := INF
			for p in s.outline():
				lowest = minf(lowest, course.base_height(p.x, p.y))
			var level := lowest - WATER_DROP
			_water_levels[s] = level
			_shape_heights(s, cells, 0.0, func(h: float, d: float) -> float:
				return minf(h, level - 0.3 - 1.6 * smoothstep(0.0, 6.0, -d)))


## Applies `f(height, signed distance)` to the samples inside the shape (or
## within `outside` metres of it) that fall in `cells`.
func _shape_heights(s: CourseShape, cells: Rect2i, outside: float, f: Callable) -> void:
	var r := _cells_of(s.bounds().grow(outside + DesignedCourse.CELL)).intersection(cells)
	var cols := course.cols
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var p := course.sample_pos(i, j)
			var d := s.signed_distance(p)
			if d <= outside:
				_h[j * cols + i] = f.call(_h[j * cols + i], d)


## Surface colour and texture weights for each grid vertex in `cells`,
## averaged over a little cross of raster samples so edges blend.
func _vertex_surfaces(cells: Rect2i) -> void:
	var cols := course.cols
	var step := roundi(DesignedCourse.CELL / RES)
	var off := 2  # raster cells, 1 m
	var palette: Array[Color] = []
	var wts: Array[Vector2] = []
	for s in COLORS.size():
		palette.append(COLORS[s])
		wts.append(Materials.terrain_weights(s))
	var o := course.area.position
	for j in range(cells.position.y, cells.end.y):
		var r := mini(j * step, _sh - 1)
		var row := r * _sw
		var row_d := maxi(r - off, 0) * _sw
		var row_u := mini(r + off, _sh - 1) * _sw
		for i in range(cells.position.x, cells.end.x):
			var c := mini(i * step, _sw - 1)
			var cl := maxi(c - off, 0)
			var cr := mini(c + off, _sw - 1)
			var s0 := _surf[row + c]
			var s1 := _surf[row + cl]
			var s2 := _surf[row + cr]
			var s3 := _surf[row_d + c]
			var s4 := _surf[row_u + c]
			var col: Color = (palette[s0] + palette[s1] + palette[s2] + palette[s3] + palette[s4]) * 0.2
			if s0 == Surface.Type.FAIRWAY or s0 == Surface.Type.GREEN or s0 == Surface.Type.TEE:
				# Mowing stripes.
				var x := o.x + i * DesignedCourse.CELL
				var z := o.y + j * DesignedCourse.CELL
				if posmod(floori((x + z * 0.15) / 6.0), 2) == 0:
					col = col.lightened(0.06)
			col.a = 1.0
			var k := j * cols + i
			_vc[k] = col
			_vw[k] = (wts[s0] + wts[s1] + wts[s2] + wts[s3] + wts[s4]) * 0.2


func _build_chunk(c: Vector2i) -> ArrayMesh:
	var cols := course.cols
	var i0 := c.x * CHUNK
	var j0 := c.y * CHUNK
	var i1 := mini(i0 + CHUNK, cols - 1)
	var j1 := mini(j0 + CHUNK, course.rows - 1)
	var nx := i1 - i0 + 1
	var nz := j1 - j0 + 1
	var verts := PackedVector3Array()
	verts.resize(nx * nz)
	var normals := PackedVector3Array()
	normals.resize(nx * nz)
	var colors := PackedColorArray()
	colors.resize(nx * nz)
	var weights := PackedVector2Array()
	weights.resize(nx * nz)
	var cell := DesignedCourse.CELL
	for j in nz:
		var gj := j0 + j
		for i in nx:
			var gi := i0 + i
			var k := gj * cols + gi
			var p := course.sample_pos(gi, gj)
			verts[j * nx + i] = Vector3(p.x, _h[k], p.y)
			var hl := _h[gj * cols + maxi(gi - 1, 0)]
			var hr := _h[gj * cols + mini(gi + 1, cols - 1)]
			var hd := _h[maxi(gj - 1, 0) * cols + gi]
			var hu := _h[mini(gj + 1, course.rows - 1) * cols + gi]
			normals[j * nx + i] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			colors[j * nx + i] = _vc[k]
			weights[j * nx + i] = _vw[k]
	var indices := PackedInt32Array()
	indices.resize((nx - 1) * (nz - 1) * 6)
	var n := 0
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var cc := a + nx
			var d := cc + 1
			# Clockwise seen from above, which Godot treats as front-facing.
			indices[n] = a
			indices[n + 1] = b
			indices[n + 2] = cc
			indices[n + 3] = b
			indices[n + 4] = d
			indices[n + 5] = cc
			n += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
