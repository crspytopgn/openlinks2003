class_name ScannedTree
extends RefCounted
## Photoscanned trees from Poly Haven (CC0), cut down for the game by
## tools/trees/scan_tree.py into res://assets/trees/<name>.oltree: the bark
## decimated, every leaf or sprig one quad. Their textures come from
## tools/fetch_free_assets.py (scan_<asset>_*). TreeFactory draws them in
## place of its generated trees when both are there.
##
## The mesh is built like TreeFactory's own: surface 0 bark, surface 1
## leaves. Leaf COLOR: r random, g how far out in the crown, b sway, a 1
## (0 for a conifer's core cards); leaf normals point out from the crown's middle, so a
## crown shades as one soft mass. Bark COLOR.r picks the texture (0 trunk,
## 1 branches).

const DIR := "res://assets/trees/"
## Leaf cards in a lite mesh (see build).
const LITE_CARDS := 1000.0

## Tree name -> Poly Haven asset (the textures' prefix).
const ASSETS := {
	"fir_a": "fir_tree_01",
	"fir_b": "fir_tree_01",
	"fir_c": "fir_tree_01",
	"jacaranda": "jacaranda_tree",
	"island_01": "island_tree_01",
	"island_02": "island_tree_02",
}


## True for the scans whose leaves are TreeFactory's needle sprig cards
## (the fir scan models single needles, far too many to draw).
static func is_conifer(name: String) -> bool:
	return ASSETS[name] == "fir_tree_01"


## True when the tree's mesh and its textures are both there.
static func available(name: String) -> bool:
	if not ResourceLoader.exists(DIR + name + ".oltree") and not FileAccess.file_exists(DIR + name + ".oltree"):
		return false
	return texture(name, "trunk.jpg") != null and leaf_textures(name).size() == 2


## A texture of the tree's asset: "trunk.jpg", "trunk_normal.jpg", "bark.jpg".
static func texture(name: String, file: String) -> Texture2D:
	return FreeAssets.tree_texture("scan_%s_%s" % [ASSETS[name], file])


