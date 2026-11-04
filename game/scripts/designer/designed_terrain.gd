class_name DesignedTerrain
extends CourseTerrain
## The ground of a DesignedCourse, for the round and the designer. Heights
## are the sculpted grid, shaped by the painted areas: bunkers are dug in,
## ponds are sunk below their water line and tee boxes become raised, level
## pads with mown banks, drawn and played at fine detail (TeePads).
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
## The first cut: rough within this many metres of a fairway is mown a
## little longer than the fairway (about one mower's width, as on real
## courses). It plays as rough; only the look and the 3D grass differ.
const FIRST_CUT_WIDTH := 1.8
## Raster code of the first cut, after the Surface.Type codes.
const FIRST_CUT_CODE := 9
const FIRST_CUT_COLOR := Color(0.25, 0.43, 0.16)
## The collar: the ring of fringe right round each green, one mower's
## width, cut a little longer and denser than the green and mown round it
## rather than in stripes, so it frames the green as a deeper band (as in
## photos of real greens, where the green reads about a tenth lighter than
## its collar). Wider fringe beyond it is the approach, mown like fairway.
## It plays as fringe; only the look differs.
const COLLAR_WIDTH := 1.2
const COLLAR_CODE := 10
const COLLAR_COLOR := Color(0.255, 0.465, 0.165)
## The green's edge is drawn from the exact distance to its outline, baked
## at GREEN_EDGE_RES metres into the rows below the surface codes in the
## splat texture (GREEN_EDGE_RANGE metres each side, 0..255, 128 on the
## line): the 0.5 m codes alone draw it as a row of scallops.
const GREEN_EDGE_RES := 1.0
const GREEN_EDGE_RANGE := 2.0
const BUNKER_DEPTH := 0.7
const BUNKER_LIP := 2.5  ## metres inside the outline the bunker reaches full depth
const BUNKER_LIP_OUT := 1.5  ## metres outside it where the bank starts down
const WATER_DROP := 0.3  ## water line below the lowest point of the bank
const WATER_BANK := 5.0  ## metres outside a pond over which the bank runs down to it
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
	Color(0.28, 0.47, 0.18),  # fringe (the approach; the collar is COLLAR_COLOR)
	Color(0.32, 0.55, 0.23),  # green
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
## Mowing stripes: how strong per surface, and how wide (the cut of the
## mower that mows it: fairway units about 3 m, triplex tee mowers 1.5 m,
## walk-behind greens mowers 0.55 m).
const MOWN := {Surface.Type.FAIRWAY: 1.0, Surface.Type.FRINGE: 0.7, Surface.Type.TEE: 0.6, Surface.Type.GREEN: 0.25}
const STRIPE_METRES := {Surface.Type.FAIRWAY: 3.0, Surface.Type.FRINGE: 3.0, Surface.Type.TEE: 1.5, Surface.Type.GREEN: 0.55}
const PHOTO_BLUR := 6.0  ## metres; crowns, cars and flags blur out
## Largest splat map side in texels (older phones and browsers top out at
## 4096); a bigger course gets a coarser one.
const SPLAT_MAX := 4096
## Hazard stakes (for the look only; the ball passes them, as stakes are
## movable): yellow round each pond a little outside its edge, white along
## out-of-bounds areas, a metre tall.
const STAKE_WATER_SPACING := 9.0
const STAKE_OB_SPACING := 18.0
const STAKE_WATER_OFFSET := 0.8
const STAKE_HEIGHT := 1.0
const STAKE_YELLOW := Color(0.86, 0.68, 0.08)
const STAKE_WHITE := Color(0.9, 0.9, 0.88)

var course: DesignedCourse

