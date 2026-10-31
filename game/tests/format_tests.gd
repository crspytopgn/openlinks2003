extends RefCounted
## Checks for the GDScript format readers (game/scripts/formats), on
## synthetic data only; nothing from the original game. run_tests.gd calls
## run_all() and reports what it returns.

var failures: Array[String] = []


## Returns a description of each failed check.
func run_all() -> Array[String]:
	_test_scripts_compile()
	_test_arc0_and_btcv()
	_test_object_library()
	_test_model()
	_test_course_billboards()
	_test_course_models()
	_test_course_objects()
	_test_panorama()
	_test_d3f()
	_test_hud_art()
	_test_backdrop()
	_test_env_sound()
	_test_ambience_loop()
	return failures


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _test_scripts_compile() -> void:
	for path in ["res://scripts/object_viewer.gd", "res://scripts/assets/decoded_object_library.gd",
			"res://scripts/course_viewer.gd", "res://scripts/course/course_models.gd",
			"res://scripts/course/crz_course_loader.gd", "res://scripts/main.gd",
			"res://scripts/round_camera.gd", "res://scripts/ui/hud_art.gd", "res://scripts/ui/info_bar.gd",
			"res://scripts/ui/shot_panel.gd", "res://scripts/ui/shot_windows.gd", "res://scripts/data/d3f_font.gd",
			"res://scripts/audio/course_ambience.gd", "res://scripts/graphics/course_backdrop.gd"]:
		var script: GDScript = load(path)
		check(script != null and script.can_instantiate(), "%s compiles" % path)


func put_u16(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xff)
	b.append((v >> 8) & 0xff)


func put_u32(b: PackedByteArray, v: int) -> void:
	for i in 4:
		b.append((v >> (8 * i)) & 0xff)


func put_f32(b: PackedByteArray, v: float) -> void:
	var tmp := PackedByteArray()
	tmp.resize(4)
	tmp.encode_float(0, v)
	b.append_array(tmp)


func put_counted(b: PackedByteArray, s: String) -> void:
	put_u32(b, s.length() + 1)
	b.append_array(s.to_ascii_buffer())
	b.append(0)


## One-entry ARC0 archive around `payload`.
func make_arc0(entry_name: String, payload: PackedByteArray) -> PackedByteArray:
	var packed := payload.compress(FileAccess.COMPRESSION_DEFLATE)
	var b := PackedByteArray()
	b.append_array("ARC0".to_ascii_buffer())
	put_u32(b, 16 + packed.size() + 64)
	put_u32(b, 1)
	put_u32(b, 16 + packed.size())
	b.append_array(packed)
	put_u32(b, 0)
	var n := entry_name.to_ascii_buffer()
	n.resize(32)
	b.append_array(n)
	put_u32(b, 16)
	put_u32(b, packed.size())
	put_u32(b, payload.size())
	put_u32(b, 2)
	put_u32(b, 0)
	put_u32(b, 0)
	put_u32(b, 0)
	return b


## Block runs filling `blocks` blocks with one flat colour (B, G, R, A).
func flat_runs(blocks: int, bgra: Array) -> PackedByteArray:
	var b := PackedByteArray()
	put_u16(b, 0x4000 | blocks)
	for i in blocks:
		b.append_array(PackedByteArray(bgra))
	return b


func _test_arc0_and_btcv() -> void:
	# 70 x 6 image with one 64-pixel tile at the bottom left: red in tile rows
	# 0-59, blue in rows 60-63, so the image shows red on top and blue below.
	var btcv := PackedByteArray()
	btcv.append_array("BTCV".to_ascii_buffer())
	put_u16(btcv, 70)
	put_u16(btcv, 6)
	put_u16(btcv, 1)
	put_u16(btcv, 11)
	put_u32(btcv, 0)
	put_u32(btcv, 1)
	var runs := flat_runs(240, [0, 0, 255, 255])
	runs.append_array(flat_runs(16, [255, 0, 0, 255]))
	put_u16(btcv, 0)
	put_u16(btcv, 64)
	put_u16(btcv, 0)
	put_u16(btcv, 0)
	put_u32(btcv, 36)
	put_u32(btcv, runs.size())
	btcv.append_array(runs)

	var arc := Arc0.from_bytes(make_arc0("Sample A.btc", btcv))
	check(arc != null and arc.entries.size() == 1, "ARC0 header")
	if arc == null:
		return
	check(arc.find("sample a.BTC") == 0, "ARC0 find ignores case")
	var img := Btcv.decode(arc.read(0))
	check(img != null, "BTCV decodes")
	if img == null:
		return
	check(img.get_width() == 70 and img.get_height() == 6, "BTCV size")
	check(img.get_pixel(0, 1).r > 0.9 and img.get_pixel(0, 1).b < 0.1, "BTCV tile row 59 is red")
	check(img.get_pixel(3, 5).b > 0.9 and img.get_pixel(3, 5).r < 0.1, "BTCV tile row 63 is blue")
	check(img.get_pixel(67, 2).a < 0.01, "BTCV uncovered area is transparent")


