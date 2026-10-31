class_name CourseObjects
extends RefCounted
## The objects on a Links 2003 course, read straight from its archive: plants
## and rocks (billboards), 3D objects (bridges, fences, buildings) and
## tournament spectators. Draws them for the playable round and turns trees,
## rocks and 3D objects into obstacles for the ball. The parsers port
## libs/olcore/src/course_objects.cpp; change both together. See
## docs/formats/course-objects.md.
##
## Billboards of every type share one texture atlas and one shader, so each
## 100 m chunk of the course draws as a few MultiMeshes, one per height
## class; low plants are hidden beyond 150 to 700 m.

const FEET := 0.3048
const CELL_FEET := 64.0
const PLACEMENT_UNIT := 1.0 / 16.0  ## feet per stored step
const CHUNK := 100.0  ## metres per side of a drawing chunk
const ATLAS_SIZE := 4096  ## atlas width
const ATLAS_HEIGHT := 2048  ## at most; 32 MB of RGBA, which a browser can hold
const MAX_SPRITE := 512  ## largest sprite side kept in the atlas, pixels
const PAD := 2  ## transparent pixels around each sprite in the atlas
## With an HD texture pack on desktop, sprites keep up to twice the detail.
const HD_MAX_SPRITE := 1024
const HD_ATLAS_HEIGHT := 4096
## Billboards below each height (m) are hidden beyond the matching distance
## (CLASS_RANGE; 0 = always drawn). The last class is everything taller.
const CLASS_LIMITS: Array[float] = [0.6, 2.0, 5.0]
const CLASS_RANGE: Array[float] = [150.0, 300.0, 700.0, 0.0]
const CLASSES := 4
const CROWD_RANGE := 250.0
const FAR_REACH := 900.0  ## how far from a hole the always-drawn chunks go
## With 3D trees on (TreeFactory), tree billboards at least this tall are
## drawn as 3D trees, in cells of TREE_CELL metres. The ball's obstacles
## stay those of the billboards.
const TREE_MIN_HEIGHT := 3.0
const TREE_CELL := 50.0
const CROWD_GROUPS: Array[String] = ["fan", "Sit", "media", "Official"]
const CROWD_SPRITE_FEET := 6.0  ## a 128-pixel spectator sprite
const CROWD_LIBRARIES: Array[String] = ["CROWDS.LIB", "Crowds.lib"]
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
// Trees and plants lean and flutter in the wind (0 sway: stand still, as in
// Links 2003). The quad runs from y 0 at the base to 1 at the top.
global uniform vec2 wind_vector;
global uniform float foliage_sway;

