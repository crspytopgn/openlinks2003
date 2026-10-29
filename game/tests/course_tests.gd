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
	_test_holes_and_ground()
	return failures


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _test_scripts_compile() -> void:
	for path in ["res://scripts/course/crz_course_loader.gd", "res://scripts/course/crz_terrain.gd",
			"res://scripts/course_viewer.gd"]:
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
	for tri in [[0, 1, 2, 4], [0, 2, 3, 7]]:
		put_u16(b, tri[3])  # material
		put_u32(b, 0)
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
