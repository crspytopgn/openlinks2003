class_name Caddie
extends Node3D
## The optional caddie (Settings > Caddie, off by default): a person standing
## off to the side with the bag at each of the players' shots, and a note
## with their read of it (CaddieAdvice). Computer golfers play without one.
## The figure is the free golfer's model (CC0, see FreeGolfer) in a
## standing pose, in a tournament caddie's white overalls, so it needs no game files.

const SIDE_M := 2.7  ## from the ball, on the side away from the golfer
const AHEAD_M := 0.8
const PUTT_SIDE_M := 3.4
const PUTT_BACK_M := 1.0
const PLAN_BUDGET_MS := 3.0  ## planning per frame, to keep the web build smooth
const OVERALLS := Color(0.93, 0.93, 0.9)  ## the white boiler suit of a tournament caddie

var note: CaddieNote
var advice: CaddieAdvice
var figure: Node3D
var bag: GolfBag


func _init() -> void:
	name = "Caddie"
	bag = GolfBag.new()
	add_child(bag)
	figure = make_figure()
	if figure != null:
		add_child(figure)
	note = CaddieNote.new()
	visible = false


## Reads the shot about to be played and stands beside it. `aim_dir` is the
## flat direction the golfer faces down; `skill` the swing skill level.
func advise(model: ShotModel, clubs: Array[Club], hole: HoleData, from: Vector3, lie: int, wind: Vector3, skill: int, aim_dir: Vector3) -> void:
	_stand(hole, from, aim_dir, CaddieAdvice._is_putting_lie(lie, CaddieAdvice._flat(from, hole.pin)))
	advice = CaddieAdvice.new()
	advice.start(model, clubs, hole, from, lie, wind, skill)
	note.clear()
	_show_when_ready()


## The swing has started, or it isn't the player's shot: say nothing more.
func quiet() -> void:
	advice = null
	note.clear()


## Stands down for a computer golfer's shot.
func step_aside() -> void:
	quiet()
	visible = false


func _process(_delta: float) -> void:
	_show_when_ready()


func _show_when_ready() -> void:
	if advice == null or not note.text_empty():
		return
	if advice.step(PLAN_BUDGET_MS):
		note.say(advice.text)


func _stand(hole: HoleData, ball: Vector3, dir: Vector3, putting: bool) -> void:
	var left := Vector3.UP.cross(dir)
	var tries: Array[Vector3] = []
	if putting:
		tries.append(ball - left * PUTT_SIDE_M - dir * PUTT_BACK_M)
		tries.append(ball + left * (PUTT_SIDE_M + 0.8) - dir * PUTT_BACK_M)
	else:
		tries.append(ball - left * SIDE_M + dir * AHEAD_M)
		tries.append(ball - left * SIDE_M - dir * 1.5)
		tries.append(ball + left * (SIDE_M + 1.0) + dir * AHEAD_M)
	var spot := tries[0]
	for t in tries:
		var s := hole.terrain.surface_at(t.x, t.z)
		if s != Surface.Type.WATER and s != Surface.Type.OUT_OF_BOUNDS:
			spot = t
			break
	spot.y = hole.terrain.height_at(spot.x, spot.z)
	position = spot
	# Facing the golfer, half turned down the line.
	var look := (ball - spot)
	look.y = 0.0
	look = (look.normalized() + dir).normalized()
	if look.length_squared() < 1e-4:
		look = dir
	basis = Basis.looking_at(look, Vector3.UP)
	# The bag on their right, standing on the ground.
	var bag_at := spot + basis.x * 0.5
	bag.position = Vector3(0.5, hole.terrain.height_at(bag_at.x, bag_at.z) - spot.y, 0.0)
	visible = true


## The free golfer (FreeGolfer, a look of their own) standing at ease in white overalls, breathing and
## shifting his weight (the mocap `idle` clip, from a random point so two
## figures never move together); arms posed down if the clip is missing.
## null without the model.
static func make_figure() -> Node3D:
	var look := PlayerLook.random(hash("caddie"))
	look.outfit = "sleeves"
	look.top = OVERALLS
	look.bottom = OVERALLS
	look.cap_colour = OVERALLS
	var model: Node3D = FreeGolfer.create(look)
	if model == null:
		return null
	(model as FreeGolfer).walk_in = false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.name.begins_with("Driver") or mesh.name.begins_with("Putter") or mesh.name.begins_with("Iron"):
			mesh.visible = false
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null and player.has_animation(&"idle"):
		player.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
		# Started once the figure is in the scene.
		player.ready.connect(func() -> void:
			player.play(&"idle")
			player.seek(randf() * player.current_animation_length, true), CONNECT_ONE_SHOT)
		return model
	if player != null:
		player.stop()
		player.active = false
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		skeleton.reset_bone_poses()
		for side: String in ["l", "r"]:
			_arm_down(skeleton, side)
	return model


## Turns an arm from the model's rest pose (arms out in an A) to hang by
## the side, the elbow a little bent. Works from the bones' own positions,
## so it doesn't depend on how the model's bones are oriented.
static func _arm_down(skeleton: Skeleton3D, side: String) -> void:
	var upper := skeleton.find_bone("upperarm_" + side)
	var lower := skeleton.find_bone("lowerarm_" + side)
	var hand := skeleton.find_bone("hand_" + side)
	if upper < 0 or lower < 0 or hand < 0:
		return
	var out := signf(skeleton.get_bone_global_pose(lower).origin.x - skeleton.get_bone_global_pose(upper).origin.x)
	if out == 0.0:
		out = 1.0
	_point(skeleton, upper, lower, Vector3(0.17 * out, -1.0, 0.02))
	_point(skeleton, lower, hand, Vector3(0.03 * out, -1.0, -0.15))


## Turns `bone` so that its child `child` lies along `want` from it.
static func _point(skeleton: Skeleton3D, bone: int, child: int, want: Vector3) -> void:
	var g := skeleton.get_bone_global_pose(bone)
	var along := skeleton.get_bone_global_pose(child).origin - g.origin
	if along.length_squared() < 1e-8:
		return
	var turn := Basis(Quaternion(along.normalized(), want.normalized()))
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := parent_basis.inverse() * (turn * g.basis)
	skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
