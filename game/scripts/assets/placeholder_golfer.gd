class_name PlaceholderGolfer
extends GolferRig
## The fallback golfer when neither the original game files nor the free
## model (FreeGolfer) are there: a low-poly figure in a polo shirt, slacks and
## cap, built from primitives, with a hand-keyed swing.
##
## The swing is driven by a few numbers: the hands travel round a circle in
## the swing plane (the plane through the swing centre and the ball line),
## the wrists hinge the club further round, the shoulders turn about the
## tilted spine and the spine bends sideways. Both arms reach the grip with
## two-bone IK. Everything is original to this project.

const SPINE_TILT := deg_to_rad(30.0)  ## forward bend at address
const SPINE_BASE := Vector3(0, 1.0, 0.02)
const SHOULDER := Vector3(0.2, 0.47, 0)  ## right shoulder in the torso frame
const SWING_CENTRE := Vector3(0, 1.35, -0.2)
const BALL := Vector3(0, 0, -0.75)  ## GolferRig puts the ball here
const CLUB_LENGTH := 1.0  ## left hand to club head
const RIGHT_HAND_ON_GRIP := 0.08  ## right hand sits this far down the grip
const UPPER_ARM := 0.31
const LOWER_ARM := 0.34  ## forearm and hand, to the middle of the grip
const BACKSWING_TIME := 0.9

## Swing state; the tweens animate these (degrees).
var swing_angle := 0.0  ## hands round the swing circle, + away from the target
var hinge := 0.0  ## club angle past the hands
var turn := 0.0  ## shoulder turn about the spine, - away from the target
var side_bend := 10.0  ## right shoulder lowered
var cheer := 0.0  ## 0..1, raises the right fist

var _torso: Node3D
var _head: Node3D
var _hips: Node3D
var _arms: Array[MeshInstance3D] = []  ## left upper, left lower, right upper, right lower
var _hands: Array[MeshInstance3D] = []
var _shaft: MeshInstance3D
var _club_head: MeshInstance3D
var _putter_head: MeshInstance3D
var _putting := false
var _tween: Tween


