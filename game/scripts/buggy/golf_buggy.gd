class_name GolfBuggy
extends Node3D
## The optional golf buggy (Settings > Golf buggy, off by default): a
## two-seat electric cart in glossy white with a canopy, tinted windscreen
## and a bag on the back. The detailed model is golf_cart.glb, our own
## (CC0), built by tools/buggy/build_golf_cart.py; without it a simple one
## is built from boxes here. It sits on the ground
## on all four wheels, pitching and rolling with the slopes; the body leans
## on its springs as it brakes, accelerates and corners (a damped spring
## per axis, about 1.3 Hz); the wheels turn and steer. BuggyDrive does the
## driving; the round moves the camera.

const MODEL_PATH := "res://assets/buggy/golf_cart.glb"
const WHEELS := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
## Real dimensions (a Club Car Precedent; see tools/buggy/build_golf_cart.py).
const WHEEL_RADIUS := 0.2286  ## 18 in tyres
const TRACK_FRONT := 0.445  ## half the 0.89 m front track
const TRACK_REAR := 0.49  ## half the 0.98 m rear track
const TRACK := 0.4675  ## half the track, on average, where the cart sits on the ground
const AXLE := 0.8175  ## half the 1.635 m wheelbase
const CHASE_BACK := 7.5
const CHASE_UP := 3.0
const CHASE_LOOK_AHEAD := 8.0
const SPRING := 70.0  ## body roll and pitch: stiffness, 1/s^2
const DAMPING := 9.0  ## and damping, 1/s
const PITCH_PER_ACCEL := 0.012  ## radians of squat or dive per m/s^2
const ROLL_PER_ACCEL := 0.016  ## radians of lean per m/s^2 of cornering
const BODY_PIVOT := 0.3  ## the body leans about this height

static var _body_mesh: ArrayMesh
static var _wheel_mesh: ArrayMesh

var drive := BuggyDrive.new()
var _wheels: Array[Node3D] = []
var _wheel_base: Array[Basis] = []  ## each wheel's own turn (the left ones face out)
var _chassis := Node3D.new()  ## the body and bag, on the springs
var _pitch := 0.0
var _pitch_rate := 0.0
var _roll := 0.0
var _roll_rate := 0.0
var _spin := 0.0
var _chase_pos := Vector3.INF
var _chase_look := Vector3.ZERO


func _init() -> void:
	name = "GolfBuggy"
	add_child(_chassis)
	_chassis.position.y = BODY_PIVOT
	if not _use_model():
		var body := MeshInstance3D.new()
		body.mesh = body_mesh()
		body.position.y = -BODY_PIVOT
		_chassis.add_child(body)
		# Front is -z, as for any node that looks_at().
		for corner: Vector2 in [Vector2(-TRACK_FRONT, -AXLE), Vector2(TRACK_FRONT, -AXLE), Vector2(-TRACK_REAR, AXLE), Vector2(TRACK_REAR, AXLE)]:
			var w := MeshInstance3D.new()
			w.mesh = wheel_mesh()
			w.position = Vector3(corner.x, WHEEL_RADIUS, corner.y)
			add_child(w)
			_wheels.append(w)
			_wheel_base.append(Basis.IDENTITY)
	var bag := GolfBag.new()
	bag.position = Vector3(0.0, 0.72 - BODY_PIVOT, 1.0)
	bag.rotation = Vector3(deg_to_rad(-12.0), PI, 0.0)
	_chassis.add_child(bag)


## Puts the cart at `p` facing `heading_deg` (0 is +z), stopped.
func park(p: Vector3, heading_deg: float, terrain: CourseTerrain) -> void:
	drive.place(p, heading_deg, terrain)
	_pitch = 0.0
	_pitch_rate = 0.0
	_roll = 0.0
	_roll_rate = 0.0
	_chassis.basis = Basis.IDENTITY
	fit(terrain)
	_chase_pos = Vector3.INF


func step(dt: float, throttle: float, steer: float, terrain: CourseTerrain) -> void:
	drive.step(dt, throttle, steer, terrain)
	_spin += drive.speed * dt / WHEEL_RADIUS
	_springs(dt)
	fit(terrain)


## The body on its springs: squats under acceleration, dives under braking
## and leans out of corners.
func _springs(dt: float) -> void:
	var h := minf(dt, 0.05)
	var want_pitch := drive.accel_long * PITCH_PER_ACCEL
	var want_roll := -drive.accel_lat * ROLL_PER_ACCEL
	_pitch_rate += (SPRING * (want_pitch - _pitch) - DAMPING * _pitch_rate) * h
	_pitch += _pitch_rate * h
	_roll_rate += (SPRING * (want_roll - _roll) - DAMPING * _roll_rate) * h
	_roll += _roll_rate * h
	# Nose up (+x rotation lifts -z) under acceleration; lean right (-z
	# rotation) when turning left, as the weight pushes out.
	_chassis.basis = Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _roll)


