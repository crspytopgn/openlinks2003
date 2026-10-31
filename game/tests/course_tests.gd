extends RefCounted
## Checks for the course reader (Bunky, CrzArchive, CrzCourseLoader and
## CrzTerrain) on synthetic data only; nothing from the original game. The
## cipher uses made-up tables, and the expected ciphertexts are the ones
## libs/olcore/tests/test_course.cpp checks, so the port and the C++ agree.
## run_tests.gd calls run_all() and reports what it returns.

const TEST_COURSE := "user://test_course.crz"

var failures: Array[String] = []


func run_all() -> Array[String]:
	_test_scripts_compile()
	_test_bunky_known_answers()
	_test_bunky_round_trips()
	_test_locked_archive()
	_test_terrain()
	_test_mappings()
	_test_shadow_file()
	_test_holes_and_ground()
	_test_terrain_types_and_bounds()
	_test_community_courses()
	return failures


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _test_scripts_compile() -> void:
	for path in ["res://scripts/course/crz_course_loader.gd", "res://scripts/course/crz_terrain.gd",
			"res://scripts/course/terrain_mappings.gd", "res://scripts/course/shadow_file.gd", "res://scripts/course/course_areas.gd",
			"res://scripts/course_viewer.gd", "res://scripts/course/community_courses.gd", "res://scripts/boot.gd"]:
		var script: GDScript = load(path)
		check(script != null and script.can_instantiate(), "%s compiles" % path)


## Linear congruential fill, with the pi words the table finder looks for.
static func test_tables() -> PackedInt64Array:
	var t := PackedInt64Array()
	t.resize(Bunky.P_WORDS + Bunky.S_WORDS)
	var x := 1
	for i in t.size():
		x = (x * 1664525 + 1013904223) & 0xFFFFFFFF
		t[i] = x
	t[5] = 0x299f31d0
	t[6] = 0x082efa98
	t[7] = 0xec4e6c89
	return t