func _test_object_library() -> void:
	var b := PackedByteArray()
	put_u32(b, 5)
	put_u32(b, 1)
	put_counted(b, "Rocks")
	put_u32(b, 1)
	put_counted(b, "Rocks000.btx")
	put_counted(b, "Rocks\\Rocks000.btx")
	put_u32(b, 1)
	for f in [25.0, 2.0, 6.0, 0.0, 150.0, 241.0, 0.0, 0.5, 0.0]:
		put_f32(b, f)
	put_u32(b, 0x84247be0)
	put_u32(b, 0)
	put_u32(b, 1)
	for i in 6:
		put_f32(b, 1.0)
	var lib := ObjectCatalog.from_bytes(b)
	check(lib != null and lib.categories.size() == 1, "OBJECT.LIB parses")
	if lib == null:
		return
	var o := lib.find_id(0x84247be0)
	check(o.get("path", "") == "Rocks\\Rocks000.btx", "OBJECT.LIB object path")
	check(is_equal_approx(ObjectCatalog.default_height_m(o), 4.0 * 0.3048), "billboard default height")


func _test_model() -> void:
	# A 10 x 5 inch quad with one 4 x 4 texture (four levels).
	var tex := PackedByteArray()
	put_u32(tex, 0)
	for level in 4:
		put_u32(tex, 4)
		put_u32(tex, 4)
		tex.append_array(flat_runs(1, [0, 255, 0, 255]))
	var textures := XyzModel.read_textures(make_arc0("Textures", tex))
	check(textures.size() == 1, "CMF has one texture")

	var x := PackedByteArray()
	x.resize(0xa4)
	for p in [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 5, 0), Vector3(0, 5, 0)]:
		put_f32(x, p.x)
		put_f32(x, p.y)
		put_f32(x, p.z)
	var uv_at := x.size()
	for uv in [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]:
		put_f32(x, uv.x)
		put_f32(x, uv.y)
	var face_at := x.size()
	put_u16(x, 4)
	put_u16(x, 0)
	put_u16(x, 0)
	put_u16(x, 0)
	put_u32(x, 0)
	var corner_at := x.size()
	for i in 4:
		put_u16(x, i)
	var mat_at := x.size()
	x.resize(x.size() + 16)
	x.encode_u32(0, x.size())
	var tables := [[4, 0xa4], [4, uv_at], [1, face_at], [4, corner_at], [1, mat_at]]
	for i in 5:
		x.encode_u32(0x18 + 8 * i, tables[i][0])
		x.encode_u32(0x1c + 8 * i, tables[i][1])
	x.encode_u32(0x40, 1)
	var mesh := XyzModel.build_mesh(x, textures)
	check(mesh != null and mesh.get_surface_count() == 1, "XYZ builds a mesh")
	if mesh == null:
		return
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(verts.size() == 6, "quad becomes two triangles")
	var top := 0.0
	for v in verts:
		top = maxf(top, v.y)
	check(is_equal_approx(top, 5.0 * XyzModel.INCH), "XYZ units are inches")