## Sits the cart on the ground under its four wheels.
func fit(terrain: CourseTerrain) -> void:
	var fwd := drive.forward()
	var left := Vector3.UP.cross(fwd)
	var c := drive.position
	var front := _ground(terrain, c + fwd * AXLE)
	var back := _ground(terrain, c - fwd * AXLE)
	var l := _ground(terrain, c + left * TRACK)
	var r := _ground(terrain, c - left * TRACK)
	var f := front - back
	var right := r - l
	var up := right.cross(f).normalized()
	if up.y < 0.5:
		up = Vector3.UP
	var z := -f.normalized()
	var x := up.cross(z).normalized()
	z = x.cross(up).normalized()
	transform = Transform3D(Basis(x, up, z), Vector3(c.x, (front.y + back.y + l.y + r.y) * 0.25, c.z))
	var steer_angle := deg_to_rad(BuggyDrive.MAX_STEER_DEG) * drive.steer
	for i in _wheels.size():
		var yaw := steer_angle if i < 2 else 0.0
		var spin := -_spin if _wheel_base[i].x.x > 0.0 else _spin  # the turned-round wheels spin the other way in their own frame
		_wheels[i].basis = Basis(Vector3.UP, yaw) * _wheel_base[i] * Basis(Vector3.RIGHT, spin)


## Builds from the detailed model: its body on the springs, its wheels on
## the ground. False without the file (or with a broken one).
func _use_model() -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	var body := model.find_child("Body", true, false) as Node3D
	var wheels: Array[Node3D] = []
	for wheel_name: String in WHEELS:
		var w := model.find_child(wheel_name, true, false) as Node3D
		if w != null:
			wheels.append(w)
	if body == null or wheels.size() != 4:
		model.free()
		return false
	body.get_parent().remove_child(body)
	body.position.y = -BODY_PIVOT
	_chassis.add_child(body)
	for w in wheels:
		var t := w.transform
		w.get_parent().remove_child(w)
		add_child(w)
		w.transform = t
		_wheels.append(w)
		_wheel_base.append(t.basis)
	model.free()
	for node in body.find_children("*", "MeshInstance3D", true, false) + [body]:
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return true


## Follows the cart from behind and above; returns [position, look at].
func chase(dt: float, terrain: CourseTerrain) -> Array:
	var fwd := drive.forward()
	if drive.speed < -0.5:
		fwd = -fwd  # look where it's going when backing up
	var want := drive.position - fwd * CHASE_BACK + Vector3.UP * CHASE_UP
	want.y = maxf(want.y, terrain.height_at(want.x, want.z) + 1.5)
	var look := drive.position + fwd * CHASE_LOOK_AHEAD + Vector3.UP
	if _chase_pos == Vector3.INF:
		_chase_pos = want
		_chase_look = look
	var k := 1.0 - exp(-dt * 4.0)
	_chase_pos = _chase_pos.lerp(want, k)
	_chase_look = _chase_look.lerp(look, k)
	return [_chase_pos, _chase_look]


func _ground(terrain: CourseTerrain, p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.z), p.z)


# --- The model -----------------------------------------------------------------

