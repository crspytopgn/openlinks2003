class_name GolferSurface
extends RefCounted
## How the free golfer's skin, clothes and glove catch the light, on top
## of the look pack's textures.
##
## - Skin: light scatters under it (subsurface scattering, Forward+ only;
##   Compatibility ignores it), a soft sheen rather than matt paint, and a
##   faint rim where the light grazes it.
## - Cloth: the soft rim light that fabric fibres catch at grazing angles.
##   (A knit weave as a detail normal map was tried: Godot's detail normal
##   replaces the clothes' own fold normal maps rather than adding to them,
##   and the fine tiling shimmered, so it is left out.)
## - Glove: the left hand in white leather (GolferParts.bake splits the
##   hand off the body for it).

## Stitch repeats per UV unit on the glove (the hand's share of the body
## UV layout is small).
const WEAVE_TILES := 90.0
const GLOVE_COLOUR := Color(0.86, 0.85, 0.82)

static var _weave: Texture2D
static var _pores: Texture2D
static var _stubble: Texture2D
const SKIN_SHADER := preload("res://shaders/golfer_skin.gdshader")
const HAIR_SHADER := preload("res://shaders/golfer_hair.gdshader")
const FINE_HAIR_SHADER := preload("res://shaders/golfer_fine_hair.gdshader")


static func skin(mat: StandardMaterial3D) -> StandardMaterial3D:
	mat.roughness = 0.52
	mat.metallic_specular = 0.38
	mat.subsurf_scatter_enabled = true
	mat.subsurf_scatter_strength = 0.35
	mat.subsurf_scatter_skin_mode = true
	mat.rim_enabled = true
	mat.rim = 0.12
	mat.rim_tint = 0.6
	return mat


## The skin as golfer_skin.gdshader: `mat`'s texture and tone, varied by
## the look pack's region map (flushed cheeks and nose, lips, the T-zone,
## and a man's beard shadow and stubble from PlayerLook.stubble), with
## pores. Null without a region map (an older pack), so the caller can
## keep skin() instead.
static func skin_shader(mat: StandardMaterial3D, look: PlayerLook, regions: Texture2D) -> ShaderMaterial:
	if regions == null:
		return null
	var m := ShaderMaterial.new()
	m.resource_name = "Skin"
	m.shader = SKIN_SHADER
	m.set_shader_parameter("albedo", mat.albedo_color)
	m.set_shader_parameter("texture_albedo", mat.albedo_texture)
	m.set_shader_parameter("regions", regions)
	m.set_shader_parameter("pores", pores())
	m.set_shader_parameter("stubble_dots", stubble_dots())
	var man := look.sex < 0.5
	# Stubble grows in darker than the hair often looks; grey hair greys it.
	m.set_shader_parameter("beard_colour", look.hair_colour.darkened(0.5))
	m.set_shader_parameter("stubble", look.stubble if man else 0.0)
	m.set_shader_parameter("shave_shadow", (0.35 + 0.65 * look.stubble) if man else 0.0)
	m.set_shader_parameter("lip_strength", 1.15 if not man else 0.8)
	m.set_shader_parameter("flush_strength", 1.0)
	return m


