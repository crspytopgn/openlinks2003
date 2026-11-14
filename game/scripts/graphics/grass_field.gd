class_name GrassField
extends Node3D
## Real 3D grass in the rough, only near the camera: tufts of blades in
## 12 m chunks, built a couple of chunks per frame as the camera moves and
## dropped when it moves away. Tufts take the ground's colour under them
## (CourseTerrain.ground_color_at), bend in the wind and shrink away at the
## edge of the radius. Purely visual: the ball and the physics never see it.
## Density and radius come from the Grass setting (GraphicsSettings.grass).

const SHADER := preload("res://shaders/grass.gdshader")
const CHUNK := 12.0
const BUILDS_PER_FRAME := 2
## Per level (Off, Low, Medium, High): tufts per square metre of rough
## near the camera, and how far from the camera the grass reaches. Chunks
## further out than NEAR of the reach (where the tufts are sinking into
## the ground and only a few pixels tall) grow FAR_SHARE as many, so the
## near rough can be a dense fur, as in real rough and in 2K25, for about
## the triangles the old even scatter cost.
const DENSITY := [0.0, 4.0, 8.0, 13.0]
const RADIUS := [0.0, 22.0, 36.0, 55.0]
const NEAR := 0.45
const FAR_SHARE := 0.25
## Tuft height range (m) per surface: real first cut is mown at about
## 4 cm, rough at 6 to 10 cm, and the deep rough is left longer.
const HEIGHTS := {
	Surface.Type.ROUGH: Vector2(0.06, 0.11),
	Surface.Type.DEEP_ROUGH: Vector2(0.12, 0.22),
}
const FIRST_CUT_HEIGHT := Vector2(0.035, 0.05)
const BLADES := 12
## Mown turf (tee, fairway, fringe) up close: a fine fur of short blades
## over the photo texture, only a few metres round the camera, where the
## texture alone reads as a flat print. Per level: tufts per square metre
## and the radius (m). Small chunks, as the radius is small.
const MOWN_DENSITY := [0.0, 0.0, 130.0, 220.0]
const MOWN_RADIUS := [0.0, 0.0, 3.5, 5.0]
const MOWN_CHUNK := 3.0
const MOWN_BUILDS_PER_FRAME := 2
## Blade heights (m) as cut: tees and fairways at about 12 to 15 mm, the
## fringe a little longer. Leaning blades stand a bit lower than that.
const MOWN_HEIGHTS := {
	Surface.Type.TEE: Vector2(0.012, 0.02),
	Surface.Type.FAIRWAY: Vector2(0.014, 0.024),
	Surface.Type.FRINGE: Vector2(0.018, 0.028),
}
const MOWN_BLADES := 10
const MOWN_FOOTPRINT := 0.2

var terrain: CourseTerrain
var level := 0
var _chunks := {}  ## Vector2i -> MultiMeshInstance3D (null for an empty chunk)
var _far := {}  ## Vector2i -> true for a chunk built at the far density
var _mown := {}  ## Vector2i (MOWN_CHUNK grid) -> MultiMeshInstance3D or null

static var _tuft: ArrayMesh
static var _mat: ShaderMaterial
static var _mown_tuft: ArrayMesh
static var _mown_mat: ShaderMaterial


func _init() -> void:
	name = "Grass"


## Starts over on a new terrain or grass level.
func setup(t: CourseTerrain, grass_level: int) -> void:
	terrain = t
	level = clampi(grass_level, 0, DENSITY.size() - 1)
	for node in _chunks.values():
		if node != null:
			node.queue_free()
	_chunks.clear()
	_far.clear()
	for node in _mown.values():
		if node != null:
			node.queue_free()
	_mown.clear()
	var mr: float = MOWN_RADIUS[level]
	if mr > 0.0:
		mown_material().set_shader_parameter("fade_start", mr * 0.45)
		mown_material().set_shader_parameter("fade_end", mr)
	var r: float = RADIUS[level]
	# Tufts sink into the ground from a third of the way out: a few pixels
	# across, they read as dark clumps (clover) rather than rough.
	material().set_shader_parameter("fade_start", r * 0.35)
	material().set_shader_parameter("fade_end", r)