void vertex() {
	if (foliage_sway > 0.0) {
		vec3 root = MODEL_MATRIX[3].xyz;
		float phase = dot(root.xz, vec2(0.37, 0.23));
		float speed = min(length(wind_vector), 15.0);
		float gust = sin(TIME * 0.9 + phase) * 0.6 + sin(TIME * 2.1 + phase * 1.7) * 0.4;
		float bend = (0.01 + speed * 0.0035) * gust + speed * 0.002;
		// Sideways in the sprite's own plane, more towards the top.
		VERTEX.x += bend * foliage_sway * VERTEX.y * VERTEX.y;
	}
	// INSTANCE_CUSTOM holds the sprite's rectangle in the atlas.
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
	// Turn about the vertical to face the camera, keeping the instance scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""

static var _shader: Shader


## One kind of billboard (plants or spectators) of a course: placements,
## sprites in an atlas, and the placements sorted into chunks.
class Sprites:
	var xyzh := PackedFloat32Array()  ## per placement: base x, y, z and height, Godot metres
	var sprite := PackedInt32Array()  ## per placement
	var aspect := PackedFloat32Array()  ## per sprite, width / height
	var rects := PackedFloat32Array()  ## per sprite: u, v, width, height in the atlas
	var material: ShaderMaterial
	var fixed_range := -1.0  ## when >= 0, the visibility range of every chunk
	var origin := Vector2.ZERO
	var cols := 0
	var rows := 0
	## Placements of bucket b ((row * cols + col) * CLASSES + class) are
	## order[start[b] .. start[b + 1]).
	var start := PackedInt32Array()
	var order := PackedInt32Array()
	var cache := {}  ## bucket -> MultiMesh (or null when empty)
	## Per sprite: the TreeFactory.Species it is drawn as with 3D trees on,
	## or -1. Empty for spectators.
	var species := PackedInt32Array()


var plants: Sprites
var crowds: Sprites
var obstacles := ObstacleField.new()
var _meshes: Array[ArrayMesh] = []
var _mesh_bounds: Array[AABB] = []
var _placements: Array[Dictionary] = []  ## {model, transform}


# --- Parsers (port of course_objects.cpp) --------------------------------------

## `MasterObj` entry: [{name, sprite, aspect, width, height}] per type.
## Empty on error.
static func parse_billboard_types(b: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if b.size() < 16:
		return out
	var count := b.decode_u32(8)
	var table := b.decode_u32(12)
	if count > 100000 or table + 4 * count > b.size():
		return out
	for k in count:
		var rec := b.decode_u32(table + 4 * k)
		if rec + 0x38 > b.size():
			return [] as Array[Dictionary]
		var t := {"width": b.decode_u32(rec), "height": b.decode_u32(rec + 4), "aspect": b.decode_float(rec + 0x18), "sprite": "", "name": ""}
		var lods := b.decode_u32(rec + 8)
		var lod_list := b.decode_u32(rec + 12)
		if lods > 0 and lod_list + 12 <= b.size():
			# First level: its sprite descriptor, then the sprite's first tile
			# record, which starts with the sprite's file name.
			var desc := b.decode_u32(lod_list + 8)
			if desc + 16 <= b.size():
				var tiles := b.decode_u32(desc + 12)
				if tiles + 32 <= b.size():
					var sprite := b.slice(tiles, tiles + 32).get_string_from_ascii()
					t.sprite = sprite
					t.name = sprite.substr(0, sprite.length() - 5) if sprite.to_lower().ends_with(".btc") else sprite
		out.append(t)
	return out


## `2DPlant` entry: {type: PackedInt32Array, xyzh: PackedFloat32Array (base
## and height in Godot metres)}. Empty on error.
static func parse_billboard_placements(b: PackedByteArray) -> Dictionary:
	if b.size() < 0x40 or b.slice(0, 4).get_string_from_ascii() != "2JBO":
		return {}
	var count := b.decode_u32(8)
	var types := PackedInt32Array()
	var xyzh := PackedFloat32Array()
	types.resize(count)
	xyzh.resize(count * 4)
	var n := 0
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	var have_cell := false
	var pos := 0x40
	var end := b.size()
	while pos + 2 <= end:
		var type := b.decode_u16(pos)
		pos += 2
		if type == 0xFFFF:
			# Start of a 64-foot cell: its corner and a base height.
			if pos + 12 > end:
				return {}
			cx = b.decode_float(pos)
			cy = b.decode_float(pos + 4)
			cz = b.decode_float(pos + 8)
			pos += 12
			have_cell = true
			continue
		if not have_cell or n >= count or pos + 4 > end:
			return {}
		var word := b.decode_u32(pos)
		pos += 4
		if word & 0x20000000:
			pos += 1
		if word & 0x40000000:
			pos += 2
		if pos + 8 > end:
			return {}
		var x := cx + b.decode_u16(pos) * PLACEMENT_UNIT
		var y := cy + b.decode_u16(pos + 2) * PLACEMENT_UNIT
		var z := cz + b.decode_s16(pos + 4) * PLACEMENT_UNIT
		types[n] = type
		# Course feet (z up) to Godot metres (y up).
		xyzh[4 * n] = x * FEET
		xyzh[4 * n + 1] = z * FEET
		xyzh[4 * n + 2] = -y * FEET
		xyzh[4 * n + 3] = b.decode_u16(pos + 6) * PLACEMENT_UNIT * FEET
		pos += 8
		n += 1
	if n != count:
		return {}
	return {"type": types, "xyzh": xyzh}


## `TrnyPlant` entry: {kind, instance: PackedInt32Array, xyz:
## PackedFloat32Array (Godot metres)}. Empty on error.
static func parse_crowd_placements(b: PackedByteArray) -> Dictionary:
	if b.size() < 0x40:
		return {}
	var count := b.decode_u32(4)
	var kinds := PackedInt32Array()
	var instances := PackedInt32Array()
	var xyz := PackedFloat32Array()
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	var have_cell := false
	var pos := 0x40
	var end := b.size()
	while pos < end:
		var kind := b[pos]
		pos += 1
		if kind == 0xFF:
			if pos + 12 > end:
				return {}
			cx = b.decode_float(pos)
			cy = b.decode_float(pos + 4)
			cz = b.decode_float(pos + 8)
			pos += 12
			have_cell = true
			continue
		if not have_cell or pos + 4 > end:
			return {}
		var word := b.decode_u32(pos)
		pos += 4
		if word & 0x20000000:
			pos += 1
		if word & 0x40000000:
			pos += 2
		if pos + 6 > end:
			return {}
		var x := cx + b.decode_u16(pos) * PLACEMENT_UNIT
		var y := cy + b.decode_u16(pos + 2) * PLACEMENT_UNIT
		var z := cz + b.decode_s16(pos + 4) * PLACEMENT_UNIT
		pos += 6
		kinds.append(kind)
		instances.append(word & 0x1FFFFFFF)
		xyz.append_array(PackedFloat32Array([x * FEET, z * FEET, -y * FEET]))
	if kinds.size() != count:
		return {}
	return {"kind": kinds, "instance": instances, "xyz": xyz}


## `MasterObj3D` entry: per model, its surfaces (one per texture) as
## {texture, positions (model units, Godot axes), uvs, indices}. Empty on
## error.
static func parse_course_models(b: PackedByteArray) -> Array:
	var out: Array = []
	if b.size() < 12:
		return out
	var count := b.decode_u32(8)
	var p := b.decode_u32(4)
	if count > 10000:
		return out
	for k in count:
		if p + 4 > b.size():
			return []
		var size := b.decode_u32(p)
		if size < 0x44 or p + size + 12 > b.size():
			return []
		var surfaces: Variant = _triangulate(b, p)
		if surfaces == null:
			return []
		p += size
		if b.decode_u32(p) != k:
			return []
		p += 12  # index, id, kind
		out.append(surfaces)
	return out


## The .XYZ mesh at `base` (see model.md), as an Array of surfaces per
## texture with each face fanned from its first corner; null on error.
static func _triangulate(b: PackedByteArray, base: int) -> Variant:
	var counts := PackedInt32Array()
	var offsets := PackedInt32Array()
	for i in 4:
		counts.append(b.decode_u32(base + 0x18 + 8 * i))
		offsets.append(base + b.decode_u32(base + 0x1c + 8 * i))
	var size := b.decode_u32(base)
	var end := base + size
	if offsets[0] + 12 * counts[0] > end or offsets[2] + 12 * counts[2] > end:
		return null
	# One pass per texture, so each surface is built in local arrays.
	var textures := {}
	for f in counts[2]:
		textures[b.decode_u16(offsets[2] + 12 * f + 6)] = true
	var keys := textures.keys()
	keys.sort()
	var out: Array = []
	for tex: int in keys:
		var positions := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for f in counts[2]:
			var fp := offsets[2] + 12 * f
			var n := b.decode_u16(fp)
			var first := b.decode_u16(fp + 2)
			if n < 3 or b.decode_u16(fp + 6) != tex:
				continue
			if offsets[1] + 8 * (first + n) > end or offsets[3] + 2 * (first + n) > end:
				return null
			var start := positions.size()
			for c in range(first, first + n):
				var v := b.decode_u16(offsets[3] + 2 * c)
				if v >= counts[0]:
					return null
				var vp := offsets[0] + 12 * v
				# Course axes (z up) to Godot axes (y up): (x, y, z) -> (x, z, -y).
				positions.append(Vector3(b.decode_float(vp), b.decode_float(vp + 8), -b.decode_float(vp + 4)))
				uvs.append(Vector2(b.decode_float(offsets[1] + 8 * c), b.decode_float(offsets[1] + 8 * c + 4)))
			# Godot treats clockwise as front-facing, the reverse of this data.
			for k in range(1, n - 1):
				indices.append_array(PackedInt32Array([start, start + k + 1, start + k]))
		if not indices.is_empty():
			out.append({"texture": tex, "positions": positions, "uvs": uvs, "indices": indices})
	return out


## `3DPlant` entry: the drawn placements as [{model, transform}], where the
## transform takes model units in Godot axes to Godot metres. Empty on error.
static func parse_model_placements(b: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if b.size() % 88 != 0:
		return out
	@warning_ignore("integer_division")
	for i in b.size() / 88:
		var o := i * 88
		if b.decode_float(o + 0x3C) == 0.0:
			continue  # a point record that draws nothing
		var p := {
			"position": Vector3(b.decode_float(o + 8), b.decode_float(o + 12), b.decode_float(o + 16)),
			"z_offset": b.decode_float(o + 0x30),
			"scale": Vector3(b.decode_float(o + 0x40), b.decode_float(o + 0x44), b.decode_float(o + 0x48)),
			"yaw": b.decode_float(o + 0x4C),
			"pitch": b.decode_float(o + 0x50),
		}
		# The placement is affine: find its origin and axes by placing
		# points. Model-space Godot axes are (x, z, -y) of the stored ones.
		var origin := place_point(p, Vector3.ZERO)
		var gx := place_point(p, Vector3(1, 0, 0)) - origin
		var gy := place_point(p, Vector3(0, 0, 1)) - origin
		var gz := place_point(p, Vector3(0, -1, 0)) - origin
		var basis := Basis(_to_godot(gx), _to_godot(gy), _to_godot(gz))
		out.append({"model": b.decode_u32(o + 4), "transform": Transform3D(basis, _to_godot(origin))})
	return out


## A stored model point to course feet for one placement:
## position + Rz(yaw) Ry(pitch) (scale * (v + (0, 0, z_offset))).
static func place_point(p: Dictionary, v: Vector3) -> Vector3:
	var scale: Vector3 = p.scale
	var x := scale.x * v.x
	var y := scale.y * v.y
	var z := scale.z * (v.z + float(p.z_offset))
	var cp := cos(float(p.pitch))
	var sp := sin(float(p.pitch))
	var x1 := cp * x + sp * z
	var z1 := -sp * x + cp * z
	var cy := cos(float(p.yaw))
	var sy := sin(float(p.yaw))
	var at: Vector3 = p.position
	return Vector3(at.x + cy * x1 - sy * y, at.y + sy * x1 + cy * y, at.z + z1)


## Course feet (z up) to Godot metres (y up).
static func _to_godot(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y) * FEET


## `texture3dobj.t3l` entry: per model {maq: PackedStringArray, level:
## PackedInt32Array}, one entry per texture. Empty on error.
static func parse_object_textures(b: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if b.size() < 12:
		return out
	var count := b.decode_u32(4)
	if count > 10000 or 12 + 20 * count > b.size():
		return out
	for k in count:
		var rec := 12 + 20 * k
		var textures := b.decode_u32(rec + 4)
		var levels := b.decode_u32(rec + 8)
		var list := b.decode_u32(rec + 12)
		if textures > 4096 or levels + 32 > b.size():
			return [] as Array[Dictionary]
		# Only the first level record carries a name: the model's .maq.
		var maq := b.slice(levels, levels + 32).get_string_from_ascii()
		var maqs := PackedStringArray()
		var level := PackedInt32Array()
		for _t in textures:
			if list + 4 > b.size():
				return [] as Array[Dictionary]
			var n := b.decode_u32(list)
			maqs.append(maq)
			level.append(b.decode_u32(list + 8) if n > 0 and list + 12 <= b.size() else 0)
			list += 8 + 4 * n
		out.append({"maq": maqs, "level": level})
	return out


## One level of a `.maq` entry (8-bit, 256-colour palette) as an RGBA image,
## or null on error.
static func decode_maq(b: PackedByteArray, level: int) -> Image:
	if b.size() < 16:
		return null
	var count := b.decode_u32(8)
	var first := b.decode_u32(12)
	var e := first + 36 * level
	if level < 0 or level >= count or e + 36 > b.size() or b.decode_u32(e + 8) != 8:
		return null
	var w := b.decode_u32(e)
	var h := b.decode_u32(e + 4)
	var palette := b.decode_u32(e + 28)
	var pixels := b.decode_u32(e + 32)
	if w == 0 or h == 0 or w > 4096 or h > 4096 or palette + 1024 > b.size() or pixels + w * h > b.size():
		return null
	var colours := PackedByteArray()
	colours.resize(1024)
	for i in 256:
		# Blue, green, red, alpha.
		colours[4 * i] = b[palette + 4 * i + 2]
		colours[4 * i + 1] = b[palette + 4 * i + 1]
		colours[4 * i + 2] = b[palette + 4 * i]
		colours[4 * i + 3] = b[palette + 4 * i + 3]
	var rgba := PackedByteArray()
	rgba.resize(w * h * 4)
	for i in w * h:
		var c := 4 * b[pixels + i]
		rgba[4 * i] = colours[c]
		rgba[4 * i + 1] = colours[c + 1]
		rgba[4 * i + 2] = colours[c + 2]
		rgba[4 * i + 3] = colours[c + 3]
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)


# --- Loading ------------------------------------------------------------------

## The slow part of reading the objects, as plain data that can be cached:
## {types, type, xyzh} of the billboards. `read` is a Callable taking an
## entry name and returning its bytes (empty if missing).
static func decode(read: Callable) -> Dictionary:
	var types := parse_billboard_types(read.call("MasterObj"))
	var placements := parse_billboard_placements(read.call("2DPlant"))
	if types.is_empty() or placements.is_empty():
		return {}
	var plain: Array = []
	for t in types:
		plain.append({"name": t.name, "sprite": t.sprite, "aspect": t.aspect})
	return {"types": plain, "type": placements.type, "xyzh": placements.xyzh}


## Builds the course's objects from decode()'s data and the archive (`read`
## as for decode()). `crowd_library` holds the spectator sprites; with null,
## no spectators are drawn.
static func build(read: Callable, decoded: Dictionary, crowd_library: Arc0 = null) -> CourseObjects:
	var objects := CourseObjects.new()
	if not decoded.is_empty():
		objects._load_plants(read, decoded)
	objects._load_models(read)
	if crowd_library != null:
		objects._load_crowds(read.call("TrnyPlant"), crowd_library)
	objects.obstacles.finalize()
	return objects


## CROWDS.LIB from the game folder, or null.
static func find_crowd_library() -> Arc0:
	var path := GameFolder.find_file(PackedStringArray(CROWD_LIBRARIES))
	if path.is_empty():
		return null
	return Arc0.from_bytes(FileAccess.get_file_as_bytes(path))


func _load_plants(read: Callable, decoded: Dictionary) -> void:
	var types: Array = decoded.types
	var images: Array[Image] = []
	var s := Sprites.new()
	var aspect := PackedFloat32Array()
	for t: Dictionary in types:
		var bytes: PackedByteArray = read.call(str(t.sprite)) if not str(t.sprite).is_empty() else PackedByteArray()
		var img: Image = Btcv.decode(bytes) if not bytes.is_empty() else null
		if img != null:
			img = HdPack.replace("billboards", str(t.sprite), img)
		images.append(img)
		aspect.append(float(t.aspect))
	s.aspect = aspect
	s.xyzh = decoded.xyzh
	s.sprite = decoded.type
	var atlas := build_atlas(images)
	s.rects = atlas.rects
	s.material = _material(atlas.texture)
	for t: Dictionary in types:
		s.species.append(tree_species(str(t.name)))
	_index(s)
	plants = s
	_add_plant_obstacles(types)


## Spectators drawn with the CROWDS.LIB sprites "<group><NNN><view>A.btc"
## (front views only). Which group each placement kind uses is a guess; see
## docs/formats/course-objects.md.
func _load_crowds(bytes: PackedByteArray, library: Arc0) -> void:
	var placements := parse_crowd_placements(bytes)
	if placements.is_empty():
		return
	var people := {}  # group -> sorted front-view sprite names
	for g in CROWD_GROUPS:
		var list := PackedStringArray()
		for e: Dictionary in library.entries:
			var n: String = e.name
			if n.length() == g.length() + 9 and n.substr(0, g.length()).to_lower() == g.to_lower() and n.to_lower().ends_with("aa.btc"):
				list.append(n)
		if not list.is_empty():
			list.sort()
			people[g] = list
	var s := Sprites.new()
	s.fixed_range = CROWD_RANGE
	var out_xyzh := PackedFloat32Array()
	var out_sprite := PackedInt32Array()
	var aspect := PackedFloat32Array()
	var sprite_of := {}  # name -> sprite index
	var images: Array[Image] = []
	var heights := PackedFloat32Array()  # per sprite, metres
	var kinds: PackedInt32Array = placements.kind
	var instances: PackedInt32Array = placements.instance
	var xyz: PackedFloat32Array = placements.xyz
	for i in kinds.size():
		if kinds[i] >= CROWD_GROUPS.size() or not people.has(CROWD_GROUPS[kinds[i]]):
			continue
		var list: PackedStringArray = people[CROWD_GROUPS[kinds[i]]]
		var name := list[instances[i] % list.size()]
		if not sprite_of.has(name):
			var img := Btcv.decode(library.read_named(name))
			sprite_of[name] = images.size()
			images.append(img)
			var w := img.get_width() if img != null else 128
			var h := img.get_height() if img != null else 128
			aspect.append(float(w) / float(h))
			heights.append(h / 128.0 * CROWD_SPRITE_FEET * FEET)
			if img != null:
				images[images.size() - 1] = HdPack.replace("crowds", name, img)
		var k: int = sprite_of[name]
		out_xyzh.append_array(PackedFloat32Array([xyz[3 * i], xyz[3 * i + 1], xyz[3 * i + 2], heights[k]]))
		out_sprite.append(k)
	if out_sprite.is_empty():
		return
	s.xyzh = out_xyzh
	s.sprite = out_sprite
	s.aspect = aspect
	var atlas := build_atlas(images)
	s.rects = atlas.rects
	s.material = _material(atlas.texture)
	_index(s)
	crowds = s


func _load_models(read: Callable) -> void:
	var models := parse_course_models(read.call("MasterObj3D"))
	if models.is_empty():
		return
	_placements = parse_model_placements(read.call("3DPlant"))
	var refs := parse_object_textures(read.call("texture3dobj.t3l"))
	var maqs := {}
	var textures := {}
	for k in models.size():
		var surfaces: Array = models[k]
		var mesh := ArrayMesh.new()
		var bounds := AABB()
		var first := true
		for surface: Dictionary in surfaces:
			var positions: PackedVector3Array = surface.positions
			if positions.is_empty():
				continue
			for p in positions:
				if first:
					bounds = AABB(p, Vector3.ZERO)
					first = false
				else:
					bounds = bounds.expand(p)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = positions
			arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
			arrays[Mesh.ARRAY_INDEX] = surface.indices
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays)
			st.generate_normals()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
			var tex: Texture2D = null
			var t: int = surface.texture
			if k < refs.size() and t < (refs[k].maq as PackedStringArray).size():
				tex = _maq_texture(read, refs[k].maq[t], refs[k].level[t], maqs, textures)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _model_material(tex))
		_meshes.append(mesh)
		_mesh_bounds.append(bounds)
	_add_model_obstacles()


static func _maq_texture(read: Callable, maq: String, level: int, maqs: Dictionary, textures: Dictionary) -> Texture2D:
	var key := "%s#%d" % [maq.to_lower(), level]
	if textures.has(key):
		return textures[key]
	if not maqs.has(maq):
		maqs[maq] = read.call(maq)
	var img := decode_maq(maqs[maq], level)
	var tex: Texture2D = null
	if img != null:
		img = HdPack.replace("models/" + HdPack.course, "%s_%d" % [maq.get_basename(), level], img)
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	textures[key] = tex
	return tex


static func _model_material(tex: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # thin parts are single-sided
	mat.roughness = 1.0
	if tex != null:
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	else:
		mat.albedo_color = Color(0.6, 0.6, 0.6)
	return mat


# --- Obstacles ----------------------------------------------------------------

## Trees get a solid trunk and a canopy, bushes a canopy, rocks a solid;
## grasses and the rest let the ball through. The proportions are guesses
## from the sprites, to be checked against the original game.
func _add_plant_obstacles(types: Array) -> void:
	var shape := PackedInt32Array()  # per type: 0 none, 1 tree, 2 conifer, 3 bush, 4 rock
	for t: Dictionary in types:
		shape.append(plant_shape(str(t.name)))
	var xyzh := plants.xyzh
	var type := plants.sprite
	var aspect := plants.aspect
	for i in type.size():
		var t := type[i]
		var kind := shape[t] if t < shape.size() else 0
		if kind == 0:
			continue
		var x := xyzh[4 * i]
		var y := xyzh[4 * i + 1]
		var z := xyzh[4 * i + 2]
		var h := xyzh[4 * i + 3]
		var w := h * aspect[t]
		match kind:
			1, 2:
				if h < 1.5:
					continue
				var crown := 0.35 if kind == 1 else 0.2
				obstacles.add_cylinder(x, z, clampf(0.02 * h, 0.1, 0.45), y - 1.0, y + h * (crown + 0.05), ObstacleField.Kind.SOLID)
				obstacles.add_cylinder(x, z, 0.4 * w, y + h * crown, y + h * 0.97, ObstacleField.Kind.CANOPY)
			3:
				if h >= 0.8:
					obstacles.add_cylinder(x, z, 0.4 * w, y - 0.5, y + h * 0.9, ObstacleField.Kind.CANOPY)
			4:
				obstacles.add_cylinder(x, z, 0.4 * w, y - 1.0, y + h * 0.9, ObstacleField.Kind.SOLID)


## How a billboard type stops the ball, from its name (the Course Designer
## category): 0 not at all, 1 tree, 2 conifer, 3 bush, 4 rock.
static func plant_shape(type_name: String) -> int:
	var n := type_name.to_lower()
	for word in ["evergreen", "pine", "fir", "spruce", "cedar"]:
		if n.contains(word):
			return 2
	for word in ["tree", "maple", "cherry", "decid", "fall", "dead", "oak", "palm", "willow", "birch"]:
		if n.contains(word):
			return 1
	if n.contains("bush") or n.contains("shrub") or n.contains("hedge"):
		return 3
	if n.contains("rock") or n.contains("stone") or n.contains("boulder"):
		return 4
	return 0


## The TreeFactory.Species a billboard type is drawn as with 3D trees on,
## or -1 to keep its billboard (palms and dead trees look nothing like the
## generated trees).
static func tree_species(type_name: String) -> int:
	var n := type_name.to_lower()
	if n.contains("palm") or n.contains("dead"):
		return -1
	match plant_shape(type_name):
		1:
			return TreeFactory.Species.BROADLEAF
		2:
			return TreeFactory.Species.PINE
	return -1


## 3D objects block the ball with their bounding box (in the model's own
## axes), unless they are too flat to matter.
func _add_model_obstacles() -> void:
	for p in _placements:
		var m: int = p.model
		if m >= _mesh_bounds.size():
			continue
		var bounds := _mesh_bounds[m]
		var t: Transform3D = p.transform
		var axes: Array[Vector3] = [t.basis.x, t.basis.y, t.basis.z]
		var half := bounds.size * 0.5
		var world_half := Vector3.ZERO
		var lengths := Vector3.ZERO
		for k in 3:
			lengths[k] = axes[k].length()
			if lengths[k] < 1e-9:
				break
			world_half[k] = half[k] * lengths[k]
		if lengths.x < 1e-9 or lengths.y < 1e-9 or lengths.z < 1e-9:
			continue
		var unit: Array[Vector3] = [axes[0] / lengths.x, axes[1] / lengths.y, axes[2] / lengths.z]
		var basis := Basis(unit[0], unit[1], unit[2])
		var rise := 0.0
		for k in 3:
			rise += absf(unit[k].y) * world_half[k]
		if rise < 0.15:
			continue
		obstacles.add_box(t * bounds.get_center(), basis, world_half, ObstacleField.Kind.SOLID)


# --- Drawing ------------------------------------------------------------------

## True when the atlas may use the HD limits: an HD pack is on, outside the
## browser (whose memory the larger atlas would strain).
static func hd_atlas() -> bool:
	return not OS.has_feature("web") and HdPack.is_active()


## Packs `images` (null for a missing one) into one atlas: {texture, rects}
## with rects as u, v, width, height per image. Sprites are shrunk to fit.
static func build_atlas(images: Array[Image]) -> Dictionary:
	var sizes: Array[Vector2i] = []
	var area := 0.0
	var hd := hd_atlas()
	var max_sprite := HD_MAX_SPRITE if hd else MAX_SPRITE
	var atlas_height := HD_ATLAS_HEIGHT if hd else ATLAS_HEIGHT
	for img in images:
		var s := Vector2i(4, 4) if img == null or img.is_empty() else img.get_size()
		var big := maxi(s.x, s.y)
		if big > max_sprite:
			s = Vector2i(maxi(1, roundi(float(s.x) * max_sprite / big)), maxi(1, roundi(float(s.y) * max_sprite / big)))
		sizes.append(s)
		area += (s.x + 2 * PAD) * (s.y + 2 * PAD)
	var scale := minf(1.0, sqrt(0.8 * ATLAS_SIZE * atlas_height / maxf(area, 1.0)))
	var placed: Array[Rect2i] = []
	while true:
		placed = _pack(sizes, scale, atlas_height)
		if not placed.is_empty() or scale < 0.05:
			break
		scale *= 0.9
	var height := 4
	for r in placed:
		height = maxi(height, r.end.y + PAD)
	var atlas := Image.create_empty(ATLAS_SIZE, nearest_po2(height), false, Image.FORMAT_RGBA8)
	var rects := PackedFloat32Array()
	var size := Vector2(atlas.get_size())
	for i in images.size():
		var r := placed[i] if i < placed.size() else Rect2i(0, 0, 1, 1)
		var img := images[i]
		if img == null or img.is_empty():
			img = Image.create_empty(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.2, 0.4, 0.15))
		else:
			img = img.duplicate() as Image
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			if img.get_size() != r.size:
				img.resize(r.size.x, r.size.y, Image.INTERPOLATE_BILINEAR)
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, r.size), r.position)
		rects.append_array(PackedFloat32Array([r.position.x / size.x, r.position.y / size.y, r.size.x / size.x, r.size.y / size.y]))
	atlas.generate_mipmaps()
	return {"texture": ImageTexture.create_from_image(atlas), "rects": rects}


