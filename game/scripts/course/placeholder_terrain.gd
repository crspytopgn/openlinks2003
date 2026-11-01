class_name PlaceholderTerrain
extends CourseTerrain
## Procedural stand-in ground for one hole: gentle undulations, a fairway
## along the hole's route, a tilted green, bunkers and ponds. Replaced by real
## course terrain once the .CRZ format is decoded.

const GRID_STEP := 2.5  ## metres between visual mesh vertices
const MARGIN := 40.0  ## ground drawn beyond the out-of-bounds line
## The first cut: rough this close to the fairway is mown a little longer
## than the fairway (its colour only; the ball plays it as rough).
const FIRST_CUT := 2.5
const FIRST_CUT_COLOR := Color(0.25, 0.43, 0.16)
## Mowing stripe strength per surface (the terrain shader draws them along
## the hole, crisp, from UV: x across the hole, -y the strength).
const STRIPES := {Surface.Type.FAIRWAY: 1.0, Surface.Type.GREEN: 0.6, Surface.Type.TEE: 0.3}
## Splat map (see the terrain shader): the surfaces rasterised every
## SPLAT_STEP metres, so their edges are drawn crisp rather than blended
## across the GRID_STEP mesh. Code FIRST_CUT_CODE is the first cut.
const SPLAT_STEP := 1.0
const FIRST_CUT_CODE := 9

## Olive, yellow-green turf as real courses have in sun (brighter, bluer
## greens read as lime under the Photoreal light).
var _colors := {
	Surface.Type.TEE: Color(0.29, 0.48, 0.19),
	Surface.Type.FAIRWAY: Color(0.29, 0.47, 0.18),
	Surface.Type.FRINGE: Color(0.27, 0.47, 0.19),
	Surface.Type.GREEN: Color(0.30, 0.52, 0.21),
	Surface.Type.ROUGH: Color(0.22, 0.38, 0.14),
	Surface.Type.DEEP_ROUGH: Color(0.19, 0.31, 0.12),
	Surface.Type.SAND: Color(0.78, 0.72, 0.55),
	Surface.Type.WATER: Color(0.12, 0.25, 0.35),
	Surface.Type.OUT_OF_BOUNDS: Color(0.13, 0.27, 0.10),
}

var tee := Vector2.ZERO
var route := PackedVector2Array()  ## tee first, green centre last
var fairway_width := 34.0
var fairway_start := 25.0  ## metres of rough in front of the tee
var green_radius := 13.0
var green_slope := Vector2.ZERO  ## rise per metre across the green
var bunkers: Array[Vector3] = []  ## x, z, radius
var ponds: Array[Vector3] = []  ## x, z, radius
var bounds := Rect2()  ## in-bounds area, x and z
var phase := Vector3.ZERO  ## varies the undulations between holes

var _tee_level := 0.0
var _green_level := 0.0
var _pond_levels: Array[float] = []
var _route_lengths: Array[float] = []


## Call after setting the layout fields.
func finalize() -> void:
	_tee_level = _base(tee.x, tee.y) + 0.3
	var g := green_center()
	_green_level = _base(g.x, g.y) + 0.5
	_pond_levels.clear()
	for p in ponds:
		_pond_levels.append(_base(p.x, p.y) - 0.6)
	_route_lengths.clear()
	var total := 0.0
	_route_lengths.append(0.0)
	for i in range(1, route.size()):
		total += route[i - 1].distance_to(route[i])
		_route_lengths.append(total)


func green_center() -> Vector2:
	return route[route.size() - 1]


## Height of the water surface of pond i.
func water_level(i: int) -> float:
	return _pond_levels[i]


func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _base(x, z)

	var d_tee := p.distance_to(tee)
	if d_tee < 10.0:
		h = lerpf(_tee_level, h, smoothstep(4.0, 10.0, d_tee))

	var g := green_center()
	var d_green := p.distance_to(g)
	if d_green < green_radius + 9.0:
		var green_h := _green_level + green_slope.dot(p - g)
		h = lerpf(green_h, h, smoothstep(green_radius, green_radius + 9.0, d_green))

	for b in bunkers:
		var d := p.distance_to(Vector2(b.x, b.y))
		if d < b.z + 1.5:
			h -= 0.7 * (1.0 - smoothstep(b.z * 0.3, b.z + 1.5, d))

	for i in ponds.size():
		var w := ponds[i]
		var d := p.distance_to(Vector2(w.x, w.y))
		if d < w.z + 7.0:
			h = lerpf(_pond_levels[i] - 1.2, h, smoothstep(w.z - 3.0, w.z + 7.0, d))
	return h


