class_name CrzTerrain
extends CourseTerrain
## Ground of a real course: the triangle mesh from the course archive, with a
## ground class per material from its TerrainTypes entry. Built by
## CrzCourseLoader; all holes of a course share one.

const CELL := 8.0  ## metres per side of a lookup grid cell
## How far one repeat of a ground texture spans: 12 feet, the scale of the
## courses' "Default Planar" texture mapping (docs/formats/crz.md).
const TILE_METRES := 12.0 * 0.3048

## Ground class (see olcore::parse_ground_classes) to how the ball plays.
## Ground classes that take a free photographed texture in place of the
## disc's own when photo_ground is on (not rocks).
const PHOTO_CLASSES: Array[int] = [0, 1, 2, 3, 4, 6, 7, 8, 10]
## Ground classes drawn with a photo set of their own rather than the one
## of their surface (FreeAssets.slot_for): paths and dirt.
const CLASS_SLOTS := {6: "path", 7: "dirt"}
const GROUND_SHADER := preload("res://shaders/course_ground.gdshader")
const MAPPED_SHADER := preload("res://shaders/terrain_mapped.gdshader")

## Set from the graphics settings: the Photoreal lighting draws the ground
## with the free photo textures (COURSE_GROUND shader), Classic with the
## disc's own. Takes effect on the next hole.
## Metres per repeat of each photo ground: the turf scans cover about a
## metre and a half of lawn.
const PHOTO_TILES := {"grass": 2.0, "rough": 2.2, "sand": 2.0, "path": 3.0, "dirt": 2.5}
## How strongly each scan's light and dark blades show: the lawn scan is
## shot in soft light and reads flat at playing distance.
const PHOTO_GAINS := {"grass": 2.2, "rough": 1.4, "sand": 1.0}
## Hue of healthy, watered turf (HSV, 0..1).
const MOWN_HUE := 0.27
static var photo_ground := false
static var _means := {}  ## Texture2D -> mean colour

const CLASS_SURFACE := {
	0: Surface.Type.ROUGH,
	1: Surface.Type.GREEN,
	2: Surface.Type.FAIRWAY,
	3: Surface.Type.ROUGH,
	4: Surface.Type.SAND,
	5: Surface.Type.WATER,
	6: Surface.Type.FAIRWAY,  # paths, concrete, asphalt
	7: Surface.Type.ROUGH,  # dirt
	8: Surface.Type.DEEP_ROUGH,  # bushes
	9: Surface.Type.DEEP_ROUGH,  # rocks
	10: Surface.Type.DEEP_ROUGH,  # deep or dry grass
}

## Vertex positions in metres, Godot axes.
var positions := PackedVector3Array()
var normals := PackedVector3Array()
## Three vertex indices per triangle, wound clockwise seen from above.
var triangles := PackedInt32Array()
## Material index per triangle.
var triangle_material := PackedInt32Array()
## Ground class per material.
var ground_classes := PackedByteArray()
## Per material, from its TerrainTypes record: the course's own bounce and
## roll values (LinksGround.Params) and its flags (hazard, free drop). Empty
## when the course's records could not be read.
var surfaces: Array[LinksGround.Params] = []
var material_flags := PackedInt32Array()
## The hole outlines and out-of-bounds areas; null for none.
var bounds: CourseAreas.HoleBounds
## Per material: {"texture": Texture2D or null, "colour": Color}, and for a
## free stand-in texture also "normal" (Texture2D or null), "tint" (Color)
## and "tile" (metres per repeat). A blended material also has "blend":
## {mask, texture_b (Texture2D), ground_a, ground_b (ground classes)}.
var materials: Array[Dictionary] = []
## Texture mapping (index into `mappings`) per triangle; empty when the
## course has none, and the textures then repeat every TILE_METRES.
var triangle_mapping := PackedInt32Array()
## The course's `Mappings` records (TerrainMappings.parse).
var mappings: Array[Dictionary] = []