## Eyebrows and eyelashes as fine hair rather than painted card: soft,
## see-through edges instead of a hard cut-out, lashes thinner and in the
## hair's colour (fair hair has fair lashes), so they read as hair at a
## close-up and fade at a distance as real ones do.
static func fine_hair(mat: StandardMaterial3D, lashes: bool, hair_colour: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = mat.resource_name
	m.shader = FINE_HAIR_SHADER
	m.set_shader_parameter("texture_albedo", mat.albedo_texture)
	m.set_shader_parameter("cutoff", mat.alpha_scissor_threshold)
	if lashes:
		m.set_shader_parameter("albedo", hair_colour.darkened(0.55).lerp(Color(0.06, 0.05, 0.045), 0.4))
		m.set_shader_parameter("opacity", 0.55)
	else:
		m.set_shader_parameter("albedo", mat.albedo_color)
		m.set_shader_parameter("opacity", 0.9)
		m.set_shader_parameter("strands", 0.7)
	return m


## Hair cards as golfer_hair.gdshader, from the pack's hair material.
static func hair(mat: StandardMaterial3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = mat.resource_name
	m.shader = HAIR_SHADER
	m.set_shader_parameter("albedo", mat.albedo_color)
	m.set_shader_parameter("texture_albedo", mat.albedo_texture)
	m.set_shader_parameter("cutoff", mat.alpha_scissor_threshold)
	return m


static func cloth(mat: StandardMaterial3D) -> StandardMaterial3D:
	mat.roughness = maxf(mat.roughness, 0.85)
	mat.metallic_specular = minf(mat.metallic_specular, 0.3)
	mat.rim_enabled = true
	mat.rim = 0.25
	mat.rim_tint = 0.7
	return mat


static func glove() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Glove"
	mat.albedo_color = GLOVE_COLOUR
	mat.roughness = 0.6
	mat.metallic_specular = 0.4
	mat.normal_enabled = true
	mat.normal_texture = weave()
	mat.normal_scale = 0.12
	mat.uv1_scale = Vector3(WEAVE_TILES, WEAVE_TILES, 1.0)
	return mat


## A 64 px tile of stitched leather as a normal map: rows of little
## raised loops, offset every other row.
static func weave() -> Texture2D:
	if _weave != null:
		return _weave
	const N := 64
	const LOOPS := 8
	var height := PackedFloat32Array()
	height.resize(N * N)
	var cell := float(N) / LOOPS
	for y in N:
		for x in N:
			var row := int(y / cell)
			var u := fposmod(x / cell + 0.5 * (row % 2), 1.0) - 0.5
			var v := fposmod(y / cell, 1.0) - 0.5
			# A loop: a raised ring, highest at its sides.
			var r := sqrt(u * u * 1.6 + v * v)
			height[y * N + x] = clampf(1.0 - absf(r - 0.3) * 4.0, 0.0, 1.0)
	var img := Image.create_empty(N, N, false, Image.FORMAT_RGB8)
	for y in N:
		for x in N:
			var dx := height[y * N + (x + 1) % N] - height[y * N + (x + N - 1) % N]
			var dy := height[((y + 1) % N) * N + x] - height[((y + N - 1) % N) * N + x]
			var n := Vector3(-dx * 1.2, dy * 1.2, 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	img.generate_mipmaps()
	_weave = ImageTexture.create_from_image(img)
	return _weave


## A 128 px tile of skin pores as a normal map: small pits scattered
## over a faint fine grain.
static func pores() -> Texture2D:
	if _pores != null:
		return _pores
	const N := 128
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var height := PackedFloat32Array()
	height.resize(N * N)
	for i in N * N:
		height[i] = rng.randf() * 0.15
	for _k in 260:
		var cx := rng.randi_range(0, N - 1)
		var cy := rng.randi_range(0, N - 1)
		var r := rng.randf_range(0.8, 1.8)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var d := sqrt(float(dx * dx + dy * dy)) / r
				if d < 1.0:
					var i := ((cy + dy + N) % N) * N + (cx + dx + N) % N
					height[i] -= (1.0 - d * d) * 0.8
	_pores = _normal_map(height, N, 1.0)
	return _pores


## A 128 px tile of stubble: dark dots about every 9 px, jittered.
static func stubble_dots() -> Texture2D:
	if _stubble != null:
		return _stubble
	const N := 128
	const CELL := 9.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var img := Image.create_empty(N, N, false, Image.FORMAT_L8)
	var cells := int(N / CELL)
	var step := float(N) / cells
	for gy in cells:
		for gx in cells:
			var cx := (gx + rng.randf_range(0.2, 0.8)) * step
			var cy := (gy + rng.randf_range(0.2, 0.8)) * step
			var r := rng.randf_range(1.0, 1.8)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var px := int(cx) + dx
					var py := int(cy) + dy
					var d := Vector2(px + 0.5 - cx, py + 0.5 - cy).length() / r
					if d < 1.0:
						var x := (px + N) % N
						var y := (py + N) % N
						var v := maxf(img.get_pixel(x, y).r, 1.0 - d * d)
						img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	_stubble = ImageTexture.create_from_image(img)
	return _stubble


static func _normal_map(height: PackedFloat32Array, n: int, strength: float) -> Texture2D:
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var dx := height[y * n + (x + 1) % n] - height[y * n + (x + n - 1) % n]
			var dy := height[((y + 1) % n) * n + x] - height[((y + n - 1) % n) * n + x]
			var nv := Vector3(-dx * strength, dy * strength, 1.0).normalized()
			img.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