func surface_at(x: float, z: float) -> int:
	var p := Vector2(x, z)
	if not bounds.has_point(p):
		return Surface.Type.OUT_OF_BOUNDS
	for w in ponds:
		if p.distance_to(Vector2(w.x, w.y)) < w.z:
			return Surface.Type.WATER
	for b in bunkers:
		if p.distance_to(Vector2(b.x, b.y)) < b.z:
			return Surface.Type.SAND
	var d_green := p.distance_to(green_center())
	if d_green < green_radius:
		return Surface.Type.GREEN
	if d_green < green_radius + 2.0:
		return Surface.Type.FRINGE
	if absf(p.x - tee.x) < 5.0 and absf(p.y - tee.y) < 7.0:
		return Surface.Type.TEE
	var r := _route_distance(p)
	if r.x < fairway_width * 0.5 and r.y > fairway_start:
		return Surface.Type.FAIRWAY
	if r.x < fairway_width * 0.5 + 10.0:
		return Surface.Type.ROUGH
	return Surface.Type.DEEP_ROUGH


## Distance from the route centre line (x) and how far along it (y).
func route_distance(x: float, z: float) -> Vector2:
	return _route_distance(Vector2(x, z))


func build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	var ground := _build_ground_mesh()
	ground.material_override = _splat_material()
	root.add_child(ground)
	for i in ponds.size():
		var w := ponds[i]
		var water := Materials.water_disc(w.z + 4.0)
		water.position = Vector3(w.x, _pond_levels[i], w.y)
		root.add_child(water)
	if TreeFactory.enabled():
		_add_tree_line(root)
	return root


## Woods round the edge of the ground, out of bounds, so the hole is set
## among trees instead of ending in a bare edge against the sky. Visual
## only (far trees are impostors); the ball never gets there.
func _add_tree_line(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(tee.x), roundi(tee.y)))
	var trees := PackedFloat32Array()
	var ring := bounds.grow(MARGIN * 0.55)
	var corners := [ring.position, Vector2(ring.end.x, ring.position.y), ring.end, Vector2(ring.position.x, ring.end.y)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var out := (b - a).normalized().orthogonal()
		var length := a.distance_to(b)
		var at := 0.0
		while at < length:
			for row in 2:
				var p := a.lerp(b, at / length) + out * (row * 9.0 + rng.randf_range(-3.0, 3.0))
				var species := TreeFactory.Species.PINE if rng.randf() < 0.45 else TreeFactory.Species.BROADLEAF
				trees.append_array(PackedFloat32Array([p.x, height_at(p.x, p.y) - 0.2, p.y, rng.randf_range(10.0, 17.0), species]))
			at += rng.randf_range(6.0, 10.0)
	for batch: Dictionary in TreeFactory.batches(trees, 50.0):
		var node := MultiMeshInstance3D.new()
		node.name = "TreeLine"
		node.multimesh = batch.multimesh
		node.position = batch.position
		if batch.full:
			node.visibility_range_end = TreeFactory.impostor_distance() + float(batch.reach) + 5.0
		else:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)