## Adds the nearest missing chunks around `eye` and drops far ones.
func update_around(eye: Vector3) -> void:
	material().set_shader_parameter("camera_pos", eye)
	mown_material().set_shader_parameter("camera_pos", eye)
	if terrain == null or level == 0:
		return
	_update_mown(eye)
	var r: float = RADIUS[level]
	var here := Vector2(eye.x, eye.z)
	for key: Vector2i in _chunks.keys():
		if _chunk_centre(key).distance_to(here) > r + CHUNK:
			var node: Node = _chunks[key]
			if node != null:
				node.queue_free()
			_chunks.erase(key)
			_far.erase(key)
	var wanted: Array[Vector2i] = []
	var reach := ceili(r / CHUNK)
	var at := Vector2i(floori(eye.x / CHUNK), floori(eye.z / CHUNK))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := at + Vector2i(dx, dz)
			var d := _chunk_centre(key).distance_to(here)
			if d >= r + CHUNK * 0.71:
				continue
			# Missing, or built at the other density for where it now is.
			if not _chunks.has(key) or _far.has(key) != _is_far(d, r):
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_centre(a).distance_squared_to(here) < _chunk_centre(b).distance_squared_to(here))
	for i in mini(BUILDS_PER_FRAME, wanted.size()):
		var key := wanted[i]
		var far := _is_far(_chunk_centre(key).distance_to(here), r)
		var mm := build_chunk(terrain, key, DENSITY[level] * (FAR_SHARE if far else 1.0))
		var node: MultiMeshInstance3D = null
		if mm != null:
			node = MultiMeshInstance3D.new()
			node.multimesh = mm
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
		var old: Node = _chunks.get(key)
		if old != null:
			old.queue_free()
		_chunks[key] = node
		if far:
			_far[key] = true
		else:
			_far.erase(key)


## The mown fur's chunks: the nearest missing ones in, far ones out.
func _update_mown(eye: Vector3) -> void:
	var r: float = MOWN_RADIUS[level]
	if r <= 0.0:
		return
	var here := Vector2(eye.x, eye.z)
	# High over the ground (flyover, aerial cameras) the fur is sub-pixel.
	var near_ground := eye.y - terrain.height_at(eye.x, eye.z) < r
	for key: Vector2i in _mown.keys():
		if not near_ground or _mown_centre(key).distance_to(here) > r + MOWN_CHUNK:
			var node: Node = _mown[key]
			if node != null:
				node.queue_free()
			_mown.erase(key)
	if not near_ground:
		return
	var wanted: Array[Vector2i] = []
	var reach := ceili(r / MOWN_CHUNK)
	var at := Vector2i(floori(eye.x / MOWN_CHUNK), floori(eye.z / MOWN_CHUNK))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := at + Vector2i(dx, dz)
			if not _mown.has(key) and _mown_centre(key).distance_to(here) < r + MOWN_CHUNK * 0.71:
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _mown_centre(a).distance_squared_to(here) < _mown_centre(b).distance_squared_to(here))
	for i in mini(MOWN_BUILDS_PER_FRAME, wanted.size()):
		var mm := build_mown_chunk(terrain, wanted[i], MOWN_DENSITY[level])
		var node: MultiMeshInstance3D = null
		if mm != null:
			node = MultiMeshInstance3D.new()
			node.multimesh = mm
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
		_mown[wanted[i]] = node


