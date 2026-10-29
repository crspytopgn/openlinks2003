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
	return failures


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _test_scripts_compile() -> void:
	for path in ["res://scripts/object_viewer.gd", "res://scripts/assets/decoded_object_library.gd",
			"res://scripts/course_viewer.gd"]:
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
	var instances := 0
	for child in root.get_children():
		var node := child as MultiMeshInstance3D
		instances += node.multimesh.instance_count
		var t := node.multimesh.get_instance_transform(0)
		check(is_equal_approx(t.basis.get_scale().y, 0.5) or is_equal_approx(t.basis.get_scale().y, 20.0) \
				or is_equal_approx(t.basis.get_scale().y, 0.4), "billboards: scaled by height")
	check(instances == 3, "billboards: every placement drawn")
	var far := root.get_child(1) as MultiMeshInstance3D
	var first := root.get_child(0) as MultiMeshInstance3D
	var world := first.position + first.multimesh.get_instance_transform(0).origin
	check(world.distance_to(Vector3(10, 1, -20)) < 0.01, "billboards: chunk offset restored")
	check(is_zero_approx(far.visibility_range_end), "billboards: tall chunk always drawn")
	check(is_equal_approx(first.visibility_range_end, 150.0), "billboards: small chunk culled with distance")
	root.free()
