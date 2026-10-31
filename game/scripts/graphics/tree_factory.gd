class_name TreeFactory
extends RefCounted
## Photo-textured 3D trees for the Photoreal looks, with impostors at a
## distance. Each tree is generated from a seed: tapered branches with the
## free bark texture, and leaf cards whose leaves come from the free leaf
## texture (see FreeAssets; plain shapes without it). Leaf normals point
## out from the middle of the crown, so a crown shades like one soft mass,
## the way real trees read from a distance.
##
## Far trees are impostors: one camera-facing quad showing the tree from the
## nearest of FRAMES directions. The views are rendered once, the first time
## a tree is made, into one atlas (a row per variant). Until then, and in
## headless runs, which render nothing, the full trees are drawn at every
## distance. Visual only: the ball's obstacles come from the course data.

enum Species { BROADLEAF, PINE }

const VARIANTS := [
	[Species.BROADLEAF, 11],
	[Species.BROADLEAF, 23],
	[Species.BROADLEAF, 37],
	[Species.PINE, 5],
	[Species.PINE, 19],
]
const FRAMES := 8
const FRAME_PIXELS := 256
## Distance at which a tree turns into its impostor, per GraphicsSettings
## tree level (0 = classic trees, no 3D).
const IMPOSTOR_DISTANCE: Array[float] = [0.0, 35.0, 70.0, 120.0]

const LEAF_SHADER := preload("res://shaders/tree_leaves.gdshader")
const BARK_SHADER := preload("res://shaders/tree_bark.gdshader")
const IMPOSTOR_SHADER := preload("res://shaders/tree_impostor.gdshader")

## Set by GolfRound from the graphics settings: 0 keeps the classic trees.
static var level := 0

static var _meshes: Array[ArrayMesh] = []
static var _sizes: PackedFloat32Array = []
static var _materials := {}
static var _atlas: ImageTexture
static var _impostor_mats: Array[ShaderMaterial] = []
static var _baking := false
static var _baked := false
static var _waiting: Array[WeakRef] = []
static var _next := {}


static func enabled() -> bool:
	return level > 0


## A tree of `species`, cycling through its variants. `seed_hint` picks the
## variant when given (>= 0).
static func instance(species: Species, seed_hint := -1) -> Node3D:
	var choices: Array[int] = []
	for v in VARIANTS.size():
		if VARIANTS[v][0] == species:
			choices.append(v)
	var n: int = _next.get(species, 0)
	_next[species] = n + 1
	var variant := choices[(seed_hint if seed_hint >= 0 else n) % choices.size()]
	return make_variant(variant)


static func make_variant(variant: int) -> Node3D:
	_ensure_meshes()
	var root := Node3D.new()
	root.name = "Tree"
	root.set_meta("tree_variant", variant)
	var full := MeshInstance3D.new()
	full.name = "Full"
	full.mesh = _meshes[variant]
	root.add_child(full)
	if _baked:
		_add_impostor(root)
	else:
		_waiting.append(weakref(root))
		_start_bake()
	return root


## The mesh of a variant: surface 0 is bark, surface 1 leaves.
static func mesh(variant: int) -> ArrayMesh:
	_ensure_meshes()
	return _meshes[variant]


## Side of the square (metres) that holds the variant, base at the bottom.
static func frame_size(variant: int) -> float:
	_ensure_meshes()
	return _sizes[variant]


static func _ensure_meshes() -> void:
	if not _meshes.is_empty():
		return
	for v in VARIANTS:
		var m := build_mesh(v[0], v[1])
		var box := m.get_aabb()
		var half_width := maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
		_meshes.append(m)
		_sizes.append(maxf(box.end.y, half_width * 2.0) * 1.02)