var _origin := Vector2.ZERO
var _cols := 0
var _rows := 0
var _cell_start := PackedInt32Array()
var _cell_items := PackedInt32Array()
var _last := -1
var _mesh: ArrayMesh
var _mesh_photo := false
var _ground_colors := {}  ## material * 2 + photo -> Color, see ground_color_at()
var _strips := {}  ## strip mapping -> {triangle: [vertex, uv] x 3}
var _frames := {}  ## planar or cylindrical mapping -> [inverse axes, origin]


## Builds the lookup grid. Call once after filling the arrays.
func finalize() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in positions:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	if positions.is_empty():
		lo = Vector2.ZERO
		hi = Vector2.ZERO
	_origin = lo
	_cols = int((hi.x - lo.x) / CELL) + 1
	_rows = int((hi.y - lo.y) / CELL) + 1
	var tri_count := triangles.size() / 3
	# Two passes: count the triangles touching each cell, then fill.
	var counts := PackedInt32Array()
	counts.resize(_cols * _rows + 1)
	counts.fill(0)
	var spans := PackedInt32Array()
	spans.resize(tri_count * 4)
	for t in tri_count:
		var a := positions[triangles[3 * t]]
		var b := positions[triangles[3 * t + 1]]
		var c := positions[triangles[3 * t + 2]]
		var c0 := _col(minf(a.x, minf(b.x, c.x)))
		var c1 := _col(maxf(a.x, maxf(b.x, c.x)))
		var r0 := _row(minf(a.z, minf(b.z, c.z)))
		var r1 := _row(maxf(a.z, maxf(b.z, c.z)))
		spans[4 * t] = c0
		spans[4 * t + 1] = c1
		spans[4 * t + 2] = r0
		spans[4 * t + 3] = r1
		for r in range(r0, r1 + 1):
			for col in range(c0, c1 + 1):
				counts[r * _cols + col + 1] += 1
	for i in range(1, counts.size()):
		counts[i] += counts[i - 1]
	_cell_start = counts
	_cell_items.resize(counts[counts.size() - 1])
	var fill := counts.duplicate()
	for t in tri_count:
		for r in range(spans[4 * t + 2], spans[4 * t + 3] + 1):
			for col in range(spans[4 * t], spans[4 * t + 1] + 1):
				var cell := r * _cols + col
				_cell_items[fill[cell]] = t
				fill[cell] += 1


func _col(x: float) -> int:
	return clampi(int((x - _origin.x) / CELL), 0, _cols - 1)


func _row(z: float) -> int:
	return clampi(int((z - _origin.y) / CELL), 0, _rows - 1)


## Index of the triangle under (x, z), or -1 off the course.
func triangle_at(x: float, z: float) -> int:
	if _last >= 0 and _height_in(_last, x, z) != INF:
		return _last
	if _cols == 0 or x < _origin.x or z < _origin.y:
		return -1
	var col := int((x - _origin.x) / CELL)
	var row := int((z - _origin.y) / CELL)
	if col >= _cols or row >= _rows:
		return -1
	var cell := row * _cols + col
	for i in range(_cell_start[cell], _cell_start[cell + 1]):
		var t := _cell_items[i]
		if _height_in(t, x, z) != INF:
			_last = t
			return t
	return -1


## Height of triangle t at (x, z), or INF if the point is outside it.
func _height_in(t: int, x: float, z: float) -> float:
	var a := positions[triangles[3 * t]]
	var b := positions[triangles[3 * t + 1]]
	var c := positions[triangles[3 * t + 2]]
	var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(d) < 1e-9:
		return INF
	var u := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
	var v := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
	var w := 1.0 - u - v
	const EPS := -1e-5
	if u < EPS or v < EPS or w < EPS:
		return INF
	return u * a.y + v * b.y + w * c.y


func height_at(x: float, z: float) -> float:
	var t := triangle_at(x, z)
	return _height_in(t, x, z) if t >= 0 else 0.0


func surface_at(x: float, z: float) -> int:
	var t := triangle_at(x, z)
	if t < 0:
		return Surface.Type.OUT_OF_BOUNDS
	var m := triangle_material[t]
	var ground := ground_classes[m] if m < ground_classes.size() else 3
	return CLASS_SURFACE.get(ground, Surface.Type.ROUGH)