func _build_ground_mesh() -> MeshInstance3D:
	var area := bounds.grow(MARGIN)
	var nx := int(ceil(area.size.x / GRID_STEP)) + 1
	var nz := int(ceil(area.size.y / GRID_STEP)) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var verts := PackedVector3Array()
	verts.resize(nx * nz)
	var colors := PackedColorArray()
	colors.resize(nx * nz)
	var weights := PackedVector2Array()
	weights.resize(nx * nz)
	var uvs := PackedVector2Array()
	uvs.resize(nx * nz)
	var dir := (green_center() - tee).normalized()
	var across := Vector2(-dir.y, dir.x)
	for j in nz:
		for i in nx:
			var x := area.position.x + i * GRID_STEP
			var z := area.position.y + j * GRID_STEP
			var h := height_at(x, z)
			var k := j * nx + i
			heights[k] = h
			verts[k] = Vector3(x, h, z)
			colors[k] = _color_at(x, z)
			var surface := surface_at(x, z)
			weights[k] = Materials.terrain_weights(surface)
			uvs[k] = Vector2(across.dot(Vector2(x, z)), -float(STRIPES.get(surface, 0.0)))

	var normals := PackedVector3Array()
	normals.resize(nx * nz)
	for j in nz:
		for i in nx:
			var hl := heights[j * nx + maxi(i - 1, 0)]
			var hr := heights[j * nx + mini(i + 1, nx - 1)]
			var hd := heights[maxi(j - 1, 0) * nx + i]
			var hu := heights[mini(j + 1, nz - 1) * nx + i]
			normals[j * nx + i] = Vector3(hl - hr, 2.0 * GRID_STEP, hd - hu).normalized()

	var indices := PackedInt32Array()
	indices.resize((nx - 1) * (nz - 1) * 6)
	var n := 0
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			# Clockwise seen from above, which Godot treats as front-facing.
			indices[n] = a
			indices[n + 1] = b
			indices[n + 2] = c
			indices[n + 3] = b
			indices[n + 4] = d
			indices[n + 5] = c
			n += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = weights
	# The vertex colour again, which the splat map's colour replaces.
	var palette := PackedFloat32Array()
	palette.resize(nx * nz * 4)
	for k in nx * nz:
		palette[k * 4] = colors[k].r
		palette[k * 4 + 1] = colors[k].g
		palette[k * 4 + 2] = colors[k].b
	arrays[Mesh.ARRAY_CUSTOM0] = palette
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var inst := MeshInstance3D.new()
	inst.name = "Ground"
	inst.mesh = mesh
	inst.material_override = Materials.terrain()
	return inst


## The terrain material with this hole's splat map.
func _splat_material() -> ShaderMaterial:
	var area := bounds.grow(MARGIN)
	var w := maxi(1, ceili(area.size.x / SPLAT_STEP))
	var h := maxi(1, ceili(area.size.y / SPLAT_STEP))
	var data := PackedByteArray()
	data.resize(w * h)
	for j in h:
		var z := area.position.y + (j + 0.5) * SPLAT_STEP
		for i in w:
			var x := area.position.x + (i + 0.5) * SPLAT_STEP
			data[j * w + i] = _splat_code(x, z)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_R8, data)
	var mat := Materials.terrain().duplicate() as ShaderMaterial
	var cols := PackedVector3Array()
	var wts := PackedVector2Array()
	var mown := PackedFloat32Array()
	for s in 10:
		var c: Color = FIRST_CUT_COLOR if s == FIRST_CUT_CODE else _colors[s]
		cols.append(Vector3(c.r, c.g, c.b))
		wts.append(Materials.terrain_weights(Surface.Type.ROUGH if s == FIRST_CUT_CODE else s))
		# The mesh's UV already carries the stripes along the hole.
		mown.append(0.0)
	mat.set_shader_parameter("surface_colors", cols)
	mat.set_shader_parameter("surface_weights", wts)
	mat.set_shader_parameter("surface_mown", mown)
	mat.set_shader_parameter("splat_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("splat_origin", area.position)
	mat.set_shader_parameter("splat_size", Vector2(w, h) * SPLAT_STEP)
	mat.set_shader_parameter("has_splat", true)
	return mat


func _splat_code(x: float, z: float) -> int:
	var s := surface_at(x, z)
	if s == Surface.Type.ROUGH:
		var r := _route_distance(Vector2(x, z))
		if r.x < fairway_width * 0.5 + FIRST_CUT and r.y > fairway_start:
			return FIRST_CUT_CODE
	return s


func ground_color_at(x: float, z: float) -> Color:
	return _color_at(x, z)


func _color_at(x: float, z: float) -> Color:
	var s := surface_at(x, z)
	if s == Surface.Type.ROUGH:
		var r := _route_distance(Vector2(x, z))
		if r.x < fairway_width * 0.5 + FIRST_CUT and r.y > fairway_start:
			return FIRST_CUT_COLOR
	return _colors[s]


func _base(x: float, z: float) -> float:
	return (1.8 * sin(x * 0.021 + phase.x) * cos(z * 0.017 + phase.y)
		+ 0.9 * sin((x + z) * 0.045 + phase.z)
		+ 0.35 * sin(x * 0.11 + z * 0.07 + phase.x))


func _route_distance(p: Vector2) -> Vector2:
	var best := INF
	var along := 0.0
	for i in range(1, route.size()):
		var a := route[i - 1]
		var b := route[i]
		var ab := b - a
		var len2 := ab.length_squared()
		var f := 0.0 if len2 <= 0.0 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var d := p.distance_to(a + ab * f)
		if d < best:
			best = d
			along = _route_lengths[i - 1] + sqrt(len2) * f
	return Vector2(best, along)