## Generates a tree. Deterministic: the same species and seed always give
## the same mesh.
static func build_mesh(species: Species, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	if species == Species.PINE:
		_grow_pine(rng, bark, leaves)
	else:
		_grow_broadleaf(rng, bark, leaves)
	var m := ArrayMesh.new()
	bark.commit(m)
	leaves.commit(m)
	m.surface_set_material(0, material("bark"))
	m.surface_set_material(1, material("needles" if species == Species.PINE else "leaves"))
	return m


static func _grow_broadleaf(rng: RandomNumberGenerator, bark: SurfaceTool, leaves: SurfaceTool) -> void:
	var height := rng.randf_range(9.5, 13.0)
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	var fork := Vector3(0, height * rng.randf_range(0.3, 0.38), 0) + lean * 0.5
	var radius := 0.22 + height * 0.012
	_tube(bark, Vector3.ZERO, fork, radius * 1.25, radius, 7)
	var top := Vector3(lean.x, height * 0.82, lean.z)
	_tube(bark, fork, top, radius, radius * 0.25, 6)
	var centre := Vector3(lean.x * 0.7, height * 0.62, lean.z * 0.7)
	var reach := Vector2(height * rng.randf_range(0.33, 0.42), height * 0.32)  # crown radii: across, up
	var count := rng.randi_range(7, 9)
	var tips: Array[Vector3] = []
	for i in count:
		var along := rng.randf_range(0.0, 1.0)
		var start := fork.lerp(top, along * 0.75)
		var yaw := (float(i) + rng.randf_range(-0.3, 0.3)) / count * TAU
		var rise := rng.randf_range(0.35, 0.8)
		var dir := Vector3(cos(yaw), rise, sin(yaw)).normalized()
		var length := reach.x * rng.randf_range(0.75, 1.0) * (1.1 - along * 0.4)
		var end := start + dir * length
		_tube(bark, start, end, radius * 0.45 * (1.0 - along * 0.4), 0.03, 5)
		for j in 3:
			var at := start.lerp(end, rng.randf_range(0.4, 0.85))
			var side := (dir + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.0, 0.6), rng.randf_range(-0.8, 0.8))).normalized()
			var twig := at + side * length * rng.randf_range(0.3, 0.5)
			_tube(bark, at, twig, 0.05, 0.015, 4)
			tips.append(twig)
		tips.append(end)
	tips.append(top)
	# Leaf cards in clumps around the branch tips, filling the crown.
	for tip in tips:
		for k in 12:
			var p := tip + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.9), rng.randf_range(-1, 1)) * 1.4
			var size := rng.randf_range(1.5, 2.2)
			_leaf_card(leaves, rng, p, centre, reach, size, size, Vector3.ZERO)
	# A few inner cards so the crown isn't hollow when seen through, and a
	# solid shaded core behind them.
	for k in 18:
		var p := centre + Vector3(rng.randf_range(-1, 1) * reach.x, rng.randf_range(-0.6, 0.8) * reach.y, rng.randf_range(-1, 1) * reach.x) * 0.6
		_leaf_card(leaves, rng, p, centre, reach, 1.8, 1.8, Vector3.ZERO)
	_core(leaves, rng, centre, Vector3(reach.x, reach.y, reach.x) * 0.62)


static func _grow_pine(rng: RandomNumberGenerator, bark: SurfaceTool, leaves: SurfaceTool) -> void:
	var height := rng.randf_range(13.0, 17.0)
	var radius := 0.2 + height * 0.01
	var top := Vector3(rng.randf_range(-0.2, 0.2), height, rng.randf_range(-0.2, 0.2))
	_tube(bark, Vector3.ZERO, top * 0.5, radius * 1.2, radius * 0.6, 7)
	_tube(bark, top * 0.5, top, radius * 0.6, 0.02, 6)
	var centre := Vector3(0, height * 0.5, 0)
	var reach := Vector2(height * 0.24, height * 0.5)
	var y := height * rng.randf_range(0.22, 0.3)
	while y < height * 0.97:
		var t := y / height
		var spokes := rng.randi_range(5, 7)
		var twist := rng.randf() * TAU
		var length := (1.0 - t) * height * 0.28 + 0.5
		var axis := top * t
		for i in spokes:
			var yaw := twist + (float(i) + rng.randf_range(-0.25, 0.25)) / spokes * TAU
			var droop := rng.randf_range(-0.35, 0.05)
			var dir := Vector3(cos(yaw), droop, sin(yaw)).normalized()
			var end := axis + dir * length
			_tube(bark, axis, end, 0.05 + 0.04 * (1.0 - t), 0.015, 4)
			# Sprigs lie along the branch, flattish, overlapping.
			var pieces := maxi(1, ceili(length / 1.3))
			for p in pieces:
				var a := axis.lerp(end, float(p) / pieces)
				var b := axis.lerp(end, float(p + 1) / pieces + 0.15)
				var mid := (a + b) * 0.5 + Vector3(0, 0.08, 0)
				var across := dir.cross(Vector3.UP).normalized()
				var along := (b - a).normalized()
				var crown := Vector3(axis.x, mid.y, axis.z) + Vector3(0, -0.6, 0)
				var half := (b - a).length() * 0.5 + 0.25
				# Two sprigs crossed along the branch, so it has body from
				# the side as well as from above.
				for turn in [-0.5, 0.5]:
					var side := across.rotated(along, turn + rng.randf_range(-0.2, 0.2))
					_leaf_card(leaves, rng, mid, crown, reach, 0.55, half, side, along)
		y += rng.randf_range(0.75, 1.05) * (1.0 - t * 0.3)
	_core(leaves, rng, centre + Vector3(0, -height * 0.1, 0), Vector3(reach.x * 0.55, height * 0.32, reach.x * 0.55))
	# The leader at the top.
	_leaf_card(leaves, rng, top - Vector3(0, 0.6, 0), centre, reach, 0.35, 0.6, Vector3.RIGHT, Vector3.UP)
	_leaf_card(leaves, rng, top - Vector3(0, 0.6, 0), centre, reach, 0.35, 0.6, Vector3.BACK, Vector3.UP)


