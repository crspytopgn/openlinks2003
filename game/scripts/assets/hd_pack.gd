class_name HdPack
extends RefCounted
## An HD texture pack: upscaled copies of the game's textures that are used
## in place of the originals, texture by texture. Nothing from the original
## game ships with this project: players make a pack from their own files
## with tools/oltex and an upscaler such as Upscayl (docs/hd-textures.md).
##
## A pack is a folder (or a .zip of one) holding the kind folders that oltex
## writes: terrain/, sky/, horizon/, billboards/, crowds/, golfers/, models/,
## ui/. Inside each, "<sub>__<name>.png" stands for the texture <name> of
## <sub> (a course or golfer), and sub/name.png works too. File names may
## keep an upscaler's suffix ("_upscayl_4x_remacri") and their original case.
##
## The pack comes from, in order: --hd-pack=/path on the command line, the
## LINKS2003_HD_PACK environment variable, then [hd_pack] path in
## user://settings.cfg, used while [hd_pack] enabled is true.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "hd_pack"
const KINDS: Array[String] = ["terrain", "sky", "horizon", "billboards", "crowds", "golfers", "models", "ui"]
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
## Extensions dropped from texture names given to key(), and the characters
## oltex replaces with "_" in file names.
const SOURCE_EXTENSIONS: Array[String] = ["tga", "btc", "maq", "png", "jpg", "bmp"]
const UNSAFE: Array[String] = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
## Wrapped border oltex adds around textures that tile, in original pixels,
## and whether it is added at the top and bottom too.
const PAD := {"terrain": 16, "sky": 64, "horizon": 64}
const PAD_Y := {"terrain": true}

## The course being loaded, lower case (such as "cabo"): its own textures
## are under terrain/<course>__ and models/<course>__.
static var course := ""
## Wins over the settings when set (tests, or a pack picked this session).
static var override_path := ""

static var _saved := {}  ## [hd_pack] from the settings file, once read
static var _source := ""  ## the pack that _index describes
static var _index := {}  ## key -> path in the folder, or file name in _zip
static var _zip: ZIPReader = null


## The pack folder or .zip in use, or "" when HD textures are off.
static func active_path() -> String:
	if not override_path.is_empty():
		return override_path
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--hd-pack="):
			return arg.trim_prefix("--hd-pack=")
	var env := OS.get_environment("LINKS2003_HD_PACK")
	if not env.is_empty():
		return env
	return saved_path() if saved_enabled() else ""


static func saved_path() -> String:
	_load_saved()
	return str(_saved.path)


static func saved_enabled() -> bool:
	_load_saved()
	return bool(_saved.enabled)


