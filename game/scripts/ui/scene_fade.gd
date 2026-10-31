class_name SceneFade
extends CanvasLayer
## Smooth transitions: a fade through black between scenes (the fade lives
## on the tree's root, so it carries across the change) and a quick fade-in
## for menu panels as they open.

const OUT_S := 0.22
const IN_S := 0.35
const PANEL_S := 0.18

var _cover: ColorRect


## Fades out, switches to the scene at `path`, then fades back in.
static func change_scene(tree: SceneTree, path: String) -> void:
	if tree.root.has_node("SceneFade"):
		return  # already on the way somewhere
	var fade := SceneFade.new()
	fade.name = "SceneFade"
	tree.root.add_child(fade)
	fade._run(path)


## Fades `c` in over a moment, for a panel that has just been shown.
static func pop_in(c: CanvasItem) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, PANEL_S)


func _init() -> void:
	layer = 128
	_cover = ColorRect.new()
	_cover.color = Color(0, 0, 0, 0)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_cover)


func _run(path: String) -> void:
	var t := create_tween()
	t.tween_property(_cover, "color:a", 1.0, OUT_S)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(path))
	# Give the new scene a frame to build before revealing it.
	t.tween_interval(0.05)
	t.tween_property(_cover, "color:a", 0.0, IN_S)
	t.tween_callback(queue_free)