## A tapered tube from `a` to `b` with UVs in metres (around, along).
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int) -> void:
	var axis := (b - a).normalized()
	var helper := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(helper).normalized()
	var w := axis.cross(u)
	var length := a.distance_to(b)
	for i in sides:
		var a0 := float(i) / sides * TAU
		var a1 := float(i + 1) / sides * TAU
		var n0 := u * cos(a0) + w * sin(a0)
		var n1 := u * cos(a1) + w * sin(a1)
		var u0 := float(i) / sides * ra * TAU
		var u1 := float(i + 1) / sides * ra * TAU
		var quad := [
			[a + n0 * ra, n0, Vector2(u0, 0.0)], [a + n1 * ra, n1, Vector2(u1, 0.0)],
			[b + n1 * rb, n1, Vector2(u1, length)], [b + n0 * rb, n0, Vector2(u0, length)],
		]
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(quad[k][1])
			st.set_uv(quad[k][2])
			st.add_vertex(quad[k][0])


## A leaf card at `p`. Normals point away from the crown's centre; COLOR
## carries a random tint (r), how far out in the crown it is (g, for the
## inner shade) and how much it sways (b). `across` and `along` orient the
## card; zero `across` gives a random orientation.
static func _leaf_card(st: SurfaceTool, rng: RandomNumberGenerator, p: Vector3, centre: Vector3, reach: Vector2,
		half_w: float, half_h: float, across: Vector3, along := Vector3.ZERO) -> void:
	var out := p - centre
	var outer := clampf(Vector3(out.x / reach.x, out.y / reach.y, out.z / reach.x).length(), 0.0, 1.0)
	var normal := (out.normalized() + Vector3(0, 0.35, 0)).normalized()
	if across == Vector3.ZERO:
		across = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.4), rng.randf_range(-1, 1))
		if across.length() < 0.1:
			across = Vector3.RIGHT
	across = across.normalized()
	if along == Vector3.ZERO:
		along = across.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		if along.length() < 0.1:
			along = Vector3.UP
	var a := across * half_w
	var b := along * half_h
	var color := Color(rng.randf(), outer, clampf(p.y / 15.0, 0.2, 1.0) * (0.4 + 0.6 * outer), 1.0)
	var corners := [[p - a - b, Vector2(0, 1)], [p + a - b, Vector2(1, 1)], [p + a + b, Vector2(1, 0)], [p - a + b, Vector2(0, 0)]]
	for k: int in [0, 2, 1, 0, 3, 2]:
		st.set_color(color)
		st.set_normal(normal)
		st.set_uv(corners[k][1])
		st.add_vertex(corners[k][0])


## The solid core of a crown: crossed discs filling an ellipsoid with radii
## `r` (COLOR.a 0 tells the leaf shader to draw them solid and dark).
static func _core(st: SurfaceTool, rng: RandomNumberGenerator, centre: Vector3, r: Vector3) -> void:
	var axes := [[Vector3.RIGHT, Vector3.UP], [Vector3.BACK, Vector3.UP], [Vector3.RIGHT, Vector3.BACK],
		[Vector3(1, 0, 1).normalized(), Vector3.UP], [Vector3(1, 0, -1).normalized(), Vector3.UP]]
	for pair in axes:
		var across: Vector3 = pair[0]
		var along: Vector3 = pair[1]
		var a := across * Vector3(r.x, r.y, r.z).dot(across.abs())
		var b := along * Vector3(r.x, r.y, r.z).dot(along.abs())
		var normal := across.cross(along).normalized()
		var color := Color(rng.randf(), 0.0, 0.0, 0.0)
		var corners := [[centre - a - b, Vector2(0, 1)], [centre + a - b, Vector2(1, 1)], [centre + a + b, Vector2(1, 0)], [centre - a + b, Vector2(0, 0)]]
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_color(color)
			st.set_normal(normal)
			st.set_uv(corners[k][1])
			st.add_vertex(corners[k][0])