static func _mown_centre(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * MOWN_CHUNK


## Number of mown-fur chunks built so far, empty ones included.
func mown_chunk_count() -> int:
	return _mown.size()


## The mown fur of one MOWN_CHUNK cell, or null where there's no tee,
## fairway or fringe. Deterministic, like build_chunk.
static func build_mown_chunk(t: CourseTerrain, key: Vector2i, density: float) -> MultiMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x6d6f776e
	var side := maxi(1, roundi(MOWN_CHUNK * sqrt(density)))
	var cell := MOWN_CHUNK / side
	var buffer := PackedFloat32Array()
	buffer.resize(side * side * 16)
	var n := 0
	var origin := Vector2(key) * MOWN_CHUNK
	for i in side * side:
		var x := origin.x + (i % side + rng.randf()) * cell
		var z := origin.y + (floorf(float(i) / side) + rng.randf()) * cell
		var yaw := rng.randf() * TAU
		var size := rng.randf()
		var phase := rng.randf()
		var surface := t.surface_at(x, z)
		if not MOWN_HEIGHTS.has(surface):
			continue
		var hr: Vector2 = MOWN_HEIGHTS[surface]
		var h := lerpf(hr.x, hr.y, size)
		var w := MOWN_FOOTPRINT
		var c := t.ground_color_at(x, z)
		var o := n * 16
		var cs := cos(yaw)
		var sn := sin(yaw)
		buffer[o] = cs * w
		buffer[o + 1] = 0.0
		buffer[o + 2] = sn * w
		buffer[o + 3] = x
		buffer[o + 4] = 0.0
		buffer[o + 5] = h
		buffer[o + 6] = 0.0
		buffer[o + 7] = t.height_at(x, z) - 0.003
		buffer[o + 8] = -sn * w
		buffer[o + 9] = 0.0
		buffer[o + 10] = cs * w
		buffer[o + 11] = z
		buffer[o + 12] = c.r
		buffer[o + 13] = c.g
		buffer[o + 14] = c.b
		buffer[o + 15] = phase
		n += 1
	if n == 0:
		return null
	buffer.resize(n * 16)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	if _mown_tuft == null:
		_mown_tuft = mown_tuft_mesh()
		_mown_tuft.surface_set_material(0, mown_material())
	mm.mesh = _mown_tuft
	mm.instance_count = n
	mm.buffer = buffer
	mm.set_meta("buffer", buffer)
	return mm


## The mown fur's material: the rough's, with its own fade radius.
static func mown_material() -> ShaderMaterial:
	if _mown_mat == null:
		_mown_mat = material().duplicate() as ShaderMaterial
		# Every blade keeps its own shade: the fur is only a few metres
		# deep, so there is no far band to melt into the turf.
		_mown_mat.set_shader_parameter("blend_amount", 0.0)
		# Lit flat like the turf under them: tilted Forward+ normals and
		# lifted tips read as pale straws scattered on the tee.
		_mown_mat.set_shader_parameter("blade_relief", 0.0)
		_mown_mat.set_shader_parameter("tip_light", 1.08 if GraphicsSettings.is_forward_plus() else 1.25)
	return _mown_mat


## One mown tuft in a unit box: MOWN_BLADES single-triangle blades, upright
## with a slight lean (a fresh cut stands up), UV and UV2 as tuft_mesh.
static func mown_tuft_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1503
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var blades := PackedVector2Array()
	for b in MOWN_BLADES:
		var a := rng.randf() * TAU
		var root := Vector3(cos(a), 0.0, sin(a)) * sqrt(rng.randf()) * 0.45
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0.0, sin(face)) * rng.randf_range(0.009, 0.013)
		var lean := Vector3(cos(a + 1.3), 0.0, sin(a + 1.3)) * rng.randf_range(0.0, 0.08)
		var tall := rng.randf_range(0.6, 1.0)
		var blade := Vector2(rng.randf(), rng.randf() * 0.15)
		verts.append_array(PackedVector3Array([root - side, root + side, root + lean + Vector3(0, tall, 0)]))
		uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.5, tall)]))
		for k in 3:
			normals.append(Vector3.UP)
			blades.append(blade)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = blades
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## True when a chunk `d` metres out grows at the far density.
static func _is_far(d: float, reach: float) -> bool:
	# The chunk's nearest corner is up to 0.71 CHUNK closer than its centre.
	return d - CHUNK * 0.71 > reach * NEAR


## Number of chunks built so far, empty ones included.
func chunk_count() -> int:
	return _chunks.size()


