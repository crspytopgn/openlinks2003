class_name CourseDesigner
extends Node3D
## The course designer: sculpt the ground, paint fairways, greens, bunkers,
## ponds and rough, plant trees and lay out holes, then play the course.
## Works the same in the browser and on desktop; courses are saved under
## user://courses/ and can be exported and imported as `.olc` files. See
## docs/course-designer.md.

const MENU_SCENE := "res://scenes/boot.tscn"
const ROUND_SCENE := "res://scenes/main.tscn"
const UNDO_LIMIT := 30
const PICK_PIXELS := 12.0
const TEE_COLORS := [Color(0.25, 0.45, 1.0), Color(1, 1, 1), Color(1.0, 0.3, 0.25)]
const LINE_COLORS := {
	Surface.Type.TEE: Color(0.6, 1.0, 0.6),
	Surface.Type.FAIRWAY: Color(0.55, 0.95, 0.35),
	Surface.Type.FRINGE: Color(0.7, 1.0, 0.5),
	Surface.Type.GREEN: Color(0.4, 1.0, 0.8),
	Surface.Type.ROUGH: Color(0.35, 0.65, 0.25),
	Surface.Type.DEEP_ROUGH: Color(0.3, 0.5, 0.2),
	Surface.Type.SAND: Color(1.0, 0.9, 0.55),
	Surface.Type.WATER: Color(0.4, 0.7, 1.0),
	Surface.Type.OUT_OF_BOUNDS: Color(1.0, 1.0, 1.0),
}

## The course the designer opens with (the last one saved or played).
static var last_path := ""

var course: DesignedCourse
var terrain: DesignedTerrain
var path := ""  ## where the course was last saved; empty if never
var hole_index := -1
var selected := -1  ## selected shape

var camera: DesignerCamera
var scenery: Scenery
var panel: DesignerPanel
var files: DesignerFiles
var status: Label

var _graphics: GraphicsSettings
var _ground: Node3D
var _chunks := {}  ## Vector2i -> MeshInstance3D
var _water: Node3D
var _apron: MeshInstance3D
var _paths: Node3D
var _trees_root: Node3D
var _tree_nodes: Array[Node3D] = []
var _markers: Node3D
var _lines := ImmediateMesh.new()
var _cursor_lines := ImmediateMesh.new()
var _line_material: StandardMaterial3D

var _cursor: Variant = null  ## Vector3 under the mouse, or null
var _mouse := Vector2.ZERO
var _draft := PackedVector2Array()
var _drag := ""  ## "", "point", "shape", "tee", "pin", "aim"
var _drag_index := 0
var _drag_last := Vector2.ZERO
var _drag_moved := false
var _painting := false
var _stroke_changed := false
var _flatten_level := 0.0
var _tree_budget := 0.0
var _right_press := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _preview: RoundCamera  ## flies over a hole the way the round does
var _preview_tee := Vector3.ZERO

var _surface_dirty := false
var _surface_rect := Rect2()
var _ground_dirty := false
var _overlay_dirty := true
var _markers_dirty := true
var _unsaved := false
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []

var _new_dialog: ConfirmationDialog
var _new_size: OptionButton
var _new_starter: CheckBox
var _open_dialog: ConfirmationDialog
var _real: RealCourseDialog
var _photo_material: ShaderMaterial  ## null when the course has no aerial photo
var _photo_on := true
var _open_list: ItemList
var _discard_dialog: ConfirmationDialog
var _after_discard: Callable


func _ready() -> void:
	AssetProviders.ensure_defaults()
	_rng.randomize()
	_graphics = GraphicsSettings.load_saved()
	_graphics.apply_display(get_viewport())
	scenery = Scenery.new()
	add_child(scenery)
	scenery.apply(_graphics)
	camera = DesignerCamera.new()
	add_child(camera)
	camera.current = true
	_preview = RoundCamera.new()
	_preview.far = 6000.0
	add_child(_preview)

	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_material.no_depth_test = true
	_line_material.render_priority = 10
	for mesh: ImmediateMesh in [_lines, _cursor_lines]:
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = _line_material
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)
	_markers = Node3D.new()
	_markers.name = "Markers"
	add_child(_markers)
	_build_ui()

	var c: DesignedCourse = null
	if not last_path.is_empty():
		c = DesignedCourse.load_file(last_path)
	if c != null:
		_set_course(c, last_path)
	else:
		_set_course(DesignedCourse.starter(), "")
		_unsaved = true
	_set_status("Welcome to the course designer. Pick a tool on the left; hover a tool for what it does.")


# --- Course ---------------------------------------------------------------------

func _set_course(c: DesignedCourse, p_path: String) -> void:
	course = c
	path = p_path
	terrain = DesignedTerrain.new(course)
	_load_photo()
	camera.terrain = terrain
	_preview.terrain = terrain
	camera.bounds = course.area
	hole_index = 0 if not course.holes.is_empty() else -1
	selected = -1
	_draft.clear()
	_drag = ""
	_undo.clear()
	_redo.clear()
	_unsaved = false
	_build_ground()
	_rebuild_trees()
	_overlay_dirty = true
	_markers_dirty = true
	panel.show_course_name(course.course_name)
	panel.show_credits(course.credits)
	panel.show_photo_option(_photo_material != null, _photo_on)
	_show_holes()
	if hole_index >= 0:
		_focus_hole()
	else:
		camera.focus(course.area.get_center(), course.area.size.length() * 0.5)


