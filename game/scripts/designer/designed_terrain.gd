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
## Water surfaces: grid spacing inside a pond, and how far out from the
## bank the shallows reach (see water_surface_mesh()).
const SHORE_STEP := 4.0
const SHORE_REACH := 10.0
const APRON := 700.0  ## ground drawn beyond the course edge
## Paint order: later layers cover earlier ones.
const LAYERS := [
	Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS, Surface.Type.ROUGH, Surface.Type.FAIRWAY,
	Surface.Type.FRINGE, Surface.Type.TEE, Surface.Type.GREEN, Surface.Type.SAND, Surface.Type.WATER,
]
const COLORS := [
	Color(0.29, 0.48, 0.19),  # tee (olive, as real turf reads in sun)
	Color(0.29, 0.47, 0.18),  # fairway
	Color(0.27, 0.47, 0.19),  # fringe
	Color(0.30, 0.52, 0.21),  # green
	Color(0.22, 0.38, 0.14),  # rough
	Color(0.19, 0.31, 0.12),  # deep rough
	Color(0.78, 0.72, 0.55),  # sand
	Color(0.12, 0.25, 0.35),  # water
	Color(0.13, 0.27, 0.10),  # out of bounds
]

## How far each surface's colour moves toward the aerial photo's (real
## courses with a photo): a little on the mown grass, so it keeps its game
## colours and stripes, more on the rough and beyond, so worn patches,
## fields, tracks and dry grass look as they really do. Same order as COLORS.
const PHOTO_TINT := [0.15, 0.2, 0.2, 0.1, 0.55, 0.65, 0.5, 0.0, 0.75]
const PHOTO_BLUR := 6.0  ## metres; crowns, cars and flags blur out
## Largest splat map side in texels (older phones and browsers top out at
## 4096); a bigger course gets a coarser one.
const SPLAT_MAX := 4096

var course: DesignedCourse

var _h := PackedFloat32Array()  ## heights after the shapes, on the course grid
var _img: Image  ## surface raster (R8 holds the Surface.Type)
var _surf := PackedByteArray()
var _sw := 0
var _sh := 0
var _vc := PackedColorArray()  ## surface colour per grid vertex
var _vw := PackedVector2Array()  ## rough and sand weights per grid vertex
var _vp := PackedFloat32Array()  ## surface colour per grid vertex before tint and stripes (RGB)
var _material: ShaderMaterial
var _splat: ImageTexture
var _water_levels := {}  ## CourseShape -> water line
var _meshes := {}  ## Vector2i chunk -> ArrayMesh
var _tint := PackedByteArray()  ## softened photo colour per grid vertex (RGB8); empty without a photo


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
	_vp = PackedFloat32Array()
	_vp.resize(course.cols * course.rows * 3)
	_meshes.clear()
	_make_tint()
	var all := Rect2i(0, 0, course.cols, course.rows)
	_raster(Rect2i(0, 0, _sw, _sh))
	_derive(all)
	_vertex_surfaces(all)
	_update_splat()
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
	_update_splat()
	_invalidate(cells)


## After placing or removing trees and other objects.
func update_objects() -> void:
	obstacles = ObstacleField.new()
	for o in course.objects:
		DesignerObjects.add_obstacles(obstacles, o, height_at(o.position.x, o.position.z), course.object_info)
	for p in course.paths:
		if p.bridge and p.is_valid():
			_add_bridge_obstacles(p)
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


## Cart paths give a free drop, as on the game's own courses.
func free_drop_at(x: float, z: float) -> bool:
	for p in course.paths:
		if not p.bridge and p.distance_to(Vector2(x, z)) <= p.width * 0.5:
			return true
	return false


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
			inst.material_override = material()
			root.add_child(inst)
	root.add_child(build_apron())
	root.add_child(build_paths())
	root.add_child(build_water())
	return root


## The ground's material: the shared terrain shader with this course's
## splat map, so surface edges are drawn at the raster's 0.5 m rather than
## blended across the 2 m height grid.
func material() -> ShaderMaterial:
	if _material == null:
		_material = Materials.terrain().duplicate() as ShaderMaterial
		var cols := PackedVector3Array()
		var wts := PackedVector2Array()
		var mown := PackedFloat32Array()
		for i in COLORS.size():
			# Under the water line, the bank: darker rough rather than the
			# map's blue, which would ring each pond.
			var c: Color = COLORS[Surface.Type.ROUGH].darkened(0.35) if i == Surface.Type.WATER else COLORS[i]
			cols.append(Vector3(c.r, c.g, c.b))
			wts.append(Materials.terrain_weights(i))
			mown.append(1.0 if i in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE] else 0.0)
		_material.set_shader_parameter("surface_colors", cols)
		_material.set_shader_parameter("surface_weights", wts)
		_material.set_shader_parameter("surface_mown", mown)
		_material.set_shader_parameter("has_splat", true)
		_update_splat()
	return _material


