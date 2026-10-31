class_name FreeGolfer
extends GolferRig
## The golfer used without the original game files: a realistic man built
## from MakeHuman's CC0 assets, with a hand-keyed swing, putt and celebration
## baked into the glTF by tools/golfer/build_free_golfer.py. The swing and
## putt are then replaced with motion capture by tools/golfer/mocap_swing.py.
## PlaceholderGolferAssets falls back to PlaceholderGolfer if the file is
## missing.

const SCENE_PATH := "res://assets/golfer/free_golfer.glb"
const BLEND_TIME := 0.15
const LOOPING: Array[StringName] = [&"address", &"address_putt"]

var _player: AnimationPlayer
var _driver: Array[Node3D] = []
var _putter: Array[Node3D] = []
var _putting := false


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
	golfer._player = player
	for anim_name in LOOPING:
		if player.has_animation(anim_name):
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("Driver"):
			golfer._driver.append(node)
		elif node.name.begins_with("Putter"):
			golfer._putter.append(node)
	golfer._show_putter(false)
	return golfer


func has_animation(animation: StringName) -> bool:
	return _player.has_animation(animation)


## Address in the putting stance with the putter on the green.
func set_shot(club: Club, _distance_m: float, _power: float = 1.0) -> void:
	_putting = club.is_putter


## The putter stays out after a putt, for the next address and the
## celebration, until a full swing.
func play(animation: StringName) -> void:
	match animation:
		&"putt":
			_putting = true
		&"backswing", &"swing":
			_putting = false
	var clip := animation
	if animation == &"address" and _putting:
		clip = &"address_putt"
	_show_putter(_putting)
	if _player.has_animation(clip):
		_player.play(clip, BLEND_TIME)


func _show_putter(on: bool) -> void:
	for node in _driver:
		node.visible = not on
	for node in _putter:
		node.visible = on
