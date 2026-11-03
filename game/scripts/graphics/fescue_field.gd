class_name FescueField
extends Node3D
## Tall fescue on the course's deep rough, out to a long way from the
## camera. Out of play a course lets its slopes grow long: fine grey-green
## grass 40 to 75 cm tall, some of it straw, with pale seed heads above. Without it the
## built-in course's hills read as green felt from the tee (most of a hole's
## ground is deep rough). Each tuft is three crossed cards from the fescue
## atlas (FreeAssets "fescue.png", tools/grass/fescue_atlas.py), in 32 m
## chunks built a couple per frame as the camera moves, like GrassField's
## near tufts, which it takes over from past about 20 m so a ball in the
## rough near the camera is never hidden. Visual only. Off without the atlas
## or with the Grass setting off; reach and density follow that setting.

const SHADER := preload("res://shaders/fescue.gdshader")
const CHUNK := 32.0
const BUILDS_PER_FRAME := 2
## Per Grass level (Off, Low, Medium, High): tufts per square metre of deep
## rough, and how far out they grow.
const DENSITY := [0.0, 0.4, 0.6, 0.8]
const RADIUS := [0.0, 90.0, 140.0, 180.0]
const SURFACES := [Surface.Type.DEEP_ROUGH]
## The ground normal's x and z, times this and the tuft's height, are the
## card's up axis x and z (see build_chunk and shaders/fescue.gdshader).
const NORMAL_LEAN := 0.01
## A far tuft's brightness against a near one's (shaders/fescue.gdshader
## far_gain), per renderer.
const FAR_GAIN_COMPAT := 1.2
const FAR_GAIN_FORWARD_PLUS := 0.7

var terrain: CourseTerrain
var level := 0
var _chunks := {}  ## Vector2i -> MultiMeshInstance3D (null for an empty chunk)

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial


func _init() -> void:
	name = "Fescue"


## True when the fescue atlas is there to draw with.
static func available() -> bool:
	return FreeAssets.tree_texture("fescue.png") != null


func setup(t: CourseTerrain, grass_level: int) -> void:
	terrain = t
	level = clampi(grass_level, 0, DENSITY.size() - 1) if available() else 0
	for node in _chunks.values():
		if node != null:
			node.queue_free()
	_chunks.clear()
	var r: float = RADIUS[level]
	material().set_shader_parameter("far_start", r * 0.7)
	material().set_shader_parameter("far_end", r)


func update_around(eye: Vector3) -> void:
	if terrain == null or level == 0:
		return
	material().set_shader_parameter("camera_pos", eye)
	var r: float = RADIUS[level]
	var here := Vector2(eye.x, eye.z)
	for key: Vector2i in _chunks.keys():
		if _centre(key).distance_to(here) > r + CHUNK:
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
			if not _chunks.has(key) and _centre(key).distance_to(here) < r + CHUNK * 0.71:
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _centre(a).distance_squared_to(here) < _centre(b).distance_squared_to(here))
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


func chunk_count() -> int:
	return _chunks.size()


static func _centre(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK


## The tufts of one chunk, or null with no deep rough in it. Deterministic.
static func build_chunk(t: CourseTerrain, key: Vector2i, density: float) -> MultiMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 77
	var tries := roundi(CHUNK * CHUNK * density)
	var buffer := PackedFloat32Array()
	buffer.resize(tries * 16)
	var n := 0
	var origin := Vector2(key) * CHUNK
	for i in tries:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var yaw := rng.randf() * TAU
		var h := rng.randf_range(0.4, 0.75)
		var w := h * rng.randf_range(1.0, 1.3)
		var pick := rng.randf()
		if not SURFACES.has(t.surface_at(x, z)):
			continue
		var c := t.ground_color_at(x, z)
		# The ground's slope rides along in the card's up axis as a tiny
		# lean (NORMAL_LEAN of the height, under a centimetre), so the
		# shader can light the tuft as the ground under it is lit.
		var up := t.normal_at(x, z)
		var o := n * 16
		var cs := cos(yaw)
		var sn := sin(yaw)
		buffer[o] = cs * w
		buffer[o + 1] = 0.0
		buffer[o + 2] = sn * w
		buffer[o + 3] = x
		buffer[o + 4] = up.x * NORMAL_LEAN * h
		buffer[o + 5] = h
		buffer[o + 6] = up.z * NORMAL_LEAN * h
		buffer[o + 7] = t.height_at(x, z) - 0.03
		buffer[o + 8] = -sn * w
		buffer[o + 9] = 0.0
		buffer[o + 10] = cs * w
		buffer[o + 11] = z
		buffer[o + 12] = c.r
		buffer[o + 13] = c.g
		buffer[o + 14] = c.b
		buffer[o + 15] = pick
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
	mm.set_meta("buffer", buffer)
	return mm


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("atlas", FreeAssets.tree_texture("fescue.png"))
		# Compatibility has no sky fill: lift the cards as GrassField does.
		_mat.set_shader_parameter("brightness", 1.0 if GraphicsSettings.is_forward_plus() else 1.25)
		# Far tufts against their own near brightness, so a distant bank
		# matches the sunlit ground beside it (tuned on hole 2's hillside).
		_mat.set_shader_parameter("far_gain", FAR_GAIN_FORWARD_PLUS if GraphicsSettings.is_forward_plus() else FAR_GAIN_COMPAT)
	return _mat


static func _shared_mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = tuft_mesh()
		_mesh.surface_set_material(0, material())
	return _mesh


## Three cards 1 m wide and 1 m tall crossed at 60 degrees, standing on
## the origin; UV (0, 0) at the top left, as the atlas cells.
static func tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := float(k) / 3.0 * PI
		var side := Vector3(cos(a), 0.0, sin(a)) * 0.5
		var corners := [[-side, Vector2(0, 1)], [side, Vector2(1, 1)], [side + Vector3.UP, Vector2(1, 0)], [-side + Vector3.UP, Vector2(0, 0)]]
		for i: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(corners[i][1])
			st.add_vertex(corners[i][0])
	return st.commit()