func _test_course_billboards() -> void:
	# objects.bin as `olcourse export` writes it: two types, the second
	# with three placements in two chunks.
	var b := PackedByteArray()
	b.append_array("OLOB".to_ascii_buffer())
	put_u32(b, 1)
	put_u32(b, 2)
	put_u32(b, 0)
	put_u32(b, 3)
	for v in [10.0, 1.0, -20.0, 0.5, 30.0, 2.0, -40.0, 0.4, 250.0, 3.0, 5.0, 20.0]:
		put_f32(b, v)
	var placements := CourseBillboards.read_placements(b)
	check(placements.size() == 2, "billboards: two types")
	if placements.size() != 2:
		return
	check(placements[0].is_empty() and placements[1].size() == 12, "billboards: placement counts")
	check(is_equal_approx(placements[1][8], 250.0) and is_equal_approx(placements[1][11], 20.0), "billboards: values")
	check(CourseBillboards.read_placements(b.slice(0, b.size() - 4)).is_empty(), "billboards: truncated data rejected")

	var types := [{"name": "Grass", "texture": "", "aspect": 1.5}, {"name": "Tree", "texture": "", "aspect": 0.5}]
	var root := CourseBillboards.build("res://does-not-exist", types, placements)
	check(root.get_child_count() == 2, "billboards: one MultiMesh per chunk")
	# The headless test run has no real renderer, so check the buffer the
	# MultiMesh is given rather than reading instances back.
	var instances := 0
	for child in root.get_children():
		instances += (child as MultiMeshInstance3D).multimesh.instance_count
	check(instances == 3, "billboards: every placement drawn")
	var far := root.get_child(1) as MultiMeshInstance3D
	var first := root.get_child(0) as MultiMeshInstance3D
	check(first.position.distance_to(Vector3(50, 1.5, -50)) < 0.01, "billboards: chunk centre")
	var buffer := CourseBillboards.instance_buffer(placements[1], [0, 4], first.position)
	check(buffer.size() == 24, "billboards: 12 floats per instance")
	check(is_equal_approx(buffer[0], 0.5) and is_equal_approx(buffer[5], 0.5) and is_equal_approx(buffer[10], 0.5),
			"billboards: scaled by height")
	var world := first.position + Vector3(buffer[3], buffer[7], buffer[11])
	check(world.distance_to(Vector3(10, 1, -20)) < 0.01, "billboards: chunk offset restored")
	check(is_equal_approx(buffer[12 + 5], 0.4), "billboards: second instance height")
	check(is_zero_approx(far.visibility_range_end), "billboards: tall chunk always drawn")
	check(is_equal_approx(first.visibility_range_end, 150.0), "billboards: small chunk culled with distance")
	root.free()


func _test_course_models() -> void:
	# models.bin as `olcourse export` writes it: one model with one
	# triangle, placed twice.
	var b := PackedByteArray()
	b.append_array("OLMD".to_ascii_buffer())
	put_u32(b, 1)
	put_u32(b, 1)
	put_u32(b, 1)
	var tex := "textures/models/none.tga".to_ascii_buffer()
	put_u32(b, tex.size())
	b.append_array(tex)
	put_u32(b, 3)
	for v in [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]:
		put_f32(b, v)
	for v in [0.0, 0.0, 1.0, 0.0, 0.0, 1.0]:
		put_f32(b, v)
	put_u32(b, 3)
	for i in [0, 1, 2]:
		put_u32(b, i)
	put_u32(b, 2)
	for origin_x in [10.0, 20.0]:
		put_u32(b, 0)
		for v in [0.5, 0.0, 0.0, origin_x, 0.0, 0.5, 0.0, 3.0, 0.0, 0.0, 0.5, -4.0]:
			put_f32(b, v)
	var data := CourseModels.read(b)
	check(not data.is_empty(), "models: reads")
	if data.is_empty():
		return
	var meshes: Array = data["meshes"]
	var placements: Array = data["placements"]
	check(meshes.size() == 1 and (meshes[0] as Array).size() == 1, "models: one mesh, one surface")
	check(placements.size() == 2, "models: two placements")
	var t: Transform3D = placements[1]["transform"]
	check(t.origin.distance_to(Vector3(20, 3, -4)) < 1e-4 and is_equal_approx(t.basis.get_scale().x, 0.5), "models: transform")
	check(CourseModels.read(b.slice(0, b.size() - 8)).is_empty(), "models: truncated data rejected")
	var root := CourseModels.build("res://does-not-exist", data)
	check(root.get_child_count() == 2, "models: one node per placement")
	var node := root.get_child(0) as MeshInstance3D
	check(node.mesh.get_surface_count() == 1, "models: mesh built")
	check(is_equal_approx(node.position.x, 10.0), "models: placed")
	root.free()