func _init() -> void:
	var shirt := _material(Color(0.12, 0.25, 0.5))
	var pants := _material(Color(0.78, 0.72, 0.58))
	var skin := _material(Color(0.87, 0.67, 0.52))
	var white := _material(Color(0.95, 0.95, 0.95))
	var dark := _material(Color(0.15, 0.15, 0.17))
	var steel := _material(Color(0.7, 0.72, 0.75))
	steel.metallic = 0.8
	steel.roughness = 0.3

	# Legs stay put: a slight knee flex, feet a little wider than the hips.
	for side in [-1.0, 1.0]:
		var hip := Vector3(0.1 * side, 0.95, 0.03)
		var knee := Vector3(0.15 * side, 0.52, -0.07)
		var ankle := Vector3(0.2 * side, 0.09, 0.0)
		add_child(_segment(_capsule(0.075, hip.distance_to(knee), pants), hip, knee))
		add_child(_segment(_capsule(0.06, knee.distance_to(ankle), pants), knee, ankle))
		var shoe := MeshInstance3D.new()
		shoe.mesh = _box(Vector3(0.1, 0.07, 0.27), white)
		shoe.position = ankle + Vector3(0.01 * side, -0.05, -0.06)
		shoe.rotation.y = -0.15 * side
		add_child(shoe)

	_hips = Node3D.new()
	_hips.position = Vector3(0, 0.97, 0.02)
	add_child(_hips)
	var pelvis := MeshInstance3D.new()
	pelvis.mesh = _capsule(0.12, 0.36, pants)
	pelvis.rotation.z = PI / 2
	_hips.add_child(pelvis)
	var belt := MeshInstance3D.new()
	belt.mesh = _cylinder(0.135, 0.04, dark)
	belt.position.y = 0.07
	belt.scale = Vector3(1.25, 1, 0.9)
	_hips.add_child(belt)

	_torso = Node3D.new()
	_torso.position = SPINE_BASE
	add_child(_torso)
	var chest := MeshInstance3D.new()
	chest.mesh = _capsule(0.16, 0.58, shirt)
	chest.position.y = 0.27
	chest.scale = Vector3(1.25, 1, 0.85)
	_torso.add_child(chest)
	var collar := MeshInstance3D.new()
	collar.mesh = _cylinder(0.065, 0.05, white)
	collar.position.y = 0.54
	_torso.add_child(collar)
	for side in [-1.0, 1.0]:
		var shoulder := MeshInstance3D.new()
		shoulder.mesh = _sphere(0.075, shirt)
		shoulder.position = Vector3(SHOULDER.x * side, SHOULDER.y, 0)
		_torso.add_child(shoulder)

	_head = Node3D.new()
	_head.position = Vector3(0, 0.58, 0)
	_torso.add_child(_head)
	var neck := MeshInstance3D.new()
	neck.mesh = _cylinder(0.05, 0.1, skin)
	neck.position.y = 0.03
	_head.add_child(neck)
	var face := MeshInstance3D.new()
	face.mesh = _sphere(0.105, skin)
	face.position.y = 0.15
	face.scale = Vector3(0.9, 1.05, 1)
	_head.add_child(face)
	var nose := MeshInstance3D.new()
	nose.mesh = _sphere(0.022, skin)
	nose.position = Vector3(0, 0.14, -0.1)
	_head.add_child(nose)
	var cap := MeshInstance3D.new()
	cap.mesh = _sphere(0.11, white)
	cap.position.y = 0.19
	cap.scale = Vector3(1, 0.65, 1)
	_head.add_child(cap)
	var brim := MeshInstance3D.new()
	brim.mesh = _box(Vector3(0.17, 0.012, 0.11), white)
	brim.position = Vector3(0, 0.19, -0.13)
	brim.rotation.x = 0.15
	_head.add_child(brim)

	for i in 4:
		var upper := i % 2 == 0
		var arm := _capsule(0.05 if upper else 0.04, UPPER_ARM if upper else LOWER_ARM - 0.05, shirt if upper else skin)
		var instance := MeshInstance3D.new()
		instance.mesh = arm
		add_child(instance)
		_arms.append(instance)
	for i in 2:
		var hand := MeshInstance3D.new()
		hand.mesh = _sphere(0.045, white if i == 0 else skin)  # a glove on the left hand
		add_child(hand)
		_hands.append(hand)

	_shaft = MeshInstance3D.new()
	_shaft.mesh = _cylinder(0.008, CLUB_LENGTH, steel)
	add_child(_shaft)
	_club_head = MeshInstance3D.new()
	_club_head.mesh = _box(Vector3(0.12, 0.05, 0.09), dark)
	add_child(_club_head)
	_putter_head = MeshInstance3D.new()
	_putter_head.mesh = _box(Vector3(0.11, 0.03, 0.03), steel)
	_putter_head.visible = false
	add_child(_putter_head)
	_update_pose()