## Paths, concrete, asphalt and walls give a free drop, as in Links 2003:
## the records flagged for it, or ground class 6 without records.
func free_drop_at(x: float, z: float) -> bool:
	var t := triangle_at(x, z)
	if t < 0:
		return false
	var m := triangle_material[t]
	if m < material_flags.size():
		return material_flags[m] & CourseAreas.FREE_DROP != 0
	return m < ground_classes.size() and ground_classes[m] == 6


## The records the course flags as hazards (water, mud, some dry brush).
func hazard_at(x: float, z: float) -> bool:
	var t := triangle_at(x, z)
	if t < 0:
		return false
	var m := triangle_material[t]
	return m < material_flags.size() and material_flags[m] & CourseAreas.HAZARD != 0


## Inside the hole's outline and outside its out-of-bounds areas.
func in_bounds(x: float, z: float) -> bool:
	if bounds == null:
		return true
	return bounds.in_bounds(hole_number, x / CrzCourseLoader.FEET, -z / CrzCourseLoader.FEET)


func links_surface_at(x: float, z: float) -> LinksGround.Params:
	var t := triangle_at(x, z)
	if t < 0:
		return null
	var m := triangle_material[t]
	return surfaces[m] if m < surfaces.size() else null


## The mean colour of the material's texture times its tint, or its flat
## colour.
func ground_color_at(x: float, z: float) -> Color:
	var t := triangle_at(x, z)
	if t < 0:
		return super(x, z)
	var m := triangle_material[t]
	# Keyed by the ground style too: grass tufts take the photo ground's
	# deeper colour when it is on.
	var key := m * 2 + (1 if photo_ground else 0)
	if not _ground_colors.has(key):
		var info: Dictionary = materials[m] if m < materials.size() else {}
		var c: Color = info.get("colour", Color(0.3, 0.5, 0.2))
		var tex: Texture2D = info.get("texture")
		if tex != null:
			var tint: Color = info.get("tint", Color.WHITE)
			c = FreeAssets.mean_color(tex) * tint
		var ground := ground_classes[m] if m < ground_classes.size() else 3
		if photo_ground and ground in PHOTO_CLASSES:
			c = realistic_class(c, ground)
		_ground_colors[key] = c
	return _ground_colors[key]


func normal_at(x: float, z: float) -> Vector3:
	var t := triangle_at(x, z)
	if t < 0:
		return Vector3.UP
	var a := positions[triangles[3 * t]]
	var b := positions[triangles[3 * t + 1]]
	var c := positions[triangles[3 * t + 2]]
	var n := (c - a).cross(b - a).normalized()
	return n if n.y >= 0.0 else -n


func build_visual() -> Node3D:
	if _mesh == null or _mesh_photo != photo_ground:
		_mesh_photo = photo_ground
		_mesh = _build_mesh()
	var node := MeshInstance3D.new()
	node.mesh = _mesh
	return node


## One surface per material, each with its own copy of the vertices it uses.
## UV is the first texture layer's coordinates under the triangle's
## mapping, UV2 the second layer's, and CUSTOM0 the mask's (blended
## materials only).
func _build_mesh() -> ArrayMesh:
	var by_material := {}
	for t in triangles.size() / 3:
		var m := triangle_material[t]
		if not by_material.has(m):
			by_material[m] = []
		(by_material[m] as Array).append(t)
	var keys := by_material.keys()
	keys.sort()
	var mesh := ArrayMesh.new()
	var mapped := not mappings.is_empty() and triangle_mapping.size() == triangles.size() / 3
	for m in keys:
		var blended := _blend_of(int(m)) != null
		var remap := {}
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uv1 := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var mask := PackedFloat32Array()
		var indices := PackedInt32Array()
		for t: int in by_material[m]:
			var layers := _triangle_layers(t) if mapped else PackedInt32Array([-1, -1, -1])
			var a := _corner_uvs(layers[1], t)
			var b := a if layers[2] == layers[1] else _corner_uvs(layers[2], t)
			var s := _corner_uvs(layers[0], t) if blended else PackedVector2Array()
			# Corners share a vertex when they come from the same mapping
			# and no seam fix-up changed them.
			var key_base := (triangle_mapping[t] + 1) if mapped else 0
			if a.size() > 3 or b.size() > 3:
				key_base = -1
			for k in 3:
				var v := triangles[3 * t + k]
				var key := v * 131072 + key_base if key_base >= 0 else -1 - verts.size()
				if not remap.has(key):
					remap[key] = verts.size()
					verts.append(positions[v])
					norms.append(normals[v])
					uv1.append(a[k])
					uv2.append(b[k])
					if blended:
						mask.append(clampf(s[k].x, 0.0, 1.0))
						mask.append(s[k].y)
				indices.append(remap[key])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uv1
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var flags := 0
		if blended:
			arrays[Mesh.ARRAY_CUSTOM0] = mask
			flags = Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(int(m), mapped))
	return mesh