static func _chunk_centre(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK


## The tufts of one chunk, or null when it has no rough. Deterministic: the
## same chunk always grows the same grass.
static func build_chunk(t: CourseTerrain, key: Vector2i, density: float) -> MultiMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	# One tuft in each cell of a grid, jittered: an even sward, where
	# purely random places leave clumps and bare patches.
	var side := maxi(1, roundi(CHUNK * sqrt(density)))
	var cell := CHUNK / side
	var tries := side * side
	var buffer := PackedFloat32Array()
	buffer.resize(tries * 16)
	var n := 0
	var origin := Vector2(key) * CHUNK
	for i in tries:
		var x := origin.x + (i % side + rng.randf()) * cell
		var z := origin.y + (floorf(float(i) / side) + rng.randf()) * cell
		var yaw := rng.randf() * TAU
		var size := rng.randf()
		var phase := rng.randf()
		var surface := t.surface_at(x, z)
		if not HEIGHTS.has(surface):
			continue
		var hr: Vector2 = FIRST_CUT_HEIGHT if surface == Surface.Type.ROUGH and t.first_cut_at(x, z) else HEIGHTS[surface]
		var h := lerpf(hr.x, hr.y, size)
		var w := 0.3 + size * 0.2
		var c := t.ground_color_at(x, z)
		var o := n * 16
		var cs := cos(yaw)
		var sn := sin(yaw)
		# Row-major 3x4: yaw about y, width w across, height h up.
		buffer[o] = cs * w
		buffer[o + 1] = 0.0
		buffer[o + 2] = sn * w
		buffer[o + 3] = x
		buffer[o + 4] = 0.0
		buffer[o + 5] = h
		buffer[o + 6] = 0.0
		buffer[o + 7] = t.height_at(x, z) - 0.01
		buffer[o + 8] = -sn * w
		buffer[o + 9] = 0.0
		buffer[o + 10] = cs * w
		buffer[o + 11] = z
		buffer[o + 12] = c.r
		buffer[o + 13] = c.g
		buffer[o + 14] = c.b
		buffer[o + 15] = phase
		n += 1
	if n == 0:
		return null
	buffer.resize(n * 16)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _shared_mesh()
	mm.instance_count = n
	mm.buffer = buffer
	# The headless renderer keeps no MultiMesh data, so tests read this.
	mm.set_meta("buffer", buffer)
	return mm


## The one grass material; its camera and fade uniforms are shared.
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		# Compatibility has no sky fill light, so the blades' sides get less
		# light than the photo ground beside them; lift them to match. Under
		# the Photoreal fill of PR #155 anything less left the rough from the
		# tee as dark clumps on lighter ground (like clover).
		_mat.set_shader_parameter("brightness", 1.0 if GraphicsSettings.is_forward_plus() else 2.0)
		var fwd := GraphicsSettings.is_forward_plus()
		_mat.set_shader_parameter("blend_amount", 0.35 if fwd else 1.0)
		_mat.set_shader_parameter("blade_relief", 0.7 if fwd else 0.0)
		# The lift over-saturates: real tee turf measures about Lab
		# 56/-16/31, the lifted blades took the tee to 51/-17/40.
		_mat.set_shader_parameter("saturation", 1.0 if fwd else 0.8)
	return _mat


static func _shared_mesh() -> ArrayMesh:
	if _tuft == null:
		_tuft = tuft_mesh()
		_tuft.surface_set_material(0, material())
	return _tuft


## One tuft in a unit box: BLADES thin, leaning blades of three triangles
## each, UV.y running from 0 at the root to 1 at the tip. UV2 per blade:
## x its shade, y how dry it is (straw), so a tuft isn't one flat colour.
static func tuft_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2003
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var blades := PackedVector2Array()
	var indices := PackedInt32Array()
	for b in BLADES:
		var a := rng.randf() * TAU
		# Spread over the whole footprint (sqrt: even, not bunched at the
		# middle), so neighbouring tufts knit into one sward.
		var root := Vector3(cos(a), 0.0, sin(a)) * sqrt(rng.randf()) * 0.45
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0.0, sin(face)) * rng.randf_range(0.014, 0.022)
		var lean := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.05, 0.35)
		var tall := rng.randf_range(0.5, 1.0)
		var dry := 1.0 if rng.randf() < 0.1 else rng.randf() * 0.25
		var blade := Vector2(rng.randf(), dry)
		var base := verts.size()
		verts.append_array(PackedVector3Array([root - side, root + side,
			root + lean * 0.5 + side * 0.6 + Vector3(0, tall * 0.55, 0),
			root + lean * 0.5 - side * 0.6 + Vector3(0, tall * 0.55, 0), root + lean + Vector3(0, tall, 0)]))
		uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.55 * tall),
			Vector2(0, 0.55 * tall), Vector2(0.5, tall)]))
		for k in 5:
			normals.append(Vector3.UP)
			blades.append(blade)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3, base + 3, base + 2, base + 4]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = blades
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
