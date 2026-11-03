class_name FarScenery
extends Node3D
## The land beyond the course, for courses that bring no horizon panorama of
## their own (the built-in course, designed and real-world courses): rings
## of wooded hills and farmland ridges, one behind the other, each paler and
## bluer than the one in front until the last melts into the sky. In real
## photos of parkland courses (Knole Park, Sundridge Park on Geograph) the
## treeline a kilometre or two off is a dark blue-green band with bumpy
## crowns, the ridges behind it step towards the sky's colour, and each
## one's foot is lost in a milky ground haze while its top stays crisp.
## That stepping is what makes the horizon read as miles away; one flat
## edge where the ground meets the sky reads as the end of a model.
##
## Each ring is one band of quads round the course. Its outline (the hills
## and the tree crowns on them) comes from a small profile texture baked
## here, so the GPU work is a texture read and a few mixes per pixel, cheap
## enough for phones and the web build. The scene's own distance fog then
## fades each ring by how far off it really is, so the layers keep in step
## with the time of day's haze. The rings are fixed round the course, not
## the camera, so they shift against each other as the player walks.

## One ring: how far beyond the course's edge it stands (metres), its
## hills' height and size, its tree crowns' height and width, how much of
## it is woods rather than open fields, the ground haze at its foot, how
## much air it is seen through (metres, for the distance haze: the rings
## stand closer than the land they show, as the camera's far plane allows)
## and the lowest quality that draws it.
const LAYERS := [
	{out = 350.0, hill = 18.0, hill_size = 500.0, tree = 19.0, crown = 9.0, woods = 0.8, haze = 0.3, air = 1300.0, quality = GraphicsSettings.Quality.LOW},
	{out = 700.0, hill = 45.0, hill_size = 800.0, tree = 20.0, crown = 11.0, woods = 0.75, haze = 0.4, air = 2400.0, quality = GraphicsSettings.Quality.MEDIUM},
	{out = 1050.0, hill = 80.0, hill_size = 1100.0, tree = 21.0, crown = 13.0, woods = 0.7, haze = 0.45, air = 3800.0, quality = GraphicsSettings.Quality.LOW},
	{out = 1400.0, hill = 130.0, hill_size = 1500.0, tree = 22.0, crown = 15.0, woods = 0.65, haze = 0.5, air = 5800.0, quality = GraphicsSettings.Quality.HIGH},
]
## Clear summer air over farmland: how much of the haze colour a kilometre
## of air lays over the land, by the scene's fog (Knole Park on a clear
## day: a wooded ridge about 5 km off is about a quarter haze in linear
## light, the treeline 1 km off about a tenth). The scene's own fog is
## heavier, for the course; the far land follows it a third as fast.
const AIR_PER_FOG := 0.33
## The round camera's far plane (main.gd): every ring must be inside it
## from anywhere on the course.
const CAMERA_FAR := 3000.0
const MIN_GAP := 40.0
## Profile samples round each ring: about 3 m apart on the front ring, so
## crowns are a few samples wide.
const PROFILE_WIDTH := 4096
const SEGMENTS := 256
## How far below its base each band reaches, so it still covers the gap
## past the course's ground when the camera is high up (the flyover).
const DEPTH_BELOW := 400.0
## Deciduous woods seen from a distance, before haze: dark olive green,
## the crowns' sunlit tops a little lighter (linear colours).
const FOREST := Color(0.035, 0.05, 0.022)
const FOREST_TOP := Color(0.06, 0.08, 0.035)
## Open farmland on the ridges: summer grass and crops.
const FIELD := Color(0.11, 0.12, 0.05)

const SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;
// Per ring: R the outline height (0 to 1 of `top`), G woods (1) or fields
// (0) on the hill, B how deep the tree crowns along the top are (of `top`).
uniform sampler2D profile : filter_linear, repeat_enable;
uniform float row = 0.5;
uniform float top = 100.0;
uniform float base_y = 0.0;
uniform float circumference = 10000.0;
uniform float tree = 20.0;
uniform vec3 forest : source_color;
uniform vec3 forest_top : source_color;
uniform vec3 field : source_color;
uniform vec3 haze_color : source_color = vec3(0.7, 0.78, 0.86);
uniform float ground_haze = 0.4;
uniform float distance_haze = 0.4;
uniform float haze_height = 60.0;
uniform float detail = 0.0;
uniform float brightness = 1.0;
global uniform vec3 sun_travel;
varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = texture(profile, vec2(UV.x, row)).rgb;
	float h = p.r * top;
	float y = world.y - base_y;
	// A pixel's worth of soft edge, so the crowns don't crawl.
	float aa = max(fwidth(y), 0.01);
	float alpha = 1.0 - smoothstep(h - aa, h + aa, y);
	if (alpha <= 0.0) {
		discard;
	}
	// Crowns along the top (woods, or a copse in the fields), then the
	// hill under them: woods in their own shade, or fields.
	float depth = h - y;
	float crown = p.b * top;
	float in_crown = 1.0 - smoothstep(crown - aa - 1.0, crown + aa + 1.0, depth);
	vec3 trees = mix(forest_top, forest, smoothstep(0.0, 1.0, depth / max(tree * 0.6, 1.0)));
	float woods = max(p.g, in_crown);
	vec3 c = mix(field, trees, woods);
	if (detail > 0.0) {
		// Single crowns and the gaps between them, on the near rings.
		vec2 q = vec2(UV.x * circumference, y) / 7.0;
		float n = value_noise(q) * 0.6 + value_noise(q * 2.7) * 0.4;
		c *= mix(1.0, 0.65 + 0.7 * n, detail * woods);
	}
	// Lit from the front when looking away from the sun, a dark silhouette
	// against a brighter haze when looking into it.
	vec3 view = normalize(world - CAMERA_POSITION_WORLD);
	float away = dot(normalize(view.xz + vec2(1e-4)), normalize(sun_travel.xz + vec2(1e-4)));
	c *= mix(0.7, 1.2, away * 0.5 + 0.5) * brightness;
	vec3 haze = haze_color * (1.0 + 0.2 * max(-away, 0.0));
	// Ground haze: the ring's foot fades away, its top stays clear.
	float g = ground_haze * (1.0 - smoothstep(0.0, haze_height, y));
	ALBEDO = mix(c, haze, 1.0 - (1.0 - distance_haze) * (1.0 - g));
	ALPHA = alpha;
}
"""

var _rings: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []


## The far scenery round `course` (null when it has no holes).
static func create(course: CourseData) -> FarScenery:
	var bounds := course_bounds(course)
	if bounds.size == Vector2.ZERO:
		return null
	# The land round about stands on the course's middle height, so from
	# a high tee it still rises above the course's own trees.
	var base := 0.0
	for h in course.holes:
		base += (h.tee.y + h.pin.y) * 0.5
	base /= course.holes.size()
	var f := FarScenery.new()
	f.name = "FarScenery"
	f.build(bounds, base - 3.0, hash(course.course_name))
	return f


## The ground the course covers, seen from above (x, z): its designed
## area when it has one, else its holes' tees and pins with room round them.
static func course_bounds(course: CourseData) -> Rect2:
	var r := Rect2()
	var first := true
	for h in course.holes:
		for p: Vector3 in [h.tee, h.pin]:
			var q := Vector2(p.x, p.z)
			if first:
				r = Rect2(q, Vector2.ZERO)
				first = false
			else:
				r = r.expand(q)
		if h.terrain is DesignedTerrain:
			r = r.merge((h.terrain as DesignedTerrain).course.area)
	if first:
		return Rect2()
	return r.grow(120.0)


## The rings' radii round the course's middle for a course whose ground has
## `half_diagonal`: past the course by each layer's `out`, but squeezed in
## where a large course would put the back rings beyond the camera's far
## plane (from the far corner of the course). They always keep MIN_GAP
## between them; on a huge course the back ones then drop out of view from
## its far corners, and the near ones still show.
static func radii(half_diagonal: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var limit := CAMERA_FAR - 60.0 - half_diagonal
	var first: float = half_diagonal + LAYERS[0].out
	var last: float = half_diagonal + LAYERS[LAYERS.size() - 1].out
	var squeeze := 1.0
	if last > limit:
		squeeze = maxf(limit - first, MIN_GAP * (LAYERS.size() - 1)) / maxf(last - first, 1.0)
	for l: Dictionary in LAYERS:
		out.append(first + (float(l.out) - float(LAYERS[0].out)) * squeeze)
	return out


func build(bounds: Rect2, base_y: float, seed: int) -> void:
	var centre := bounds.get_center()
	position = Vector3(centre.x, base_y, centre.y)
	var r := radii(bounds.size.length() * 0.5)
	var img := profiles(seed, r)
	var tex := ImageTexture.create_from_image(img)
	var shader := Shader.new()
	shader.code = SHADER
	for i in LAYERS.size():
		var l: Dictionary = LAYERS[i]
		var top: float = float(l.hill) + float(l.tree) * 1.3
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("profile", tex)
		mat.set_shader_parameter("row", (i + 0.5) / LAYERS.size())
		mat.set_shader_parameter("top", top)
		mat.set_shader_parameter("base_y", base_y)
		mat.set_shader_parameter("circumference", TAU * r[i])
		mat.set_shader_parameter("tree", l.tree)
		mat.set_shader_parameter("forest", FOREST.linear_to_srgb())
		mat.set_shader_parameter("forest_top", FOREST_TOP.linear_to_srgb())
		mat.set_shader_parameter("field", FIELD.linear_to_srgb())
		mat.set_shader_parameter("ground_haze", l.haze)
		mat.set_shader_parameter("haze_height", top * 0.7)
		# The back ring draws first, each nearer one over it.
		mat.render_priority = -10 + (LAYERS.size() - 1 - i)
		var ring := MeshInstance3D.new()
		ring.name = "Ring%d" % i
		ring.mesh = _ring_mesh(r[i], top + 2.0, -DEPTH_BELOW)
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(ring)
		_rings.append(ring)
		_materials.append(mat)


## Draws the rings the quality calls for, with crown detail from High up.
func apply_quality(quality: int) -> void:
	for i in _rings.size():
		var l: Dictionary = LAYERS[i]
		_rings[i].visible = quality >= int(l.quality)
		_materials[i].set_shader_parameter("detail", (0.5 if i == 0 else 0.3) if quality >= GraphicsSettings.Quality.HIGH and i < 2 else 0.0)


## The haze the rings fade into: the scene's fog colour, and its density
## (Environment.fog_density) for how thick it is. `brightness` scales the
## land for the lighting (Classic's linear tone map shows it darker).
func set_haze(color: Color, fog_density: float, brightness := 1.0) -> void:
	for i in _materials.size():
		var m := _materials[i]
		m.set_shader_parameter("haze_color", color)
		m.set_shader_parameter("brightness", brightness)
		m.set_shader_parameter("distance_haze", distance_haze(fog_density, LAYERS[i].air))


## How much haze `air` metres of air lay over the far land.
static func distance_haze(fog_density: float, air: float) -> float:
	return 1.0 - exp(-fog_density * AIR_PER_FOG * air)


## The outlines of every ring, one row each: R the height (0 to 1 of the
## ring's hills plus crowns), G how wooded the hill is, B the crowns' depth. Rolling hills from smooth noise;
## on them woods with rounded crowns (the bumps of |noise|, rounded on top
## and pinched between trees) broken by open fields. Sampled round a circle
## so each row wraps without a seam.
static func profiles(seed: int, ring_radii: PackedFloat32Array) -> Image:
	var img := Image.create(PROFILE_WIDTH, LAYERS.size(), false, Image.FORMAT_RGB8)
	var hills := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	var crowns := _noise(FastNoiseLite.TYPE_SIMPLEX, 0)
	var clumps := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	var fields := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	for i in LAYERS.size():
		var l: Dictionary = LAYERS[i]
		hills.seed = seed + 11 * i
		crowns.seed = seed + 11 * i + 3
		clumps.seed = seed + 11 * i + 5
		fields.seed = seed + 11 * i + 7
		hills.frequency = 1.0 / float(l.hill_size)
		crowns.frequency = 1.0 / float(l.crown)
		clumps.frequency = 1.0 / (float(l.crown) * 5.0)
		fields.frequency = 1.0 / 600.0
		var radius := ring_radii[i]
		var tree: float = l.tree
		var top: float = float(l.hill) + tree * 1.3
		for x in PROFILE_WIDTH:
			var a := TAU * float(x) / PROFILE_WIDTH
			# Points round the ring in metres, so the shapes have real sizes.
			var at := Vector2(cos(a), sin(a)) * radius
			var ground: float = float(l.hill) * clampf(0.5 + 0.7 * hills.get_noise_2dv(at), 0.0, 1.0)
			# Woods where the field noise is high enough for this ring.
			var w := smoothstep(-0.2, 0.2, fields.get_noise_2dv(at) + float(l.woods) - 0.6)
			var bump := sqrt(clampf(1.0 - absf(crowns.get_noise_2dv(at)), 0.0, 1.0))
			var clump := 0.8 + 0.3 * clumps.get_noise_2dv(at)
			var canopy := tree * clump * (0.6 + 0.4 * bump)
			# Copses still dot the fields here and there.
			# Domed, as a clump of crowns is: steep at its edges, round on top.
			var copse := tree * 0.85 * sqrt(smoothstep(0.3, 0.5, clumps.get_noise_2dv(at * 0.25 + Vector2(913.0, 0.0)))) * (0.8 + 0.2 * bump)
			var trees := lerpf(copse, canopy, w)
			var hgt := ground + maxf(trees, 0.5)
			img.set_pixel(x, i, Color(clampf(hgt / top, 0.0, 1.0), w, clampf(trees / top, 0.0, 1.0)))
	return img


static func _noise(type: FastNoiseLite.NoiseType, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 0 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = maxi(octaves, 1)
	return n


## A closed band round the centre at `radius`, from `bottom` to `top`
## (metres from the base). UV.x runs once round, UV.y down the band.
static func _ring_mesh(radius: float, top: float, bottom: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for s in SEGMENTS + 1:
		var t := float(s) / SEGMENTS
		var a := TAU * t
		var d := Vector3(sin(a), 0.0, -cos(a)) * radius
		verts.append(d + Vector3.UP * top)
		verts.append(d + Vector3.UP * bottom)
		uvs.append(Vector2(t, 0.0))
		uvs.append(Vector2(t, 1.0))
		if s > 0:
			var i := 2 * s
			idx.append_array(PackedInt32Array([i - 2, i - 1, i, i, i - 1, i + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-radius, bottom, -radius), Vector3(2.0 * radius, top - bottom, 2.0 * radius))
	return mesh