## Shelf packing, tallest first. Empty if the sprites do not fit.
static func _pack(sizes: Array[Vector2i], scale: float, atlas_height := ATLAS_HEIGHT) -> Array[Rect2i]:
	var scaled: Array[Vector2i] = []
	var order: Array[int] = []
	for i in sizes.size():
		scaled.append(Vector2i(maxi(1, roundi(sizes[i].x * scale)), maxi(1, roundi(sizes[i].y * scale))))
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return scaled[a].y > scaled[b].y)
	var out: Array[Rect2i] = []
	out.resize(sizes.size())
	var x := PAD
	var y := PAD
	var shelf := 0
	for i in order:
		var s := scaled[i]
		if x + s.x + PAD > ATLAS_SIZE:
			x = PAD
			y += shelf + 2 * PAD
			shelf = 0
		if y + s.y + PAD > atlas_height or s.x + 2 * PAD > ATLAS_SIZE:
			return [] as Array[Rect2i]
		out[i] = Rect2i(Vector2i(x, y), s)
		x += s.x + 2 * PAD
		shelf = maxi(shelf, s.y)
	return out


static func _material(texture: Texture2D) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("atlas", texture)
	return mat


## Height class of a billboard (an index into CLASS_RANGE).
static func height_class(height_m: float) -> int:
	for c in CLASS_LIMITS.size():
		if height_m < CLASS_LIMITS[c]:
			return c
	return CLASS_LIMITS.size()