func _focus_hole() -> void:
	var h := course.holes[hole_index]
	var a := h.pin if h.tees.is_empty() else h.tees[0]
	var mid := (a + h.pin) * 0.5
	camera.yaw = rad_to_deg(atan2(h.pin.x - a.x, h.pin.y - a.y)) if a != h.pin else camera.yaw
	camera.pitch = 55.0
	camera.focus(mid, maxf(150.0, a.distance_to(h.pin) * 1.1))


func _build_ground() -> void:
	if _ground != null:
		_ground.queue_free()
	_ground = Node3D.new()
	_ground.name = "Ground"
	add_child(_ground)
	_chunks.clear()
	var n := terrain.chunk_count()
	for cj in n.y:
		for ci in n.x:
			var inst := MeshInstance3D.new()
			inst.material_override = Materials.terrain()
			inst.material_overlay = _photo_material if _photo_on else null
			_ground.add_child(inst)
			_chunks[Vector2i(ci, cj)] = inst
	_ground_dirty = true
	_rebuild_water_and_apron()


func _refresh_ground() -> void:
	_ground_dirty = false
	for c: Vector2i in _chunks:
		var inst: MeshInstance3D = _chunks[c]
		if inst.mesh == null or not terrain.chunk_built(c):
			inst.mesh = terrain.chunk_mesh(c)


func _rebuild_water_and_apron() -> void:
	if _water != null and is_instance_valid(_water):
		_water.queue_free()
	_water = terrain.build_water()
	_ground.add_child(_water)
	if _apron != null and is_instance_valid(_apron):
		_apron.queue_free()
	_apron = terrain.build_apron()
	_ground.add_child(_apron)
	if _paths != null and is_instance_valid(_paths):
		_paths.queue_free()
	_paths = terrain.build_paths()
	_ground.add_child(_paths)


func _rebuild_trees() -> void:
	if _trees_root != null:
		_trees_root.queue_free()
	_trees_root = Node3D.new()
	_trees_root.name = "Trees"
	add_child(_trees_root)
	_tree_nodes.clear()
	for o in course.objects:
		_tree_nodes.append(_make_tree(o))


func _make_tree(o: PlacedObject) -> Node3D:
	# Objects the player's files don't have are drawn with a built-in stand-in.
	var node: Node3D = null
	var shown := DesignerObjects.stand_in(o, course.object_info)
	if shown != null:
		node = AssetProviders.object_library.instantiate(shown.id)
	if node == null:
		node = Node3D.new()
		shown = o
	node.position = Vector3(o.position.x, terrain.height_at(o.position.x, o.position.z), o.position.z)
	node.rotation_degrees.y = o.yaw_deg
	node.scale = Vector3.ONE * shown.scale
	_trees_root.add_child(node)
	return node


func _settle_trees() -> void:
	for i in course.objects.size():
		var o := course.objects[i]
		_tree_nodes[i].position.y = terrain.height_at(o.position.x, o.position.z)
	terrain.update_objects()


func _mark_surfaces(area: Rect2) -> void:
	_surface_rect = _surface_rect.merge(area) if _surface_dirty else area
	_surface_dirty = true
	_overlay_dirty = true
	_changed()


func _changed() -> void:
	_unsaved = true


# --- Undo -----------------------------------------------------------------------

func _snapshot() -> Dictionary:
	var d := course.to_dict(false)
	d["raw_heights"] = course.heights.duplicate()
	d["hole_index"] = hole_index
	return d


func _push_undo() -> void:
	_undo.append(_snapshot())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()


func _restore(d: Dictionary) -> void:
	course.heights = d["raw_heights"]
	course.shapes.clear()
	for s: Dictionary in d["shapes"]:
		course.shapes.append(CourseShape.from_dict(s))
	course.holes.clear()
	for h: Dictionary in d["holes"]:
		course.holes.append(DesignedHole.from_dict(h))
	course.objects.clear()
	for o: Dictionary in d["objects"]:
		course.objects.append(PlacedObject.new(str(o.id), Vector3(float(o.x), 0, float(o.z)), float(o.yaw), float(o.scale)))
	course.paths.clear()
	for p: Dictionary in d["paths"]:
		course.paths.append(CoursePath.from_dict(p))
	hole_index = mini(int(d["hole_index"]), course.holes.size() - 1)
	selected = -1
	terrain.rebuild()
	_ground_dirty = true
	_rebuild_water_and_apron()
	_rebuild_trees()
	_overlay_dirty = true
	_markers_dirty = true
	_show_holes()
	_changed()


func _undo_step(from: Array[Dictionary], to: Array[Dictionary], what: String) -> void:
	if from.is_empty():
		_set_status("Nothing to %s." % what)
		return
	to.append(_snapshot())
	_restore(from.pop_back())
	_set_status(what.capitalize() + " done.")


# --- Frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if _preview.current:
		_preview.update(delta, 0.0, _preview_tee)
		if not _preview.flying():
			_stop_flyover()
		return
	if not get_viewport().gui_get_focus_owner() is LineEdit:
		camera.process_keys(delta)
	if _painting:
		_cursor = _pick(_mouse)
		_apply_brush(delta)
	if _surface_dirty:
		_surface_dirty = false
		terrain.update_surfaces(_surface_rect)
		_ground_dirty = true
		_rebuild_water_and_apron()
	if _ground_dirty:
		_refresh_ground()
	if _markers_dirty:
		_build_markers()
	if _overlay_dirty:
		_draw_overlay()
	_draw_cursor()