static func body_mesh() -> ArrayMesh:
	if _body_mesh != null:
		return _body_mesh
	var paint := _tool()
	var trim := _tool()
	var seat := _tool()
	var metal := _tool()
	var glass := _tool()
	var light := _tool()
	# Chassis and body: front is -z.
	_box(trim, Vector3(1.12, 0.12, 2.2), Vector3(0, 0.3, 0))
	_box(paint, Vector3(1.16, 0.32, 0.62), Vector3(0, 0.55, -0.86))  # front cowl
	_box(paint, Vector3(1.1, 0.22, 0.4), Vector3(0, 0.78, -0.7), Basis(Vector3.RIGHT, deg_to_rad(-18.0)))  # dash slope
	_box(paint, Vector3(1.16, 0.42, 0.95), Vector3(0, 0.56, 0.35))  # seat base
	_box(paint, Vector3(1.18, 0.08, 0.38), Vector3(0, 0.5, 0.95))  # rear deck
	for side: float in [-1.0, 1.0]:
		_box(paint, Vector3(0.04, 0.12, 0.62), Vector3(0.6 * side, 0.52, -0.82))  # wheel arch lips
		_box(trim, Vector3(0.12, 0.05, 0.5), Vector3(0.6 * side, 0.36, -0.2))  # step
	_box(trim, Vector3(1.2, 0.1, 0.08), Vector3(0, 0.42, -1.17))  # bumper
	_box(trim, Vector3(1.2, 0.1, 0.08), Vector3(0, 0.38, 1.16))
	# Bench seat and backrest.
	_box(seat, Vector3(1.04, 0.13, 0.5), Vector3(0, 0.83, 0.32))
	_box(seat, Vector3(1.04, 0.4, 0.1), Vector3(0, 1.1, 0.6), Basis(Vector3.RIGHT, deg_to_rad(-10.0)))
	# Canopy on four posts, and the windscreen.
	_box(paint, Vector3(1.2, 0.05, 1.75), Vector3(0, 1.92, 0.08))
	for x: float in [-0.52, 0.52]:
		_post(metal, Vector3(x, 0.8, -0.62), Vector3(x, 1.9, -0.6))
		_post(metal, Vector3(x, 0.98, 0.66), Vector3(x, 1.9, 0.72))
	_box(glass, Vector3(1.04, 0.95, 0.012), Vector3(0, 1.4, -0.62), Basis(Vector3.RIGHT, deg_to_rad(4.0)))
	# Steering column and wheel.
	_post(trim, Vector3(-0.27, 0.8, -0.55), Vector3(-0.27, 1.12, -0.32))
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.15
	wheel.outer_radius = 0.18
	wheel.rings = 16
	wheel.ring_segments = 6
	trim.append_from(wheel, 0, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(55.0)), Vector3(-0.27, 1.13, -0.3)))
	# Headlights.
	for x: float in [-0.38, 0.38]:
		var lamp := SphereMesh.new()
		lamp.radius = 0.06
		lamp.height = 0.06
		lamp.is_hemisphere = true
		lamp.radial_segments = 10
		lamp.rings = 4
		light.append_from(lamp, 0, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3(x, 0.6, -1.17)))
	# Bag rack.
	_box(metal, Vector3(0.5, 0.04, 0.04), Vector3(0, 1.05, 1.08))
	var paint_mat := _material(Color(0.93, 0.93, 0.91), 0.22, 0.0)
	paint_mat.clearcoat_enabled = true
	paint_mat.clearcoat = 0.6
	var glass_mat := _material(Color(0.55, 0.62, 0.66, 0.28), 0.05, 0.2)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var light_mat := _material(Color(1.0, 0.98, 0.9), 0.1, 0.0)
	light_mat.emission_enabled = true
	light_mat.emission = Color(1.0, 0.95, 0.8)
	light_mat.emission_energy_multiplier = 0.6
	_body_mesh = _commit([paint, trim, seat, metal, glass, light], [
		paint_mat, _material(Color(0.06, 0.06, 0.065), 0.55, 0.0), _material(Color(0.42, 0.3, 0.2), 0.6, 0.0),
		_material(Color(0.8, 0.8, 0.82), 0.25, 0.9), glass_mat, light_mat])
	return _body_mesh


static func wheel_mesh() -> ArrayMesh:
	if _wheel_mesh != null:
		return _wheel_mesh
	var rubber := _tool()
	var hub := _tool()
	var tyre := CylinderMesh.new()
	tyre.top_radius = WHEEL_RADIUS
	tyre.bottom_radius = WHEEL_RADIUS
	tyre.height = 0.2
	tyre.radial_segments = 20
	var on_side := Basis(Vector3.FORWARD, deg_to_rad(90.0))
	rubber.append_from(tyre, 0, Transform3D(on_side, Vector3.ZERO))
	var cap := CylinderMesh.new()
	cap.top_radius = WHEEL_RADIUS * 0.6
	cap.bottom_radius = WHEEL_RADIUS * 0.6
	cap.height = 0.21
	cap.radial_segments = 12
	hub.append_from(cap, 0, Transform3D(on_side, Vector3.ZERO))
	# A spoke, so the wheels can be seen turning.
	_box(hub, Vector3(0.215, 0.05, WHEEL_RADIUS * 1.6), Vector3.ZERO)
	_wheel_mesh = _commit([rubber, hub], [_material(Color(0.05, 0.05, 0.05), 0.85, 0.0), _material(Color(0.75, 0.75, 0.77), 0.3, 0.8)])
	return _wheel_mesh


static func _tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _box(st: SurfaceTool, size: Vector3, at: Vector3, b := Basis.IDENTITY) -> void:
	var box := BoxMesh.new()
	box.size = size
	st.append_from(box, 0, Transform3D(b, at))


## A thin tube from `a` to `b`.
static func _post(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var tube := CylinderMesh.new()
	tube.top_radius = 0.022
	tube.bottom_radius = 0.022
	tube.height = a.distance_to(b)
	tube.radial_segments = 8
	var up := (b - a).normalized()
	var turn := Basis(Quaternion(Vector3.UP, up))
	st.append_from(tube, 0, Transform3D(turn, (a + b) * 0.5))


static func _commit(tools: Array, mats: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i in tools.size():
		(tools[i] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[i])
	return mesh


static func _material(c: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	m.metallic = metallic
	return m
