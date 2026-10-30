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

## Which sky from PANSKY.LIB: sky01 is clear, sky12 overcast.
const DEFAULT_SKY := "sky04"
const SKY_LIBRARIES := ["PANSKY.LIB", "PanSky.lib"]
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
void fragment() {
	vec4 c = texture(band, UV);
	ALBEDO = c.rgb;
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


## Builds the backdrop from the player's files: `horizon` is the course's
## Panorama image (null for none); the sky comes from PANSKY.LIB.
static func create(horizon: Image, sky_name := "") -> CourseBackdrop:
	var b := CourseBackdrop.new()
	b.name = "Backdrop"
	if horizon != null:
		horizon = HdPack.replace("horizon", HdPack.course, horizon)
	var sky := load_sky(sky_name if not sky_name.is_empty() else GameFolder.setting("sky", DEFAULT_SKY))
	if sky != null:
		b.has_sky = true
		b.sky_top = _row_mean(sky, 0, 8)
		b.sky_haze = _row_mean(sky, sky.get_height() - 8, 8)
		b.add_child(_band(sky, SKY_RADIUS, 0.0, 0.25, -2))
	if horizon != null:
		b.has_horizon = true
		b.ground = _row_mean(horizon, horizon.get_height() - 16, 16)
		b.add_child(_band(horizon, HORIZON_RADIUS, HORIZON_ROW, 0.0, -1))
	return b


## A sky from PANSKY.LIB by name ("sky04"), or null.
static func load_sky(sky_name: String) -> Image:
	var path := GameFolder.find_file(PackedStringArray(SKY_LIBRARIES))
	if path.is_empty():
		return null
	var lib := Arc0.from_bytes(FileAccess.get_file_as_bytes(path))
	if lib == null:
		return null
	var entry := sky_name if sky_name.get_extension() == "btc" else sky_name + ".btc"
	if lib.find(entry) < 0:
		entry = DEFAULT_SKY + ".btc"
	if lib.find(entry) < 0:
		return null
	var sky := LinksPanorama.decode(lib.read_named(entry))
	return HdPack.replace("sky", entry, sky) if sky != null else null


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
