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
## Per level (Off, Low, Medium, High): tufts per square metre of rough, and
## how far from the camera the grass reaches.
const DENSITY := [0.0, 2.0, 4.0, 7.0]
const RADIUS := [0.0, 22.0, 36.0, 55.0]
## Tuft height range (m) per surface.
const HEIGHTS := {
	Surface.Type.ROUGH: Vector2(0.07, 0.15),
	Surface.Type.DEEP_ROUGH: Vector2(0.16, 0.3),
}
const BLADES := 6

var terrain: CourseTerrain
var level := 0
var _chunks := {}  ## Vector2i -> MultiMeshInstance3D (null for an empty chunk)

static var _tuft: ArrayMesh
static var _mat: ShaderMaterial


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
	var r: float = RADIUS[level]
	material().set_shader_parameter("fade_start", r * 0.6)
	material().set_shader_parameter("fade_end", r)


## Adds the nearest missing chunks around `eye` and drops far ones.
func update_around(eye: Vector3) -> void:
	material().set_shader_parameter("camera_pos", eye)
	if terrain == null or level == 0:
		return
	var r: float = RADIUS[level]
	var here := Vector2(eye.x, eye.z)
	for key: Vector2i in _chunks.keys():
		if _chunk_centre(key).distance_to(here) > r + CHUNK:
			var node: Node = _chunks[key]
			if node != null:
				node.queue_free()
			_chunks.erase(key)
	var wanted: Array[Vector2i] = []
	var reach := ceili(r / CHUNK)
	var at := Vector2i(floori(eye.x / CHUNK), floori(eye.z / CHUNK))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := at + Vector2i(dx, dz)
			if not _chunks.has(key) and _chunk_centre(key).distance_to(here) < r + CHUNK * 0.71:
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_centre(a).distance_squared_to(here) < _chunk_centre(b).distance_squared_to(here))
	for i in mini(BUILDS_PER_FRAME, wanted.size()):
		var key := wanted[i]
		var mm := build_chunk(terrain, key, DENSITY[level])
		var node: MultiMeshInstance3D = null
		if mm != null:
			node = MultiMeshInstance3D.new()
			node.multimesh = mm
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
		_chunks[key] = node


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
	var tries := roundi(CHUNK * CHUNK * density)
	var buffer := PackedFloat32Array()
	buffer.resize(tries * 16)
	var n := 0
	var origin := Vector2(key) * CHUNK
	for i in tries:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var yaw := rng.randf() * TAU
		var size := rng.randf()
		var phase := rng.randf()
		var surface := t.surface_at(x, z)
		if not HEIGHTS.has(surface):
			continue
		var hr: Vector2 = HEIGHTS[surface]
		var h := lerpf(hr.x, hr.y, size)
		var w := 0.25 + size * 0.15
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
	return mm


## The one grass material; its camera and fade uniforms are shared.
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat


static func _shared_mesh() -> ArrayMesh:
	if _tuft == null:
		_tuft = tuft_mesh()
		_tuft.surface_set_material(0, material())
	return _tuft


## One tuft in a unit box: BLADES thin, leaning blades of two triangles each,
## UV.y running from 0 at the root to 1 at the tip.
static func tuft_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2003
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for b in BLADES:
		var a := rng.randf() * TAU
		var root := Vector3(cos(a), 0.0, sin(a)) * rng.randf() * 0.3
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0.0, sin(face)) * 0.035
		var lean := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.1, 0.35)
		var tall := rng.randf_range(0.6, 1.0)
		var base := verts.size()
		verts.append_array(PackedVector3Array([root - side, root + side,
			root + lean * 0.5 + side * 0.6 + Vector3(0, tall * 0.55, 0),
			root + lean * 0.5 - side * 0.6 + Vector3(0, tall * 0.55, 0), root + lean + Vector3(0, tall, 0)]))
		uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.55 * tall),
			Vector2(0, 0.55 * tall), Vector2(0.5, tall)]))
		for k in 5:
			normals.append(Vector3.UP)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3, base + 3, base + 2, base + 4]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
