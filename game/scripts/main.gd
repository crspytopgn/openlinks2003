extends Node3D
## Prototype driving range. Press Space to hit a drive, C to view a course.
##
## The flight model here is a temporary GDScript port of
## libs/olcore/src/ball_physics.cpp so the project runs without a compiled
## extension. It will be replaced by the C++ library via GDExtension; keep the
## two in sync until then.

const MASS := 0.04593
const RADIUS := 0.021335
const AIR_DENSITY := 1.225
const DRAG_COEFFICIENT := 0.25
const GRAVITY := 9.81
const SPIN_DECAY_PER_S := 0.04
const RPM_TO_RAD_S := TAU / 60.0
const SUBSTEPS := 8

var ball: MeshInstance3D
var camera: Camera3D
var label: Label
var trail: MeshInstance3D
var trail_points: PackedVector3Array = PackedVector3Array()

var flying := false
var ball_pos := Vector3.ZERO
var ball_vel := Vector3.ZERO
var ball_spin := Vector3.ZERO
var apex := 0.0


func _ready() -> void:
	_build_world()
	_update_label("Press Space to hit a drive, C to view a course")


func _build_world() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	# Rough, then a fairway strip down the +z axis.
	_add_ground(Vector2(400, 700), Color(0.18, 0.40, 0.14), 0.0)
	_add_ground(Vector2(40, 650), Color(0.30, 0.60, 0.22), 0.01)

	ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	# Drawn 10x real size so it stays visible from the tee camera.
	sphere.radius = RADIUS * 10.0
	sphere.height = RADIUS * 20.0
	ball.mesh = sphere
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color.WHITE
	ball.material_override = ball_mat
	add_child(ball)

	trail = MeshInstance3D.new()
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.albedo_color = Color(1, 1, 0.6)
	trail.material_override = trail_mat
	add_child(trail)

	camera = Camera3D.new()
	camera.position = Vector3(0, 2.5, -8)
	camera.far = 2000.0
	add_child(camera)
	camera.look_at(Vector3(0, 1, 40))

	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(label)

	_reset_ball()


func _add_ground(size: Vector2, color: Color, height: float) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	inst.material_override = mat
	inst.position = Vector3(0, height, size.y / 2.0 - 20.0)
	add_child(inst)


func _reset_ball() -> void:
	flying = false
	ball_pos = Vector3.ZERO
	ball.position = ball_pos + Vector3(0, RADIUS * 10.0, 0)
	trail_points.clear()
	trail.mesh = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		get_tree().change_scene_to_file("res://scenes/course_viewer.tscn")
		return
	if event.is_action_pressed("swing"):
		if flying:
			return
		_reset_ball()
		# Small random variation so repeated shots differ.
		_launch(70.0, 11.0, randf_range(-2.0, 2.0), 2700.0, randf_range(-600.0, 600.0))


## Mirrors olcore::make_launch. +x is left, +y up, +z downrange.
func _launch(speed: float, launch_deg: float, azimuth_deg: float, backspin_rpm: float, sidespin_rpm: float) -> void:
	var el := deg_to_rad(launch_deg)
	var az := deg_to_rad(azimuth_deg)
	var dir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
	var horiz := Vector3(dir.x, 0, dir.z).normalized()
	var right := horiz.cross(Vector3.UP)
	ball_vel = dir * speed
	ball_spin = right * backspin_rpm * RPM_TO_RAD_S + Vector3.UP * sidespin_rpm * RPM_TO_RAD_S
	apex = 0.0
	flying = true


## Mirrors olcore::acceleration.
func _acceleration(vel: Vector3, spin: Vector3) -> Vector3:
	var a := Vector3(0, -GRAVITY, 0)
	var speed := vel.length()
	if speed < 1e-6:
		return a
	var area := PI * RADIUS * RADIUS
	var q := 0.5 * AIR_DENSITY * area * speed * speed
	a += vel * (-q * DRAG_COEFFICIENT / (MASS * speed))
	var wxv := spin.cross(vel)
	var spin_rate := spin.length()
	if wxv.length() > 1e-6 and spin_rate > 1e-6:
		var cl := clampf(-0.05 + sqrt(0.0025 + 0.36 * RADIUS * spin_rate / speed), 0.0, 0.35)
		a += wxv.normalized() * (q * cl / MASS)
	return a


func _physics_process(delta: float) -> void:
	if not flying:
		return
	var dt := delta / SUBSTEPS
	for i in SUBSTEPS:
		# Semi-implicit Euler at a fine substep; the C++ version uses RK4.
		ball_vel += _acceleration(ball_vel, ball_spin) * dt
		ball_pos += ball_vel * dt
		ball_spin *= maxf(0.0, 1.0 - SPIN_DECAY_PER_S * dt)
		apex = maxf(apex, ball_pos.y)
		if ball_pos.y <= 0.0 and ball_vel.y < 0.0:
			ball_pos.y = 0.0
			flying = false
			break

	ball.position = ball_pos + Vector3(0, RADIUS * 10.0, 0)
	trail_points.append(ball_pos)
	_draw_trail()

	var carry := Vector2(ball_pos.x, ball_pos.z).length()
	if flying:
		_update_label("Carry %.0f m   Height %.0f m" % [carry, ball_pos.y])
	else:
		_update_label("Carry %.0f m (%.0f yd)   Apex %.0f m   -  Space to hit again" % [carry, carry * 1.0936, apex])


func _draw_trail() -> void:
	if trail_points.size() < 2:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in trail_points:
		im.surface_add_vertex(p)
	im.surface_end()
	trail.mesh = im


func _update_label(text: String) -> void:
	label.text = text