## [colour, opacity] of the leaves (the firs use the shared twig maps).
static func leaf_textures(name: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var asset: String = ASSETS[name]
	var col: Texture2D
	var alpha: Texture2D
	if asset == "fir_tree_01":
		col = FreeAssets.tree_texture("twig_albedo.jpg")
		alpha = FreeAssets.tree_texture("twig_opacity.png")
	else:
		col = FreeAssets.tree_texture("scan_%s_leaves.jpg" % asset)
		alpha = FreeAssets.tree_texture("scan_%s_leaves_alpha.png" % asset)
	if col != null and alpha != null:
		out = [col, alpha]
	return out


## The tree's mesh, mirrored left to right with `mirror` (a second variant
## from one scan), or null. `lite` gives the cheap version drawn between
## TreeFactory's lite and impostor distances: about LITE_CARDS leaves,
## grown to keep the crown's cover, and the lite bark.
static func build(name: String, mirror: bool, lite := false) -> ArrayMesh:
	var f := FileAccess.open(DIR + name + ".oltree", FileAccess.READ)
	if f == null or f.get_buffer(8).get_string_from_ascii() != "OLTREE1":
		return null
	var size := f.get_32()
	var d := f.get_buffer(f.get_length() - f.get_position()).decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if d.size() != size:
		return null
	var sx := -1.0 if mirror else 1.0
	var crown_c := Vector3(d.decode_float(0) * sx, d.decode_float(4), d.decode_float(8))
	var crown_r := Vector3(d.decode_float(12), d.decode_float(16), d.decode_float(20)).max(Vector3.ONE * 0.1)
	var top := crown_c.y + crown_r.y
	var bark := []
	var o := _read_bark(d, 24, sx, bark)
	# Leaves: one quad per card.
	var nc := d.decode_u32(o)
	o += 4
	# The lite leaves: about LITE_CARDS of them, grown to hold the cover.
	var step := maxi(1, roundi(float(nc) / LITE_CARDS)) if lite else 1
	var grow := minf(sqrt(float(step)), 2.6)
	var kept := ceili(float(nc) / step)
	var lv := PackedVector3Array()
	var ln := PackedVector3Array()
	var lu := PackedVector2Array()
	var lc := PackedColorArray()
	var li := PackedInt32Array()
	lv.resize(kept * 4)
	ln.resize(kept * 4)
	lu.resize(kept * 4)
	lc.resize(kept * 4)
	li.resize(kept * 6)
	var c := 0
	for k in nc:
		if k % step != 0:
			o += 28
			continue
		var p := Vector3(d.decode_half(o) * sx, d.decode_half(o + 2), d.decode_half(o + 4))
		var ua := Vector3(d.decode_half(o + 6) * sx, d.decode_half(o + 8), d.decode_half(o + 10)) * grow
		var va := Vector3(d.decode_half(o + 12) * sx, d.decode_half(o + 14), d.decode_half(o + 16)) * grow
		var x0 := d.decode_u16(o + 18) / 65535.0
		var y0 := d.decode_u16(o + 20) / 65535.0
		var x1 := d.decode_u16(o + 22) / 65535.0
		var y1 := d.decode_u16(o + 24) / 65535.0
		var r := d.decode_u8(o + 26) / 255.0
		var kind := d.decode_u8(o + 27)
		o += 28
		var rel := (p - crown_c) / crown_r
		var out := clampf(rel.length(), 0.0, 1.0)
		var n := (rel / crown_r).normalized() if rel.length_squared() > 1e-6 else Vector3.UP
		var sway := clampf(out * 0.6 + p.y / top * 0.6, 0.0, 1.0)
		# Kind 2: a core card of a conifer, the solid shaded middle.
		var col := Color(r, out, sway, 0.0 if kind == 2 else 1.0)
		var b := c * 4
		lv[b] = p - ua - va
		lv[b + 1] = p + ua - va
		lv[b + 2] = p + ua + va
		lv[b + 3] = p - ua + va
		lu[b] = Vector2(x0, y0)
		lu[b + 1] = Vector2(x1, y0)
		lu[b + 2] = Vector2(x1, y1)
		lu[b + 3] = Vector2(x0, y1)
		for q in 4:
			ln[b + q] = n
			lc[b + q] = col
		var t := c * 6
		li[t] = b
		li[t + 1] = b + 1
		li[t + 2] = b + 2
		li[t + 3] = b
		li[t + 4] = b + 2
		li[t + 5] = b + 3
		c += 1
	if lite and o < d.size():
		bark = []
		_read_bark(d, o, sx, bark)
	var m := ArrayMesh.new()
	for surf in [bark, [lv, ln, lu, lc, li]]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surf[0]
		arrays[Mesh.ARRAY_NORMAL] = surf[1]
		arrays[Mesh.ARRAY_TEX_UV] = surf[2]
		arrays[Mesh.ARRAY_COLOR] = surf[3]
		arrays[Mesh.ARRAY_INDEX] = surf[4]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Reads a bark block at `o` into `out` ([vertices, normals, uvs, colours,
## indices]); returns the offset after it.
static func _read_bark(d: PackedByteArray, o: int, sx: float, out: Array) -> int:
	var nv := d.decode_u32(o)
	var ni := d.decode_u32(o + 4)
	o += 8
	var bv := PackedVector3Array()
	var bn := PackedVector3Array()
	var bu := PackedVector2Array()
	var bc := PackedColorArray()
	bv.resize(nv)
	bn.resize(nv)
	bu.resize(nv)
	bc.resize(nv)
	for i in nv:
		bv[i] = Vector3(d.decode_half(o) * sx, d.decode_half(o + 2), d.decode_half(o + 4))
		bn[i] = Vector3(d.decode_s8(o + 6) * sx, d.decode_s8(o + 7), d.decode_s8(o + 8)).normalized()
		bc[i] = Color(float(d.decode_s8(o + 9)), 0, 0, 1)
		bu[i] = Vector2(d.decode_half(o + 10), d.decode_half(o + 12))
		o += 14
	var bi := PackedInt32Array()
	bi.resize(ni)
	for i in ni:
		bi[i] = d.decode_u32(o)
		o += 4
	if sx < 0.0:
		for t in range(0, ni, 3):
			var k := bi[t + 1]
			bi[t + 1] = bi[t + 2]
			bi[t + 2] = k
	out.append_array([bv, bn, bu, bc, bi])
	return o