## A `MasterObj` with one type, "Tall Trees001", aspect 0.5.
func _master_obj() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(0xE0)
	b.fill(0)
	b.encode_u32(0, 0xE0)
	b.encode_u32(4, 0x80)
	b.encode_u32(8, 1)
	b.encode_u32(12, 0x40)
	b.encode_u32(0x40, 0x50)  # type table -> type record
	b.encode_u32(0x50, 64)
	b.encode_u32(0x54, 128)
	b.encode_u32(0x58, 1)  # one level
	b.encode_u32(0x5C, 0x90)  # level list
	b.encode_float(0x50 + 0x18, 0.5)
	b.encode_u32(0x98, 0xA0)  # level -> sprite descriptor width field
	b.encode_u32(0xA0 + 12, 0xC0)  # first tile record
	var name := "Tall Trees001A.btc".to_ascii_buffer()
	for i in name.size():
		b[0xC0 + i] = name[i]
	return b


func _test_course_objects() -> void:
	# 2DPlant: one cell at (64, 128) ft, base 10 ft, then a second cell.
	var plant := PackedByteArray()
	plant.append_array("2JBO".to_ascii_buffer())
	put_u32(plant, 2)
	put_u32(plant, 3)
	while plant.size() < 0x40:
		plant.append(0)
	put_u16(plant, 0xFFFF)
	for v in [64.0, 128.0, 10.0]:
		put_f32(plant, v)
	put_u16(plant, 0)
	put_u32(plant, 5 | 0x20000000 | 0x40000000)  # both extra fields
	plant.append(7)
	put_u16(plant, 99)
	for v in [16, 32, 0x10000 - 16, 160]:  # x 1 ft, y 2 ft, z -1 ft, height 10 ft
		put_u16(plant, v)
	put_u16(plant, 0)
	put_u32(plant, 6)
	for v in [0, 0, 0, 8]:
		put_u16(plant, v)
	put_u16(plant, 0xFFFF)
	for v in [0.0, 0.0, 0.0]:
		put_f32(plant, v)
	put_u16(plant, 0)
	put_u32(plant, 7)
	for v in [160, 0, 0, 320]:
		put_u16(plant, v)
	var placed := CourseObjects.parse_billboard_placements(plant)
	check(not placed.is_empty(), "objects: 2DPlant parses")
	if placed.is_empty():
		return
	var xyzh: PackedFloat32Array = placed.xyzh
	check(xyzh.size() == 12, "objects: three placements")
	var f := CourseObjects.FEET
	check(Vector3(xyzh[0], xyzh[1], xyzh[2]).distance_to(Vector3(65, 9, -130) * f) < 1e-4, "objects: placement in Godot metres")
	check(is_equal_approx(xyzh[3], 10 * f), "objects: placement height")
	check(CourseObjects.parse_billboard_placements(plant.slice(0, plant.size() - 2)).is_empty(), "objects: truncated 2DPlant rejected")

	var types := CourseObjects.parse_billboard_types(_master_obj())
	check(types.size() == 1 and types[0].name == "Tall Trees001" and types[0].sprite == "Tall Trees001A.btc", "objects: MasterObj type name")
	check(types.size() == 1 and is_equal_approx(types[0].aspect, 0.5), "objects: MasterObj aspect")

	# TrnyPlant: a cell, then a spectator with an extra byte.
	var crowd := PackedByteArray()
	put_u32(crowd, 2)
	put_u32(crowd, 1)
	while crowd.size() < 0x40:
		crowd.append(0)
	crowd.append(0xFF)
	for v in [64.0, 0.0, 0.0]:
		put_f32(crowd, v)
	crowd.append(1)
	put_u32(crowd, 3 | 0x20000000)
	crowd.append(9)
	for v in [16, 16, 0]:
		put_u16(crowd, v)
	var people := CourseObjects.parse_crowd_placements(crowd)
	check(not people.is_empty() and people.kind[0] == 1 and people.instance[0] == 3, "objects: TrnyPlant kind and instance")
	check(not people.is_empty() and is_equal_approx(people.xyz[0], 65 * f), "objects: TrnyPlant position")

	# place_point: scale, z offset, then a quarter turn about z.
	var p := {"position": Vector3(100, 200, 5), "z_offset": 2.0, "scale": Vector3(2, 2, 2), "yaw": PI / 2, "pitch": 0.0}
	check(CourseObjects.place_point(p, Vector3(1, 0, 0)).distance_to(Vector3(100, 202, 9)) < 1e-4, "objects: place_point")

	# .maq: one 2x1 level, colour 1 is blue 10, green 20, red 30.
	var maq := PackedByteArray()
	maq.resize(16 + 36 + 1024 + 2)
	maq.fill(0)
	maq.encode_u32(4, 1)
	maq.encode_u32(8, 1)
	maq.encode_u32(12, 16)
	maq.encode_u32(16, 2)
	maq.encode_u32(20, 1)
	maq.encode_u32(24, 8)
	maq.encode_u32(16 + 28, 52)
	maq.encode_u32(16 + 32, 52 + 1024)
	for i in 4:
		maq[52 + 4 + i] = [10, 20, 30, 255][i]
	maq[52 + 1024] = 1
	var img := CourseObjects.decode_maq(maq, 0)
	check(img != null and img.get_size() == Vector2i(2, 1), "objects: maq size")
	if img != null:
		var c := img.get_pixel(0, 0)
		check(c.r8 == 30 and c.g8 == 20 and c.b8 == 10, "objects: maq palette is BGRA")

	check(CourseObjects.plant_shape("Tall Trees212") == 1 and CourseObjects.plant_shape("Evergreens004") == 2, "objects: tree shapes")
	check(CourseObjects.plant_shape("Bushes156") == 3 and CourseObjects.plant_shape("Rocks027") == 4, "objects: bush and rock shapes")
	check(CourseObjects.plant_shape("Grasses113") == 0, "objects: grass lets the ball through")
	check(CourseObjects.height_class(0.3) == 0 and CourseObjects.height_class(10.0) == 3, "objects: height classes")

	# The whole thing from an archive with no sprites: all three placements
	# are the tree type.
	var entries := {"masterobj": _master_obj(), "2dplant": plant}
	var read := func(n: String) -> PackedByteArray: return entries.get(n.to_lower(), PackedByteArray())
	var decoded := CourseObjects.decode(read)
	check(not decoded.is_empty(), "objects: decode")
	if decoded.is_empty():
		return
	var objects := CourseObjects.build(read, decoded)
	# The 0.15 m plant (height 8/16 ft) is too small to stop the ball; the
	# other two each get a trunk and a canopy.
	check(objects.obstacles.size() == 4, "objects: trunk and canopy per tree (%d)" % objects.obstacles.size())
	var base := Vector3(xyzh[0], xyzh[1], xyzh[2])
	var hit := objects.obstacles.segment_hit(base + Vector3(0, 0.5, -3), base + Vector3(0, 0.5, 3))
	check(not hit.is_empty() and int(hit.kind) == ObstacleField.Kind.SOLID, "objects: trunk blocks the ball")
	hit = objects.obstacles.segment_hit(base + Vector3(0, 2.5, -3), base + Vector3(0, 2.5, 3))
	check(not hit.is_empty() and int(hit.kind) == ObstacleField.Kind.CANOPY, "objects: canopy higher up")

	var hole := HoleData.new()
	hole.tee = base
	hole.pin = base + Vector3(0, 0, 50)
	var root := objects.build_visual(hole)
	var instances := 0
	var tall: MultiMeshInstance3D = null
	for child in root.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null:
			instances += mmi.multimesh.instance_count
			if is_zero_approx(mmi.visibility_range_end):
				tall = mmi
	check(instances == 3, "objects: every placement drawn (%d)" % instances)
	check(tall != null, "objects: the 20 ft tree is always drawn")
	if tall != null:
		# The headless renderer keeps no MultiMesh data; check the buffer built.
		var buffer: PackedFloat32Array = tall.multimesh.get_meta("buffer")
		check(buffer.size() == 16, "objects: 16 floats per instance")
		check(is_equal_approx(buffer[5], 20 * f) and is_equal_approx(buffer[0], 10 * f), "objects: scaled by height and aspect")
		var rect := objects.plants.rects
		check(is_equal_approx(buffer[12], rect[0]) and is_equal_approx(buffer[15], rect[3]), "objects: atlas rectangle as custom data")
		var world := tall.position + Vector3(buffer[3], buffer[7], buffer[11])
		check(world.distance_to(Vector3(10 * f, 0, 0)) < 1e-3, "objects: chunk offset restored")
	root.free()

	# With 3D trees on, the two trees taller than 3 m become 3D trees (full
	# and impostor) and the small plant stays a billboard.
	check(CourseObjects.tree_species("Tall Trees212") == TreeFactory.Species.BROADLEAF and CourseObjects.tree_species("Evergreens004") == TreeFactory.Species.PINE, "objects: tree species")
	check(CourseObjects.tree_species("Palm Trees010") == -1 and CourseObjects.tree_species("Bushes001") == -1, "objects: palms and bushes keep their billboards")
	TreeFactory.level = 2
	root = objects.build_visual(hole)
	var billboards := 0
	var full := 0
	var impostors := 0
	for child in root.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null:
			continue
		if mmi.multimesh.mesh is QuadMesh and mmi.multimesh.use_custom_data and mmi.multimesh.mesh.material is ShaderMaterial and (mmi.multimesh.mesh.material as ShaderMaterial).shader == TreeFactory.IMPOSTOR_SHADER:
			impostors += mmi.multimesh.instance_count
			check(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "objects: impostors cast no shadow")
		elif mmi.multimesh.mesh is ArrayMesh:
			full += mmi.multimesh.instance_count
			check(mmi.visibility_range_end > TreeFactory.impostor_distance(), "objects: full trees hidden past the impostor distance")
		else:
			billboards += mmi.multimesh.instance_count
	check(billboards == 1 and full == 2 and impostors == 2, "objects: 3D trees in place of tree billboards (%d, %d, %d)" % [billboards, full, impostors])
	check(objects.obstacles.size() == 4, "objects: 3D trees keep the billboards' obstacles")
	root.free()
	TreeFactory.level = 0
	root = objects.build_visual(hole)
	instances = 0
	for child in root.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null:
			instances += mmi.multimesh.instance_count
	check(instances == 3, "objects: billboards back with 3D trees off (%d)" % instances)
	root.free()