var _h := PackedFloat32Array()  ## heights after the shapes, on the course grid
var _g := PackedFloat32Array()  ## the same before the tee pads
var _pads := TeePads.new()
var _img: Image  ## surface raster (R8 holds the Surface.Type)
var _surf := PackedByteArray()
var _sw := 0
var _sh := 0
var _vc := PackedColorArray()  ## surface colour per grid vertex
var _vw := PackedVector2Array()  ## rough and sand weights per grid vertex
var _vp := PackedFloat32Array()  ## surface colour per grid vertex before tint and stripes (RGB)
var _material: ShaderMaterial
var _splat: ImageTexture
var _edge_img: Image  ## green edge distance (R8), GREEN_EDGE_RES per texel
var _water_levels := {}  ## CourseShape -> water line
var _meshes := {}  ## Vector2i chunk -> ArrayMesh
var _tint := PackedByteArray()  ## softened photo colour per grid vertex (RGB8); empty without a photo
## Mowing stripes run along each hole: per hole, the unit vector across it
## (tee to pin), and on a coarse grid which hole each spot belongs to.
var _across: Array[Vector2] = []
var _pins := PackedVector2Array()  ## each striped hole's pin, in _across order
var _hole_tees: Array[PackedVector2Array] = []  ## and its tees
## Fairway this close to a pin is that hole's approach, striped with it.
const APPROACH_REACH := 45.0
var _owner := PackedByteArray()
var _owner_cols := 0


func _init(p_course: DesignedCourse) -> void:
	course = p_course
	rebuild()


## Everything from scratch: after loading, or a change to the course area.
func rebuild() -> void:
	_sw = int(ceil(course.area.size.x / RES))
	_sh = int(ceil(course.area.size.y / RES))
	_img = Image.create_empty(_sw, _sh, false, Image.FORMAT_R8)
	_edge_img = Image.create_empty(maxi(1, ceili(course.area.size.x / GREEN_EDGE_RES)), maxi(1, ceili(course.area.size.y / GREEN_EDGE_RES)), false, Image.FORMAT_R8)
	_h = course.heights.duplicate()
	_g = _h.duplicate()
	_vc = PackedColorArray()
	_vc.resize(course.cols * course.rows)
	_vw = PackedVector2Array()
	_vw.resize(course.cols * course.rows)
	_vp = PackedFloat32Array()
	_vp.resize(course.cols * course.rows * 3)
	_meshes.clear()
	_make_tint()
	_make_owners()
	var all := Rect2i(0, 0, course.cols, course.rows)
	_raster(Rect2i(0, 0, _sw, _sh))
	_derive(all)
	_vertex_surfaces(all)
	_update_splat()
	update_objects()


## After sculpting: `cells` is the rect of height samples that changed.
func update_heights(cells: Rect2i) -> void:
	var r := cells.grow(int(ceil(TeePads.REACH / DesignedCourse.CELL)) + 1).intersection(Rect2i(0, 0, course.cols, course.rows))
	# A pond's water line follows its bank, and a tee pad its mean height,
	# so a change near either redoes the whole shape.
	for s in course.shapes:
		if s.surface in [Surface.Type.WATER, Surface.Type.TEE] and _cells_of(s.bounds().grow(WATER_BANK)).intersects(r):
			r = r.merge(_cells_of(s.bounds().grow(WATER_BANK + DesignedCourse.CELL)))
	r = r.intersection(Rect2i(0, 0, course.cols, course.rows))
	_derive(r)
	_invalidate(r)


## After adding, moving or removing shapes: `area` (x, z) covers where the
## surfaces may have changed (the old and new outlines).
func update_surfaces(area: Rect2) -> void:
	var grown := area.grow(FRINGE_WIDTH + TeePads.REACH + DesignedCourse.CELL * 2.0)
	var o := course.area.position
	var px := Rect2i(Vector2i(floori((grown.position.x - o.x) / RES), floori((grown.position.y - o.y) / RES)),
		Vector2i(ceili(grown.size.x / RES) + 1, ceili(grown.size.y / RES) + 1)).intersection(Rect2i(0, 0, _sw, _sh))
	_raster(px)
	var cells := _cells_of(grown)
	for s in course.shapes:
		if s.surface in [Surface.Type.WATER, Surface.Type.TEE, Surface.Type.SAND] and _cells_of(s.bounds()).intersects(cells):
			cells = cells.merge(_cells_of(s.bounds().grow(WATER_BANK + DesignedCourse.CELL)))
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
	var pad := _pads.pad_at_cell(course.cols, i, j)
	if pad != null:
		# On a tee pad the ball plays the pad's own triangles, as drawn.
		var y := pad.height_at(Vector2(x, z))
		if not is_nan(y):
			return y
	var k := j * course.cols + i
	return lerpf(lerpf(_h[k], _h[k + 1], fu), lerpf(_h[k + course.cols], _h[k + course.cols + 1], fu), fv)