## The mappings triangle t uses: [mask strip, first layer, second layer],
## -1 where there is none.
func _triangle_layers(t: int) -> PackedInt32Array:
	var k := triangle_mapping[t]
	if k < 0 or k >= mappings.size():
		return PackedInt32Array([-1, -1, -1])
	var m: Dictionary = mappings[k]
	if m.kind == TerrainMappings.Kind.BLEND:
		return m.layers
	return PackedInt32Array([-1, k, k])


## Texture coordinates of triangle t's three corners under mapping l (12
## feet per repeat, laid flat, without one). A cylindrical triangle that
## straddles the seam gets a fourth, unused entry, so its corners are not
## shared.
func _corner_uvs(l: int, t: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(3)
	if l < 0:
		for k in 3:
			var p := positions[triangles[3 * t + k]]
			out[k] = Vector2(p.x, p.z) / TILE_METRES
		return out
	var m: Dictionary = mappings[l]
	if m.kind == TerrainMappings.Kind.STRIP:
		if not _strips.has(l):
			_strips[l] = _strip_lookup(m)
		var e: Array = (_strips[l] as Dictionary).get(t, [])
		for k in 3:
			var v := triangles[3 * t + k]
			for i in range(0, e.size(), 2):
				if e[i] == v:
					out[k] = e[i + 1]
		return out
	if not _frames.has(l):
		var f: PackedFloat32Array = m.frame
		var axes := Basis(Vector3(f[0], f[1], f[2]), Vector3(f[4], f[5], f[6]), Vector3(f[8], f[9], f[10]))
		_frames[l] = [axes.inverse() if absf(axes.determinant()) > 1e-12 else Basis(), Vector3(f[12], f[13], f[14])]
	var frame: Array = _frames[l]
	var inv: Basis = frame[0]
	var scale: Vector2 = m.scale
	for k in 3:
		var local: Vector3 = inv * (TerrainMappings.to_course(positions[triangles[3 * t + k]]) - (frame[1] as Vector3))
		if m.kind == TerrainMappings.Kind.CYLINDRICAL:
			out[k] = Vector2(atan2(local.y, local.x) / TAU * scale.x, local.z * scale.y)
		else:
			out[k] = Vector2(local.x * scale.x, local.y * scale.y)
	if m.kind == TerrainMappings.Kind.CYLINDRICAL:
		var top := maxf(out[0].x, maxf(out[1].x, out[2].x))
		if top - minf(out[0].x, minf(out[1].x, out[2].x)) > absf(scale.x) * 0.5:
			for k in 3:
				if top - out[k].x > absf(scale.x) * 0.5:
					out[k].x += absf(scale.x)
			out.append(Vector2.ZERO)
	return out


static func _strip_lookup(m: Dictionary) -> Dictionary:
	var out := {}
	var tris: PackedInt32Array = m.strip_triangles
	var cv: PackedInt32Array = m.corner_vertex
	var cu: PackedVector2Array = m.corner_uv
	for i in tris.size() / 4:
		var e := []
		for k in 3:
			var c := tris[4 * i + 1 + k]
			e.append(cv[c])
			e.append(cu[c])
		out[tris[4 * i]] = e
	return out


func _blend_of(m: int) -> Variant:
	if m >= materials.size():
		return null
	return materials[m].get("blend")


func _material(m: int, mapped := false) -> Material:
	var ground := ground_classes[m] if m < ground_classes.size() else 3
	var surface: Surface.Type = CLASS_SURFACE.get(ground, Surface.Type.ROUGH)
	if surface == Surface.Type.WATER:
		return Materials.water_surface()
	var info: Dictionary = materials[m] if m < materials.size() else {}
	var blend: Variant = info.get("blend") if mapped else null
	if photo_ground:
		if blend != null:
			var photo := _photo_blend(info, blend as Dictionary)
			if photo != null:
				return photo
		elif ground in PHOTO_CLASSES:
			var photo := _photo_material(ground, info)
			if photo != null:
				return photo
	var tex: Texture2D = info.get("texture")
	if tex != null and mapped and not info.has("tile"):
		return _mapped_material(surface, info, blend)
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.albedo_color = info.get("colour", Color(0.3, 0.5, 0.2))
	if tex != null:
		mat.albedo_texture = tex
		mat.albedo_color = info.get("tint", Color.WHITE)
		var normal: Texture2D = info.get("normal")
		var scale := 1.0
		if normal == null:
			# The disc textures have no bumps of their own: borrow the
			# free photo texture's, gently, so low sun picks out the grain.
			normal = FreeAssets.ground(FreeAssets.slot_for(surface), "normal")
			scale = 0.45
		if normal != null:
			mat.normal_enabled = true
			mat.normal_texture = normal
			mat.normal_scale = scale
		mat.roughness = _disc_roughness(surface)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE / float(info.get("tile", TILE_METRES))
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.next_pass = Materials.ground_shade_pass()
	return mat


## Ground is matt; mown grass only a touch less so.
static func _disc_roughness(surface: Surface.Type) -> float:
	return 0.95 if surface == Surface.Type.GREEN or surface == Surface.Type.FAIRWAY else 1.0


## The disc's own texture (and for a blended material its mask and second
## texture) laid out by the course's mappings (MAPPED_SHADER).
static func _mapped_material(surface: Surface.Type, info: Dictionary, blend: Variant) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = MAPPED_SHADER
	mat.set_shader_parameter("texture_a", info.texture)
	mat.set_shader_parameter("roughness_a", _disc_roughness(surface))
	var normal := FreeAssets.ground(FreeAssets.slot_for(surface), "normal")
	mat.set_shader_parameter("normal_tex", normal)
	mat.set_shader_parameter("has_normal", normal != null)
	if blend != null:
		var b: Dictionary = blend
		var surface_b: Surface.Type = CLASS_SURFACE.get(b.ground_b, Surface.Type.ROUGH)
		mat.set_shader_parameter("blended", true)
		mat.set_shader_parameter("texture_b", b.texture_b)
		mat.set_shader_parameter("mask_tex", b.mask)
		mat.set_shader_parameter("roughness_a", _disc_roughness(CLASS_SURFACE.get(b.ground_a, surface)))
		mat.set_shader_parameter("roughness_b", _disc_roughness(surface_b))
	return mat


## The photo ground for a material: the free texture of its surface,
## tinted to the mean colour of the course's own texture (or its class
## colour), toned down to the brightness of real turf. Null without the
## free textures.
static func _photo_material(ground: int, info: Dictionary) -> ShaderMaterial:
	var params := _photo_params(ground, info)
	if params.is_empty():
		return null
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	for key: String in params:
		mat.set_shader_parameter(key, params[key])
	return mat


## A blended material in the photo ground: both layers' photo grounds,
## faded by the course's mask. Null when either layer has no photo ground
## (paths, dirt, rocks).
static func _photo_blend(info: Dictionary, blend: Dictionary) -> ShaderMaterial:
	var ga: int = blend.ground_a
	var gb: int = blend.ground_b
	if not (ga in PHOTO_CLASSES and gb in PHOTO_CLASSES):
		return null
	var a := _photo_params(ga, info)
	var b := _photo_params(gb, {"texture": blend.texture_b})
	if a.is_empty() or b.is_empty():
		return null
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	for key: String in a:
		mat.set_shader_parameter(key, a[key])
	for key: String in b:
		if key != "stripe_angle":
			mat.set_shader_parameter(key + "_b", b[key])
	mat.set_shader_parameter("blended", true)
	mat.set_shader_parameter("mask_tex", blend.mask)
	return mat


## The COURSE_GROUND parameters for one photo layer, or empty without the
## free textures.
static func _photo_params(ground: int, info: Dictionary) -> Dictionary:
	var surface: Surface.Type = CLASS_SURFACE.get(ground, Surface.Type.ROUGH)
	var slot: String = CLASS_SLOTS.get(ground, FreeAssets.slot_for(surface))
	var photo := FreeAssets.ground(slot, "albedo")
	if photo == null:
		return {}
	var own: Texture2D = info.get("texture")
	var target: Color = info.get("colour", Color(0.3, 0.5, 0.2))
	if own != null and own != photo:
		target = _mean(own)
	target = realistic_class(target, ground)
	var normal := FreeAssets.ground(slot, "normal")
	var rough := FreeAssets.ground(slot, "roughness")
	var p := {
		"albedo_tex": photo,
		"normal_tex": normal,
		"has_normal": normal != null,
		"roughness_tex": rough,
		"has_roughness": rough != null,
		"photo_mean": _mean(photo),
		"far_color": target,
		"tile": PHOTO_TILES.get(slot, CrzCourseLoader.FREE_TILE_METRES),
		"detail_gain": PHOTO_GAINS.get(slot, 1.0),
		# The lawn scan's yellow tips would turn the course's greens lime.
		"photo_hue": 0.1 if slot == "grass" else 0.3,
		"stripes": 0.0,
		"stripe_width": 9.0,
		"roughness_value": 0.92,
		"variation": 0.14,
	}
	if CLASS_SLOTS.has(ground):
		# Paths and dirt: no stripes, a little wear in patches.
		p.roughness_value = 0.9
		p.variation = 0.08
		return p
	match surface:
		Surface.Type.GREEN:
			# Cut to a few millimetres: the lawn scan smaller and softer,
			# so it reads as fine, dense turf rather than fairway grass.
			p.tile = 0.6
			p.detail_gain = 1.3
			p.stripes = 0.07
			p.stripe_width = 3.0
			p.roughness_value = 0.78
			p.variation = 0.05
		Surface.Type.FAIRWAY:
			p.stripes = 0.09
			p.roughness_value = 0.82
			p.variation = 0.09
		Surface.Type.SAND:
			p.variation = 0.06
			p.roughness_value = 0.95
	return p


## realistic() for ground class `ground`: paths and dirt keep their hue
## and colour, a little darker, as the disc draws them pale too.
static func realistic_class(c: Color, ground: int) -> Color:
	if CLASS_SLOTS.has(ground):
		return Color.from_hsv(c.h, c.s, c.v * 0.85)
	return realistic(c, CLASS_SURFACE.get(ground, Surface.Type.ROUGH))


## A course colour (sRGB) as real ground of that surface would be: the 2003
## textures are bright and pale for a dim CRT and a flat light; turf in
## sunlight is darker and deeper.
static func realistic(c: Color, surface: Surface.Type) -> Color:
	# (Lighter than they would be with a sheen: the ground is matt, so the
	# sun's glare no longer brightens it.)
	var out := Color.from_hsv(c.h, clampf(c.s * 1.15, 0.0, 0.85), c.v * 0.8)
	if surface == Surface.Type.ROUGH or surface == Surface.Type.DEEP_ROUGH:
		# Pale disc rough reads as bare ground; real rough and fescue are
		# olive and straw, with more colour and less light.
		out = Color.from_hsv(c.h, clampf(maxf(c.s * 1.6, 0.3), 0.0, 0.7), c.v * 0.7)
	elif surface == Surface.Type.SAND:
		out = Color.from_hsv(c.h, clampf(c.s * 0.9, 0.0, 0.5), minf(c.v * 0.92, 0.85))
	elif c.h > 0.12 and c.h < 0.45:
		# Mown grass: the disc's yellowish greens pulled towards the deep
		# green of watered turf.
		out = Color.from_hsv(lerpf(c.h, MOWN_HUE, 0.5), out.s * 0.92, c.v * 0.72)
	return out


static func _mean(tex: Texture2D) -> Color:
	if not _means.has(tex):
		_means[tex] = FreeAssets.mean_color(tex)
	return _means[tex]
