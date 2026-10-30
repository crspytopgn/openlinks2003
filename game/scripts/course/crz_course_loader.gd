class_name CrzCourseLoader
extends CourseLoader
## Plays Links 2003 courses (.CRZ, and the .RNG driving range) straight from
## the player's own files. The parsers port libs/olcore/src/course.cpp;
## change both together. See docs/formats/crz.md.
##
## Most course archives are locked. The cipher tables and key are recovered
## from the player's game executable the first time and kept in
## user://crz_keys.cfg. The decoded terrain is cached in user://course_cache/
## so later loads skip the slow decrypt.

const FEET := 0.3048
const KEYS_PATH := "user://crz_keys.cfg"
const CACHE_DIR := "user://course_cache"
const CACHE_VERSION := 1
const EXE_NAMES := ["LINKSM_1.EXE", "LinksMMIII.exe", "LinksM~1.exe"]
const TEXTURE_LIBRARIES := ["STDTER_1.LIB", "StdTerrain.lib", "StdTer~1.lib"]
## How far one repeat of a free ground texture spans.
const FREE_TILE_METRES := 2.5

const HEADER_VERSION := 15
const TERRAIN_VERSION := 6
const MATERIALS_VERSION := 4
const TERRAIN_TYPES_VERSION := 4
const TERRAIN_TYPE_SIZE := 243
const GROUND_CLASS_OFFSET := 0x54
const TEES_PER_HOLE := 5
const PINS_PER_HOLE := 18
const AIM_POINTS_PER_HOLE := 5
const MATERIAL_SLOTS := 12

static var _keys := {}
static var _free_means := {}  ## free ground slot -> its average colour


