class_name RangeDressing
extends Node3D
## What makes the practice ground's range look like one, from photos of real
## club and tour ranges: hitting stations along the grass tee line, each with
## a pyramid of balls and a pair of plastic tee-line markers; a rope on
## stakes behind; old divots along the line; range balls lying out on the
## field; and at each target a flag and a yardage board facing the tee.
## Everything to real scale; all the balls are one MultiMesh draw. Visual
## only: the ball plays the terrain.

const BALL_RADIUS := 0.02135  ## 42.67 mm
const STATION_GAP := 3.2  ## metres between hitting stations
const STATIONS := 11  ## each side of the player's
## A pyramid of 55 balls: layers of 5 x 5, 4 x 4 ... 1, as tour ranges stack them.
const PYRAMID_LAYERS := 5
## Where it sits from the ball: on the golfer's side, a little ahead.
const PYRAMID_SPOT := Vector3(0.55, 0.0, 0.45)
const FIELD_BALLS_BY_QUALITY: Array[int] = [150, 400, 800, 1200]
const FLAGSTICK_M := 2.13
const BOARD_SIZE := Vector2(1.5, 0.9)
const BOARD_HEIGHT := 0.55  ## bottom edge above the ground
const ROPE_BEHIND := 3.6  ## metres behind the tee line's front
const STAKE_GAP := 4.0
const STAKE_HEIGHT := 0.75

var _white := StandardMaterial3D.new()
var _post := StandardMaterial3D.new()
var _ink := Color(0.06, 0.07, 0.06)
var _marker_mesh: Mesh
var _marker_mat: StandardMaterial3D


func _init() -> void:
	name = "RangeDressing"
	_white.albedo_color = Color(0.93, 0.93, 0.9)
	_white.roughness = 0.6
	_post.albedo_color = Color(0.32, 0.24, 0.16)
	_post.roughness = 0.9


## Dresses `hole` (PracticeGround.make_range) at `quality`
## (GraphicsSettings.Quality); the player hits from `ball` and leaves its
## station's pyramid out of the way of the swing.
static func build(hole: HoleData, quality: int, ball: Vector3) -> RangeDressing:
	var d := RangeDressing.new()
	var t := hole.terrain
	var balls := PackedVector3Array()
	for s in range(-STATIONS, STATIONS + 1):
		var x := ball.x + s * STATION_GAP
		var spot := Vector3(x, 0.0, ball.z) + PYRAMID_SPOT
		d._pyramid(t, spot, balls)
		d._markers(t, Vector3(x - STATION_GAP * 0.5, 0.0, ball.z + 1.6))
	d._field_balls(t, FIELD_BALLS_BY_QUALITY[clampi(quality, 0, FIELD_BALLS_BY_QUALITY.size() - 1)], balls)
	d._balls(balls)
	d._rope(t, ball)
	for i in PracticeGround.TARGETS.size():
		var target: Array = PracticeGround.TARGETS[i]
		var p := PracticeGround.target_position(t, i)
		d._flag(p, target[3])
		d._board(t, p, ball, PracticeGround.target_radius(i), int(target[0]))
	return d


## Old divots along the tee line where others have been hitting, as on any
## real range by mid-morning (CourseMarks; a few for each station).
static func add_divots(marks: CourseMarks, terrain: CourseTerrain, ball: Vector3, club: Club) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2003
	for s in range(-4, 5):
		if s == 0:
			continue
		for k in 3:
			var at := Vector3(ball.x + s * STATION_GAP + rng.randf_range(-0.3, 0.3), 0.0, ball.z - k * 0.25 + rng.randf_range(-0.1, 0.1))
			at.y = terrain.height_at(at.x, at.z)
			marks.add_divot(terrain, at, Vector3(rng.randf_range(-0.08, 0.08), 0, 1).normalized(), club, Surface.Type.TEE)


## A ball pyramid centred on `spot` (x, z).
func _pyramid(t: CourseTerrain, spot: Vector3, out: PackedVector3Array) -> void:
	var d := BALL_RADIUS * 2.0
	var ground := t.height_at(spot.x, spot.z)
	for layer in PYRAMID_LAYERS:
		var n := PYRAMID_LAYERS - layer
		var y := ground + BALL_RADIUS + layer * d * 0.7071
		for i in n:
			for j in n:
				out.append(Vector3(spot.x + (i - (n - 1) * 0.5) * d, y, spot.z + (j - (n - 1) * 0.5) * d))


