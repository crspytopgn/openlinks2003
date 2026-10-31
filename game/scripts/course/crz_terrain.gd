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
## disc's own when photo_ground is on (not paths, dirt or rocks).
const PHOTO_CLASSES: Array[int] = [0, 1, 2, 3, 4, 8, 10]
const GROUND_SHADER := preload("res://shaders/course_ground.gdshader")

## Set from the graphics settings: the Photoreal lighting draws the ground
## with the free photo textures (COURSE_GROUND shader), Classic with the
## disc's own. Takes effect on the next hole.
## Metres per repeat of each photo ground: the turf scans cover about a
## metre and a half of lawn.
const PHOTO_TILES := {"grass": 2.0, "rough": 2.2, "sand": 2.5}
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
## Per material: {"texture": Texture2D or null, "colour": Color}, and for a
## free stand-in texture also "normal" (Texture2D or null), "tint" (Color)
## and "tile" (metres per repeat)
var materials: Array[Dictionary] = []

var _origin := Vector2.ZERO
var _cols := 0
var _rows := 0
var _cell_start := PackedInt32Array()
var _cell_items := PackedInt32Array()
var _last := -1
var _mesh: ArrayMesh
var _mesh_photo := false
var _ground_colors := {}  ## material * 2 + photo -> Color, see ground_color_at()


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


## Paths, concrete and asphalt (ground class 6) give a free drop, as in
## Links 2003.
func free_drop_at(x: float, z: float) -> bool:
	var t := triangle_at(x, z)
	if t < 0:
		return false
	var m := triangle_material[t]
	return m < ground_classes.size() and ground_classes[m] == 6


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
			c = realistic(c, CLASS_SURFACE.get(ground, Surface.Type.ROUGH))
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
	var remap := PackedInt32Array()
	remap.resize(positions.size())
	for m in keys:
		remap.fill(-1)
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var indices := PackedInt32Array()
		for t: int in by_material[m]:
			for k in 3:
				var v := triangles[3 * t + k]
				if remap[v] < 0:
					remap[v] = verts.size()
					verts.append(positions[v])
					norms.append(normals[v])
				indices.append(remap[v])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(int(m)))
	return mesh


func _material(m: int) -> Material:
	var ground := ground_classes[m] if m < ground_classes.size() else 3
	var surface: Surface.Type = CLASS_SURFACE.get(ground, Surface.Type.ROUGH)
	if surface == Surface.Type.WATER:
		return Materials.water_surface()
	var info: Dictionary = materials[m] if m < materials.size() else {}
	if photo_ground and ground in PHOTO_CLASSES:
		var photo := _photo_material(surface, info)
		if photo != null:
			return photo
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.albedo_color = info.get("colour", Color(0.3, 0.5, 0.2))
	var tex: Texture2D = info.get("texture")
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
		if surface == Surface.Type.GREEN or surface == Surface.Type.FAIRWAY:
			# Mown grass has a faint sheen.
			mat.roughness = 0.82
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE / float(info.get("tile", TILE_METRES))
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.next_pass = Materials.ground_shade_pass()
	return mat


## The photo ground for a material: the free texture of its surface,
## tinted to the mean colour of the course's own texture (or its class
## colour), toned down to the brightness of real turf. Null without the
## free textures.
static func _photo_material(surface: Surface.Type, info: Dictionary) -> ShaderMaterial:
	var slot := FreeAssets.slot_for(surface)
	var photo := FreeAssets.ground(slot, "albedo")
	if photo == null:
		return null
	var own: Texture2D = info.get("texture")
	var target: Color = info.get("colour", Color(0.3, 0.5, 0.2))
	if own != null and own != photo:
		target = _mean(own)
	target = realistic(target, surface)
	var mean := _mean(photo)
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("albedo_tex", photo)
	var normal := FreeAssets.ground(slot, "normal")
	mat.set_shader_parameter("normal_tex", normal)
	mat.set_shader_parameter("has_normal", normal != null)
	var rough := FreeAssets.ground(slot, "roughness")
	mat.set_shader_parameter("roughness_tex", rough)
	mat.set_shader_parameter("has_roughness", rough != null)
	mat.set_shader_parameter("photo_mean", mean)
	mat.set_shader_parameter("far_color", target)
	mat.set_shader_parameter("tile", PHOTO_TILES.get(slot, CrzCourseLoader.FREE_TILE_METRES))
	mat.set_shader_parameter("detail_gain", PHOTO_GAINS.get(slot, 1.0))
	# The lawn scan's yellow tips would turn the course's greens lime.
	mat.set_shader_parameter("photo_hue", 0.1 if slot == "grass" else 0.3)
	match surface:
		Surface.Type.GREEN:
			mat.set_shader_parameter("stripes", 0.07)
			mat.set_shader_parameter("stripe_width", 3.0)
			mat.set_shader_parameter("roughness_value", 0.78)
			mat.set_shader_parameter("variation", 0.05)
		Surface.Type.FAIRWAY:
			mat.set_shader_parameter("stripes", 0.09)
			mat.set_shader_parameter("roughness_value", 0.82)
			mat.set_shader_parameter("variation", 0.09)
		Surface.Type.SAND:
			mat.set_shader_parameter("variation", 0.06)
			mat.set_shader_parameter("roughness_value", 0.95)
	return mat


## A course colour (sRGB) as real ground of that surface would be: the 2003
## textures are bright and pale for a dim CRT and a flat light; turf in
## sunlight is darker and deeper.
static func realistic(c: Color, surface: Surface.Type) -> Color:
	var out := Color.from_hsv(c.h, clampf(c.s * 1.15, 0.0, 0.85), c.v * 0.72)
	if surface == Surface.Type.ROUGH or surface == Surface.Type.DEEP_ROUGH:
		# Pale disc rough reads as bare ground; real rough and fescue are
		# olive and straw, with more colour and less light.
		out = Color.from_hsv(c.h, clampf(maxf(c.s * 1.6, 0.3), 0.0, 0.7), c.v * 0.62)
	elif surface == Surface.Type.SAND:
		out = Color.from_hsv(c.h, clampf(c.s * 0.9, 0.0, 0.5), minf(c.v * 0.92, 0.85))
	elif c.h > 0.12 and c.h < 0.45:
		# Mown grass: the disc's yellowish greens pulled towards the deep
		# green of watered turf.
		out = Color.from_hsv(lerpf(c.h, MOWN_HUE, 0.5), out.s, c.v * 0.62)
	return out


static func _mean(tex: Texture2D) -> Color:
	if not _means.has(tex):
		_means[tex] = FreeAssets.mean_color(tex)
	return _means[tex]