func surface_at(x: float, z: float) -> int:
	var a := course.area
	if not a.has_point(Vector2(x, z)):
		return Surface.Type.OUT_OF_BOUNDS
	var c := mini(int((x - a.position.x) / RES), _sw - 1)
	var r := mini(int((z - a.position.y) / RES), _sh - 1)
	var s := _surf[r * _sw + c]
	return Surface.Type.ROUGH if s == FIRST_CUT_CODE else (Surface.Type.FRINGE if s == COLLAR_CODE else s)


func first_cut_at(x: float, z: float) -> bool:
	var a := course.area
	if not a.has_point(Vector2(x, z)):
		return false
	var c := mini(int((x - a.position.x) / RES), _sw - 1)
	var r := mini(int((z - a.position.y) / RES), _sh - 1)
	return _surf[r * _sw + c] == FIRST_CUT_CODE


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
	if TreeFactory.enabled() and hole_number > 0:
		_add_distant_trees(root)
	return root


## The course's trees beyond the ones the round places for this hole
## (DesignedCourse.near_hole), as batched trees that are impostors far off,
## so the woods across the course are seen rather than bare ground. Visual
## only: every tree's obstacles are in `obstacles` already.
func _add_distant_trees(root: Node3D) -> void:
	var dh := course.played_hole(hole_number)
	if dh == null:
		return
	var trees := PackedFloat32Array()
	for o in course.objects:
		var p := Vector2(o.position.x, o.position.z)
		if DesignedCourse.near_hole(dh, p):
			continue
		var species := -1
		match o.id:
			"tree_pine":
				species = TreeFactory.Species.PINE
			"tree_broadleaf":
				species = TreeFactory.Species.BROADLEAF
		if species < 0:
			continue
		var h := TreeFactory.natural_height(species, p.x, p.y) * o.scale
		trees.append_array(PackedFloat32Array([p.x, height_at(p.x, p.y), p.y, h, species]))
	for batch: Dictionary in TreeFactory.batches(trees, 160.0):
		var node := MultiMeshInstance3D.new()
		node.name = "DistantTrees"
		node.multimesh = batch.multimesh
		node.position = batch.position
		# They stand at least HOLE_REACH from the tees and the line of play,
		# so their shadows seldom reach the ground the player looks at, and
		# drawing them again for the sun is most of what woods cost.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if batch.full:
			node.visibility_range_end = TreeFactory.impostor_distance() + float(batch.reach) + 5.0
		root.add_child(node)


## The ground's material: the shared terrain shader with this course's
## splat map, so surface edges are drawn at the raster's 0.5 m rather than
## blended across the 2 m height grid.
func material() -> ShaderMaterial:
	if _material == null:
		_material = Materials.terrain().duplicate() as ShaderMaterial
		var cols := PackedVector3Array()
		var wts := PackedVector2Array()
		var mown := PackedFloat32Array()
		var widths := PackedFloat32Array()
		var cut := PackedFloat32Array()
		for i in COLORS.size():
			# Under the water line, the bank: darker rough rather than the
			# map's blue, which would ring each pond.
			var c: Color = COLORS[Surface.Type.ROUGH].darkened(0.35) if i == Surface.Type.WATER else COLORS[i]
			cols.append(Vector3(c.r, c.g, c.b))
			wts.append(Materials.terrain_weights(i))
			mown.append(float(MOWN.get(i, 0.0)))
			widths.append(float(STRIPE_METRES.get(i, 0.0)))
			cut.append(Materials.terrain_cut(i))
		# The splat's tenth entry: the first cut; the eleventh the collar.
		cols.append(Vector3(FIRST_CUT_COLOR.r, FIRST_CUT_COLOR.g, FIRST_CUT_COLOR.b))
		wts.append(Materials.terrain_weights(Surface.Type.ROUGH))
		mown.append(0.0)
		widths.append(0.0)
		cut.append(0.0)
		cols.append(Vector3(COLLAR_COLOR.r, COLLAR_COLOR.g, COLLAR_COLOR.b))
		wts.append(Materials.terrain_weights(Surface.Type.FRINGE))
		mown.append(0.0)
		widths.append(0.0)
		cut.append(Materials.COLLAR_CUT)
		_material.set_shader_parameter("surface_stripe_metres", widths)
		_material.set_shader_parameter("surface_colors", cols)
		_material.set_shader_parameter("surface_cut", cut)
		_material.set_shader_parameter("surface_weights", wts)
		_material.set_shader_parameter("surface_mown", mown)
		_material.set_shader_parameter("has_splat", true)
		_update_splat()
	return _material