## Mirrors test_panorama_tiles in libs/olcore/tests/test_main.cpp.
func _test_panorama() -> void:
	check(LinksPanorama.row_sizes(720) == PackedInt32Array([256, 256, 256]), "panorama rows for 720")
	check(LinksPanorama.row_sizes(320) == PackedInt32Array([256, 64]), "panorama rows for 320")
	check(LinksPanorama.row_sizes(260) == PackedInt32Array([256, 4]), "panorama rows for 260")
	var d := PackedByteArray("nap".to_ascii_buffer())
	d.append(0)
	put_u32(d, 70)
	put_u32(d, 260)
	put_u32(d, 1)
	put_u32(d, 2)
	var runs := PackedByteArray()
	put_u16(runs, 0x4000)  # 4096 flat blocks
	for i in 4096:
		runs.append_array(PackedByteArray([0, 0, 255, 255]))  # B, G, R, A: red
	d.append_array("desu".to_ascii_buffer())
	put_u32(d, runs.size())
	d.append_array(runs)
	for c in 18:
		if c == 2:
			d.append_array("desu".to_ascii_buffer())
			put_u32(d, 6)
			put_u16(d, 0x4001)
			d.append_array(PackedByteArray([255, 0, 0, 255]))  # blue
		else:
			d.append_array("tpme".to_ascii_buffer())
	check(LinksPanorama.is_panorama(d) and not LinksPanorama.is_sky(d), "panorama tag")
	var img := LinksPanorama.decode(d)
	check(img != null and img.get_width() == 70 and img.get_height() == 260, "panorama size")
	if img != null:
		check(img.get_pixel(69, 255).r > 0.99 and img.get_pixel(69, 255).a > 0.99, "panorama big tile")
		check(img.get_pixel(9, 258).b > 0.99 and img.get_pixel(9, 258).a > 0.99, "panorama small tile")
		check(img.get_pixel(4, 258).a < 0.01, "panorama empty tile")
	d.append(0)
	check(LinksPanorama.decode(d) == null, "panorama with trailing bytes")


