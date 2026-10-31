class_name GolferPreview
extends SubViewportContainer
## A small lit stage showing one golfer (FreeGolfer) for the player
## creator: drag to turn them round, switch between the whole body at
## address and a close-up of the face, or watch a swing. show_look()
## restyles the golfer; changes made while dragging a slider are applied at
## most every RESTYLE_SECONDS.

const RESTYLE_SECONDS := 0.06
const BODY_VIEW := {"distance": 3.4, "height": 0.95, "fov": 38.0}
const FACE_VIEW := {"distance": 0.95, "height": 1.58, "fov": 30.0}

var golfer: FreeGolfer
var face_view := false
var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D
var _yaw := 200.0
var _look: PlayerLook
var _dirty := false
var _since := 0.0
var _swinging := false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.75)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.86)
	sky_mat.ground_horizon_color = Color(0.45, 0.55, 0.42)
	sky_mat.ground_bottom_color = Color(0.2, 0.3, 0.18)
	sky.sky_material = sky_mat
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 12.0
	_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -150, 0)
	fill.light_energy = 0.3
	_viewport.add_child(fill)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.2
	disc.height = 0.02
	disc.radial_segments = 48
	ground.mesh = disc
	ground.position.y = -0.01
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.22, 0.42, 0.18)
	grass.roughness = 1.0
	ground.material_override = grass
	_viewport.add_child(ground)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_place_camera()


## Shows `look` (restyling the golfer, or making them the first time).
## Returns false if the golfer model is missing.
func show_look(look: PlayerLook) -> bool:
	_look = look
	if golfer == null:
		golfer = FreeGolfer.create(look)
		if golfer == null:
			return false
		golfer.walk_in = false
		_pivot.add_child(golfer)
		_pose()
		return true
	_dirty = true
	return true


func set_face_view(on: bool) -> void:
	face_view = on
	_place_camera()
	_pose()


## Plays a full swing, then back to address.
func swing() -> void:
	if golfer == null:
		return
	face_view = false
	_place_camera()
	_swinging = true
	golfer.play(&"backswing")
	await get_tree().create_timer(0.95).timeout
	if golfer == null:
		return
	golfer.play(&"swing")
	await get_tree().create_timer(2.2).timeout
	_swinging = false
	_pose()


func _pose() -> void:
	if golfer == null or _swinging:
		return
	var player := golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if face_view:
		# Standing straight, looking ahead.
		player.stop()
		for skeleton in golfer.find_children("*", "Skeleton3D", true, false):
			(skeleton as Skeleton3D).reset_bone_poses()
	else:
		golfer.play(&"address")


func _process(delta: float) -> void:
	_since += delta
	if _dirty and _since >= RESTYLE_SECONDS and golfer != null:
		_dirty = false
		_since = 0.0
		golfer.apply_look(_look)
		_pose()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_yaw -= (event as InputEventMouseMotion).relative.x * 0.5
		_place_camera()
	elif event is InputEventScreenDrag:
		_yaw -= (event as InputEventScreenDrag).relative.x * 0.5
		_place_camera()


func _place_camera() -> void:
	if _camera == null:
		return
	var v: Dictionary = FACE_VIEW if face_view else BODY_VIEW
	var height: float = v.height
	if face_view and golfer != null and _look != null:
		height *= _look.height_cm / 175.0
	var yaw := deg_to_rad(_yaw)
	var target := Vector3(0, height, 0)
	_camera.fov = v.fov
	_camera.position = target + Vector3(sin(yaw), 0.08 if face_view else 0.25, cos(yaw)) * float(v.distance)
	_camera.look_at(target, Vector3.UP)
