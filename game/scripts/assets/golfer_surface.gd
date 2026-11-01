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