func _update_splat() -> void:
	if _material == null or _img == null:
		return
	# The surface codes, and below them the green edge distances, coarser
	# where the codes leave too few rows (the codes keep their detail).
	var codes := _img
	if _sw > SPLAT_MAX or _sh > SPLAT_MAX:
		var k := float(SPLAT_MAX) / maxi(_sw, _sh)
		codes = _img.duplicate() as Image
		codes.resize(maxi(1, floori(_sw * k)), maxi(1, floori(_sh * k)), Image.INTERPOLATE_NEAREST)
	var edges := _edge_img
	var e := minf(float(SPLAT_MAX - codes.get_height()) / edges.get_height(), float(SPLAT_MAX) / edges.get_width())
	var img := codes
	if e * edges.get_height() < 64.0:
		_material.set_shader_parameter("splat_codes", Vector2i.ZERO)
	else:
		if e < 1.0:
			edges = _edge_img.duplicate() as Image
			edges.resize(maxi(1, floori(edges.get_width() * e)), maxi(1, floori(edges.get_height() * e)), Image.INTERPOLATE_BILINEAR)
		img = Image.create_empty(maxi(codes.get_width(), edges.get_width()), codes.get_height() + edges.get_height(), false, Image.FORMAT_R8)
		img.blit_rect(codes, Rect2i(Vector2i.ZERO, codes.get_size()), Vector2i.ZERO)
		img.blit_rect(edges, Rect2i(Vector2i.ZERO, edges.get_size()), Vector2i(0, codes.get_height()))
		_material.set_shader_parameter("splat_codes", codes.get_size())
		_material.set_shader_parameter("green_edge_size", edges.get_size())
		_material.set_shader_parameter("green_edge_texel", GREEN_EDGE_RES * Vector2(_edge_img.get_size()) / Vector2(edges.get_size()))
		_material.set_shader_parameter("green_edge_range", GREEN_EDGE_RANGE)
	if _splat == null or _splat.get_size() != Vector2(img.get_size()):
		_splat = ImageTexture.create_from_image(img)
		_material.set_shader_parameter("splat_tex", _splat)
	else:
		_splat.update(img)
	_material.set_shader_parameter("splat_origin", course.area.position)
	_material.set_shader_parameter("splat_size", Vector2(_sw, _sh) * RES)


## The surfaces a cart path is not drawn over (it stops at their edge).
const PATH_NOT_ON := [Surface.Type.SAND, Surface.Type.GREEN, Surface.Type.WATER]


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
	# A cart path on the ground stops at a bunker, green or pond rather
	# than being draped over it (as a flat grey slab across the sand).
	var clear := PackedByteArray()
	for v in verts.size():
		clear.append(1 if p.bridge or not PATH_NOT_ON.has(surface_at(verts[v].x, verts[v].z)) else 0)
	var indices := PackedInt32Array()
	for k in samples.size() - 1:
		var a := 2 * k
		if clear[a] == 0 or clear[a + 1] == 0 or clear[a + 2] == 0 or clear[a + 3] == 0:
			continue
		_add_tri(indices, verts, a, a + 2, a + 1)
		_add_tri(indices, verts, a + 1, a + 2, a + 3)
	if indices.is_empty():
		return MeshInstance3D.new()  # all of it over sand, a green or water
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
		# Weathered asphalt, as most cart paths are (pale concrete read
		# as a bright line across the view from the tee).
		_path_mat.albedo_color = Color(0.36, 0.35, 0.33)
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
	var stakes := build_stakes()
	if stakes != null:
		root.add_child(stakes)
	return root


