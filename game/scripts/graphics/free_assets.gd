class_name FreeAssets
extends RefCounted
## The free (CC0) textures and sky from Poly Haven and ambientCG that the public build uses
## instead of the original art. tools/fetch_free_assets.py downloads them into
## res://free_assets/; they aren't in the repository, so everything here
## returns null when they haven't been fetched and callers fall back to plain
## shading.

const DIR := "res://free_assets/"
const GROUNDS: Array[String] = ["grass", "rough", "sand"]


## `slot` is "grass", "rough", "sand", "path" or "dirt"; `map` is "albedo", "normal", "height" or
## "roughness".
static func ground(slot: String, map: String) -> Texture2D:
	return _load("%s_%s.jpg" % [slot, map])


## The ground slot that stands in for a surface: "sand", "rough" (rough,
## deep rough, out of bounds, water banks) or "grass" (the mown surfaces).
static func slot_for(surface: Surface.Type) -> String:
	match surface:
		Surface.Type.SAND:
			return "sand"
		Surface.Type.ROUGH, Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS, Surface.Type.WATER:
			return "rough"
	return "grass"


static func has_grounds() -> bool:
	for slot in GROUNDS:
		if ground(slot, "albedo") == null:
			return false
	return true


## A tree texture: "bark_albedo.jpg", "bark_normal.jpg" (Poly Haven) or
## "leaf_albedo.png", "leaf_opacity.png" (ambientCG), or null.
static func tree_texture(file: String) -> Texture2D:
	return _load(file)


static var _sky: Texture2D
static var _sky_loaded := false
static var _sky_sun := Vector2(-2.0, 0.0)  ## sky_sun() of the sky, once read


## The equirectangular HDR sky panorama, or null. Read once from
## sky_panorama.olsky, which tools/fetch_free_assets.py writes (see
## tools/sky_pack.py): the same RGB9E5 pixels as Godot's import of the .hdr,
## deflated to half the size.
static func sky() -> Texture2D:
	if not _sky_loaded:
		_sky_loaded = true
		_sky = _load_packed_sky(DIR + "sky_panorama.olsky")
	return _sky


## sky_sun() of the free sky, worked out once.
static func free_sky_sun() -> Vector2:
	if _sky_sun.x < -1.5:
		_sky_sun = sky_sun(sky())
	return _sky_sun


static func _load_packed_sky(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(8).slice(0, 6).get_string_from_ascii() != "OLSKY1":
		return null
	var width := f.get_32()
	var height := f.get_32()
	var size := f.get_32()
	if size != width * height * 4:
		return null
	var data := f.get_buffer(f.get_length() - f.get_position()).decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if data.size() != size:
		return null
	return ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RGBE9995, data))


## Where the sun is in a sky panorama: (across 0 to 1, height in radians),
## from its brightest patch after box-filtering it down (so a cloud edge
## can't win over the sun's disc). (-1, 0) when nothing stands out enough
## to be a sun, as under a grey sky.
static func sky_sun(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2(-1.0, 0.0)
	var img := tex.get_image()
	if img == null or img.is_empty():
		return Vector2(-1.0, 0.0)
	return sun_in_image(img)


static func sun_in_image(source: Image) -> Vector2:
	var img := source.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBF)
	while img.get_width() > 256:
		img.shrink_x2()
	var w := img.get_width()
	var h := img.get_height()
	var best := 0.0
	var at := Vector2i.ZERO
	var sum := 0.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += l
			if l > best:
				best = l
				at = Vector2i(x, y)
	if best < 20.0 * sum / float(w * h):
		return Vector2(-1.0, 0.0)
	return Vector2((at.x + 0.5) / w, PI * (0.5 - (at.y + 0.5) / h))


## Average colour of a texture: halved with a box filter down to a few
## pixels (a straight resize to one pixel samples only a handful of them).
static func mean_color(tex: Texture2D) -> Color:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return Color(0.5, 0.5, 0.5)
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGB8)
	while img.get_width() > 8 and img.get_height() > 8:
		img.shrink_x2()
	var sum := Color(0, 0, 0)
	for y in img.get_height():
		for x in img.get_width():
			sum += img.get_pixel(x, y)
	var n := float(img.get_width() * img.get_height())
	return Color(sum.r / n, sum.g / n, sum.b / n)


static func _load(file: String) -> Texture2D:
	var path := DIR + file
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
