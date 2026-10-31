class_name FreeGolfer
extends GolferRig
## The golfer used without the original game files: a realistic man built
## from MakeHuman's CC0 assets by tools/golfer/build_free_golfer.py, moving
## with motion capture retargeted by tools/golfer/mocap_swing.py: the
## address (with a look at the target), swing, putt, walk and reactions.
## At each new ball he walks up to it before settling over it; on the green
## he first crouches behind the ball to read the putt. GolferFeet plants his
## feet on slopes and GolferLook turns his head to follow the ball.
## PlaceholderGolferAssets falls back to PlaceholderGolfer if the file is
## missing.

const SCENE_PATH := "res://assets/golfer/free_golfer.glb"
const BLEND_TIME := 0.15
const LOOPING: Array[StringName] = [&"address", &"address_putt", &"walk"]
## The walk up to a new ball: from this far behind the address spot, at the
## mocap walk's own speed (so the feet don't slide), easing into address.
const WALK_FROM := 2.2
const WALK_SPEED := 0.89
const WALK_SETTLE := 0.35
## A move of more than this between addresses is a new ball.
const NEW_BALL := 0.5
## Where he reads a putt from: behind the ball, on the line to the hole
## (the target is -x), in the rig's frame.
const READ_SPOT := Vector3(1.6, 0.0, -0.75)

var _player: AnimationPlayer
var _driver: Array[Node3D] = []
var _putter: Array[Node3D] = []
var _putting := false
var _model: Node3D
var _walk: Tween
var _last_spot := Vector3.INF
var _look: GolferLook
var _feet: GolferFeet


## Null if the model is missing or has no animations.
static func create() -> FreeGolfer:
	if not ResourceLoader.exists(SCENE_PATH):
		return null
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate()
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		model.free()
		return null
	var golfer := FreeGolfer.new()
	golfer.add_child(model)
	golfer._model = model as Node3D
	golfer._player = player
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		golfer._feet = GolferFeet.new()
		skeletons[0].add_child(golfer._feet)
		golfer._look = GolferLook.new()
		skeletons[0].add_child(golfer._look)
	for anim_name in LOOPING:
		if player.has_animation(anim_name):
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("Driver"):
			golfer._driver.append(node)
		elif node.name.begins_with("Putter"):
			golfer._putter.append(node)
	golfer._show_putter(false)
	_matt(model)
	return golfer


## Cloth, skin and hair as matt as they are in daylight: the model's own
## materials shine like plastic under the Photoreal sun. The clubs keep
## their metal.
static func _matt(model: Node) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name.begins_with("Driver") or mi.name.begins_with("Putter") or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat == null or mat.metallic > 0.5:
				continue
			var m := mat.duplicate() as StandardMaterial3D
			m.roughness = maxf(m.roughness, 0.8)
			m.metallic_specular = minf(m.metallic_specular, 0.3)
			mi.set_surface_override_material(i, m)


func has_animation(animation: StringName) -> bool:
	return _player.has_animation(animation)


## Address in the putting stance with the putter on the green.
func set_shot(club: Club, _distance_m: float, _power: float = 1.0) -> void:
	_putting = club.is_putter


## The putter stays out after a putt, for the next address and the
## celebration, until a full swing.
func play(animation: StringName) -> void:
	_stop_walk()
	if _look:
		_look.track(null, 0.0)
	match animation:
		&"putt":
			_putting = true
		&"backswing", &"swing":
			_putting = false
	var clip := animation
	if animation == &"address" and _putting:
		clip = &"address_putt"
	_show_putter(_putting)
	if animation == &"address" and _model and is_inside_tree() and _player.has_animation(&"walk"):
		var spot := global_position
		var new_ball := _last_spot == Vector3.INF or spot.distance_to(_last_spot) > NEW_BALL
		_last_spot = spot
		if new_ball:
			_walk_in(clip)
			return
	if _player.has_animation(clip):
		_player.play(clip, BLEND_TIME)


func watch(target: Node3D, delay: float = 0.3) -> void:
	if _look:
		_look.track(target, delay)


func set_ground(height: Callable, sink: float = 0.0) -> void:
	if _feet:
		_feet.ground = height
		_feet.sink = sink


## Walks forward to the address spot, then settles into the clip. Before a
## putt he reads it first, crouched behind the ball looking down the line.
func _walk_in(clip: StringName) -> void:
	_walk = create_tween()
	var from := Vector3(0, 0, WALK_FROM)
	if clip == &"address_putt" and _player.has_animation(&"read"):
		_model.position = READ_SPOT
		_model.rotation.y = PI / 2.0  # facing the hole (-x)
		_player.play(&"read", BLEND_TIME)
		_walk.tween_interval(_player.get_animation(&"read").length - WALK_SETTLE)
		from = READ_SPOT
		var heading := -from.normalized()
		var yaw := atan2(-heading.x, -heading.z)
		_walk.tween_callback(func() -> void: _player.play(&"walk", WALK_SETTLE))
		_walk.tween_property(_model, "rotation:y", yaw, WALK_SETTLE)
	else:
		_model.position = from
		_player.play(&"walk", BLEND_TIME)
	_walk.tween_property(_model, "position", Vector3.ZERO, from.length() / WALK_SPEED)
	_walk.tween_callback(func() -> void:
		if _player.has_animation(clip):
			_player.play(clip, WALK_SETTLE))
	_walk.tween_property(_model, "rotation:y", 0.0, WALK_SETTLE)


func _stop_walk() -> void:
	if _walk and _walk.is_valid():
		_walk.kill()
	_walk = null
	if _model:
		_model.position = Vector3.ZERO
		_model.rotation.y = 0.0


func _show_putter(on: bool) -> void:
	for node in _driver:
		node.visible = not on
	for node in _putter:
		node.visible = on
