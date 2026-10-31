class_name CourseLife
extends Node3D
## Life over the course: now and then a small flock of birds crosses the
## sky, high and far off, as in any TV shot of a real course. Looks only.
##
## One MultiMesh per flock (a few dark wing silhouettes flapping in the
## shader), so a flock is a single draw call.

const MIN_GAP_S := 25.0  ## seconds between flocks, at least
const MAX_GAP_S := 70.0
const SPEED := 11.0  ## m/s, a loose flock of starlings or gulls
const MIN_HEIGHT := 30.0
const MAX_HEIGHT := 70.0
const CROSS_DIST := 600.0  ## metres a flock flies before it's gone
const WING := 0.35  ## half-span, metres

var _rng := RandomNumberGenerator.new()
var _wait := 8.0
var _flocks: Array[Dictionary] = []
static var _mesh: ArrayMesh
static var _material: ShaderMaterial


func _init() -> void:
	name = "CourseLife"
	_rng.randomize()


## The flock's path: it enters `CROSS_DIST/2` from `centre` on one side and
## flies straight across, at a height between MIN and MAX.
static func flock_path(centre: Vector3, heading_deg: float, height: float) -> Array:
	var dir := Vector3(sin(deg_to_rad(heading_deg)), 0.0, cos(deg_to_rad(heading_deg)))
	var start := centre - dir * CROSS_DIST * 0.5 + Vector3.UP * height
	return [start, dir]


## Offsets of `count` birds in a loose V, metres from the leader.
static func formation(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		var rank := (i + 1) / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		out.append(Vector3(side * rank * 2.2 + rng.randf_range(-0.8, 0.8),
			rng.randf_range(-1.0, 1.0), -rank * 2.0 + rng.randf_range(-0.8, 0.8)))
	return out


func flock_count() -> int:
	return _flocks.size()


## Starts a flock now, crossing near `centre` (the camera's view).
func spawn(centre: Vector3) -> void:
	var count := _rng.randi_range(3, 9)
	var path := flock_path(centre + Vector3(_rng.randf_range(-150, 150), 0, _rng.randf_range(-150, 150)),
		_rng.randf_range(0.0, 360.0), _rng.randf_range(MIN_HEIGHT, MAX_HEIGHT))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _wing_mesh()
	mm.instance_count = count
	var offsets := formation(count, _rng)
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _bird_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 30.0
	add_child(node)
	var dir: Vector3 = path[1]
	node.basis = Basis.looking_at(-dir, Vector3.UP)  # the birds face +z, so +z goes along dir
	for i in count:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, offsets[i]))
		mm.set_instance_custom_data(i, Color(_rng.randf(), 0, 0, 0))
	node.position = path[0]
	_flocks.append({"node": node, "dir": dir, "flown": 0.0})


## Moves the flocks on and starts new ones; `centre` is where the camera is.
func step(delta: float, centre: Vector3) -> void:
	for f in _flocks.duplicate():
		var node: Node3D = f.node
		node.position += (f.dir as Vector3) * SPEED * delta
		f.flown += SPEED * delta
		if f.flown > CROSS_DIST:
			node.queue_free()
			_flocks.erase(f)
	_wait -= delta
	if _wait <= 0.0:
		_wait = _rng.randf_range(MIN_GAP_S, MAX_GAP_S)
		spawn(centre)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		step(delta, cam.global_position)


## A bird seen from below: two swept-back wing triangles and a body.
static func _wing_mesh() -> ArrayMesh:
	if _mesh == null:
		var v := PackedVector3Array([
			Vector3(0, 0, 0.12), Vector3(-WING, 0, -0.10), Vector3(0, 0, -0.08),
			Vector3(0, 0, 0.12), Vector3(0, 0, -0.08), Vector3(WING, 0, -0.10),
			Vector3(0, 0, 0.18), Vector3(-0.03, 0, -0.18), Vector3(0.03, 0, -0.18),
		])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh


static func _bird_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/bird.gdshader")
	return _material