# --- Input ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _preview.current:
		# Any click or key ends the flyover.
		if (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
			_stop_flyover()
			get_viewport().set_input_as_handled()
		return
	if camera.handle_input(event):
		_cursor = _pick(_mouse)
		return
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		_cursor = _pick(_mouse)
		if not _drag.is_empty():
			_drag_to()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = mb.position
		_cursor = _pick(_mouse)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_press(mb)
			else:
				_on_left_release()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_press = mb.position
			elif mb.position.distance_to(_right_press) < 5.0:
				_on_right_click()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_on_key(event as InputEventKey)


func _on_key(k: InputEventKey) -> void:
	if k.ctrl_pressed or k.meta_pressed:
		match k.keycode:
			KEY_Z:
				if k.shift_pressed:
					_undo_step(_redo, _undo, "redo")
				else:
					_undo_step(_undo, _redo, "undo")
			KEY_Y:
				_undo_step(_redo, _undo, "redo")
			KEY_S:
				_save()
		return
	match k.keycode:
		KEY_ESCAPE:
			if not _draft.is_empty():
				_draft.clear()
				_set_status("Outline cancelled.")
			else:
				selected = -1
			_overlay_dirty = true
		KEY_ENTER, KEY_KP_ENTER:
			_finish_draft()
		KEY_DELETE, KEY_BACKSPACE:
			if selected >= 0:
				_push_undo()
				var old := course.shapes[selected].bounds()
				course.shapes.remove_at(selected)
				selected = -1
				_mark_surfaces(old)
		KEY_F:
			if hole_index >= 0:
				_focus_hole()


func _on_left_press(mb: InputEventMouseButton) -> void:
	var p2: Variant = null if _cursor == null else Vector2(_cursor.x, _cursor.z)
	match panel.tool:
		DesignerPanel.Tool.SELECT:
			_select_press(p2, mb.double_click)
		DesignerPanel.Tool.SHAPE:
			if p2 == null:
				return
			if _draft.size() >= 3 and _screen_distance(_draft[0]) < PICK_PIXELS:
				_finish_draft()
			else:
				_draft.append(p2)
				_overlay_dirty = true
		DesignerPanel.Tool.PATH:
			if p2 == null:
				return
			if mb.shift_pressed:
				_remove_path(p2)
			elif mb.double_click and _draft.size() >= 2:
				_finish_draft()
			else:
				_draft.append(p2)
				_overlay_dirty = true
		DesignerPanel.Tool.RAISE, DesignerPanel.Tool.LOWER, DesignerPanel.Tool.SMOOTH, DesignerPanel.Tool.FLATTEN, DesignerPanel.Tool.TREES:
			if p2 == null:
				return
			_push_undo()
			_painting = true
			_stroke_changed = false
			_tree_budget = 1.0
			_flatten_level = course.base_height(p2.x, p2.y)
		DesignerPanel.Tool.TEE:
			if p2 != null:
				_place_tee(p2)
		DesignerPanel.Tool.PIN:
			if p2 != null:
				_push_undo()
				_ensure_hole(p2)
				course.holes[hole_index].pin = p2
				_holes_changed()
		DesignerPanel.Tool.AIM:
			if p2 != null and hole_index >= 0:
				_push_undo()
				var h := course.holes[hole_index]
				h.route.append(p2)
				_sort_route(h)
				_holes_changed()
		DesignerPanel.Tool.OBJECTS:
			if p2 != null:
				_place_or_remove_object(p2, mb.shift_pressed)


func _on_left_release() -> void:
	if _painting:
		_painting = false
		if _stroke_changed:
			_rebuild_water_and_apron()
			_settle_trees()
			_overlay_dirty = true
			_markers_dirty = true
		else:
			_undo.pop_back()
	if not _drag.is_empty():
		if _drag_moved and _drag in ["tee", "pin", "aim"]:
			_holes_changed()
		_drag = ""


func _on_right_click() -> void:
	match panel.tool:
		DesignerPanel.Tool.SHAPE, DesignerPanel.Tool.PATH:
			_finish_draft()
		DesignerPanel.Tool.SELECT:
			if selected < 0:
				return
			var s := course.shapes[selected]
			for i in s.points.size():
				if _screen_distance(s.points[i]) < PICK_PIXELS and s.points.size() > 3:
					_push_undo()
					var old := s.bounds()
					s.points.remove_at(i)
					s.changed()
					_mark_surfaces(old.merge(s.bounds()))
					return
		DesignerPanel.Tool.AIM:
			if hole_index < 0:
				return
			var h := course.holes[hole_index]
			for i in h.route.size():
				if _screen_distance(h.route[i]) < PICK_PIXELS:
					_push_undo()
					h.route.remove_at(i)
					_holes_changed()
					return


func _select_press(p2: Variant, double_click: bool) -> void:
	_drag_moved = false
	if selected >= 0:
		var s := course.shapes[selected]
		if double_click and p2 != null and absf(s.signed_distance(p2)) < maxf(3.0, camera.distance * 0.01):
			_push_undo()
			var old := s.bounds()
			s.insert_point(p2)
			_mark_surfaces(old.merge(s.bounds()))
			return
		for i in s.points.size():
			if _screen_distance(s.points[i]) < PICK_PIXELS:
				_start_drag("point", i, s.points[i])
				return
	if hole_index >= 0:
		var h := course.holes[hole_index]
		for i in h.tees.size():
			if _screen_distance(h.tees[i]) < PICK_PIXELS:
				_start_drag("tee", i, h.tees[i])
				return
		if _screen_distance(h.pin) < PICK_PIXELS:
			_start_drag("pin", 0, h.pin)
			return
		for i in h.route.size():
			if _screen_distance(h.route[i]) < PICK_PIXELS:
				_start_drag("aim", i, h.route[i])
				return
	if p2 == null:
		return
	var hit := course.shape_at(p2)
	if hit != selected:
		selected = hit
		_overlay_dirty = true
	if hit >= 0:
		panel.show_surface(course.shapes[hit].surface)
		_start_drag("shape", hit, p2)
		_set_status("%s selected. Drag it or its points; Delete removes it." % Surface.name_of(course.shapes[hit].surface))


func _start_drag(kind: String, index: int, at: Vector2) -> void:
	_drag = kind
	_drag_index = index
	_drag_last = at
	_drag_moved = false


func _drag_to() -> void:
	if _cursor == null:
		return
	var p2 := Vector2(_cursor.x, _cursor.z)
	if not _drag_moved:
		if _screen_distance(_drag_last) < 3.0 and _drag == "shape":
			return
		_drag_moved = true
		_push_undo()
	match _drag:
		"point", "shape":
			var s := course.shapes[selected]
			var old := s.bounds()
			if _drag == "point":
				s.points[_drag_index] = p2
				s.changed()
			else:
				s.translate(p2 - _drag_last)
			_drag_last = p2
			_mark_surfaces(old.merge(s.bounds()))
		"tee":
			course.holes[hole_index].tees[_drag_index] = p2
			_markers_dirty = true
			_overlay_dirty = true
		"pin":
			course.holes[hole_index].pin = p2
			_markers_dirty = true
			_overlay_dirty = true
		"aim":
			course.holes[hole_index].route[_drag_index] = p2
			_markers_dirty = true
			_overlay_dirty = true


func _finish_draft() -> void:
	if panel.tool == DesignerPanel.Tool.PATH:
		_finish_path()
		return
	if _draft.size() < 3:
		if not _draft.is_empty():
			_set_status("An area needs at least three points.")
		return
	_push_undo()
	var s := CourseShape.new(panel.chosen_surface(), _draft.duplicate())
	course.shapes.append(s)
	_draft.clear()
	selected = course.shapes.size() - 1
	_mark_surfaces(s.bounds())
	_set_status("%s added." % Surface.name_of(s.surface))


func _finish_path() -> void:
	var p := CoursePath.new(_draft.duplicate(), panel.path_width.value, panel.path_bridge.button_pressed)
	if not p.is_valid():
		if not _draft.is_empty():
			_set_status("A path needs at least two points.")
		return
	_push_undo()
	course.paths.append(p)
	_draft.clear()
	_paths_changed(p.bounds())
	_set_status("%s added (%d m)." % ["Bridge" if p.bridge else "Cart path", roundi(p.length())])


func _remove_path(p2: Vector2) -> void:
	var best := -1
	var best_d := maxf(3.0, camera.distance * 0.01)
	for i in course.paths.size():
		var d := course.paths[i].distance_to(p2)
		if d < best_d:
			best = i
			best_d = d
	if best < 0:
		return
	_push_undo()
	var old := course.paths[best].bounds()
	course.paths.remove_at(best)
	_paths_changed(old)


func _paths_changed(area: Rect2) -> void:
	_mark_surfaces(area)
	terrain.update_objects()


func _apply_brush(delta: float) -> void:
	if _cursor == null:
		return
	var p2 := Vector2(_cursor.x, _cursor.z)
	var r := panel.brush_size.value
	var k := panel.strength.value
	var cells := Rect2i()
	match panel.tool:
		DesignerPanel.Tool.RAISE:
			cells = course.sculpt("raise", p2, r, k * 4.0 * delta)
		DesignerPanel.Tool.LOWER:
			cells = course.sculpt("lower", p2, r, k * 4.0 * delta)
		DesignerPanel.Tool.SMOOTH:
			cells = course.sculpt("smooth", p2, r, minf(1.0, k * 6.0 * delta))
		DesignerPanel.Tool.FLATTEN:
			cells = course.sculpt("flatten", p2, r, minf(1.0, k * 5.0 * delta), _flatten_level)
		DesignerPanel.Tool.TREES:
			_paint_trees(p2, r, k, delta)
			return
	terrain.update_heights(cells)
	_ground_dirty = true
	_stroke_changed = true
	_changed()


func _paint_trees(p2: Vector2, r: float, k: float, delta: float) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		var near := course.objects_near(p2, r)
		near.sort()
		for n in range(near.size() - 1, -1, -1):
			var i := near[n]
			course.objects.remove_at(i)
			_tree_nodes[i].queue_free()
			_tree_nodes.remove_at(i)
			_stroke_changed = true
		if not near.is_empty():
			_changed()
		return
	_tree_budget += delta * 14.0 * k
	while _tree_budget >= 1.0:
		_tree_budget -= 1.0
		for attempt in 8:
			var q := p2 + Vector2.from_angle(_rng.randf() * TAU) * r * sqrt(_rng.randf())
			if not course.area.has_point(q):
				continue
			var s := terrain.surface_at(q.x, q.y)
			if s not in [Surface.Type.ROUGH, Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS]:
				continue
			if not course.objects_near(q, 4.5).is_empty():
				continue
			var kind := panel.tree_kind.selected
			var id: String = DesignedCourse.TREE_IDS[kind] if kind < DesignedCourse.TREE_IDS.size() else DesignedCourse.TREE_IDS[_rng.randi() % DesignedCourse.TREE_IDS.size()]
			var o := PlacedObject.new(id, Vector3(q.x, 0, q.y), _rng.randf_range(0, 360), _rng.randf_range(0.8, 1.3))
			course.objects.append(o)
			_tree_nodes.append(_make_tree(o))
			_stroke_changed = true
			_changed()
			break


# --- Objects and the flyover ----------------------------------------------------

## Places the object picked in the panel at `p2`, or with `remove` takes away
## the nearest one.
func _place_or_remove_object(p2: Vector2, remove: bool) -> void:
	if remove:
		var near := course.objects_near(p2, maxf(3.0, camera.distance * 0.01))
		if near.is_empty():
			return
		_push_undo()
		var i := near[0]
		course.objects.remove_at(i)
		_tree_nodes[i].queue_free()
		_tree_nodes.remove_at(i)
	else:
		_push_undo()
		var yaw := panel.object_turn.value
		var size := panel.object_scale.value
		if panel.object_random.button_pressed:
			yaw = _rng.randf_range(0.0, 360.0)
			size *= _rng.randf_range(0.85, 1.15)
		var o := PlacedObject.new(panel.chosen_object(), Vector3(p2.x, 0, p2.y), yaw, size)
		course.objects.append(o)
		_tree_nodes.append(_make_tree(o))
	terrain.update_objects()
	_changed()


## Flies over the current hole from its back tee to the green, as the round
## does before the first shot. A click or key ends it early.
func _start_flyover() -> void:
	if hole_index < 0 or course.holes[hole_index].tees.is_empty():
		_set_status("The hole needs a tee for a flyover.")
		return
	var dh := course.holes[hole_index]
	var h := HoleData.new()
	h.terrain = terrain
	h.tee = _ground_point(dh.tees[0], 0.0)
	h.pin = _ground_point(dh.pin, 0.0)
	h.route = dh.route.duplicate()
	_preview_tee = h.tee
	var first := dh.route[0] if not dh.route.is_empty() else dh.pin
	var dir := Vector3(first.x - h.tee.x, 0.0, first.y - h.tee.z).normalized()
	_preview.aim(h.tee, dir, false)
	_preview.start_flyover(h)
	_preview.current = true
	_cursor_lines.clear_surfaces()
	_set_status("Flying over hole %d. Click or press a key to stop." % (hole_index + 1))


func _stop_flyover() -> void:
	_preview.end_flyover()
	camera.current = true
	_set_status("")


# --- Holes ----------------------------------------------------------------------

func _ensure_hole(at: Vector2) -> void:
	if hole_index >= 0:
		return
	var h := DesignedHole.new()
	h.pin = at
	course.holes.append(h)
	hole_index = course.holes.size() - 1


func _place_tee(p2: Vector2) -> void:
	_push_undo()
	_ensure_hole(p2)
	var h := course.holes[hole_index]
	var slot := panel.tee_slot.selected
	if slot < h.tees.size():
		h.tees[slot] = p2
	else:
		h.tees.append(p2)
	_holes_changed()


func _sort_route(h: DesignedHole) -> void:
	if h.tees.is_empty():
		return
	var tee := h.tees[0]
	var pts: Array[Vector2] = []
	for p in h.route:
		pts.append(p)
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(tee) < b.distance_squared_to(tee))
	h.route = PackedVector2Array(pts)