## The hazard stakes as one MultiMesh, or null if the course has none.
func build_stakes() -> MultiMeshInstance3D:
	var at: Array[Vector3] = []
	var colours: Array[Color] = []
	for s in course.shapes:
		if not s.is_valid():
			continue
		var line := PackedVector2Array()
		var spacing := 0.0
		var colour := STAKE_WHITE
		if s.surface == Surface.Type.WATER:
			var grown := Geometry2D.offset_polygon(s.outline(), STAKE_WATER_OFFSET)
			if grown.is_empty():
				continue
			line = grown[0]
			spacing = STAKE_WATER_SPACING
			colour = STAKE_YELLOW
		elif s.surface == Surface.Type.OUT_OF_BOUNDS:
			line = s.outline()
			spacing = STAKE_OB_SPACING
		else:
			continue
		for p in stake_points(line, spacing):
			at.append(Vector3(p.x, height_at(p.x, p.y), p.y))
			colours.append(colour)
	if at.is_empty():
		return null
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.022
	mesh.bottom_radius = 0.028
	mesh.height = STAKE_HEIGHT
	mesh.radial_segments = 6
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.metallic_specular = 0.3
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = at.size()
	for i in at.size():
		# A little lean, as stakes knocked in by hand stand.
		var lean := Basis(Vector3(sin(i * 1.7), 0.0, cos(i * 2.3)).normalized(), 0.04 * sin(i * 0.9))
		mm.set_instance_transform(i, Transform3D(lean, at[i] + Vector3(0.0, STAKE_HEIGHT * 0.5 - 0.05, 0.0)))
		mm.set_instance_color(i, colours[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = "Stakes"
	inst.multimesh = mm
	return inst


## Points every `spacing` metres round a closed outline, evenly spread so
## the last gap matches the others.
static func stake_points(poly: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	if n < 3 or spacing <= 0.0:
		return out
	var perimeter := 0.0
	for i in n:
		perimeter += poly[i].distance_to(poly[(i + 1) % n])
	var count := maxi(3, roundi(perimeter / spacing))
	var step := perimeter / count
	var next := 0.0
	var walked := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var seg := a.distance_to(b)
		while next < walked + seg and out.size() < count:
			out.append(a.lerp(b, (next - walked) / seg))
			next += step
		walked += seg
	return out


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
	_first_cut(px)
	_collar(px)
	_img.set_data(_sw, _sh, false, Image.FORMAT_R8, _surf)
	_green_edges(world)


## Marks the rough within FIRST_CUT_WIDTH of each fairway (not of cart
## paths) inside `px` as the first cut, in the raster bytes `_surf`.
func _first_cut(px: Rect2i) -> void:
	var o := course.area.position
	var world := Rect2(o + Vector2(px.position) * RES, Vector2(px.size) * RES)
	var rough := Surface.Type.ROUGH
	for s in course.shapes:
		if s.surface != Surface.Type.FAIRWAY or not s.is_valid() or not s.bounds().grow(FIRST_CUT_WIDTH).intersects(world):
			continue
		for poly in Geometry2D.offset_polygon(s.outline(), FIRST_CUT_WIDTH):
			for span in _spans(poly, px):
				var row: int = span.x * _sw
				for c in range(span.y, span.z + 1):
					if _surf[row + c] == rough:
						_surf[row + c] = FIRST_CUT_CODE


## Marks the fringe within COLLAR_WIDTH of each green inside `px` as the
## collar, in the raster bytes `_surf`.
func _collar(px: Rect2i) -> void:
	var o := course.area.position
	var world := Rect2(o + Vector2(px.position) * RES, Vector2(px.size) * RES)
	var fringe := Surface.Type.FRINGE
	for s in course.shapes:
		if s.surface != Surface.Type.GREEN or not s.is_valid() or not s.bounds().grow(COLLAR_WIDTH).intersects(world):
			continue
		for poly in Geometry2D.offset_polygon(s.outline(), COLLAR_WIDTH):
			for span in _spans(poly, px):
				var row: int = span.x * _sw
				for c in range(span.y, span.z + 1):
					if _surf[row + c] == fringe:
						_surf[row + c] = COLLAR_CODE


## Bakes the signed distance to each green's outline (positive inside) into
## `_edge_img` over the world rect `world`.
func _green_edges(world: Rect2) -> void:
	if _edge_img == null:
		return
	var o := course.area.position
	var size := _edge_img.get_size()
	var lo := Vector2i(clampi(floori((world.position.x - o.x) / GREEN_EDGE_RES), 0, size.x), clampi(floori((world.position.y - o.y) / GREEN_EDGE_RES), 0, size.y))
	var hi := Vector2i(clampi(ceili((world.end.x - o.x) / GREEN_EDGE_RES), 0, size.x), clampi(ceili((world.end.y - o.y) / GREEN_EDGE_RES), 0, size.y))
	var region := Rect2i(lo, hi - lo)
	if region.size.x <= 0 or region.size.y <= 0:
		return
	_edge_img.fill_rect(region, Color(0.0, 0.0, 0.0))
	var scale := 127.5 / GREEN_EDGE_RANGE
	for s in course.shapes:
		if s.surface != Surface.Type.GREEN or not s.is_valid():
			continue
		var grown := s.bounds().grow(GREEN_EDGE_RANGE + GREEN_EDGE_RES)
		if not grown.intersects(world):
			continue
		var box := Rect2i(Vector2i(floori((grown.position.x - o.x) / GREEN_EDGE_RES), floori((grown.position.y - o.y) / GREEN_EDGE_RES)),
			Vector2i(ceili(grown.size.x / GREEN_EDGE_RES) + 1, ceili(grown.size.y / GREEN_EDGE_RES) + 1)).intersection(region)
		if box.size.x <= 0 or box.size.y <= 0:
			continue
		# Unsigned distance to the outline, only near each segment.
		var dist := PackedFloat32Array()
		dist.resize(box.size.x * box.size.y)
		dist.fill(GREEN_EDGE_RANGE)
		var poly := s.outline()
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			var i0 := maxi(floori((minf(a.x, b.x) - GREEN_EDGE_RANGE - o.x) / GREEN_EDGE_RES), box.position.x)
			var i1 := mini(ceili((maxf(a.x, b.x) + GREEN_EDGE_RANGE - o.x) / GREEN_EDGE_RES), box.end.x - 1)
			var j0 := maxi(floori((minf(a.y, b.y) - GREEN_EDGE_RANGE - o.y) / GREEN_EDGE_RES), box.position.y)
			var j1 := mini(ceili((maxf(a.y, b.y) + GREEN_EDGE_RANGE - o.y) / GREEN_EDGE_RES), box.end.y - 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p := o + (Vector2(i, j) + Vector2(0.5, 0.5)) * GREEN_EDGE_RES
					var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
					var at := (j - box.position.y) * box.size.x + (i - box.position.x)
					if d < dist[at]:
						dist[at] = d
		for j in range(box.position.y, box.end.y):
			for i in range(box.position.x, box.end.x):
				var d := dist[(j - box.position.y) * box.size.x + (i - box.position.x)]
				var p := o + (Vector2(i, j) + Vector2(0.5, 0.5)) * GREEN_EDGE_RES
				var inside := Geometry2D.is_point_in_polygon(p, poly) if d < GREEN_EDGE_RANGE else s.contains(p)
				var v := clampf(127.5 + (d if inside else -d) * scale, 0.0, 255.0)
				# Greens can touch: keep the largest (the most inside).
				if v / 255.0 > _edge_img.get_pixel(i, j).r:
					_edge_img.set_pixel(i, j, Color(v / 255.0, 0.0, 0.0))


static func _code(surface: int) -> Color:
	return Color(surface / 255.0, 0.0, 0.0)


## Scanline fill of a polygon into the raster, clipped to `px`.
func _fill(poly: PackedVector2Array, surface: int, px: Rect2i) -> void:
	var color := _code(surface)
	for span in _spans(poly, px):
		_img.fill_rect(Rect2i(span.y, span.x, span.z - span.y + 1, 1), color)


## The raster cells inside a polygon, clipped to `px`, as (row, first
## column, last column) runs.
func _spans(poly: PackedVector2Array, px: Rect2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var o := course.area.position
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var r0 := maxi(px.position.y, floori((lo.y - o.y) / RES))
	var r1 := mini(px.end.y - 1, ceili((hi.y - o.y) / RES))
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
				out.append(Vector3i(r, c0, c1))
	return out


## Recomputes the shaped heights inside `cells` from the sculpted ones.
func _derive(cells: Rect2i) -> void:
	var cols := course.cols
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			_h[j * cols + i] = course.heights[j * cols + i]
	for s in course.shapes:
		if s.is_valid() and s.surface == Surface.Type.SAND:
			# The bank starts a little outside the outline: begun at it, the
			# drop fell between whichever 2 m grid points happened to be
			# inside, so the bank wandered up to a cell either side of the
			# sand's edge and showed as a lumpy, notched lip.
			_shape_heights(s, cells, BUNKER_LIP_OUT, func(h: float, d: float) -> float:
				return h - BUNKER_DEPTH * smoothstep(-BUNKER_LIP_OUT, BUNKER_LIP, -d))
	for s in course.shapes:
		if s.is_valid() and s.surface == Surface.Type.WATER:
			var lowest := INF
			for p in s.outline():
				lowest = minf(lowest, course.base_height(p.x, p.y))
			var level := lowest - WATER_DROP
			_water_levels[s] = level
			# The bank runs down to the water line at the edge and on under
			# it, with no step: a dig that starts at the outline leaves a
			# cliff that the 2 m grid draws as a sawtooth shore.
			_shape_heights(s, cells, WATER_BANK, func(h: float, d: float) -> float:
				if d > 0.0:
					return minf(h, lerpf(level + 0.05, h, smoothstep(0.0, WATER_BANK, d)))
				return minf(h, level + 0.05 - 1.95 * smoothstep(0.0, 6.0, -d)))
	# Tee pads last, on the ground as the hazards left it; the grid gets the
	# pads' shape at its own points, and TeePads the fine inserts.
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			_g[j * cols + i] = _h[j * cols + i]
	for s in course.shapes:
		if s.is_valid() and s.surface == Surface.Type.TEE:
			var level := TeePads.level_of(course, s)
			_shape_heights(s, cells, TeePads.REACH, func(h: float, d: float) -> float:
				return TeePads.profile(h, d, level))
	_pads.rebuild(course, _g, _h, cells)


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
	palette.append(FIRST_CUT_COLOR)
	wts.append(Materials.terrain_weights(Surface.Type.ROUGH))
	palette.append(COLLAR_COLOR)
	wts.append(Materials.terrain_weights(Surface.Type.FRINGE))
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
	var amount: float = PHOTO_TINT[Surface.Type.ROUGH if surface == FIRST_CUT_CODE else (Surface.Type.FRINGE if surface == COLLAR_CODE else surface)]
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
			if _pads.pad_at_cell(cols, i0 + i, j0 + j) != null:
				continue  # drawn by its tee pad's insert below
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
	indices.resize(n)
	var uvs := _stripe_uvs(i0, j0, nx, nz) if not _across.is_empty() else PackedVector2Array()
	# Packed arrays are passed by value, so the pads' part comes back to be joined on.
	var extra := _pad_parts(Rect2i(i0, j0, nx - 1, nz - 1), verts.size())
	verts.append_array(extra[0])
	normals.append_array(extra[1])
	colors.append_array(extra[2])
	weights.append_array(extra[3])
	palette.append_array(extra[4])
	uvs.append_array(extra[5])
	indices.append_array(extra[6])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = weights
	arrays[Mesh.ARRAY_CUSTOM0] = palette
	if not _across.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return mesh


## The tee pad triangles whose middles fall in the chunk's `cells`, with
## their vertices' colours and weights blended from the grid's: [vertices,
## normals, colours, weights, palette, stripe UVs, indices], the indices
## counting from `base`.
func _pad_parts(cells: Rect2i, base: int) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var weights := PackedVector2Array()
	var palette := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var o := course.area.position
	var cell := DesignedCourse.CELL
	var world := Rect2(o + Vector2(cells.position) * cell, Vector2(cells.size) * cell)
	for pad in _pads.pads:
		if not pad.cells.intersects(cells):
			continue
		var remap := PackedInt32Array()
		remap.resize(pad.points.size())
		remap.fill(-1)
		for t in range(0, pad.tris.size(), 3):
			var mid := (pad.points[pad.tris[t]] + pad.points[pad.tris[t + 1]] + pad.points[pad.tris[t + 2]]) / 3.0
			if not world.has_point(mid):
				continue
			for e in 3:
				var v := pad.tris[t + e]
				if remap[v] < 0:
					remap[v] = base + verts.size()
					var p := pad.points[v]
					verts.append(Vector3(p.x, pad.heights[v], p.y))
					normals.append(pad.normals[v])
					var b := _blended(p)
					colors.append(b[0])
					weights.append(b[1])
					palette.append_array(b[2])
					if not _across.is_empty():
						uvs.append(_stripe_uv(p))
				indices.append(remap[v])
	return [verts, normals, colors, weights, palette, uvs, indices]


## Grid colour, weights and palette (RGBA) at `p`, bilinear between the vertices.
func _blended(p: Vector2) -> Array:
	var cols := course.cols
	var u := clampf((p.x - course.area.position.x) / DesignedCourse.CELL, 0.0, cols - 1.001)
	var v := clampf((p.y - course.area.position.y) / DesignedCourse.CELL, 0.0, course.rows - 1.001)
	var i := int(u)
	var j := int(v)
	var fu := u - i
	var fv := v - j
	var k := j * cols + i
	var ks := PackedInt32Array([k, k + 1, k + cols, k + cols + 1])
	var ws := PackedFloat32Array([(1.0 - fu) * (1.0 - fv), fu * (1.0 - fv), (1.0 - fu) * fv, fu * fv])
	var col := Color(0, 0, 0, 0)
	var wt := Vector2.ZERO
	var pal := Vector3.ZERO
	for q in 4:
		var kq := ks[q]
		var w := ws[q]
		col += _vc[kq] * w
		wt += _vw[kq] * w
		pal += Vector3(_vp[kq * 3], _vp[kq * 3 + 1], _vp[kq * 3 + 2]) * w
	return [col, wt, PackedFloat32Array([pal.x, pal.y, pal.z, 0.0])]


## Which hole each OWNER_CELL square of the course is nearest (by its line
## from the back tee through the aim points to the pin), and the direction
## across each hole, for stripes mown along it. Hole boundaries fall in the
## rough between holes, where nothing is striped.
const OWNER_CELL := 8.0


func _make_owners() -> void:
	_across.clear()
	_pins.clear()
	_hole_tees.clear()
	_owner = PackedByteArray()
	var lines: Array[PackedVector2Array] = []
	for dh in course.holes:
		if dh.tees.is_empty():
			continue
		var line := PackedVector2Array([dh.tees[0]])
		line.append_array(dh.route)
		line.append(dh.pin)
		var dir := dh.pin - dh.tees[0]
		if dir.length() < 1.0 or lines.size() >= 255:
			continue
		lines.append(line)
		_across.append(dir.normalized().orthogonal())
		_pins.append(dh.pin)
		_hole_tees.append(PackedVector2Array(dh.tees))
	if lines.is_empty():
		return
	var a := course.area
	_owner_cols = ceili(a.size.x / OWNER_CELL) + 1
	var rows := ceili(a.size.y / OWNER_CELL) + 1
	_owner.resize(_owner_cols * rows)
	for j in rows:
		for i in _owner_cols:
			var p := a.position + Vector2(i, j) * OWNER_CELL
			var best := INF
			var who := 0
			for h in lines.size():
				var line := lines[h]
				for k in range(1, line.size()):
					var d := p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k]))
					if d < best:
						best = d
						who = h
			_owner[j * _owner_cols + i] = who


## Per vertex: metres across its hole (UV.x) and -1 (UV.y), which the
## terrain shader reads as "stripe along the hole".
func _stripe_uvs(i0: int, j0: int, nx: int, nz: int) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	uvs.resize(nx * nz)
	for j in nz:
		for i in nx:
			uvs[j * nx + i] = _stripe_uv(course.sample_pos(i0 + i, j0 + j))
	return uvs


func _stripe_uv(p: Vector2) -> Vector2:
	var a := course.area
	var rows := _owner.size() / _owner_cols
	var oi := clampi(roundi((p.x - a.position.x) / OWNER_CELL), 0, _owner_cols - 1)
	var oj := clampi(roundi((p.y - a.position.y) / OWNER_CELL), 0, rows - 1)
	var who := _owner[oj * _owner_cols + oi]
	# Greens, their collars and approaches, and tees are striped for their
	# own hole even where another hole's line passes nearer (the next tee
	# beside a green), so the stripe direction never changes across them;
	# where it did, the 8 m owner squares showed as blocks of moire.
	var s := surface_at(p.x, p.y)
	if s == Surface.Type.GREEN or s == Surface.Type.FRINGE or s == Surface.Type.FAIRWAY:
		var best := INF
		var near := -1
		for h in _pins.size():
			var d := p.distance_squared_to(_pins[h])
			if d < best:
				best = d
				near = h
		if near >= 0 and (s != Surface.Type.FAIRWAY or best < APPROACH_REACH * APPROACH_REACH):
			who = near
	elif s == Surface.Type.TEE:
		var best := INF
		for h in _hole_tees.size():
			for t in _hole_tees[h]:
				var d := p.distance_squared_to(t)
				if d < best:
					best = d
					who = h
	return Vector2(_across[who].dot(p), -1.0)