func can_load(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext == "crz" or ext == "rng"


func load_course(path: String) -> CourseData:
	var data := _cached(path)
	var archive: CrzArchive = null
	if data.is_empty():
		archive = _open(path)
		if archive == null:
			return null
		data = decode(archive)
		if data.is_empty():
			return null
		if data.name.is_empty():
			data.name = path.get_file().get_basename().capitalize()
		_store_cache(path, data)
	return _build(path, data, archive)


# --- Keys and cache -----------------------------------------------------------

static func _open(path: String) -> CrzArchive:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Cannot open course %s" % path)
		return null
	var plain := CrzArchive.is_plain(f.get_buffer(CrzArchive.HEADER_SIZE))
	f = null
	var keys := _game_keys(path)
	if keys.is_empty() and not plain:
		push_warning("%s is locked and no Links 2003 executable (LINKSM_1.EXE) was found" % path)
		return null
	var archive := CrzArchive.open(path, keys)
	if archive == null and not keys.is_empty():
		# The saved keys may be stale (another copy of the game); look again.
		_keys = {}
		DirAccess.remove_absolute(KEYS_PATH)
		keys = _game_keys(path)
		if not keys.is_empty():
			archive = CrzArchive.open(path, keys)
	return archive


## The cipher tables and key: from memory, from user://, or found in the
## game executable (which takes a moment).
static func _game_keys(course_path: String) -> Dictionary:
	if not _keys.is_empty():
		return _keys
	var cfg := ConfigFile.new()
	if cfg.load(KEYS_PATH) == OK:
		var tables: PackedInt64Array = cfg.get_value("keys", "tables", PackedInt64Array())
		var key: PackedByteArray = cfg.get_value("keys", "key", PackedByteArray())
		if tables.size() == Bunky.P_WORDS + Bunky.S_WORDS and key.size() == 8:
			_keys = {"tables": tables, "key": key}
			return _keys
	var exe_path := GameFolder.find_file(PackedStringArray(EXE_NAMES))
	if exe_path.is_empty():
		return {}
	var found := CrzArchive.find_keys(FileAccess.get_file_as_bytes(exe_path), course_path)
	if found.is_empty():
		push_warning("Could not find the course key in %s" % exe_path)
		return {}
	_keys = found
	cfg.set_value("keys", "tables", found.tables)
	cfg.set_value("keys", "key", found.key)
	cfg.save(KEYS_PATH)
	return _keys


static func _cache_path(path: String) -> String:
	var size := 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		size = f.get_length()
	return CACHE_DIR.path_join("%s_%d.bin" % [path.get_file().get_basename().to_lower(), size])


static func _cached(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(_cache_path(path), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v: Variant = f.get_var()
	if typeof(v) != TYPE_DICTIONARY or (v as Dictionary).get("version", 0) != CACHE_VERSION:
		return {}
	return v


static func _store_cache(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open_compressed(_cache_path(path), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f != null:
		f.store_var(data)


# --- Decoding -----------------------------------------------------------------

## Everything the game needs from an open archive, as plain data (so it can
## be cached): {version, name, holes, positions, triangles, triangle_material,
## ground_classes, material_textures}. Empty on error.
static func decode(archive: CrzArchive) -> Dictionary:
	var holes := parse_holes(archive.read_named("header"))
	var terrain := parse_terrain(archive.read_named("vertex"))
	if holes.is_empty() or terrain.is_empty():
		push_warning("Course has no holes or no terrain")
		return {}
	var name := ""
	var text := parse_course_text(archive.read_named("english.txt"))
	if text.has("CourseName"):
		name = text.CourseName
	for i in holes.size():
		holes[i].name = text.get("HoleName%d" % (i + 1), "")

	var textures := parse_texture_list(archive.read_named("txtrdesc"))
	var material_textures := PackedStringArray()
	for m in parse_materials(archive.read_named("Materials")):
		# Blended materials list a greyscale mask first ("Fairway To Rough
		# Alpha.tga"); show the first texture that is not a mask.
		var chosen := ""
		for t in m.textures as PackedInt32Array:
			if t < textures.size() and not textures[t].to_lower().contains("alpha"):
				chosen = textures[t]
				break
		material_textures.append(chosen)

	return {
		"version": CACHE_VERSION,
		"name": name,
		"holes": holes,
		"positions": terrain.positions,
		"triangles": terrain.triangles,
		"triangle_material": terrain.triangle_material,
		"ground_classes": parse_ground_classes(archive.read_named("TerrainTypes")),
		"material_textures": material_textures,
	}


## Course feet (z up) to Godot metres (y up).
static func to_godot(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y) * FEET


static func _vec(b: PackedByteArray, o: int) -> Vector3:
	return to_godot(b.decode_float(o), b.decode_float(o + 4), b.decode_float(o + 8))


## `header` entry. Each hole: {par, handicap, tees: [{position, yards}],
## pins: [Vector3], aim: [Vector3], green: Vector3, name}.
static func parse_holes(b: PackedByteArray) -> Array[Dictionary]:
	var holes: Array[Dictionary] = []
	if b.size() < 22 or b.decode_u32(4) != HEADER_VERSION:
		return holes
	var count := b.decode_u32(18)
	var o := 22
	const HOLE_SIZE := 16 + TEES_PER_HOLE * 24 + PINS_PER_HOLE * 16 + 8 + AIM_POINTS_PER_HOLE * 12 + 12 + 6
	if count > 18 or o + count * HOLE_SIZE > b.size():
		return holes
	for _h in count:
		var hole := {"par": b.decode_u32(o), "handicap": b.decode_u32(o + 4), "name": ""}
		o += 16
		var tees: Array[Dictionary] = []
		for _i in TEES_PER_HOLE:
			if b.decode_u32(o + 20) != 0:
				tees.append({"position": _vec(b, o), "yards": b.decode_u32(o + 16)})
			o += 24
		var pins: Array[Vector3] = []
		for _i in PINS_PER_HOLE:
			var p := _vec(b, o)
			if p != Vector3.ZERO:
				pins.append(p)
			o += 16
		o += 8  # pin and aim point counts
		var aim: Array[Vector3] = []
		for _i in AIM_POINTS_PER_HOLE:
			var p := _vec(b, o)
			if p != Vector3.ZERO:
				aim.append(p)
			o += 12
		hole.green = _vec(b, o)
		o += 12 + 6
		hole.tees = tees
		hole.pins = pins
		hole.aim = aim
		holes.append(hole)
	return holes


## `english.txt` entry: UTF-16 "Key = Value" lines.
static func parse_course_text(b: PackedByteArray) -> Dictionary:
	var out := {}
	if b.size() >= 2 and b[0] == 0xFF and b[1] == 0xFE:
		b = b.slice(2)
	for line in b.get_string_from_utf16().split("\n"):
		var eq := line.find("=")
		if eq >= 0:
			out[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	return out


## `vertex` entry: {positions, triangles, triangle_material}, with the
## triangles wound clockwise seen from above. Empty on error.
static func parse_terrain(b: PackedByteArray) -> Dictionary:
	if b.size() < 8 or b.decode_u32(0) != TERRAIN_VERSION:
		return {}
	var nv := b.decode_u32(4)
	var o := 8
	if o + nv * 24 + 4 > b.size():
		return {}
	var positions := PackedVector3Array()
	positions.resize(nv)
	for i in nv:
		positions[i] = _vec(b, o)
		o += 24
	var nt := b.decode_u32(o)
	o += 4 + nt * 12  # neighbours, not needed here
	# Vertex indices are u16, or u32 once there are too many vertices for that.
	var wide := nv > 0xFFFF
	var record := 20 if wide else 14
	if o + nt * record != b.size():
		return {}
	var triangles := PackedInt32Array()
	triangles.resize(nt * 3)
	var material := PackedInt32Array()
	material.resize(nt)
	for t in nt:
		material[t] = b.decode_u16(o)
		var v0 := b.decode_u32(o + 8) if wide else b.decode_u16(o + 8)
		var v1 := b.decode_u32(o + 12) if wide else b.decode_u16(o + 10)
		var v2 := b.decode_u32(o + 16) if wide else b.decode_u16(o + 12)
		if v0 >= nv or v1 >= nv or v2 >= nv:
			return {}
		var pa := positions[v0]
		var n := (positions[v1] - pa).cross(positions[v2] - pa)
		# Clockwise seen from above means the right-handed normal points down.
		if n.y > 0.0:
			var tmp := v1
			v1 = v2
			v2 = tmp
		triangles[3 * t] = v0
		triangles[3 * t + 1] = v1
		triangles[3 * t + 2] = v2
		o += record
	return {"positions": positions, "triangles": triangles, "triangle_material": material}


## `txtrdesc` entry: texture names.
static func parse_texture_list(b: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	if b.size() < 4:
		return out
	var count := b.decode_u32(0)
	if 4 + count * 64 > b.size():
		return out
	for i in count:
		out.append(b.slice(4 + i * 64, 4 + i * 64 + 32).get_string_from_ascii())
	return out


## `Materials` entry: [{textures: PackedInt32Array, kind}].
static func parse_materials(b: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if b.size() < 8 or b.decode_u32(0) != MATERIALS_VERSION:
		return out
	var count := b.decode_u32(4)
	if 8 + count * 64 > b.size():
		return out
	for i in count:
		var o := 8 + i * 64
		var textures := PackedInt32Array()
		for s in MATERIAL_SLOTS:
			var t := b.decode_s32(o + 8 + 4 * s)
			if t >= 0:
				textures.append(t)
		out.append({"textures": textures, "kind": b.decode_u32(o + 56)})
	return out


## `TerrainTypes` entry: the ground class of each material (see
## olcore::parse_ground_classes).
static func parse_ground_classes(b: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	if b.size() < 8 or b.decode_u32(0) != TERRAIN_TYPES_VERSION:
		return out
	var count := b.decode_u32(4)
	if 8 + count * TERRAIN_TYPE_SIZE > b.size():
		return out
	out.resize(count)
	for i in count:
		out[i] = b[8 + i * TERRAIN_TYPE_SIZE + GROUND_CLASS_OFFSET]
	return out


# --- Building the game's course -------------------------------------------------

func _build(path: String, data: Dictionary, archive: CrzArchive) -> CourseData:
	var terrain := CrzTerrain.new()
	terrain.positions = data.positions
	terrain.triangles = data.triangles
	terrain.triangle_material = data.triangle_material
	terrain.ground_classes = data.ground_classes
	terrain.normals = _vertex_normals(terrain.positions, terrain.triangles)
	terrain.finalize()
	terrain.materials = _materials(path, data.material_textures, terrain.ground_classes, archive)

	var course := CourseData.new()
	course.course_name = data.name
	var number := 0
	for h in data.holes as Array:
		number += 1
		var tees: Array = h.tees
		var pins: Array = h.pins
		if tees.is_empty() or pins.is_empty():
			continue
		var hole := HoleData.new()
		hole.number = number
		hole.par = h.par
		hole.terrain = terrain
		var tee: Vector3 = tees[0].position
		var pin: Vector3 = pins[0]
		hole.tee = Vector3(tee.x, terrain.height_at(tee.x, tee.z), tee.z)
		hole.pin = Vector3(pin.x, terrain.height_at(pin.x, pin.z), pin.z)
		for t: Dictionary in tees:
			var at: Vector3 = t.position
			hole.tees.append(Vector3(at.x, terrain.height_at(at.x, at.z), at.z))
		# The aim points run from the tee to the green; skip the tee itself.
		for p in h.aim as Array:
			var q := Vector2(p.x, p.z)
			if q.distance_to(Vector2(tee.x, tee.z)) > 5.0:
				hole.route.append(q)
		course.holes.append(hole)
	return course


static func _vertex_normals(positions: PackedVector3Array, triangles: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(positions.size())
	normals.fill(Vector3.ZERO)
	for t in triangles.size() / 3:
		var a := triangles[3 * t]
		var b := triangles[3 * t + 1]
		var c := triangles[3 * t + 2]
		# Wound clockwise from above, so this cross product points up.
		var n := (positions[c] - positions[a]).cross(positions[b] - positions[a])
		normals[a] += n
		normals[b] += n
		normals[c] += n
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i] != Vector3.ZERO else Vector3.UP
	return normals


## A texture and a flat colour for each material. Textures come from the
## course archive or from the standard terrain library on the game disc.
## A stock texture that isn't there (add-on courses played without the
## standard library) falls back to the free ground texture for its surface.
func _materials(path: String, names: PackedStringArray, classes: PackedByteArray, archive: CrzArchive) -> Array[Dictionary]:
	if archive == null:
		archive = _open(path)
	var library: Arc0 = null
	var lib_path := GameFolder.find_file(PackedStringArray(TEXTURE_LIBRARIES))
	if not lib_path.is_empty():
		library = Arc0.from_bytes(FileAccess.get_file_as_bytes(lib_path))
	var loaded := {}
	var out: Array[Dictionary] = []
	for m in names.size():
		var ground := classes[m] if m < classes.size() else 3
		var info := {"colour": _class_colour(ground), "texture": null}
		var tex_name := names[m]
		if not tex_name.is_empty():
			var key := tex_name.to_lower()
			if not loaded.has(key):
				loaded[key] = _load_texture(tex_name, archive, library)
			info.texture = loaded[key]
			if info.texture == null:
				info.merge(_free_ground(ground, info.colour), true)
		out.append(info)
	return out


static func _load_texture(tex_name: String, archive: CrzArchive, library: Arc0) -> Texture2D:
	var bytes := PackedByteArray()
	if archive != null and archive.has(tex_name):
		bytes = archive.read_named(tex_name)
	elif library != null and library.find(tex_name) >= 0:
		bytes = library.read_named(tex_name)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_tga_from_buffer(bytes) != OK or image.is_empty():
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## The free ground texture for a ground class, tinted towards the class
## colour so greens, fairways and rough still look apart. Empty when the free
## textures aren't there, or for water, which keeps its flat colour.
static func _free_ground(ground: int, colour: Color) -> Dictionary:
	var surface: Surface.Type = CrzTerrain.CLASS_SURFACE.get(ground, Surface.Type.ROUGH)
	if surface == Surface.Type.WATER:
		return {}
	var slot := FreeAssets.slot_for(surface)
	var tex := FreeAssets.ground(slot, "albedo")
	if tex == null:
		return {}
	if not _free_means.has(slot):
		_free_means[slot] = FreeAssets.mean_color(tex)
	var mean: Color = _free_means[slot]
	var tint := Color(colour.r / maxf(mean.r, 0.05), colour.g / maxf(mean.g, 0.05), colour.b / maxf(mean.b, 0.05))
	return {"texture": tex, "normal": FreeAssets.ground(slot, "normal"), "tint": tint,
		"tile": FREE_TILE_METRES}


static func _class_colour(ground: int) -> Color:
	match CrzTerrain.CLASS_SURFACE.get(ground, Surface.Type.ROUGH):
		Surface.Type.GREEN:
			return Color(0.36, 0.72, 0.30)
		Surface.Type.FAIRWAY:
			return Color(0.30, 0.58, 0.20)
		Surface.Type.SAND:
			return Color(0.86, 0.80, 0.60)
		Surface.Type.WATER:
			return Color(0.12, 0.25, 0.35)
		Surface.Type.DEEP_ROUGH:
			return Color(0.15, 0.33, 0.11)
	return Color(0.20, 0.43, 0.14)