func _update_splat() -> void:
	if _material == null or _img == null:
		return
	var img := _img
	if _sw > SPLAT_MAX or _sh > SPLAT_MAX:
		var k := float(SPLAT_MAX) / maxi(_sw, _sh)
		img = _img.duplicate() as Image
		img.resize(maxi(1, floori(_sw * k)), maxi(1, floori(_sh * k)), Image.INTERPOLATE_NEAREST)
	if _splat == null or _splat.get_size() != Vector2(img.get_size()):
		_splat = ImageTexture.create_from_image(img)
		_material.set_shader_parameter("splat_tex", _splat)
	else:
		_splat.update(img)
	_material.set_shader_parameter("splat_origin", course.area.position)
	_material.set_shader_parameter("splat_size", Vector2(_sw, _sh) * RES)


## Cart paths draped on the ground, and bridges with their rails.
func build_paths() -> Node3D:
	var root := Node3D.new()
	root.name = "Paths"
	for p in course.paths:
		if p.is_valid():
			root.add_child(_path_mesh(p))
	return root


func _path_mesh(p: CoursePath) -> MeshInstance3D:
	var samples := p.samples()
	var g0 := height_at(p.points[0].x, p.points[0].y)
	var last := p.points[p.points.size() - 1]
	var g1 := height_at(last.x, last.y)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var rail_verts := PackedVector3Array()
	for smp: Array in samples:
		var c: Vector2 = smp[0]
		var side: Vector2 = (smp[1] as Vector2).orthogonal() * p.width * 0.5
		var l := c + side
		var r := c - side
		var along: float = smp[2]
		if p.bridge:
			var y := p.deck_height(along, height_at(c.x, c.y), g0, g1)
			verts.append(Vector3(l.x, y, l.y))
			verts.append(Vector3(r.x, y, r.y))
			for e: Vector2 in [l, r]:
				rail_verts.append(Vector3(e.x, y, e.y))
				rail_verts.append(Vector3(e.x, y + 1.0, e.y))
		else:
			verts.append(Vector3(l.x, height_at(l.x, l.y) + 0.05, l.y))
			verts.append(Vector3(r.x, height_at(r.x, r.y) + 0.05, r.y))
		uvs.append(Vector2(0.0, along / p.width))
		uvs.append(Vector2(1.0, along / p.width))
	var indices := PackedInt32Array()
	for k in samples.size() - 1:
		var a := 2 * k
		_add_tri(indices, verts, a, a + 2, a + 1)
		_add_tri(indices, verts, a + 1, a + 2, a + 3)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _path_material(p.bridge))
	if p.bridge and rail_verts.size() >= 8:
		# Two rails, each a strip of upright quads along one edge.
		var rail_idx := PackedInt32Array()
		var n := samples.size()
		for side in 2:
			for k in n - 1:
				var a := 4 * k + 2 * side
				var b := 4 * (k + 1) + 2 * side
				rail_idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
		var rail_normals := PackedVector3Array()
		rail_normals.resize(rail_verts.size())
		rail_normals.fill(Vector3.UP)
		var rails := []
		rails.resize(Mesh.ARRAY_MAX)
		rails[Mesh.ARRAY_VERTEX] = rail_verts
		rails[Mesh.ARRAY_NORMAL] = rail_normals
		rails[Mesh.ARRAY_INDEX] = rail_idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rails)
		mesh.surface_set_material(1, _path_material(true))
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	return inst


static var _path_mat: StandardMaterial3D
static var _bridge_mat: StandardMaterial3D


static func _path_material(bridge: bool) -> StandardMaterial3D:
	if bridge:
		if _bridge_mat == null:
			_bridge_mat = StandardMaterial3D.new()
			_bridge_mat.albedo_color = Color(0.45, 0.33, 0.22)
			_bridge_mat.roughness = 0.85
			_bridge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return _bridge_mat
	if _path_mat == null:
		_path_mat = StandardMaterial3D.new()
		_path_mat.albedo_color = Color(0.62, 0.60, 0.56)
		_path_mat.roughness = 0.95
	return _path_mat


## The deck of a bridge, as a chain of solid boxes 0.3 m thick.
func _add_bridge_obstacles(p: CoursePath) -> void:
	var samples := p.samples()
	var g0 := height_at(p.points[0].x, p.points[0].y)
	var last := p.points[p.points.size() - 1]
	var g1 := height_at(last.x, last.y)
	var k := 0
	while k < samples.size() - 1:
		var k2 := mini(k + 4, samples.size() - 1)
		var a: Vector2 = samples[k][0]
		var b: Vector2 = samples[k2][0]
		var ya := p.deck_height(samples[k][2], height_at(a.x, a.y), g0, g1)
		var yb := p.deck_height(samples[k2][2], height_at(b.x, b.y), g0, g1)
		var pa := Vector3(a.x, ya, a.y)
		var pb := Vector3(b.x, yb, b.y)
		var along := (pb - pa)
		if along.length() > 0.01:
			var x_axis := along.normalized()
			var z_axis := x_axis.cross(Vector3.UP).normalized()
			var y_axis := z_axis.cross(x_axis).normalized()
			var mid := (pa + pb) * 0.5 - y_axis * 0.15
			obstacles.add_box(mid, Basis(x_axis, y_axis, z_axis), Vector3(along.length() * 0.5 + 0.05, 0.15, p.width * 0.5), ObstacleField.Kind.SOLID)
		k = k2