## Sorts the placements of `s` into chunk and height-class buckets.
static func _index(s: Sprites) -> void:
	@warning_ignore("integer_division")
	var n := s.xyzh.size() / 4
	if n == 0:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in n:
		var p := Vector2(s.xyzh[4 * i], s.xyzh[4 * i + 2])
		lo = lo.min(p)
		hi = hi.max(p)
	s.origin = lo
	s.cols = floori((hi.x - lo.x) / CHUNK) + 1
	s.rows = floori((hi.y - lo.y) / CHUNK) + 1
	# Locals throughout: writing into another object's packed array copies it.
	var xyzh := s.xyzh
	var cols := s.cols
	var fixed := s.fixed_range >= 0.0
	var bucket := PackedInt32Array()
	bucket.resize(n)
	var count := PackedInt32Array()
	count.resize(cols * s.rows * CLASSES + 1)
	count.fill(0)
	for i in n:
		var col := floori((xyzh[4 * i] - lo.x) / CHUNK)
		var row := floori((xyzh[4 * i + 2] - lo.y) / CHUNK)
		var c := CLASSES - 1 if fixed else height_class(xyzh[4 * i + 3])
		var b := (row * cols + col) * CLASSES + c
		bucket[i] = b
		count[b + 1] += 1
	for i in range(1, count.size()):
		count[i] += count[i - 1]
	s.start = count.duplicate()
	var order := PackedInt32Array()
	order.resize(n)
	for i in n:
		var b := bucket[i]
		order[count[b]] = i
		count[b] += 1
	s.order = order