## Balls lying out on the field, thickest where most shots land (100 to 200
## yards), thinning out to the back; none on the tee line.
func _field_balls(t: CourseTerrain, count: int, out: PackedVector3Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var half := PracticeGround.FIELD_WIDTH * 0.5 - 6.0
	for _i in count:
		var z := clampf(rng.randfn(150.0, 55.0), 25.0, 270.0)
		var x := clampf(rng.randfn(0.0, half * 0.45), -half, half)
		out.append(Vector3(x, t.height_at(x, z) + BALL_RADIUS * 0.8, z))


func _balls(at: PackedVector3Array) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, Transform3D(Basis(), at[i]))
	var node := MultiMeshInstance3D.new()
	node.name = "RangeBalls"
	node.multimesh = mm
	node.material_override = _white
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## A tee-line marker between stations: the course's dome tee marker
## (tools/props/build_props.py) in range blue, as clubs set them out in a row
## along the front of the teeing ground.
func _markers(t: CourseTerrain, at: Vector3) -> void:
	if _marker_mesh == null:
		_marker_mesh = CourseProps.mesh("tee_marker")
		var base: StandardMaterial3D = null
		if _marker_mesh != null:
			base = _marker_mesh.surface_get_material(0) as StandardMaterial3D
		else:
			var s := SphereMesh.new()
			s.radius = 0.0635
			s.height = 0.127
			_marker_mesh = s
		_marker_mat = base.duplicate() as StandardMaterial3D if base != null else StandardMaterial3D.new()
		_marker_mat.albedo_color = Color(0.08, 0.26, 0.6)
	var m := MeshInstance3D.new()
	m.mesh = _marker_mesh
	m.material_override = _marker_mat
	m.position = at + Vector3(0, t.height_at(at.x, at.z) - 0.005, 0)
	add_child(m)


## A white rope on wooden stakes behind the stations, keeping people from
## walking behind a swing.
func _rope(t: CourseTerrain, ball: Vector3) -> void:
	var z := ball.z - ROPE_BEHIND
	var x0 := ball.x - (STATIONS + 0.5) * STATION_GAP
	var x1 := ball.x + (STATIONS + 0.5) * STATION_GAP
	var x := x0
	var prev := Vector3.INF
	while x <= x1 + 0.01:
		var top := Vector3(x, t.height_at(x, z) + STAKE_HEIGHT, z)
		var stake := MeshInstance3D.new()
		var post := CylinderMesh.new()
		post.top_radius = 0.022
		post.bottom_radius = 0.025
		post.height = STAKE_HEIGHT
		post.radial_segments = 6
		stake.mesh = post
		stake.material_override = _post
		stake.position = top - Vector3(0, STAKE_HEIGHT * 0.5, 0)
		add_child(stake)
		if prev != Vector3.INF:
			_rope_span(prev, top)
		prev = top
		x += STAKE_GAP


func _rope_span(a: Vector3, b: Vector3) -> void:
	var rope := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.006
	cyl.bottom_radius = 0.006
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 4
	cyl.rings = 1
	rope.mesh = cyl
	rope.material_override = _white
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Along the span (the cylinder's y), sagging 3 cm in the middle.
	var along := (b - a).normalized()
	var across := Vector3.UP.cross(along).normalized()
	rope.basis = Basis(across, along, across.cross(along))
	rope.position = (a + b) * 0.5 - Vector3(0, 0.03, 0)
	add_child(rope)


## A target's flagstick with its coloured flag flying in the wind.
func _flag(p: Vector3, colour: Color) -> void:
	var pole := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.0095
	rod.bottom_radius = 0.0095
	rod.height = FLAGSTICK_M
	rod.radial_segments = 8
	pole.mesh = rod
	pole.material_override = _white
	pole.position = p + Vector3(0, FLAGSTICK_M * 0.5, 0)
	add_child(pole)
	var flag := MeshInstance3D.new()
	var cloth := PlaneMesh.new()
	cloth.orientation = PlaneMesh.FACE_Z
	cloth.size = Vector2(0.51, 0.36)
	cloth.subdivide_width = 12
	cloth.subdivide_depth = 4
	flag.mesh = cloth
	flag.position = p + Vector3(0, FLAGSTICK_M - 0.02, 0)
	flag.extra_cull_margin = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/flag.gdshader")
	mat.set_shader_parameter("albedo", colour)
	flag.material_override = mat
	add_child(flag)


## The yardage board behind target `p`: white, on two posts, the yards in
## big black figures, facing the tee line.
func _board(t: CourseTerrain, p: Vector3, ball: Vector3, radius: float, yards: int) -> void:
	var to_tee := Vector3(ball.x - p.x, 0.0, ball.z - p.z).normalized()
	var at := p - to_tee * (radius + 3.0)
	at.y = t.height_at(at.x, at.z)
	var board := Node3D.new()
	board.name = "Yardage%d" % yards
	board.position = at
	board.rotation.y = atan2(to_tee.x, to_tee.z)  # its face (+z) to the tee
	add_child(board)
	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, BOARD_HEIGHT + BOARD_SIZE.y, 0.09)
		post.mesh = box
		post.material_override = _post
		post.position = Vector3(side * BOARD_SIZE.x * 0.38, (BOARD_HEIGHT + BOARD_SIZE.y) * 0.5, -0.06)
		board.add_child(post)
	var panel := MeshInstance3D.new()
	var face := BoxMesh.new()
	face.size = Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.03)
	panel.mesh = face
	panel.material_override = _white
	panel.position = Vector3(0, BOARD_HEIGHT + BOARD_SIZE.y * 0.5, 0)
	board.add_child(panel)
	var label := Label3D.new()
	label.text = str(yards)
	label.font_size = 160
	label.pixel_size = 0.004
	label.outline_size = 0
	label.modulate = _ink
	label.shaded = true
	label.double_sided = false
	label.position = Vector3(0, BOARD_HEIGHT + BOARD_SIZE.y * 0.5, 0.017)
	board.add_child(label)