## LZW codes for `data` as plain literals, with a clear code often enough
## that the codes stay 9 bits wide.
func lzw_literals(data: PackedByteArray) -> PackedByteArray:
	var codes := PackedInt32Array([256])
	var since_clear := 0
	for b in data:
		if since_clear == 250:
			codes.append(256)
			since_clear = 0
		codes.append(b)
		since_clear += 1
	codes.append(257)
	var out := PackedByteArray()
	var acc := 0
	var bits := 0
	for c in codes:
		acc |= c << bits
		bits += 9
		while bits >= 8:
			out.append(acc & 0xff)
			acc >>= 8
			bits -= 8
	if bits > 0:
		out.append(acc & 0xff)
	return out


## Mirrors d3f_font() and test_d3f in libs/olcore/tests/test_main.cpp.
func d3f_font(colour: bool) -> PackedByteArray:
	var f := PackedByteArray()
	f.resize(0x55 + 6 * 256)
	f[0] = 0x44
	f[1] = 0x33
	f[2] = 0x46
	f[3] = 0xd4 if colour else 0xb4
	var face := "Arial".to_ascii_buffer()
	for i in face.size():
		f[4 + i] = face[i]
	f.encode_s32(0x44, -11)
	f[0x48] = 1
	f.encode_s32(0x49, 700)
	f.encode_s32(0x4d, 1)
	f.encode_s32(0x51, 10)
	var h := 0x48  # "H"
	f[0x55 + 256 + h] = 2
	f[0x55 + 512 + h] = 3
	f[0x55 + 768 + h] = 4
	f[0x55 + 1024 + h] = 0xff  # left -1
	f[0x55 + 1280 + h] = 2
	var bpp := 4 if colour else 1
	var px := PackedByteArray()
	px.resize(16 * 16 * bpp)
	for y in range(3, 10):
		for x in range(2, 6):
			var p := (y * 16 + x) * bpp
			if colour:
				px[p] = 10
				px[p + 1] = 20
				px[p + 2] = 30
				px[p + 3] = 200
			else:
				px[p] = 255
	var packed := lzw_literals(px.slice(0, px.size() - 40))
	put_u32(f, f.size() + 4)
	put_u32(f, -16 & 0xffffffff)
	put_u32(f, packed.size())
	f.append_array(packed)
	return f