## A new hole starting at the middle of the view and playing away from the
## camera, with a tee box, fairway and green to start from.
func _add_hole() -> void:
	_push_undo()
	var axes := camera.ground_axes()
	var fwd: Vector2 = axes[0]
	var tee := Vector2(camera.target.x, camera.target.z)
	var pin := tee + fwd * 330.0
	var a := course.area.grow(-20.0)
	tee = tee.clamp(a.position, a.end)
	pin = pin.clamp(a.position, a.end)
	var h := DesignedHole.new()
	h.tees = PackedVector2Array([tee])
	h.pin = pin
	h.par = DesignedHole.par_for_length(tee.distance_to(pin))
	course.holes.append(h)
	hole_index = course.holes.size() - 1
	var dir := (pin - tee).normalized()
	var angle := dir.angle()
	var area := Rect2(tee, Vector2.ZERO).expand(pin).grow(30.0)
	course.shapes.append(CourseShape.oval(Surface.Type.TEE, tee + dir * 6.0, Vector2(14.0, 5.0), angle))
	if tee.distance_to(pin) > 200.0:
		course.shapes.append(CourseShape.strip(Surface.Type.FAIRWAY,
			PackedVector2Array([tee + dir * 60.0, tee.lerp(pin, 0.6), pin - dir * 25.0]), 34.0))
	course.shapes.append(CourseShape.oval(Surface.Type.GREEN, pin, Vector2(17.0, 13.0), angle, 10))
	_mark_surfaces(area)
	_holes_changed()
	_focus_hole()
	_set_status("Hole %d added. Drag its tee and pin, reshape its areas, or add aim points for doglegs." % (hole_index + 1))


