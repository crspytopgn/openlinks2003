class_name CourseBackdrop
extends Node3D
## The far scenery Links 2003 draws behind a course: a photographic cloud
## sky (`skyNN.btc` from PANSKY.LIB) and, in front of it, the course's own
## horizon panorama (the `Panorama` entry of a .CRZ: the hills, trees and
## fields round the course). See docs/formats/panorama.md.
##
## Both are bands on cylinders centred on the camera, so they stay at the
## horizon wherever the camera goes. Pixels are square: the full width wraps
## once round, and the band's height follows from that. Above the sky band
## the Environment's sky colour takes over.

## The sky when the course names none: skyNN.btc from PANSKY.LIB, where
## sky01 is clear and sky12 overcast.
const DEFAULT_SKY := "sky04"
const SKY_LIBRARIES := ["PANSKY.LIB", "PanSky.lib"]
## The player's sky setting ([game] "sky" in user://settings.cfg): the
## course's own (the one its header names, as Links 2003 1.0 does), a random
## one (as the 1.07 patch offers), a disc sky ("sky05") or the name of a
## custom sky from the patch's skies folder ("Sunrise").
const COURSE_SKY := ""
const RANDOM_SKY := "random"
const SKY_FOLDER := "skies"
## The 1.07 patch's names for the twelve disc skies: its first twelve
## custom skies are the same pictures as sky01 to sky12.
const DISC_SKY_NAMES: Array[String] = ["Clear", "Mostly Sunny 1", "Mostly Sunny 2", "Mostly Sunny 3",
	"Scattered Clouds 1", "Scattered Clouds 2", "Scattered Clouds 3", "Partly Cloudy 1", "Partly Cloudy 2",
	"Broken Clouds", "Cloudy", "Overcast"]
## How overcast each named sky is (0 clear, 1 dark and stormy) and whether
## it is a low, warm sun (sunrise, sunset); the light follows it.
const WEATHER := {
	"clear": 0.0, "mostly sunny 1": 0.05, "mostly sunny 2": 0.1, "mostly sunny 3": 0.15,
	"scattered clouds 1": 0.25, "scattered clouds 2": 0.3, "scattered clouds 3": 0.35,
	"partly cloudy 1": 0.45, "partly cloudy 2": 0.5, "broken clouds": 0.6, "mostly cloudy": 0.7,
	"cloudy": 0.8, "overcast": 0.9, "ominous": 0.9, "stormy": 1.0, "sunrise": 0.35, "mojave_sunset": 0.3,
}
const WARM_SKIES: Array[String] = ["sunrise", "mojave_sunset"]
## Row of the horizon panorama that sits at eye level, as a fraction of its
## height. The distant land in the course panoramas meets the sky about
## here. A guess from the images; the game's own value isn't known yet.
const HORIZON_ROW := 0.625
const SKY_RADIUS := 2800.0
const HORIZON_RADIUS := 2600.0
## Textures are cut into pieces no wider than this, for GPUs (and browsers)
## that cap texture size at 4096.
const MAX_PIECE := 2048
const SEGMENTS_PER_PIECE := 32

const SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;
uniform sampler2D band : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float fade_top = 0.0;  // fraction of the band height faded out at the top
uniform vec3 haze_color : source_color = vec3(0.7, 0.78, 0.86);
uniform float haze = 0.0;  // how far the band fades into the haze
void fragment() {
	vec4 c = texture(band, UV);
	ALBEDO = mix(c.rgb, haze_color, haze);
	ALPHA = c.a * (fade_top > 0.0 ? smoothstep(0.0, fade_top, UV.y) : 1.0);
}
"""

## Average colours, for the Environment: top of the sky, bottom of the sky
## (its haze) and the bottom of the horizon (the near ground).
var sky_top := Color(0.30, 0.50, 0.80)
var sky_haze := Color(0.75, 0.82, 0.90)
var ground := Color(0.30, 0.38, 0.20)
var has_sky := false
var has_horizon := false
## The sky shown (as sky_setting() values: "sky05", "Sunrise"), "" for none.
var sky_name := ""
## How overcast the shown sky is (0 clear to 1 stormy), and whether its sun
## is low and warm.
var overcast := 0.3
var warm := false
## True when the player picked the sky rather than leaving the course's own.
var chosen := false


## Builds the backdrop from the player's files: `horizon` is the course's
## horizon panorama (null for none); the sky is the one the player's
## setting picks, by default the course's own (`course_sky`: skyNN, 0 for
## none named).
static func create(horizon: Image, course_sky := 0) -> CourseBackdrop:
	var b := CourseBackdrop.new()
	b.name = "Backdrop"
	if horizon != null:
		horizon = HdPack.replace("horizon", HdPack.course, horizon)
	b.chosen = sky_setting() != COURSE_SKY
	b.sky_name = pick_sky(sky_setting(), course_sky)
	var sky := load_sky(b.sky_name)
	if sky != null:
		b.has_sky = true
		b.sky_top = _row_mean(sky, 0, 8)
		b.sky_haze = _row_mean(sky, sky.get_height() - 8, 8)
		b.overcast = weather(b.sky_name)
		b.warm = WARM_SKIES.has(display_name(b.sky_name).to_lower())
		# Its bottom row at eye level (row 0 there would hang the whole sky
		# below the horizon, behind the land).
		var band := _band(sky, SKY_RADIUS, 1.0, 0.25, -2)
		band.name = "SkyBand"
		b.add_child(band)
	else:
		b.sky_name = ""
	if horizon != null:
		b.has_horizon = true
		b.ground = _row_mean(horizon, horizon.get_height() - 16, 16)
		var band := _band(horizon, HORIZON_RADIUS, HORIZON_ROW, 0.0, -1)
		band.name = "HorizonBand"
		b.add_child(band)
	return b


## The player's sky setting (see COURSE_SKY).
static func sky_setting() -> String:
	return GameFolder.setting("sky", COURSE_SKY)


static func save_sky_setting(value: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(GameFolder.SETTINGS_PATH)
	cfg.set_value("game", "sky", value)
	cfg.save(GameFolder.SETTINGS_PATH)


## The sky to show for a setting and the course's own sky number.
static func pick_sky(setting: String, course_sky: int) -> String:
	if setting == RANDOM_SKY:
		var choices := sky_choices()
		choices = choices.slice(2)  # past "course" and "random"
		return choices[randi() % choices.size()] if not choices.is_empty() else DEFAULT_SKY
	if setting.is_empty() or setting == COURSE_SKY:
		return "sky%02d" % course_sky if course_sky >= 1 and course_sky <= 12 else DEFAULT_SKY
	return setting


## The values sky_setting() can take, for a settings list: the course's
## own, random, the twelve disc skies and the patch's other custom skies
## found in the player's skies folder.
static func sky_choices() -> PackedStringArray:
	var out := PackedStringArray([COURSE_SKY, RANDOM_SKY])
	for i in DISC_SKY_NAMES.size():
		out.append("sky%02d" % (i + 1))
	for path in GameFolder.list_files(SKY_FOLDER):
		if path.get_extension().to_lower() != "sky":
			continue
		var n := path.get_file().get_basename()
		if not DISC_SKY_NAMES.has(n):
			out.append(n)
	return out


## A sky setting as the player sees it.
static func display_name(value: String) -> String:
	if value == COURSE_SKY:
		return "Course's own"
	if value == RANDOM_SKY:
		return "Random"
	var n := _disc_number(value)
	if n > 0:
		return DISC_SKY_NAMES[n - 1]
	return value.replace("_", " ")


## How overcast a sky is, 0 (clear) to 1 (stormy); 0.3 for one not known.
static func weather(value: String) -> float:
	return WEATHER.get(display_name(value).to_lower(), WEATHER.get(value.to_lower(), 0.3))


## 1 to 12 for "sky01" to "sky12", else 0.
static func _disc_number(value: String) -> int:
	if value.length() == 5 and value.to_lower().begins_with("sky") and value.substr(3).is_valid_int():
		var n := value.substr(3).to_int()
		return n if n >= 1 and n <= 12 else 0
	return 0


## Photoreal: the course's horizon stays (its sea and far hills), softened
## into the haze, in front of the photographed sky instead of the disc's.
func set_photo(on: bool, haze_color: Color) -> void:
	var sky := get_node_or_null("SkyBand") as MeshInstance3D
	if sky != null:
		sky.visible = not on
	var horizon := get_node_or_null("HorizonBand") as MeshInstance3D
	if horizon != null:
		for i in horizon.mesh.get_surface_count():
			var mat := horizon.mesh.surface_get_material(i) as ShaderMaterial
			mat.set_shader_parameter("haze", 0.3 if on else 0.0)
			mat.set_shader_parameter("haze_color", haze_color)


## A sky by its setting value: "sky04" from PANSKY.LIB, or the name of a
## custom sky in the skies folder ("Sunrise"); a disc sky the library lacks
## falls back to the patch's copy of it. Null when none is found.
static func load_sky(value: String) -> Image:
	var n := _disc_number(value)
	if n > 0:
		var lib := _pansky()
		var entry := "sky%02d.btc" % n
		if lib != null and lib.find(entry) >= 0:
			var sky := LinksPanorama.decode(lib.read_named(entry))
			if sky != null:
				return HdPack.replace("sky", entry, sky)
		value = DISC_SKY_NAMES[n - 1]
	for path in GameFolder.list_files(SKY_FOLDER):
		if path.get_file().get_basename().to_lower() == value.to_lower() and path.get_extension().to_lower() == "sky":
			var sky := LinksPanorama.decode_sky_archive(Arc0.from_bytes(FileAccess.get_file_as_bytes(path)))
			if sky != null:
				return HdPack.replace("sky", path.get_file(), sky)
	if value != DEFAULT_SKY and n == 0:
		return load_sky(DEFAULT_SKY)
	return null


## A stock horizon from PANSKY.LIB (PanNN.btc, 1 to 13), or null.
static func load_stock_horizon(number: int) -> Image:
	var lib := _pansky()
	var entry := "Pan%02d.btc" % number
	if lib == null or lib.find(entry) < 0:
		return null
	return LinksPanorama.decode(lib.read_named(entry))


static func _pansky() -> Arc0:
	var path := GameFolder.find_file(PackedStringArray(SKY_LIBRARIES))
	if path.is_empty():
		return null
	return Arc0.from_bytes(FileAccess.get_file_as_bytes(path))


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		global_position = cam.global_position


## A cylinder band showing `img`, the whole width once round. `eye_row` is
## the fraction of the height at eye level (0 puts the band's bottom there).
## `priority` orders the transparent bands (lower draws first).
## Column 0 faces north (-z) and columns run clockwise seen from above, so
## the picture isn't mirrored from inside.
static func _band(img: Image, radius: float, eye_row: float, fade_top: float, priority: int) -> MeshInstance3D:
	var w := img.get_width()
	var h := img.get_height()
	var px := TAU * radius / float(w)  # metres per pixel on the cylinder
	var y_top := eye_row * h * px
	var y_bottom := y_top - h * px
	var pieces := ceili(float(w) / MAX_PIECE)
	var mesh := ArrayMesh.new()
	var shader := Shader.new()
	shader.code = SHADER
	for p in pieces:
		var x0 := p * w / pieces
		var x1 := (p + 1) * w / pieces
		var piece := img.get_region(Rect2i(x0, 0, x1 - x0, h))
		piece.generate_mipmaps()
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		for s in SEGMENTS_PER_PIECE + 1:
			var t := float(s) / SEGMENTS_PER_PIECE
			var a := TAU * (x0 + t * (x1 - x0)) / float(w)
			var d := Vector3(sin(a), 0.0, -cos(a)) * radius
			verts.append(d + Vector3.UP * y_top)
			verts.append(d + Vector3.UP * y_bottom)
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
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("band", ImageTexture.create_from_image(piece))
		mat.set_shader_parameter("fade_top", fade_top)
		# Both bands are centred on the camera, so distance can't order
		# them: the sky first, then the horizon over it, then everything else.
		mat.render_priority = priority
		mesh.surface_set_material(p, mat)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = radius
	return node


## Mean colour of `count` rows from `row`, ignoring transparent pixels.
static func _row_mean(img: Image, row: int, count: int) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	var step := maxi(1, img.get_width() / 256)
	for y in range(maxi(row, 0), mini(row + count, img.get_height())):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				sum += c
				n += 1
	if n == 0:
		return Color(0.5, 0.6, 0.7)
	return Color(sum.r / n, sum.g / n, sum.b / n)