## The visible objects near one hole. The caller owns the returned node.
func build_visual(hole: HoleData) -> Node3D:
	var root := Node3D.new()
	root.name = "CourseObjects"
	var path := PackedVector2Array([Vector2(hole.tee.x, hole.tee.z)])
	path.append_array(hole.route)
	path.append(Vector2(hole.pin.x, hole.pin.z))
	for s in [plants, crowds]:
		if s != null:
			_add_billboards(root, s, path)
	for p in _placements:
		var m: int = p.model
		if m >= _meshes.size():
			continue
		var node := MeshInstance3D.new()
		node.mesh = _meshes[m]
		node.transform = p.transform
		root.add_child(node)
	return root


func _add_billboards(root: Node3D, s: Sprites, path: PackedVector2Array) -> void:
	var quad: QuadMesh = null
	var trees := not s.species.is_empty() and TreeFactory.enabled()
	# The cache holds both ways of drawing a bucket, the 3D-trees one after
	# the plain ones.
	var offset := s.start.size() if trees else 0
	for row in s.rows:
		for col in s.cols:
			var centre := s.origin + Vector2(col + 0.5, row + 0.5) * CHUNK
			var away := distance_to_path(centre, path) - CHUNK * 0.71
			var chunk := row * s.cols + col
			if trees and away <= FAR_REACH:
				_add_trees(root, s, chunk)
			for c in CLASSES:
				var b := chunk * CLASSES + c
				if s.start[b] == s.start[b + 1]:
					continue
				var range_end := s.fixed_range if s.fixed_range >= 0.0 else CLASS_RANGE[c]
				if away > (range_end + 150.0 if range_end > 0.0 else FAR_REACH):
					continue
				if quad == null:
					quad = QuadMesh.new()
					quad.center_offset = Vector3(0, 0.5, 0)
					quad.material = s.material
				if not s.cache.has(b + offset):
					s.cache[b + offset] = _multimesh(s, b, quad, trees)
				var mm: MultiMesh = s.cache[b + offset]
				if mm == null:
					continue
				var node := MultiMeshInstance3D.new()
				node.multimesh = mm
				node.position = mm.get_meta("centre")
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.visibility_range_end = range_end
				root.add_child(node)