func _delete_hole() -> void:
	if hole_index < 0:
		return
	_push_undo()
	course.holes.remove_at(hole_index)
	hole_index = mini(hole_index, course.holes.size() - 1)
	_holes_changed()


func _holes_changed() -> void:
	_markers_dirty = true
	_overlay_dirty = true
	_show_holes()
	_changed()


func _show_holes() -> void:
	panel.show_holes(course, hole_index)


# --- Drawing --------------------------------------------------------------------

func _ground_point(p: Vector2, lift := 0.3) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.y) + lift, p.y)


func _draw_overlay() -> void:
	_overlay_dirty = false
	_lines.clear_surfaces()
	var any := false
	for i in course.shapes.size():
		var s := course.shapes[i]
		var poly := s.outline()
		if poly.size() < 3:
			continue
		var c: Color = LINE_COLORS.get(s.surface, Color.WHITE)
		if i == selected:
			c = Color(1.0, 0.95, 0.2)
		_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for k in poly.size() + 1:
			_lines.surface_set_color(c)
			_lines.surface_add_vertex(_ground_point(poly[k % poly.size()]))
		_lines.surface_end()
		any = true
	if selected >= 0 and selected < course.shapes.size():
		var size := camera.distance * 0.008
		for p in course.shapes[selected].points:
			_square(p, size, Color(1.0, 0.95, 0.2))
	if not _draft.is_empty():
		_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in _draft:
			_lines.surface_set_color(Color.WHITE)
			_lines.surface_add_vertex(_ground_point(p))
		_lines.surface_end()
		var size := camera.distance * 0.008
		for p in _draft:
			_square(p, size, Color.WHITE)
	for path in course.paths:
		if not path.is_valid():
			continue
		any = true
		_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in path.points:
			_lines.surface_set_color(Color(0.85, 0.75, 0.55) if path.bridge else Color(0.85, 0.85, 0.85))
			_lines.surface_add_vertex(_ground_point(p, 0.6))
		_lines.surface_end()
	for n in course.holes.size():
		var h := course.holes[n]
		if h.tees.is_empty():
			continue
		var c := Color(1.0, 0.9, 0.2) if n == hole_index else Color(1, 1, 1, 0.5)
		_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in [h.tees[0]] + Array(h.route) + [h.pin]:
			_lines.surface_set_color(c)
			_lines.surface_add_vertex(_ground_point(p, 1.0))
		_lines.surface_end()
		any = true
	if not any:
		# An ImmediateMesh with no surfaces is fine, but keep one so the
		# instance always has something to draw.
		_lines.surface_begin(Mesh.PRIMITIVE_LINES)
		_lines.surface_add_vertex(Vector3.ZERO)
		_lines.surface_add_vertex(Vector3.ZERO)
		_lines.surface_end()