static func counting(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	for i in n:
		b.append(i & 0xFF)
	return b


func _test_bunky_known_answers() -> void:
	var t := test_tables()
	var cases := [
		["OpenLnk!", 7, 4, 40, "1c6f2d9cf1ab7c5a4fd244562a76aa58466aa1fdab90f4ef4a49429b7e579833ab88ff458adeb82e"],
		["OpenLnk!", 8, 32, 13, "1c52a1e1931db3d85453ff45c9"],
		["abc", 3, 8, 8, "f93bd2541156ccc9"],
		["abc", 3, 8, 5, "8ee248073f"],
		["Z", 1, 4, 1, "02"],
	]
	for c in cases:
		var key := (c[0] as String).to_ascii_buffer().slice(0, c[1])
		var cipher := Bunky.new(t, key, c[2])
		var encrypted := cipher.encrypt(counting(c[3]))
		check(encrypted.hex_encode() == c[4], "bunky %s/%d rounds/%d bytes: %s" % [c[0], c[2], c[3], encrypted.hex_encode()])
		check(cipher.decrypt(encrypted) == counting(c[3]), "bunky %s/%d bytes decrypts" % [c[0], c[3]])


func _test_bunky_round_trips() -> void:
	var cipher := Bunky.new(test_tables(), PackedByteArray([1, 2, 3, 4, 5, 6, 7]), 4)
	for n in range(1, 40):
		var e := cipher.encrypt(counting(n))
		check(e != counting(n) and cipher.decrypt(e) == counting(n), "bunky round trip %d bytes" % n)


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


## A locked archive laid out the way the game does it, with a `copyright`
## entry that holds the course key and a locked entry that uses it; plus a
## fake executable holding the tables and the key. Mirrors make_fixture() in
## libs/olcore/tests/test_course.cpp.
func _test_locked_archive() -> void:
	var tables := test_tables()
	var archive_key := PackedByteArray([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x00])
	var exe := PackedByteArray()
	exe.resize(100)
	exe.fill(0x90)
	for w in tables:
		put_u32(exe, w)
	# A decoy pair once, then the real key twice.
	exe.append_array(PackedByteArray([0x68, 1, 2, 3, 4, 0x68, 5, 6, 7, 8]))
	for _i in 2:
		exe.append(0x68)
		exe.append_array(archive_key.slice(4, 8))
		exe.append(0x68)
		exe.append_array(archive_key.slice(0, 4))
		exe.append(0xc3)

	var course_key := PackedByteArray([9, 8, 7, 6, 5, 4, 3, 2])
	var copyright := PackedByteArray()
	copyright.resize(0x34)
	for i in 8:
		copyright[0x2c + i] = course_key[i]
	var locked_copyright := Bunky.new(tables, archive_key.slice(0, 7), 4).encrypt(copyright)
	var secret := "terrain data".to_ascii_buffer()
	var locked_secret := Bunky.new(tables, course_key.slice(0, 7), 4).encrypt(secret)
	var entries := [
		["newformat", "V.2.0".to_ascii_buffer(), 5, false],
		["copyright", locked_copyright, 0x34, true],
		["vertex", locked_secret, secret.size(), true],
	]
	var body := PackedByteArray()
	body.resize(16)
	var dir := PackedByteArray()
	for e in entries:
		put_u32(dir, 0)
		var entry_name := (e[0] as String).to_ascii_buffer()
		entry_name.resize(32)
		dir.append_array(entry_name)
		put_u32(dir, body.size())
		put_u32(dir, (e[1] as PackedByteArray).size())
		put_u32(dir, e[2])
		put_u32(dir, 0)  # stored
		put_u32(dir, 0)  # no checksum
		put_u32(dir, 1 if e[3] else 0)
		put_u32(dir, 0)
		body.append_array(e[1])
	var dir_offset := body.size()
	var dir_cipher := Bunky.new(tables, archive_key, 32)
	body.append_array(dir_cipher.encrypt(dir))
	var head := "ARC0".to_ascii_buffer()
	put_u32(head, body.size())
	put_u32(head, entries.size())
	put_u32(head, dir_offset)
	head = dir_cipher.encrypt(head)
	for i in 16:
		body[i] = head[i]
	var f := FileAccess.open(TEST_COURSE, FileAccess.WRITE)
	f.store_buffer(body)
	f = null

	check(CrzArchive.find_tables(exe) == tables, "finds the cipher tables")
	var keys := CrzArchive.find_keys(exe, TEST_COURSE)
	check(not keys.is_empty() and keys.key == archive_key, "finds the archive key")
	if keys.is_empty():
		return
	var a := CrzArchive.open(TEST_COURSE, keys)
	check(a != null, "opens the locked archive")
	if a == null:
		return
	check(a.entries.size() == 3 and a.entries[2].locked, "reads the locked directory")
	check(a.read_named("vertex").get_string_from_ascii() == "terrain data", "reads an entry locked with the course key")
	check(a.read_named("NEWFORMAT").get_string_from_ascii() == "V.2.0", "finds entries regardless of case")
	DirAccess.remove_absolute(TEST_COURSE)


## A 30 x 30 ft square of two triangles on the plane z = 10 + y / 3.
func _square_terrain(wide: bool) -> PackedByteArray:
	var b := PackedByteArray()
	put_u32(b, 6)
	var nv := 70000 if wide else 4
	put_u32(b, nv)
	var corners := [[0.0, 0.0, 10.0], [30.0, 0.0, 10.0], [30.0, 30.0, 20.0], [0.0, 30.0, 20.0]]
	for i in nv:
		var p: Array = corners[i] if i < 4 else [0.0, 0.0, 0.0]
		for c in p:
			put_f32(b, c)
		put_f32(b, 0.0)
		put_f32(b, 0.0)
		put_u16(b, 0)
		put_u16(b, 0)
	put_u32(b, 2)
	for _i in 6:
		put_u32(b, (1 << 30) | 0xfffff)
	for tri in [[0, 1, 2, 4, 0x616d0000], [0, 2, 3, 7, 3]]:
		put_u16(b, tri[3])  # material
		put_u32(b, tri[4])  # mapping in the low half
		put_u16(b, 0)
		for k in 3:
			if wide:
				put_u32(b, tri[k])
			else:
				put_u16(b, tri[k])
	return b


func _test_terrain() -> void:
	for wide in [false, true]:
		var t := CrzCourseLoader.parse_terrain(_square_terrain(wide))
		check(not t.is_empty(), "parses terrain (wide %s)" % wide)
		if t.is_empty():
			continue
		check((t.triangles as PackedInt32Array).size() == 6, "two triangles (wide %s)" % wide)
		check((t.triangle_material as PackedInt32Array) == PackedInt32Array([4, 7]), "triangle materials")
		check((t.triangle_mapping as PackedInt32Array) == PackedInt32Array([0, 3]), "triangle mappings: the low half")
	var broken := _square_terrain(false)
	broken.append(0)
	check(CrzCourseLoader.parse_terrain(broken).is_empty(), "rejects trailing data")

	var t := CrzCourseLoader.parse_terrain(_square_terrain(false))
	var terrain := CrzTerrain.new()
	terrain.positions = t.positions
	terrain.triangles = t.triangles
	terrain.triangle_material = t.triangle_material
	var classes := PackedByteArray()
	classes.resize(8)
	classes[4] = 1
	classes[7] = 4
	terrain.ground_classes = classes
	terrain.finalize()
	# Course (x, y, z) feet maps to Godot (x, z, -y) metres.
	var f := CrzCourseLoader.FEET
	check(absf(terrain.height_at(15.0 * f, -15.0 * f) - 15.0 * f) < 1e-3, "height in the middle")
	check(absf(terrain.height_at(24.0 * f, -6.0 * f) - 12.0 * f) < 1e-3, "height on the first triangle")
	check(absf(terrain.height_at(6.0 * f, -24.0 * f) - 18.0 * f) < 1e-3, "height on the second triangle")
	check(terrain.surface_at(25.0 * f, -5.0 * f) == Surface.Type.GREEN, "green from the ground class")
	check(terrain.surface_at(5.0 * f, -25.0 * f) == Surface.Type.SAND, "sand from the ground class")
	check(terrain.surface_at(50.0, 50.0) == Surface.Type.OUT_OF_BOUNDS, "off the course is out of bounds")
	check(terrain.normal_at(15.0 * f, -15.0 * f).y > 0.9, "normal points up")
	# Both triangles must face up once wound for Godot.
	var tri := t.triangles as PackedInt32Array
	var pos := t.positions as PackedVector3Array
	for k in 2:
		var a := pos[tri[3 * k]]
		var n := (pos[tri[3 * k + 1]] - a).cross(pos[tri[3 * k + 2]] - a)
		check(n.y < 0.0, "triangle %d is clockwise seen from above" % k)


func _put_name(b: PackedByteArray, name: String) -> void:
	put_u32(b, name.length())
	b.append_array(name.to_ascii_buffer())


## The `Mappings` entry test_mappings_entry() in
## libs/olcore/tests/test_course.cpp builds: one record of each kind.
func _mappings_entry() -> PackedByteArray:
	var b := PackedByteArray()
	put_u32(b, 5)
	put_u32(b, 4)
	while b.size() < 48:
		b.append(0)
	put_u32(b, 0)
	put_u32(b, 0x8000)
	_put_name(b, "Planar")
	put_f32(b, 1)
	put_f32(b, 1)
	for f in [0, 12, 0, 0, -12, 0, 0, 0, 0, 0, 12, 0, 100, 200, 0, 1]:
		put_f32(b, f)
	put_u32(b, 1)
	put_u32(b, 0x8001)
	_put_name(b, "Pool")
	put_f32(b, 4)
	put_f32(b, 1)
	for f in [20, 0, 0, 0, 0, 20, 0, 0, 0, 0, 10, 0, 0, 0, 0, 1]:
		put_f32(b, f)
	put_u32(b, 3)
	put_u32(b, 0x8002)
	_put_name(b, "Edge path")
	put_f32(b, 1)
	put_f32(b, 12)
	put_u32(b, 1)
	for v in [999, 7, 2, 0, 1]:
		put_u32(b, v)
	put_u32(b, 3)
	for c in 3:
		put_u32(b, 999)
		put_u32(b, 3 + c)
		put_f32(b, 1.0 if c == 1 else 0.0)
		put_f32(b, 0.5 * c)
	put_u32(b, 4)
	put_u32(b, 0x8003)
	_put_name(b, "Edge multi")
	for v in [2, 0, 0, 0, 0]:
		put_u32(b, v)
	return b


func _test_mappings() -> void:
	var m := TerrainMappings.parse(_mappings_entry())
	check(m.size() == 4, "mappings: four records")
	if m.size() != 4:
		return
	check(m[0].kind == TerrainMappings.Kind.PLANAR and m[0].name == "Planar", "mappings: planar record")
	check(TerrainMappings.uv(m[0], Vector3(76, 212, 5)).is_equal_approx(Vector2(1, 2)), "mappings: planar coordinates")
	check(m[1].kind == TerrainMappings.Kind.CYLINDRICAL, "mappings: cylindrical record")
	check(TerrainMappings.uv(m[1], Vector3(0, 20, 5)).is_equal_approx(Vector2(1, 0.5)), "mappings: cylindrical coordinates")
	check(m[2].kind == TerrainMappings.Kind.STRIP and m[2].scale == Vector2(1, 12), "mappings: strip record")
	check(m[2].strip_triangles == PackedInt32Array([7, 2, 0, 1]), "mappings: strip triangle")
	check(m[2].corner_vertex == PackedInt32Array([3, 4, 5]) and (m[2].corner_uv as PackedVector2Array)[1] == Vector2(1, 0.5), "mappings: strip corners")
	check(m[3].kind == TerrainMappings.Kind.BLEND and m[3].layers == PackedInt32Array([2, 0, 0]), "mappings: blend record")
	var bad := _mappings_entry()
	bad.append(0)
	check(TerrainMappings.parse(bad).is_empty(), "mappings: rejects trailing data")
	var f := CrzCourseLoader.FEET
	check(TerrainMappings.to_course(CrzCourseLoader.to_godot(1, 2, 3)).is_equal_approx(Vector3(1, 2, 3)), "mappings: Godot metres back to course feet")

	var plain := TerrainMappings.material_layers({"textures": PackedInt32Array([4, 5, 6]), "kind": 0x3})
	check(not plain.blended and plain.mask == -1 and plain.layers == PackedInt32Array([4]), "materials: a plain layer and its details")
	check(plain.details == PackedInt32Array([5, 6]), "materials: middle and far variants")
	var far_only := TerrainMappings.material_layers({"textures": PackedInt32Array([4, 6]), "kind": 0x2})
	check(far_only.details == PackedInt32Array([-1, 6]), "materials: only a far variant")
	var blend := TerrainMappings.material_layers({"mode": 3, "layer_count": 3, "kind": 0x1 | 0xc,
		"textures": PackedInt32Array([10, 11, 20, 21, 22, 30])})
	check(blend.blended and blend.mask == 10 and blend.layers == PackedInt32Array([20, 30]), "materials: mask and two layers")
	check(blend.details == PackedInt32Array([21, 22, -1, -1]), "materials: variants per layer")

	# A terrain whose triangle 0 uses the planar mapping and triangle 1 the
	# blend (its mask strip covers triangle 1 with vertices 0, 2, 3).
	var terrain := CrzTerrain.new()
	terrain.positions = PackedVector3Array([CrzCourseLoader.to_godot(76, 212, 0), CrzCourseLoader.to_godot(100, 200, 0),
		CrzCourseLoader.to_godot(88, 200, 0), CrzCourseLoader.to_godot(76, 200, 0)])
	terrain.triangles = PackedInt32Array([0, 1, 2, 0, 2, 3])
	terrain.triangle_mapping = PackedInt32Array([0, 3])
	m[2].strip_triangles = PackedInt32Array([1, 0, 1, 2])
	m[2].corner_vertex = PackedInt32Array([0, 2, 3])
	terrain.mappings = m
	check(terrain._triangle_layers(0) == PackedInt32Array([-1, 0, 0]), "terrain: a plain mapping is both layers")
	check(terrain._triangle_layers(1) == PackedInt32Array([2, 0, 0]), "terrain: a blend gives the mask strip and the layers")
	var planar := terrain._corner_uvs(0, 0)
	check(planar.size() == 3 and planar[0].is_equal_approx(Vector2(1, 2)) and planar[1].is_equal_approx(Vector2.ZERO), "terrain: planar corners")
	var mask := terrain._corner_uvs(2, 1)
	check(mask.size() == 3 and mask[0] == Vector2(0, 0) and mask[1] == Vector2(1, 0.5) and mask[2] == Vector2(0, 1), "terrain: mask corners from the strip")
	var flat := terrain._corner_uvs(-1, 0)
	check(flat[1].is_equal_approx(Vector2(100, -200) * f / CrzTerrain.TILE_METRES), "terrain: no mapping repeats every 12 feet")


## The shadow file test_shadow_file() in libs/olcore/tests/test_course.cpp
## builds.
func _shadow_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(0x12E)
	b.fill(0)
	var magic := "VER5JDHSHADOW".to_ascii_buffer()
	for i in magic.size():
		b[i] = magic[i]
	var name := "test.CRZ".to_ascii_buffer()
	for i in name.size():
		b[14 + i] = name[i]
	b.encode_u32(0x10E, 12345)
	b.encode_u32(0x11A, 1028330567)
	b.encode_u32(0x11E, 2)  # models
	b.encode_u32(0x122, 3)  # billboard types
	b.encode_u32(0x126, 1)  # model placements
	b.encode_u32(0x12A, 2)  # billboards
	put_u32(b, 2)  # model 0: a 2 x 2 footprint
	put_u32(b, 2)
	for i in 4:
		b.append(0 if i == 3 else 0xFE)
	put_u32(b, 0)  # model 1: none
	put_u32(b, 0)
	put_u32(b, 2)  # placement 0 touches two cells
	put_u32(b, 8)
	put_u32(b, 16)
	put_f32(b, 1.0)  # billboard light
	put_f32(b, 0.25)
	put_u32(b, 0)  # type 0: no shadow
	put_u32(b, 0)
	put_u32(b, 32)  # type 1
	put_u32(b, 32)
	for i in 32 * 32:
		b.append(i & 0xFF)
	put_u32(b, 0)  # type 2: no shadow
	put_u32(b, 0)
	put_u32(b, 1)  # billboard 0 touches one cell, billboard 1 none
	put_u32(b, 0)
	put_u32(b, 24)
	return b


func _test_shadow_file() -> void:
	var f := ShadowFile.parse(_shadow_bytes(), true)
	check(not f.is_empty(), "shadow file parses")
	if f.is_empty():
		return
	check(f.course == "test.CRZ" and f.course_size == 12345 and f.stamp == 1028330567, "shadow file: course name and size")
	check(f.model_count == 2 and f.billboard_type_count == 3 and f.billboard_count == 2, "shadow file: counts")
	var objects: Array = f.object_shapes
	check(objects.size() == 2 and objects[0] != null and objects[1] == null, "shadow file: object footprints")
	if objects.size() == 2 and objects[0] != null:
		var fp: Image = objects[0]
		check(fp.get_width() == 2 and fp.get_data()[0] == 0xFE and fp.get_data()[3] == 0, "shadow file: footprint pixels")
	check(f.placement_cells.start == PackedInt32Array([0, 2]) and f.placement_cells.cells == PackedInt32Array([1, 2]), "shadow file: placement cells")
	check(f.billboard_light == PackedFloat32Array([1.0, 0.25]), "shadow file: billboard light")
	var shapes: Array = f.shapes
	check(shapes.size() == 3 and shapes[0] == null and shapes[2] == null, "shadow file: types without a shadow")
	if shapes.size() == 3 and shapes[1] != null:
		var img: Image = shapes[1]
		check(img.get_width() == 32 and img.get_height() == 32, "shadow file: shape size")
		check(img.get_data()[33] == 33, "shadow file: shape pixels")
	check(f.billboard_cells.start == PackedInt32Array([0, 1, 1]) and f.billboard_cells.cells == PackedInt32Array([3]), "shadow file: billboard cells")
	check(not ShadowFile.parse(_shadow_bytes()).has("billboard_cells"), "shadow file: cells only on request")
	var bad := _shadow_bytes()
	bad[0] = 0x58
	check(ShadowFile.parse(bad).is_empty(), "shadow file: rejects other files")
	var short := _shadow_bytes()
	short.resize(short.size() - 1)
	check(ShadowFile.parse(short).is_empty(), "shadow file: rejects a short file")
	var long := _shadow_bytes()
	long.append(0)
	check(ShadowFile.parse(long).is_empty(), "shadow file: rejects trailing bytes")


func _test_holes_and_ground() -> void:
	var b := PackedByteArray()
	put_u32(b, 0xFFFFFFFF)
	put_u32(b, 15)
	b.resize(b.size() + 10)
	put_u32(b, 1)
	for v in [4, 7, 5, 9]:  # par, handicap, ladies par, ladies handicap
		put_u32(b, v)
	for i in 5:  # tees: xyz, heading, yards, mask
		for c in [100.0 * i, 0.0, 5.0, 0.0]:
			put_f32(b, c)
		put_u32(b, 400 - 20 * i)
		put_u32(b, (1 << i) if i < 2 else 0)
	for i in 18:  # pins: xyz, group
		for c in ([0.0, 1200.0, 3.0] if i == 0 else [0.0, 0.0, 0.0]):
			put_f32(b, c)
		put_u32(b, 0)
	put_u32(b, 18)
	put_u32(b, 5)
	for i in 5:  # aim points
		for c in ([0.0, 600.0 * i, 0.0] if i < 3 else [0.0, 0.0, 0.0]):
			put_f32(b, c)
	for c in [0.0, 1200.0, 3.0]:
		put_f32(b, c)
	b.resize(b.size() + 6)
	var holes := CrzCourseLoader.parse_holes(b)
	check(CrzCourseLoader.parse_course_scenery(b).is_empty(), "no scenery without the header trailer")
	var trailer := b.duplicate()
	put_u32(trailer, 5)
	trailer.resize(trailer.size() + 60 + 16)
	put_u32(trailer, 7)  # sky07
	trailer.resize(trailer.size() + 8)
	for v in [0.785, 0.15, 30.0, 0.15]:
		put_f32(trailer, v)
	put_u32(trailer, 0)
	put_u32(trailer, 0x80000000)  # the course's own horizon
	put_u32(trailer, 0)
	trailer.resize(trailer.size() + 16)
	var scenery := CrzCourseLoader.parse_course_scenery(trailer)
	check(scenery.get("sky", -1) == 7 and scenery.get("panorama", -1) == 0, "scenery: sky and own horizon")
	check(scenery.has("values") and is_equal_approx(scenery.values[2], 30.0), "scenery: values")
	trailer.encode_u32(trailer.size() - 24, 3)
	check(CrzCourseLoader.parse_course_scenery(trailer).get("panorama", -1) == 3, "scenery: stock horizon")
	check(holes.size() == 1, "one hole")
	if holes.size() == 1:
		var h := holes[0]
		check(h.par == 4 and h.handicap == 7, "par and handicap")
		check((h.tees as Array).size() == 2 and h.tees[1].yards == 380, "tees with a mask")
		check((h.pins as Array).size() == 1, "one pin")
		check((h.pins[0] as Vector3).is_equal_approx(Vector3(0.0, 3.0, -1200.0) * CrzCourseLoader.FEET), "pin in Godot metres")
		check((h.aim as Array).size() == 2, "aim points without the empty ones")

	var types := PackedByteArray()
	put_u32(types, 4)
	put_u32(types, 2)
	types.resize(8 + 2 * 243)
	types[8 + 0x54] = 3
	types[8 + 243 + 0x54] = 1
	check(CrzCourseLoader.parse_ground_classes(types) == PackedByteArray([3, 1]), "ground classes")

	var text := PackedByteArray([0xFF, 0xFE])
	text.append_array("CourseName = Test Links\r\nHoleName1 = Café\r\n".to_utf16_buffer())
	var kv := CrzCourseLoader.parse_course_text(text)
	check(kv.get("CourseName") == "Test Links" and kv.get("HoleName1") == "Café", "course text")


## The same records and outlines as test_crz_terrain_types and
## test_hole_bounds in libs/olcore/tests/test_course.cpp.
func _test_terrain_types_and_bounds() -> void:
	var rec := PackedByteArray()
	put_u32(rec, 7)
	for i in 20:
		put_f32(rec, 0.25 * i)
	put_u32(rec, 3)
	put_u32(rec, 14)
	put_u32(rec, 0xcdcdcd41)
	var b := PackedByteArray()
	b.resize(8 + 243)
	b.fill(0xcd)
	b.encode_u32(0, 4)
	b.encode_u32(4, 1)
	for i in rec.size():
		b[8 + i] = rec[i]
	# The name sits at 0x67, in the bytes after the flags.
	var label := "Mud".to_utf16_buffer()
	label.append_array(PackedByteArray([0, 0]))
	for i in label.size():
		b[8 + 0x67 + i] = label[i]
	var types := CourseAreas.parse_terrain_types(b)
	check(types.size() == 1, "one terrain type")
	if types.size() == 1:
		var t := types[0]
		check(t.index == 7 and t.ground_class == 3 and t.category == 14, "terrain type fields")
		check(CourseAreas.is_hazard(t) and not CourseAreas.is_free_drop(t), "terrain type flags")
		check(is_equal_approx(CourseAreas.value(t, 0x14), 1.0) and is_equal_approx(CourseAreas.value(t, 0x38), 3.25), "terrain type values")
		check(t.name == "Mud", "terrain type name")
		var p := CourseAreas.links_surface(t)
		check(p.ground_class == 3 and is_equal_approx(p.restitution, 1.0) and is_equal_approx(p.lie_spin, 0.0), "surface from the record")
	b.resize(b.size() - 1)
	check(CourseAreas.parse_terrain_types(b).is_empty(), "short terrain types")

	var holes := CourseAreas.parse_id_shapes(_id_shapes(false))
	var ob := CourseAreas.parse_id_shapes(_id_shapes(true))
	check(holes.size() == 1 and holes[0].id == 42 and holes[0].closed and CourseAreas.shape_hole(holes[0]) == 2, "hole outline")
	var o := CourseAreas.shape_outline(holes[0])
	check(o.size() == 4 * 8 + 1, "outline points")
	check(o.size() > 4 and o[0] == Vector2(0, 100) and o[4] == Vector2(0, 50), "outline starts at the last node")
	check(CourseAreas.outline_contains(o, 10, 10) and not CourseAreas.outline_contains(o, -1, 10) and not CourseAreas.outline_contains(o, 50, 101), "outline contains")
	var hb := CourseAreas.HoleBounds.new(holes, ob)
	check(hb.in_bounds(2, 10, 10), "in bounds on the hole")
	check(not hb.in_bounds(2, 150, 10), "out of bounds off the hole")
	check(not hb.in_bounds(2, 50, 50), "out of bounds in the area")
	check(hb.in_bounds(1, 150, 10), "a hole without an outline")
	check(not hb.in_bounds(3, 50, 50), "the area for hole 3")
	var bad := _id_shapes(false)
	bad[0] = 2
	check(CourseAreas.parse_id_shapes(bad).is_empty(), "shape count must match")

	# The banded lookup agrees with the plain crossing test.
	var area := CourseAreas.HoleBounds.Area.new(holes[0], 1)
	var same := true
	for i in 200:
		var x := -5.0 + 110.0 * fmod(i * 0.618034, 1.0)
		var y := -5.0 + 110.0 * fmod(i * 0.414214, 1.0)
		same = same and area.contains(x, y) == CourseAreas.outline_contains(o, x, y)
	check(same, "banded outline lookup")


func _id_shapes(ob: bool) -> PackedByteArray:
	var b := PackedByteArray()
	put_u32(b, 1)
	put_u32(b, 1)
	for i in 3:
		put_f32(b, 0.0)
	put_u32(b, 42)
	put_u32(b, 4)
	b.append(1)
	var lo := 40.0 if ob else 0.0
	var hi := 60.0 if ob else 100.0
	for v in [lo, lo, 0.0, hi, hi, 0.0]:
		put_f32(b, v)
	put_u32(b, 0x6 if ob else (2 << 27) | 0x100000)
	for p in [Vector2(lo, lo), Vector2(hi, lo), Vector2(hi, hi), Vector2(lo, hi)]:
		for k in 3:
			put_f32(b, p.x)
			put_f32(b, p.y)
			put_f32(b, 100.0)
	return b


func _test_community_courses() -> void:
	check(not CommunityCourses.COURSES.is_empty(), "community course list is not empty")
	for course: Dictionary in CommunityCourses.COURSES:
		check(CommunityCourses.page_url(course).begins_with("https://linkscorner.org/courses/course.php?crz="),
			"%s has a Links Corner page" % course.name)
	check(CommunityCourses.label({"name": "Duine Mara", "designer": "Paul Seaman", "id": 2022}) == "Duine Mara by Paul Seaman",
		"community course label")