func play(animation: StringName) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_putting = animation == &"putt" or (_putting and animation == &"celebrate")
	_club_head.visible = not _putting
	_putter_head.visible = _putting
	match animation:
		&"address":
			_pose_to(0, 0, 0, 10, 0.25)
			_tween.tween_property(self, "cheer", 0.0, 0.25)
		&"backswing":
			_pose_to(150, 90, -90, 0, BACKSWING_TIME, Tween.EASE_OUT)
		&"swing":
			_tween.set_parallel(false)
			_tween.tween_method(_set_pose, _pose(), Vector4(0, 0, 20, 14), 0.2).set_ease(Tween.EASE_IN) \
					.set_trans(Tween.TRANS_QUAD)
			_tween.tween_method(_set_pose, Vector4(0, 0, 20, 14), Vector4(-150, -80, 100, 5), 0.45) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		&"putt":
			_tween.set_parallel(false)
			_tween.tween_method(_set_pose, _pose(), Vector4(16, 0, -6, 10), 0.5).set_trans(Tween.TRANS_SINE)
			_tween.tween_method(_set_pose, Vector4(16, 0, -6, 10), Vector4(-20, 0, 6, 10), 0.3) \
					.set_trans(Tween.TRANS_SINE)
		&"celebrate":
			_tween.set_parallel(false)
			_tween.tween_property(self, "cheer", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(self, "cheer", 0.7, 0.2)
			_tween.tween_property(self, "cheer", 1.0, 0.2)


func _pose() -> Vector4:
	return Vector4(swing_angle, hinge, turn, side_bend)


func _set_pose(p: Vector4) -> void:
	swing_angle = p.x
	hinge = p.y
	turn = p.z
	side_bend = p.w


func _pose_to(angle: float, wrist: float, shoulders: float, bend: float, time: float,
		easing: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
	_tween.tween_method(_set_pose, _pose(), Vector4(angle, wrist, shoulders, bend), time).set_ease(easing) \
			.set_trans(Tween.TRANS_SINE)


func _process(_delta: float) -> void:
	_update_pose()


func _update_pose() -> void:
	var spine := Vector3(0, cos(SPINE_TILT), -sin(SPINE_TILT))
	var torso_basis := Basis(spine, deg_to_rad(turn)) * Basis(Vector3.BACK, deg_to_rad(-side_bend)) \
			* Basis(Vector3.RIGHT, -SPINE_TILT)
	_torso.basis = torso_basis
	_hips.rotation.y = deg_to_rad(turn) * 0.45
	# The head stays on the ball through impact, then follows the shot.
	_head.rotation.y = deg_to_rad(-turn) * (0.75 if turn < 0.0 else 0.35)

	var down := (BALL - SWING_CENTRE).normalized()
	var radius := SWING_CENTRE.distance_to(BALL) - CLUB_LENGTH
	var t := deg_to_rad(swing_angle)
	var grip := SWING_CENTRE + radius * (cos(t) * down + sin(t) * Vector3.RIGHT)
	var c := deg_to_rad(swing_angle + hinge)
	var along := cos(c) * down + sin(c) * Vector3.RIGHT
	var head := grip + along * CLUB_LENGTH

	var left_shoulder := SPINE_BASE + torso_basis * Vector3(-SHOULDER.x, SHOULDER.y, SHOULDER.z)
	var right_shoulder := SPINE_BASE + torso_basis * SHOULDER
	var right_grip := grip + along * RIGHT_HAND_ON_GRIP
	var fist := right_shoulder + Vector3(0.1, 0.55, -0.05)
	right_grip = right_grip.lerp(fist, cheer)
	_place_arm(0, left_shoulder, grip, Vector3(-0.3, -1, 0.4))
	_place_arm(2, right_shoulder, right_grip, Vector3(0.5, -1, 0.3))

	_place(_shaft, _cylinder_axis(grip, head), grip.lerp(head, 0.5))
	var face_basis := _basis_along(along)
	_club_head.transform = Transform3D(face_basis, head + face_basis.x * 0.03)
	_putter_head.transform = Transform3D(face_basis, head + face_basis.x * 0.02)


## Two-bone IK from the shoulder to the hand target; the elbow bends towards
## `pole`. Out-of-reach targets leave the arm straight towards them.
func _place_arm(i: int, shoulder: Vector3, target: Vector3, pole: Vector3) -> void:
	var to := target - shoulder
	var dist := clampf(to.length(), 0.05, UPPER_ARM + LOWER_ARM - 0.001)
	var dir := to.normalized()
	var cos_a := (UPPER_ARM * UPPER_ARM + dist * dist - LOWER_ARM * LOWER_ARM) / (2.0 * UPPER_ARM * dist)
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * UPPER_ARM * cos_a + bend * UPPER_ARM * sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var hand := shoulder + dir * dist
	var wrist := elbow + (hand - elbow).normalized() * (LOWER_ARM - 0.05)
	_place(_arms[i], _cylinder_axis(shoulder, elbow), shoulder.lerp(elbow, 0.5))
	_place(_arms[i + 1], _cylinder_axis(elbow, wrist), elbow.lerp(wrist, 0.5))
	_hands[0 if i == 0 else 1].position = hand


func _place(node: MeshInstance3D, basis: Basis, at: Vector3) -> void:
	node.transform = Transform3D(basis, at)


## A basis whose y axis runs from a to b.
func _cylinder_axis(a: Vector3, b: Vector3) -> Basis:
	return _basis_along((b - a).normalized())


func _basis_along(y: Vector3) -> Basis:
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


func _segment(mesh: Mesh, a: Vector3, b: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = Transform3D(_cylinder_axis(a, b), a.lerp(b, 0.5))
	return node


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m


func _capsule(radius: float, length: float, mat: Material) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = length + 2.0 * radius
	m.radial_segments = 12
	m.rings = 4
	m.material = mat
	return m


func _cylinder(radius: float, height: float, mat: Material) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 12
	m.material = mat
	return m


func _sphere(radius: float, mat: Material) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 12
	m.rings = 6
	m.material = mat
	return m


func _box(size: Vector3, mat: Material) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	return m