func _square(p: Vector2, size: float, c: Color) -> void:
	_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		_lines.surface_set_color(c)
		_lines.surface_add_vertex(_ground_point(p + corner * size, 0.5))
	_lines.surface_end()


## The brush ring, or the line from the last outline point to the mouse.
func _draw_cursor() -> void:
	_cursor_lines.clear_surfaces()
	if _cursor == null:
		return
	var p2 := Vector2(_cursor.x, _cursor.z)
	var tool := panel.tool
	if tool in [DesignerPanel.Tool.RAISE, DesignerPanel.Tool.LOWER, DesignerPanel.Tool.SMOOTH, DesignerPanel.Tool.FLATTEN, DesignerPanel.Tool.TREES]:
		var r := panel.brush_size.value
		var c := Color(1, 0.4, 0.3) if tool == DesignerPanel.Tool.TREES and Input.is_key_pressed(KEY_SHIFT) else Color(1, 1, 1)
		_cursor_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for k in 49:
			_cursor_lines.surface_set_color(c)
			_cursor_lines.surface_add_vertex(_ground_point(p2 + Vector2.from_angle(TAU * k / 48.0) * r, 0.4))
		_cursor_lines.surface_end()
	elif tool in [DesignerPanel.Tool.SHAPE, DesignerPanel.Tool.PATH] and not _draft.is_empty():
		_cursor_lines.surface_begin(Mesh.PRIMITIVE_LINES)
		_cursor_lines.surface_set_color(Color.WHITE)
		_cursor_lines.surface_add_vertex(_ground_point(_draft[_draft.size() - 1]))
		_cursor_lines.surface_set_color(Color.WHITE)
		_cursor_lines.surface_add_vertex(_ground_point(p2))
		_cursor_lines.surface_end()


func _build_markers() -> void:
	_markers_dirty = false
	for child in _markers.get_children():
		child.queue_free()
	for n in course.holes.size():
		var h := course.holes[n]
		var current := n == hole_index
		for t in h.tees.size():
			var box := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.5, 0.5, 0.5)
			box.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = TEE_COLORS[t % TEE_COLORS.size()]
			box.material_override = mat
			box.position = _ground_point(h.tees[t], 0.25)
			_markers.add_child(box)
		if not h.tees.is_empty():
			_markers.add_child(_label("Tee %d" % (n + 1), _ground_point(h.tees[0], 4.0), current))
		var stick := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.03
		cyl.height = 2.4
		stick.mesh = cyl
		stick.position = _ground_point(h.pin, 1.2)
		_markers.add_child(stick)
		var flag := MeshInstance3D.new()
		var cloth := BoxMesh.new()
		cloth.size = Vector3(0.02, 0.4, 0.6)
		flag.mesh = cloth
		var flag_mat := StandardMaterial3D.new()
		flag_mat.albedo_color = Color(1.0, 0.85, 0.1) if current else Color(0.9, 0.15, 0.1)
		flag.material_override = flag_mat
		flag.position = _ground_point(h.pin, 2.2) + Vector3(0, 0, 0.3)
		_markers.add_child(flag)
		_markers.add_child(_label("Pin %d" % (n + 1), _ground_point(h.pin, 4.5), current))
		if current:
			for p in h.route:
				_markers.add_child(_label("+", _ground_point(p, 1.5), true))