func build_water() -> Node3D:
	var root := Node3D.new()
	root.name = "Water"
	for s in course.shapes:
		if s.surface != Surface.Type.WATER:
			continue
		var poly := s.outline()
		if Geometry2D.triangulate_polygon(poly).is_empty():
			continue
		var level := water_level(s)
		var surface := water_surface_mesh(poly, level)
		var verts: PackedVector3Array = surface[0]
		var open: PackedColorArray = surface[1]
		var indices: PackedInt32Array = surface[2]
		var uvs := PackedVector2Array()
		uvs.resize(verts.size())
		uvs.fill(Vector2(0.5, 0.5))
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		normals.fill(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = open
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
## A pond's water surface at `level`: [vertices, colours, indices]. The
## outline plus a grid of points inside it every SHORE_STEP metres,
## triangulated (Delaunay) and kept where a triangle's middle is inside.
## COLOR.r is how far each vertex is from the bank (0 on it, 1 from
## SHORE_REACH metres out), for the water shader's shallows and shoreline.
static func water_surface_mesh(poly: PackedVector2Array, level: float) -> Array:
	var points := poly.duplicate()
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	var step := maxf(SHORE_STEP, sqrt(box.get_area() / 1500.0))
	var y := box.position.y + step * 0.5
	while y < box.end.y:
		var x := box.position.x + step * 0.5
		while x < box.end.x:
			var p := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(p, poly) and _edge_distance(p, poly) > step * 0.4:
				points.append(p)
			x += step
		y += step
	var verts := PackedVector3Array()
	var open := PackedColorArray()
	for p in points:
		verts.append(Vector3(p.x, level, p.y))
		open.append(Color(clampf(_edge_distance(p, poly) / SHORE_REACH, 0.0, 1.0), 0.0, 0.0))
	var indices := PackedInt32Array()
	var tris := Geometry2D.triangulate_delaunay(points)
	for t in range(0, tris.size(), 3):
		var mid := (points[tris[t]] + points[tris[t + 1]] + points[tris[t + 2]]) / 3.0
		if Geometry2D.is_point_in_polygon(mid, poly):
			_add_tri(indices, verts, tris[t], tris[t + 1], tris[t + 2])
	return [verts, open, indices]


static func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


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
		if layer == Surface.Type.FAIRWAY:
			# Cart paths play as fairway (firm and mown).
			for p in course.paths:
				if not p.bridge and p.is_valid() and p.bounds().intersects(world):
					_fill(p.outline(), Surface.Type.FAIRWAY, px)
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
			var k := j * cols + i
			_vp[k * 3] = col.r
			_vp[k * 3 + 1] = col.g
			_vp[k * 3 + 2] = col.b
			if not _tint.is_empty():
				col = _photo_tinted(col, s0, k)
			col.a = 1.0
			_vc[k] = col
			_vw[k] = (wts[s0] + wts[s1] + wts[s2] + wts[s3] + wts[s4]) * 0.2


## The course photo, softened and resampled to one colour per grid vertex.
func _make_tint() -> void:
	_tint = PackedByteArray()
	var photo := course.tint_image()
	if photo == null or course.cols < 2 or course.rows < 2:
		return
	var img: Image = photo.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var cell := DesignedCourse.CELL * PHOTO_BLUR / 2.0
	img.resize(maxi(2, ceili(course.area.size.x / cell)), maxi(2, ceili(course.area.size.y / cell)), Image.INTERPOLATE_LANCZOS)
	img.resize(course.cols, course.rows, Image.INTERPOLATE_BILINEAR)
	# The photo's first pixel is the north-west corner, the grid's the
	# south-east (+x is west, +z north).
	img.flip_x()
	img.flip_y()
	_tint = img.get_data()


## A surface colour moved toward the photo's colour at grid vertex `k`,
## keeping roughly the game's brightness. Deep shade, crowns and water in
## the photo are left out.
func _photo_tinted(col: Color, surface: int, k: int) -> Color:
	var amount: float = PHOTO_TINT[surface]
	if amount <= 0.0:
		return col
	var t := Color8(_tint[k * 3], _tint[k * 3 + 1], _tint[k * 3 + 2])
	var lt := t.get_luminance()
	if lt < 0.1:
		return col
	var real := t * clampf(col.get_luminance() / lt, 0.75, 1.35)
	return col.lerp(real, amount)


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
	var palette := PackedFloat32Array()
	palette.resize(nx * nz * 4)
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
			for ch in 3:
				palette[(j * nx + i) * 4 + ch] = _vp[k * 3 + ch]
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
	arrays[Mesh.ARRAY_CUSTOM0] = palette
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return mesh
