class_name FreeAssets
extends RefCounted
## The free (CC0) textures and sky from Poly Haven that the public build uses
## instead of the original art. tools/fetch_free_assets.py downloads them into
## res://free_assets/; they aren't in the repository, so everything here
## returns null when they haven't been fetched and callers fall back to plain
## shading.

const DIR := "res://free_assets/"
const GROUNDS: Array[String] = ["grass", "rough", "sand"]


## `slot` is "grass", "rough" or "sand"; `map` is "albedo" or "normal".
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


## The equirectangular sky panorama, or null.
static func sky() -> Texture2D:
	return _load("sky_panorama.hdr")


## Average colour of a texture, from its smallest mipmap.
static func mean_color(tex: Texture2D) -> Color:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return Color(0.5, 0.5, 0.5)
	if img.is_compressed():
		img.decompress()
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	return img.get_pixel(0, 0)


static func _load(file: String) -> Texture2D:
	var path := DIR + file
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