func _label(text: String, at: Vector3, current: bool) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.font_size = 28 if current else 20
	l.outline_size = 8
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.95, 0.4) if current else Color(1, 1, 1, 0.8)
	return l


# --- Picking --------------------------------------------------------------------

## The ground point under a screen position, or null.
func _pick(screen: Vector2) -> Variant:
	if camera == null or terrain == null:
		return null
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var area := course.area
	var t := 0.0
	var prev_t := 0.0
	var was_above := true
	while t < camera.far:
		var p := from + dir * t
		var inside := area.has_point(Vector2(p.x, p.z))
		if inside:
			var above := p.y > terrain.height_at(p.x, p.z)
			if not above and was_above and t > 0.0:
				var lo := prev_t
				var hi := t
				for k in 12:
					var mid := (lo + hi) * 0.5
					var q := from + dir * mid
					if q.y > terrain.height_at(q.x, q.z):
						lo = mid
					else:
						hi = mid
				var hit := from + dir * hi
				return Vector3(hit.x, terrain.height_at(hit.x, hit.z), hit.z)
			was_above = above
		else:
			was_above = true
		prev_t = t
		t += maxf(0.5, t * 0.004)
	return null


func _screen_distance(p: Vector2) -> float:
	var w := _ground_point(p, 0.0)
	if camera.is_position_behind(w):
		return INF
	return camera.unproject_position(w).distance_to(_mouse)


# --- Files ----------------------------------------------------------------------

func _on_file_action(action: String) -> void:
	match action:
		"new":
			_confirm_discard(func() -> void: _new_dialog.popup_centered())
		"open":
			_confirm_discard(_show_open)
		"save":
			_save()
		"import":
			_confirm_discard(files.import_file)
		"real":
			_confirm_discard(func() -> void: _real.open())
		"export":
			files.export_text(course.to_json(), course.default_path().get_file())
			_set_status("Exported %s." % course.default_path().get_file())
		"play":
			_play()
		"menu":
			_confirm_discard(func() -> void: SceneFade.change_scene(get_tree(), MENU_SCENE))


func _save() -> bool:
	var p := course.default_path()
	var err := course.save_file(p)
	if err != OK:
		_set_status("Couldn't save the course (%s)." % error_string(err))
		return false
	path = p
	last_path = p
	_unsaved = false
	_set_status("Saved as %s." % p.get_file())
	return true


func _play() -> void:
	var playable := 0
	for h in course.holes:
		if not h.tees.is_empty():
			playable += 1
	if playable == 0:
		_set_status("Give at least one hole a tee and a pin first.")
		return
	if not _save():
		return
	GolfRound.setup = RoundSetup.single(path)
	# The key lets the main menu resume the round on this course.
	GolfRound.setup.course_key = path
	GolfRound.chosen_course = path
	SceneFade.change_scene(get_tree(), ROUND_SCENE)


func _show_open() -> void:
	_open_list.clear()
	for p in DesignedCourse.saved_paths():
		_open_list.add_item(p.get_file().get_basename())
		_open_list.set_item_metadata(_open_list.item_count - 1, p)
	if _open_list.item_count == 0:
		_set_status("No saved courses yet. Save one first, or import a .olc file.")
		return
	_open_dialog.popup_centered(Vector2i(420, 360))


func _on_open_confirmed() -> void:
	var picked := _open_list.get_selected_items()
	if picked.is_empty():
		return
	var p: String = _open_list.get_item_metadata(picked[0])
	var c := DesignedCourse.load_file(p)
	if c == null:
		_set_status("Couldn't read %s." % p.get_file())
		return
	last_path = p
	_set_course(c, p)
	_set_status("Opened %s." % c.course_name)


func _on_new_confirmed() -> void:
	var size: Vector2 = DesignedCourse.SIZES[_new_size.selected]
	var c := DesignedCourse.starter(size) if _new_starter.button_pressed else DesignedCourse.blank(size)
	if not _new_starter.button_pressed:
		c.course_name = "New course"
	_set_course(c, "")
	_unsaved = true
	_set_status("New course. Give it a name, then lay out its holes.")


func _on_imported(text: String, file_name: String) -> void:
	var c := DesignedCourse.from_json(text)
	if c == null:
		_set_status("%s isn't an OpenLinks course file." % file_name)
		return
	_set_course(c, "")
	_unsaved = true
	_set_status("Imported %s. Save it to keep it." % c.course_name)


