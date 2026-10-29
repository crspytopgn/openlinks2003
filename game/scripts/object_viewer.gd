extends Node3D
## Browse the Course Designer object library: pick an object to see it, or
## scatter a whole category on a patch of grass. Reads OBJECT.LIB and the
## Object folder from your own install (or a folder made with
## `tools/cdimage/cdimage.py install`). Esc goes back to the range.

const SCATTER_COUNT := 40
const SCATTER_RADIUS := 40.0

var library: DecodedObjectLibrary
var path_edit: LineEdit
var status: Label
var tree: Tree
var dialog: FileDialog
var shown: Node3D
var camera: Camera3D
var orbit_yaw := 0.6
var orbit_pitch := 0.25
var orbit_distance := 25.0
var orbit_target := Vector3(0, 4, 0)


func _ready() -> void:
	_build_world()
	_build_ui()
	var start := GameFolder.configured_path()
	path_edit.text = start
	if OS.has_feature("web"):
		_set_status("The object viewer needs a desktop build: browsers cannot read your game folder yet.")
	elif not start.is_empty():
		_load_folder(start)
	else:
		_set_status("Choose your Links 2003 folder (the one with object.lib and Object).")


func _build_world() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
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

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.5, 0.2)
	ground.material_override = mat
	add_child(ground)

	camera = Camera3D.new()
	camera.far = 2000.0
	add_child(camera)
	_update_camera()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size = Vector2(360, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var row := HBoxContainer.new()
	box.add_child(row)
	path_edit = LineEdit.new()
	path_edit.placeholder_text = "Links 2003 folder"
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.text_submitted.connect(_load_folder)
	row.add_child(path_edit)
	var browse := Button.new()
	browse.text = "Browse"
	browse.pressed.connect(func() -> void: dialog.popup_centered_ratio(0.7))
	row.add_child(browse)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(func() -> void: _load_folder(path_edit.text))
	row.add_child(load_button)

	var scatter := Button.new()
	scatter.text = "Scatter this category"
	scatter.pressed.connect(_scatter_selected_category)
	box.add_child(scatter)

	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.item_selected.connect(_on_item_selected)
	box.add_child(tree)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)

	dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.dir_selected.connect(func(dir: String) -> void:
		path_edit.text = dir
		_load_folder(dir))
	layer.add_child(dialog)


func _set_status(text: String) -> void:
	status.text = text


func _save_folder(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(GameFolder.SETTINGS_PATH)
	cfg.set_value("game", "folder", path)
	cfg.save(GameFolder.SETTINGS_PATH)


func _load_folder(path: String) -> void:
	library = DecodedObjectLibrary.open(path)
	if library == null:
		_set_status("No readable object.lib in %s. Pick the folder that holds object.lib and the Object folder." % path)
		return
	_save_folder(path)
	tree.clear()
	var root := tree.create_item()
	var total := 0
	for cat in library.catalog.categories:
		if (cat.objects as Array).is_empty():
			continue
		var item := tree.create_item(root)
		item.set_text(0, "%s (%d)" % [cat.name, (cat.objects as Array).size()])
		item.set_metadata(0, cat)
		item.collapsed = true
		for o: Dictionary in cat.objects:
			var child := tree.create_item(item)
			child.set_text(0, (o.name as String).get_basename())
			child.set_metadata(0, o)
			total += 1
	_set_status("%d objects in %d categories." % [total, library.catalog.categories.size()])


func _on_item_selected() -> void:
	var meta: Variant = tree.get_selected().get_metadata(0)
	if meta is Dictionary and (meta as Dictionary).has("id"):
		_show_objects([meta], false)


func _scatter_selected_category() -> void:
	var item := tree.get_selected()
	if item == null:
		_set_status("Pick a category or an object first.")
		return
	if item.get_parent() != tree.get_root():
		item = item.get_parent()
	_show_objects(item.get_metadata(0).objects, true)


func _show_objects(objects: Array, scatter: bool) -> void:
	if shown:
		shown.queue_free()
	shown = Node3D.new()
	add_child(shown)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2003
	var count := SCATTER_COUNT if scatter else 1
	var failed := 0
	var tallest := 1.0
	for i in count:
		var o: Dictionary = objects[rng.randi() % objects.size()] if scatter else objects[0]
		var node := library.instantiate(str(o.id))
		if node == null:
			failed += 1
			continue
		if scatter:
			var r := SCATTER_RADIUS * sqrt(rng.randf())
			var a := rng.randf() * TAU
			node.position = Vector3(cos(a) * r, 0, sin(a) * r)
			if o.kind == ObjectCatalog.KIND_MODEL:
				node.rotation.y = rng.randf() * TAU
		shown.add_child(node)
		tallest = maxf(tallest, library.height_m(str(o.id)))
	if scatter:
		orbit_target = Vector3(0, 2, 0)
		orbit_distance = SCATTER_RADIUS * 2.2
	else:
		orbit_target = Vector3(0, tallest * 0.5, 0)
		orbit_distance = maxf(tallest * 2.2, 4.0)
	_update_camera()
	if failed:
		_set_status("%d of %d objects could not be loaded (missing or unreadable files)." % [failed, count])
	elif not scatter:
		var o: Dictionary = objects[0]
		_set_status("%s, id %d. %s" % [o.path, o.id, "3D model" if o.kind == ObjectCatalog.KIND_MODEL else "billboard"])


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	var motion := event as InputEventMouseMotion
	if motion and motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
		orbit_yaw -= motion.relative.x * 0.01
		orbit_pitch = clampf(orbit_pitch + motion.relative.y * 0.01, -0.1, 1.4)
		_update_camera()
		return
	var button := event as InputEventMouseButton
	if button and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(orbit_distance * 0.9, 1.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(orbit_distance * 1.1, 1000.0)
		_update_camera()


func _update_camera() -> void:
	var dir := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch))
	camera.position = orbit_target + dir * orbit_distance
	camera.look_at(orbit_target)