func _test_d3f() -> void:
	var b := d3f_font(false)
	check(D3fFont.is_d3f(b), "d3f magic")
	var f := D3fFont.read(b)
	check(f != null, "d3f reads")
	if f == null:
		return
	check(f.face == "Arial" and f.pixel_height == 11 and f.italic and f.weight == 700 and f.line_height == 10, "d3f header")
	check(not f.colour and f.pages.size() == 1 and f.pages[0].get_width() == 16, "d3f page")
	check(f.glyphs[0x48] == PackedInt32Array([0, 2, 3, 4, -1, 2]), "d3f glyph")
	check(f.glyphs[0x41][3] == 0, "d3f missing glyph")
	check(f.pages[0].get_pixel(2, 3).a8 == 255 and f.pages[0].get_pixel(2, 3).r8 == 255, "d3f coverage pixel")
	check(f.pages[0].get_pixel(2, 2).a8 == 0, "d3f empty pixel")
	check(f.ascent() == 7, "d3f ascent")
	var font := f.to_font()
	check(font.fixed_size == 11, "d3f font size")
	# Advance per H: left -1 + width 4 + right 2.
	check(is_equal_approx(font.get_string_size("HH", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, 10.0), "d3f advance")
	check(D3fFont.char_of(0x80) == 0x20ac and D3fFont.char_of(0xe9) == 0xe9, "d3f code page")

	var c := D3fFont.read(d3f_font(true))
	check(c != null and c.colour, "d3f colour")
	if c != null:
		var p := c.pages[0].get_pixel(3, 4)
		check(p.r8 == 30 and p.g8 == 20 and p.b8 == 10 and p.a8 == 200, "d3f BGRA to RGBA")
	var bad := b.duplicate()
	bad.encode_s32(0x55 + 6 * 256, 999999)
	check(D3fFont.read(bad) == null, "d3f bad page offset")
	check(not D3fFont.is_d3f(b.slice(0, 40)), "d3f too short")


func _test_hud_art() -> void:
	check(HudArt.club_kind("Driver", false) == 0 and HudArt.club_kind("3 Wood", false) == 0, "club kind wood")
	check(HudArt.club_kind("7 Iron", false) == 1 and HudArt.club_kind("Sand Wedge", false) == 1, "club kind iron")
	check(HudArt.club_kind("Putter", true) == 2, "club kind putter")
	check(HudArt.elevation_index(0.0) == 6, "elevation level")
	check(HudArt.elevation_index(100.0) == 0 and HudArt.elevation_index(-100.0) == 12, "elevation ends")
	check(HudArt.elevation_index(3.05) == 4, "elevation 10 ft up")
	# The panels draw with no textures at all.
	var art := HudArt.new()
	var panel := ShotPanel.new(art)
	var windows := ShotWindows.new(art)
	check(panel.size.y > 100.0 and windows.size.x > 100.0, "classic panels size")
	panel.free()
	windows.free()


func _test_backdrop() -> void:
	var img := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.2))
	var band := CourseBackdrop._band(img, 100.0, 0.5, 0.0, -1)
	check(band.mesh.get_surface_count() == 1, "backdrop band pieces")
	var aabb := band.mesh.get_aabb()
	# 64 pixels round a 100 m circle: 16 rows are 16 * TAU * 100 / 64 high,
	# half above eye level.
	var h := 16.0 * TAU * 100.0 / 64.0
	check(absf(aabb.end.y - h * 0.5) < 0.01 and absf(aabb.position.y + h * 0.5) < 0.01, "backdrop band height")
	band.free()
	var mean := CourseBackdrop._row_mean(img, 0, 4)
	# RGBA8 rounds 0.5 to 128/255.
	check(absf(mean.r - 0.2) < 0.01 and absf(mean.g - 0.5) < 0.01 and absf(mean.b - 0.2) < 0.01, "backdrop colour")