## The 3D trees of one chunk: the full trees of each cell, hidden beyond
## the impostor distance, and the impostors of the whole chunk.
func _add_trees(root: Node3D, s: Sprites, chunk: int) -> void:
	var key := "trees %d" % chunk
	if not s.cache.has(key):
		var trees := PackedFloat32Array()
		var xyzh := s.xyzh
		for b in range(chunk * CLASSES, (chunk + 1) * CLASSES):
			for k in range(s.start[b], s.start[b + 1]):
				var i := s.order[k]
				if is_3d_tree(s, i):
					trees.append_array(PackedFloat32Array([xyzh[4 * i], xyzh[4 * i + 1], xyzh[4 * i + 2], xyzh[4 * i + 3], s.species[s.sprite[i]]]))
		s.cache[key] = TreeFactory.batches(trees, TREE_CELL)
	var distance := TreeFactory.impostor_distance()
	for batch: Dictionary in s.cache[key]:
		var node := MultiMeshInstance3D.new()
		node.multimesh = batch.multimesh
		node.position = batch.position
		if batch.full:
			# A little past the farthest tree, measured from the cell's middle.
			node.visibility_range_end = distance + float(batch.reach) + 5.0
		else:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)


## Whether placement i of `s` is drawn as a 3D tree when they are on.
static func is_3d_tree(s: Sprites, i: int) -> bool:
	var t := s.sprite[i]
	return t < s.species.size() and s.species[t] >= 0 and s.xyzh[4 * i + 3] >= TREE_MIN_HEIGHT