## Saves the choice; it takes effect for textures loaded from then on.
static func save(path: String, enabled: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep the other sections; a missing file is fine
	cfg.set_value(SECTION, "path", path)
	cfg.set_value(SECTION, "enabled", enabled)
	if cfg.save(SETTINGS_PATH) != OK:
		push_warning("Could not save the HD pack setting to %s" % SETTINGS_PATH)
	_saved = {"path": path, "enabled": enabled}


## Reads [hd_pack] once; textures are looked up far too often to read the
## settings file each time.
static func _load_saved() -> void:
	if not _saved.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_saved = {"path": str(cfg.get_value(SECTION, "path", "")), "enabled": bool(cfg.get_value(SECTION, "enabled", false))}


## True if an HD pack is switched on and holds at least one texture.
static func is_active() -> bool:
	_refresh()
	return not _index.is_empty()


## How many textures the pack at `path` holds (0 if it isn't one).
static func count_textures(path: String) -> int:
	var built := _build_index(path)
	if built[1] != null:
		(built[1] as ZIPReader).close()
	return (built[0] as Dictionary).size()


## The key of texture `name` of `dir` ("terrain/cabo", "billboards"): the
## same names tools/oltex gives the files, lower case, without extension.
static func key(dir: String, name: String) -> String:
	var parts := dir.to_lower().split("/", false)
	var file := name.to_lower()
	if SOURCE_EXTENSIONS.has(file.get_extension()):
		file = file.get_basename()
	for c in UNSAFE:
		file = file.replace(c, "_")
	if parts.size() <= 1:
		return dir.to_lower() + "/" + file
	return parts[0] + "/" + "__".join(parts.slice(1)) + "__" + file


## The upscaled version of texture `name` of `dir`, or `original` when the
## pack doesn't have it (or no pack is on). `original` gives the size to
## trim the wrapped border back to; the result is never mipmapped.
static func replace(dir: String, name: String, original: Image) -> Image:
	var img := find(dir, name, original)
	return img if img != null else original


## The upscaled image, or null. See replace().
static func find(dir: String, name: String, original: Image = null) -> Image:
	_refresh()
	if _index.is_empty():
		return null
	var k := key(dir, name)
	if not _index.has(k):
		return null
	var img := _read(_index[k])
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	var kind := k.get_slice("/", 0)
	if original != null and not original.is_empty() and PAD.has(kind):
		img = trim_border(img, original.get_size(), PAD[kind], PAD_Y.get(kind, false))
	return _limit(img)


## Cuts the wrapped border off an upscaled texture whose original was `size`
## before oltex added `pad` pixels left and right (and top and bottom when
## `pad_y`). An image that was upscaled without the border is kept: one whose
## shape doesn't fit the bordered size, or that is a whole multiple of the
## plain size but not of the bordered one.
static func trim_border(img: Image, size: Vector2i, pad: int, pad_y: bool) -> Image:
	var padded := Vector2(size.x + 2 * pad, size.y + (2 * pad if pad_y else 0))
	var scale := img.get_width() / padded.x
	if absf(img.get_height() / padded.y - scale) > 0.02 * scale:
		return img
	var plain := img.get_width() / float(size.x)
	var fits_plain := absf(img.get_height() / float(size.y) - plain) <= 0.02 * plain
	if fits_plain and _is_whole(plain) and not _is_whole(scale):
		return img
	var px := roundi(pad * scale)
	var py := px if pad_y else 0
	var region := Rect2i(px, py, img.get_width() - 2 * px, img.get_height() - 2 * py)
	if region.size.x <= 0 or region.size.y <= 0:
		return img
	return img.get_region(region)


static func _is_whole(x: float) -> bool:
	return x >= 0.98 and absf(x - roundf(x)) < 0.02


## Turns a file's path inside a pack into its key, or "" if it isn't a
## texture: drops folders above the kind folder, the extension and any
## upscaler suffix, and writes sub/name as sub__name.
static func key_for_file(rel: String) -> String:
	var ext := rel.get_extension().to_lower()
	if not IMAGE_EXTENSIONS.has(ext):
		return ""
	var parts := rel.to_lower().replace("\\", "/").split("/", false)
	var start := -1
	for i in parts.size() - 1:
		if KINDS.has(parts[i]):
			start = i
			break
	if start < 0:
		return ""
	var file := parts[parts.size() - 1].get_basename()
	var cut := file.find("_upscayl_")
	if cut > 0:
		file = file.substr(0, cut)
	var subs := parts.slice(start + 1, parts.size() - 1)
	subs.append(file)
	return parts[start] + "/" + "__".join(subs)


static func _refresh() -> void:
	var path := active_path()
	if path == _source:
		return
	if _zip != null:
		_zip.close()
		_zip = null
	_source = path
	var built := _build_index(path)
	_index = built[0]
	_zip = built[1]
	if not path.is_empty():
		print("HD pack: %d textures from %s" % [_index.size(), path])


## [key -> location, the open ZIPReader or null].
static func _build_index(path: String) -> Array:
	var index := {}
	if path.is_empty():
		return [index, null]
	if path.get_extension().to_lower() == "zip" and FileAccess.file_exists(path):
		var zip := ZIPReader.new()
		if zip.open(path) != OK:
			return [index, null]
		for f in zip.get_files():
			var k := key_for_file(f)
			if not k.is_empty():
				index[k] = f
		return [index, zip]
	if DirAccess.dir_exists_absolute(path):
		_walk(path, path.get_file(), 0, index)
	return [index, null]


static func _walk(dir: String, rel: String, depth: int, index: Dictionary) -> void:
	if depth > 4:
		return
	for f in DirAccess.get_files_at(dir):
		var k := key_for_file(rel.path_join(f))
		if not k.is_empty():
			index[k] = dir.path_join(f)
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), rel.path_join(d), depth + 1, index)


static func _read(where: String) -> Image:
	var bytes: PackedByteArray
	if _zip != null:
		bytes = _zip.read_file(where)
	else:
		bytes = FileAccess.get_file_as_bytes(where)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match where.get_extension().to_lower():
		"png":
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
	return img if err == OK else null


## Shrinks images too big for the graphics card: 16384 pixels a side on
## desktop, 8192 in the browser.
static func _limit(img: Image) -> Image:
	var most := 8192 if OS.has_feature("web") else 16384
	var big := maxi(img.get_width(), img.get_height())
	if big > most:
		var f := float(most) / big
		img.resize(maxi(1, roundi(img.get_width() * f)), maxi(1, roundi(img.get_height() * f)), Image.INTERPOLATE_LANCZOS)
	return img