func _test_env_sound() -> void:
	var b := PackedByteArray()
	put_u32(b, 2)
	put_counted(b, "Birds")
	put_u32(b, 0)
	put_u32(b, 2)
	put_counted(b, "a.wav")
	put_counted(b, "b.wav")
	put_counted(b, "Crow")
	put_u32(b, 1)
	put_u32(b, 1)
	put_counted(b, "c.wav")
	put_u32(b, 2)
	for e in [[0, 100.0, 200.0, 30.0, 29997.0], [1, -50.0, 0.0, 10.0, 29994.0]]:
		put_u32(b, e[0])
		for v in [e[1], e[2], e[3], e[4], 75.0, 0.2, 0.0, 0.0]:
			put_f32(b, v)
	var parsed := CourseAmbience.parse_env_sound(b)
	check(not parsed.is_empty(), "EnvSound parses")
	if parsed.is_empty():
		return
	check(parsed.defs.size() == 2 and parsed.defs[0].files == PackedStringArray(["a.wav", "b.wav"]), "EnvSound kinds")
	check(parsed.emitters.size() == 2 and parsed.emitters[0].looping and not parsed.emitters[1].looping, "EnvSound loops")
	var p: Vector3 = parsed.emitters[0].position
	check(p.is_equal_approx(Vector3(100.0, 30.0, -200.0) * 0.3048), "EnvSound position")


func _test_ambience_loop() -> void:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 100
	var data := PackedByteArray()
	data.resize(1000 * 2)
	for i in 1000:
		data.encode_s16(i * 2, 1000 if i < 900 else -1000)
	s.data = data
	CourseAmbience.make_loop(s, 1.0)
	check(s.data.size() == 900 * 2 and s.loop_mode == AudioStreamWAV.LOOP_FORWARD and s.loop_end == 900, "ambience loop length")
	check(s.data.decode_s16(0) == -1000 and s.data.decode_s16(99 * 2) > 900, "ambience crossfade")