## The shared materials: "bark", "leaves" and "needles", plus "bake_..."
## versions that draw plain albedo for the impostor atlas.
static func material(which: String) -> ShaderMaterial:
	if _materials.has(which):
		return _materials[which]
	var bake := which.begins_with("bake_")
	var kind := which.trim_prefix("bake_")
	var mat := ShaderMaterial.new()
	if kind == "bark":
		mat.shader = BARK_SHADER
		var albedo := FreeAssets.tree_texture("bark_albedo.jpg")
		if albedo != null:
			mat.set_shader_parameter("bark_color", albedo)
			mat.set_shader_parameter("bark_normal", FreeAssets.tree_texture("bark_normal.jpg"))
			mat.set_shader_parameter("has_texture", true)
	else:
		mat.shader = LEAF_SHADER
		mat.set_shader_parameter("needles", kind == "needles")
		var leaf := FreeAssets.tree_texture("leaf_albedo.png")
		var opacity := FreeAssets.tree_texture("leaf_opacity.png")
		if leaf != null and opacity != null and kind == "leaves":
			mat.set_shader_parameter("leaf_color", leaf)
			mat.set_shader_parameter("leaf_opacity", opacity)
			mat.set_shader_parameter("has_texture", true)
	mat.set_shader_parameter("bake", bake)
	_materials[which] = mat
	return mat


static func _add_impostor(root: Node3D) -> void:
	var variant: int = root.get_meta("tree_variant")
	var distance := IMPOSTOR_DISTANCE[clampi(level, 1, IMPOSTOR_DISTANCE.size() - 1)]
	var full := root.get_node("Full") as GeometryInstance3D
	full.visibility_range_end = distance
	full.visibility_range_end_margin = 4.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0, 0.5, 0)
	var imp := MeshInstance3D.new()
	imp.name = "Impostor"
	imp.mesh = quad
	imp.material_override = _impostor_mats[variant]
	imp.scale = Vector3.ONE * _sizes[variant]
	imp.visibility_range_begin = distance
	imp.visibility_range_begin_margin = 4.0
	root.add_child(imp)


## Renders every variant from FRAMES directions into the atlas: one
## viewport, a row of turned copies per variant, one frame.
static func _start_bake() -> void:
	if _baking or DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_baking = true
	_bake(tree)


static func _bake(tree: SceneTree) -> void:
	var rows := VARIANTS.size()
	var vp := SubViewport.new()
	vp.name = "TreeImpostorBake"
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(FRAMES * FRAME_PIXELS, rows * FRAME_PIXELS)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = rows
	cam.near = 1.0
	cam.far = 100.0
	cam.position = Vector3(0, rows * 0.5, 50)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	vp.add_child(cam)
	for v in rows:
		for k in FRAMES:
			var mi := MeshInstance3D.new()
			mi.mesh = _meshes[v]
			mi.set_surface_override_material(0, material("bake_bark"))
			mi.set_surface_override_material(1, material("bake_needles" if VARIANTS[v][0] == Species.PINE else "bake_leaves"))
			mi.scale = Vector3.ONE / _sizes[v]
			mi.position = Vector3(k + 0.5 - FRAMES * 0.5, rows - 1 - v, 0)
			# Copy k shows the tree as seen from azimuth k * 360 / FRAMES.
			mi.rotation.y = -float(k) / FRAMES * TAU
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			vp.add_child(mi)
	tree.root.add_child.call_deferred(vp)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		_baking = false
		return
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	for v in rows:
		var mat := ShaderMaterial.new()
		mat.shader = IMPOSTOR_SHADER
		mat.set_shader_parameter("atlas", _atlas)
		mat.set_shader_parameter("frames", float(FRAMES))
		mat.set_shader_parameter("rows", float(rows))
		mat.set_shader_parameter("row", float(v))
		_impostor_mats.append(mat)
	_baked = true
	for ref in _waiting:
		var node := ref.get_ref() as Node3D
		if node != null and is_instance_valid(node):
			_add_impostor(node)
	_waiting.clear()


## The baked atlas, or null before the first bake (and when headless).
static func atlas() -> ImageTexture:
	return _atlas
