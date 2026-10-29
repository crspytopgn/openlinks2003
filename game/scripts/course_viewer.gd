extends Node3D
## Fly-around viewer for a course exported with `olcourse export`
## (see tools/olcourse). Choose the exported folder in the dialog, or pass it
## on the command line:  godot --path game -- --course=/path/to/export
##
## Right mouse drag: look.  WASD: move.  Q/E: down/up.  Shift: faster.
## N / P: next / previous hole tee.  O: overview.  L: load another course.
## Esc: back to the driving range.

const TILE_METRES := 6.0
const MOVE_SPEED := 40.0
const LOOK_SENSITIVITY := 0.004
const SETTINGS_PATH := "user://settings.cfg"

var camera: Camera3D
var label: Label
var course_root: Node3D
var holes: Array = []
var course_name := ""
var hole_index := -1
var yaw := 0.0
var pitch := -0.4
var looking := false
var overview_position := Vector3(0, 400, 600)
var overview_target := Vector3.ZERO


func _ready() -> void:
	_build_environment()
	var dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--course="):
			dir = arg.substr("--course=".length())
	if dir.is_empty():
		dir = _remembered_dir()
	if not dir.is_empty() and FileAccess.file_exists(dir.path_join("course.json")):
		_load_course(dir)
	else:
		_set_text("Choose a course folder made by `olcourse export` (it contains course.json).")
		_ask_for_folder()


func _build_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)

	camera = Camera3D.new()
	camera.near = 0.2
	camera.far = 8000.0
	add_child(camera)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	canvas.add_child(label)


func _remembered_dir() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	return str(cfg.get_value("viewer", "course_dir", ""))


func _remember_dir(dir: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("viewer", "course_dir", dir)
	cfg.save(SETTINGS_PATH)


func _ask_for_folder() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = "Choose an exported course folder"
	dialog.dir_selected.connect(_on_dir_selected)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)


func _on_dir_selected(dir: String) -> void:
	if not FileAccess.file_exists(dir.path_join("course.json")):
		_set_text("No course.json in %s. Run `olcourse export` first." % dir)
		return
	_remember_dir(dir)
	_load_course(dir)


func _load_course(dir: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("course.json")))
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_text("Could not read %s" % dir.path_join("course.json"))
		return
	var course: Dictionary = parsed
	var mesh := _load_terrain(dir.path_join("terrain.bin"), dir, course.get("materials", []))
	if mesh == null:
		_set_text("Could not read %s" % dir.path_join("terrain.bin"))
		return

	if course_root != null:
		course_root.queue_free()
	course_root = Node3D.new()
	add_child(course_root)
	var terrain := MeshInstance3D.new()
	terrain.mesh = mesh
	course_root.add_child(terrain)

	var billboards := _load_billboards(dir, course.get("billboards", []))
	var models_path := dir.path_join("models.bin")
	if FileAccess.file_exists(models_path):
		var models := CourseModels.read(FileAccess.get_file_as_bytes(models_path))
		if not models.is_empty():
			course_root.add_child(CourseModels.build(dir, models))

	course_name = str(course.get("name", "Course"))
	if billboards > 0:
		course_name += "  (%d trees and plants)" % billboards
	holes = course.get("holes", [])
	for hole in holes:
		_add_hole_markers(hole)

	var aabb := mesh.get_aabb()
	var centre := aabb.get_center()
	overview_position = centre + Vector3(0, maxf(aabb.size.x, aabb.size.z) * 0.6, aabb.size.z * 0.55)
	overview_target = centre
	_show_overview()


func _load_terrain(path: String, dir: String, materials: Array) -> ArrayMesh:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "OLTR" or f.get_32() != 1:
		return null
	var surfaces := f.get_32()
	var mesh := ArrayMesh.new()
	var cache := {}
	for _s in surfaces:
		var material_index := f.get_32()
		var vertex_count := f.get_32()
		var index_count := f.get_32()
		var positions := _read_vectors(f, vertex_count)
		var normals := _read_vectors(f, vertex_count)
		var indices := f.get_buffer(index_count * 4).to_int32_array()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var info: Dictionary = materials[material_index] if material_index < materials.size() else {}
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(info, dir, cache))
	return mesh


## Adds the course's trees, bushes and grass; returns how many were placed.
func _load_billboards(dir: String, types: Array) -> int:
	var path := dir.path_join("objects.bin")
	if types.is_empty() or not FileAccess.file_exists(path):
		return 0
	var placements := CourseBillboards.read_placements(FileAccess.get_file_as_bytes(path))
	if placements.is_empty():
		return 0
	course_root.add_child(CourseBillboards.build(dir, types, placements))
	var total := 0
	for p in placements:
		@warning_ignore("integer_division")
		total += p.size() / CourseBillboards.FLOATS_PER_PLACEMENT
	return total