func _on_real_built(c: DesignedCourse, summary: Dictionary) -> void:
	# The aerial photo is kept beside the course file, not in it.
	var photo: Image = summary.get("photo", null)
	if photo != null:
		var file := c.default_path().get_basename().get_file() + ".photo.jpg"
		DirAccess.make_dir_recursive_absolute(DesignedCourse.FOLDER)
		if photo.save_jpg(DesignedCourse.FOLDER.path_join(file), 0.85) == OK:
			c.source["photo"] = file
	# Other courses at the same club are saved beside it.
	var others: Array = summary.get("others", [])
	for o: DesignedCourse in others:
		if c.source.has("photo"):
			o.source["photo"] = c.source["photo"]
		o.save_file(o.default_path())
	_photo_on = true
	_set_course(c, "")
	_unsaved = true
	var saved := _save()
	_set_status("Built %s: %d holes, %d areas, %d trees%s. %s" % [c.course_name, int(summary.get("holes", 0)),
		int(summary.get("areas", 0)), int(summary.get("trees", 0)),
		(", ground every %.1f m" % float(summary.get("metres_per_pixel", 0))) if summary.has("metres_per_pixel") else "",
		("Saved; polish it here, then play it." if saved else "Save it to keep it.") +
		(" Also saved: %s (Open)." % ", ".join(others.map(func(o: DesignedCourse) -> String: return o.course_name)) if not others.is_empty() else "")])


## The course's aerial photo as a ground overlay material, if it has one.
func _load_photo() -> void:
	_photo_material = null
	var file := str(course.source.get("photo", ""))
	if file.is_empty() or file.get_file() != file:
		return
	var img := Image.load_from_file(DesignedCourse.FOLDER.path_join(file)) if FileAccess.file_exists(DesignedCourse.FOLDER.path_join(file)) else null
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	_photo_material = ShaderMaterial.new()
	_photo_material.shader = load("res://shaders/aerial_photo.gdshader")
	_photo_material.set_shader_parameter("photo", ImageTexture.create_from_image(img))
	var a := course.area
	_photo_material.set_shader_parameter("area", Vector4(a.position.x, a.position.y, a.size.x, a.size.y))


func _confirm_discard(then: Callable) -> void:
	if not _unsaved:
		then.call()
		return
	_after_discard = then
	_discard_dialog.popup_centered()


# --- Interface ------------------------------------------------------------------

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	panel = DesignerPanel.new()
	panel.file_action.connect(_on_file_action)
	panel.tool_changed.connect(func(_t: int) -> void:
		_draft.clear()
		_overlay_dirty = true)
	panel.surface_changed.connect(_on_surface_changed)
	panel.hole_selected.connect(func(i: int) -> void:
		hole_index = i
		_holes_changed()
		_focus_hole())
	panel.hole_action.connect(func(a: String) -> void:
		if a == "add":
			_add_hole()
		elif a == "delete":
			_delete_hole()
		else:
			_start_flyover())
	panel.par_changed.connect(func(v: int) -> void:
		if hole_index >= 0:
			_push_undo()
			course.holes[hole_index].par = v
			_holes_changed())
	panel.photo_toggled.connect(func(on: bool) -> void:
		_photo_on = on
		for c: Vector2i in _chunks:
			(_chunks[c] as MeshInstance3D).material_overlay = _photo_material if on else null)
	panel.name_changed.connect(func(t: String) -> void:
		course.course_name = t
		_changed())
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = 320
	canvas.add_child(panel)

	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_left = 336
	status.offset_top = -36
	status.offset_bottom = -10
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_constant_override("outline_size", 6)
	status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(status)

	files = DesignerFiles.new()
	files.imported.connect(_on_imported)
	add_child(files)

	_real = RealCourseDialog.new()
	_real.status.connect(_set_status)
	_real.built.connect(_on_real_built)
	canvas.add_child(_real)

	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "New course"
	var box := VBoxContainer.new()
	_new_size = OptionButton.new()
	for n in DesignedCourse.SIZE_NAMES:
		_new_size.add_item(n)
	_new_size.select(1)
	box.add_child(_new_size)
	_new_starter = CheckBox.new()
	_new_starter.text = "Start with rolling ground and one hole"
	_new_starter.button_pressed = true
	box.add_child(_new_starter)
	_new_dialog.add_child(box)
	_new_dialog.confirmed.connect(_on_new_confirmed)
	canvas.add_child(_new_dialog)

	_open_dialog = ConfirmationDialog.new()
	_open_dialog.title = "Open a course"
	_open_dialog.ok_button_text = "Open"
	_open_list = ItemList.new()
	_open_list.custom_minimum_size = Vector2(380, 260)
	_open_list.item_activated.connect(func(_i: int) -> void:
		_open_dialog.hide()
		_on_open_confirmed())
	_open_dialog.add_child(_open_list)
	_open_dialog.confirmed.connect(_on_open_confirmed)
	canvas.add_child(_open_dialog)

	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.title = "Unsaved changes"
	_discard_dialog.dialog_text = "This course has changes that aren't saved. Carry on without saving them?"
	_discard_dialog.ok_button_text = "Don't save"
	_discard_dialog.confirmed.connect(func() -> void:
		if _after_discard.is_valid():
			_after_discard.call())
	canvas.add_child(_discard_dialog)


func _on_surface_changed(s: int) -> void:
	if panel.tool != DesignerPanel.Tool.SELECT or selected < 0:
		return
	_push_undo()
	course.shapes[selected].surface = s
	_mark_surfaces(course.shapes[selected].bounds())


func _set_status(text: String) -> void:
	if status != null:
		status.text = text