## The MultiMesh of one bucket: per instance a row-major 3x4 transform
## (width and height as the scale, the base relative to the chunk centre)
## and the sprite's atlas rectangle as custom data. Null when no placement
## is left (`skip_trees` leaves out the ones drawn as 3D trees).
static func _multimesh(s: Sprites, b: int, quad: QuadMesh, skip_trees := false) -> MultiMesh:
	var order := s.order
	var xyzh := s.xyzh
	var sprite := s.sprite
	var aspect := s.aspect
	var rects := s.rects
	var picked := PackedInt32Array()
	for k in range(s.start[b], s.start[b + 1]):
		if not (skip_trees and is_3d_tree(s, order[k])):
			picked.append(order[k])
	var count := picked.size()
	if count == 0:
		return null
	var ground := 0.0
	var cx := 0.0
	var cz := 0.0
	for i in picked:
		cx += xyzh[4 * i]
		ground += xyzh[4 * i + 1]
		cz += xyzh[4 * i + 2]
	# Origins relative to the middle: visibility ranges are measured from
	# the node.
	var centre := Vector3(cx, ground, cz) / count
	var buffer := PackedFloat32Array()
	buffer.resize(count * 16)
	var o := 0
	for i in picked:
		var t := sprite[i]
		var h := xyzh[4 * i + 3]
		buffer[o] = h * aspect[t]
		buffer[o + 3] = xyzh[4 * i] - centre.x
		buffer[o + 5] = h
		buffer[o + 7] = xyzh[4 * i + 1] - centre.y
		buffer[o + 10] = 1.0
		buffer[o + 11] = xyzh[4 * i + 2] - centre.z
		buffer[o + 12] = rects[4 * t]
		buffer[o + 13] = rects[4 * t + 1]
		buffer[o + 14] = rects[4 * t + 2]
		buffer[o + 15] = rects[4 * t + 3]
		o += 16
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	mm.buffer = buffer
	mm.set_meta("centre", centre)
	mm.set_meta("buffer", buffer)
	return mm


## Horizontal distance from `p` to the polyline `path`.
static func distance_to_path(p: Vector2, path: PackedVector2Array) -> float:
	if path.size() == 1:
		return p.distance_to(path[0])
	var best := INF
	for i in path.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])
		best = minf(best, p.distance_to(q))
	return best
