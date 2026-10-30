class_name DecodedObjectLibrary
extends ObjectLibrary
## The real Course Designer objects, read from the player's game folder:
## billboards from .btx archives and 3D models from .XYZ and .cmf files, with
## OBJECT.LIB as the catalog. See docs/formats/object-library.md.
##
## `instantiate()` takes an object id from OBJECT.LIB as a decimal string, or
## a catalog file name such as "Tall Trees100.btx".

var folder: CaseInsensitiveDir
var catalog: ObjectCatalog
var _by_name := {}
var _by_id := {}
var _textures := {}
var _meshes := {}


## Returns null if `game_folder` has no readable object.lib.
static func open(game_folder: String) -> DecodedObjectLibrary:
	var gf := CaseInsensitiveDir.new(game_folder)
	var cat_data := ObjectCatalog.from_bytes(gf.read("object.lib"))
	if cat_data == null:
		return null
	var lib := DecodedObjectLibrary.new()
	lib.folder = gf
	lib.catalog = cat_data
	for cat in cat_data.categories:
		for o: Dictionary in cat.objects:
			lib._by_id[str(o.id)] = o
			lib._by_name[(o.name as String).to_lower()] = o
	return lib


func find(id: String) -> Dictionary:
	if _by_id.has(id):
		return _by_id[id]
	return _by_name.get(id.to_lower(), {})


func instantiate(id: String) -> Node3D:
	var o := find(id)
	if o.is_empty():
		return null
	var node := _make_model(o) if o.kind == ObjectCatalog.KIND_MODEL else _make_billboard(o)
	if node:
		node.name = (o.name as String).get_basename().validate_node_name()
	return node


## Height in metres of the node `instantiate()` builds, before scaling.
func height_m(id: String) -> float:
	var o := find(id)
	if o.is_empty():
		return 0.0
	if o.kind == ObjectCatalog.KIND_MODEL:
		var size: PackedFloat32Array = o.size
		return size[0] * XyzModel.INCH
	return ObjectCatalog.default_height_m(o)


func _path(o: Dictionary) -> String:
	return "Object/" + (o.path as String)


func _billboard_texture(o: Dictionary) -> ImageTexture:
	var key: String = o.path
	if _textures.has(key):
		return _textures[key]
	var tex: ImageTexture = null
	var arc := Arc0.from_bytes(folder.read(_path(o)))
	if arc and not arc.entries.is_empty():
		var img := Btcv.decode(arc.read(0))
		if img:
			img = HdPack.replace("billboards", str(arc.entries[0].name), img)
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


func _make_billboard(o: Dictionary) -> Node3D:
	var tex := _billboard_texture(o)
	if tex == null:
		return null
	var h := ObjectCatalog.default_height_m(o)
	var w := h * tex.get_width() / float(tex.get_height())
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	quad.center_offset = Vector3(0, h * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	return mi


func _make_model(o: Dictionary) -> Node3D:
	var key: String = o.path
	if not _meshes.has(key):
		var base := _path(o).get_basename()
		var textures := XyzModel.read_textures(folder.read(base + ".cmf"))
		for i in textures.size():
			var hd := HdPack.find("models/library", "%s_%d" % [base.get_file(), i], textures[i])
			if hd != null:
				hd.generate_mipmaps()
				textures[i] = hd
		_meshes[key] = XyzModel.build_mesh(folder.read(base + ".XYZ"), textures)
	if _meshes[key] == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	return mi