func _read_vectors(f: FileAccess, count: int) -> PackedVector3Array:
	var floats := f.get_buffer(count * 12).to_float32_array()
	var out := PackedVector3Array()
	out.resize(count)
	for i in count:
		out[i] = Vector3(floats[3 * i], floats[3 * i + 1], floats[3 * i + 2])
	return out


## One material per terrain surface: the material's base texture, projected
## from above (the course's own texture mappings are not decoded yet).
func _material(info: Dictionary, dir: String, cache: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	var colour: Array = info.get("colour", [0.3, 0.5, 0.2])
	mat.albedo_color = Color(colour[0], colour[1], colour[2])
	var file := str(info.get("texture", ""))
	if not file.is_empty():
		if not cache.has(file):
			var image := Image.load_from_file(dir.path_join(file))
			if image != null and not image.is_empty():
				image.generate_mipmaps()
				cache[file] = ImageTexture.create_from_image(image)
			else:
				cache[file] = null
		var tex: Texture2D = cache[file]
		if tex != null:
			mat.albedo_texture = tex
			mat.albedo_color = Color.WHITE
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = true
			mat.uv1_scale = Vector3.ONE / TILE_METRES
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _add_hole_markers(hole: Dictionary) -> void:
	var tee_mat := StandardMaterial3D.new()
	tee_mat.albedo_color = Color(0.95, 0.95, 0.95)
	for tee in hole.get("tees", []):
		var box := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.4, 0.3, 0.4)
		box.mesh = cube
		box.material_override = tee_mat
		box.position = _vec(tee["position"]) + Vector3(0, 0.15, 0)
		course_root.add_child(box)

	var pins: Array = hole.get("pins", [])
	if pins.is_empty():
		return
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.9, 0.1, 0.1)
	flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pin := _vec(pins[0]["position"])
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 2.3
	pole.mesh = cyl
	pole.position = pin + Vector3(0, 1.15, 0)
	course_root.add_child(pole)
	var flag := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(0.6, 0.4, 0.02)
	flag.mesh = quad
	flag.material_override = flag_mat
	flag.position = pin + Vector3(0.3, 2.1, 0)
	course_root.add_child(flag)


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _show_overview() -> void:
	hole_index = -1
	camera.position = overview_position
	_look_at(overview_target)
	_set_text("%s\nOverview. N / P: hole tees, O: overview, right drag: look, WASD QE: fly, L: load course, Esc: back" % course_name)


func _show_hole(i: int) -> void:
	if holes.is_empty():
		return
	hole_index = posmod(i, holes.size())
	var hole: Dictionary = holes[hole_index]
	var tees: Array = hole.get("tees", [])
	if tees.is_empty():
		return
	var tee := _vec(tees[0]["position"])
	var aim: Array = hole.get("aim", [])
	var target := _vec(hole.get("green", [0, 0, 0]))
	if aim.size() > 1:
		target = _vec(aim[1])
	camera.position = tee + Vector3(0, 2.0, 0) - (target - tee).normalized() * 6.0
	_look_at(target + Vector3(0, 1.0, 0))
	_set_text("%s\nHole %d  %s   Par %d   %d yards   (hcp %d)" % [
		course_name, int(hole.get("number", hole_index + 1)), str(hole.get("name", "")),
		int(hole.get("par", 0)), int(tees[0].get("yards", 0)), int(hole.get("handicap", 0))])


func _look_at(target: Vector3) -> void:
	var d := (target - camera.position).normalized()
	yaw = atan2(-d.x, -d.z)
	pitch = asin(clampf(d.y, -1.0, 1.0))
	_apply_look()


func _apply_look() -> void:
	camera.rotation = Vector3(pitch, yaw, 0)


func _set_text(text: String) -> void:
	label.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and looking:
		yaw -= event.relative.x * LOOK_SENSITIVITY
		pitch = clampf(pitch - event.relative.y * LOOK_SENSITIVITY, -1.5, 1.5)
		_apply_look()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_N:
				_show_hole(hole_index + 1)
			KEY_P:
				_show_hole(hole_index - 1)
			KEY_O:
				if course_root != null:
					_show_overview()
			KEY_L:
				_ask_for_folder()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/main.tscn")


func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1
	if Input.is_key_pressed(KEY_S):
		move.z += 1
	if Input.is_key_pressed(KEY_A):
		move.x -= 1
	if Input.is_key_pressed(KEY_D):
		move.x += 1
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1
	if Input.is_key_pressed(KEY_E):
		move.y += 1
	if move == Vector3.ZERO:
		return
	var speed := MOVE_SPEED * (5.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	camera.position += camera.global_transform.basis * move.normalized() * speed * delta
