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

enum Species { BROADLEAF, PINE, BUSH }

const VARIANTS := [
	[Species.BROADLEAF, 11],
	[Species.BROADLEAF, 23],
	[Species.BROADLEAF, 37],
	[Species.BROADLEAF, 41],
	[Species.BROADLEAF, 53],
	[Species.PINE, 5],
	[Species.PINE, 19],
	[Species.PINE, 30],
	[Species.BUSH, 3],
	[Species.BUSH, 29],
]
const FRAMES := 8
const FRAME_PIXELS := 256
## Frame size at tree level 2 and up (High and Ultra, and capable iPads
## and browsers). The Broadcast tee camera is a long lens, so a tree just
## past the impostor distance (70 m at level 2) stands about 500 pixels
## tall at 1080p: from 256-pixel frames its crown came out blurred and
## blocky, which was most of what made the far tree lines on the iPad look
## cheap. With ten variants the atlas goes from 2048x2560 to 3072x3840
## (about 63 MB with mipmaps instead of 28), still inside WebGL's 4096
## limit; the normal atlas is half that size each way, in RGB (about 12 MB).
const FRAME_PIXELS_HIGH := 384
## Distance at which a tree turns into its impostor, per GraphicsSettings
## tree level (0 = classic trees, no 3D).
const IMPOSTOR_DISTANCE: Array[float] = [0.0, 35.0, 70.0, 120.0]
## Added to a tree's species in batches() for a tree that is only ever an
## impostor: the back rows of a wood, hidden behind the front rows, which
## never need the full mesh.
const FAR_ONLY := 8

const LEAF_SHADER := preload("res://shaders/tree_leaves.gdshader")
const BARK_SHADER := preload("res://shaders/tree_bark.gdshader")
const IMPOSTOR_SHADER := preload("res://shaders/tree_impostor.gdshader")
## Forward+: sky light passed on through the leaves (the shaders' transmit),
## so crowns in shade stay green instead of going blue-grey. Compatibility
## has its own fill (see material()) and keeps 0.
const TRANSMIT_FORWARD_PLUS := 0.5

## Set by GolfRound from the graphics settings: 0 keeps the classic trees.
static var level := 0

static var _meshes: Array[ArrayMesh] = []
static var _sizes: PackedFloat32Array = []
static var _materials := {}
static var _atlas: ImageTexture
static var _normal_atlas: ImageTexture  ## the impostors' normals, half size
static var _impostor_mats: Array[ShaderMaterial] = []
static var _baking := false
static var _baked := false
static var _waiting: Array[WeakRef] = []
static var _next := {}
static var _instanced_meshes: Array[ArrayMesh] = []
static var _instanced_impostor: ShaderMaterial
static var _impostor_quad: QuadMesh


## The impostor atlas's frame size in pixels for the current tree level.
static func frame_pixels() -> int:
	return FRAME_PIXELS_HIGH if level >= 2 else FRAME_PIXELS


static func enabled() -> bool:
	return level > 0


static func set_level(value: int) -> void:
	level = value
	_update_distance()


## The distance (metres) at which trees turn into impostors at `level`.
static func impostor_distance() -> float:
	return IMPOSTOR_DISTANCE[clampi(level, 1, IMPOSTOR_DISTANCE.size() - 1)]


## Height in metres of the tree TreeFactory.instance() makes for `species`
## at (x, z) (the variant there), before any scale.
static func natural_height(species: Species, x: float, z: float) -> float:
	_ensure_instanced()
	return _meshes[variant_at(species, x, z)].get_aabb().end.y


## A variant of `species` picked by a hash of (x, z), so a course's trees
## come out the same every time.
static func variant_at(species: Species, x: float, z: float) -> int:
	var choices: Array[int] = []
	for v in VARIANTS.size():
		if VARIANTS[v][0] == species:
			choices.append(v)
	var h := hash(Vector2i(roundi(x * 10.0), roundi(z * 10.0)))
	return choices[absi(h) % choices.size()]


## Many trees as MultiMeshes, for a course's trees in place of its
## billboards. `trees` holds per tree: base x, y, z (Godot metres), height
## and species. Full trees are grouped by variant into cells of `cell`
## metres, and the impostors of all of them go in one MultiMesh. Each
## shader switches between the two per tree at the camera's distance (the
## global tree_impostor_distance), and a cell's full trees are culled
## beyond that. Returns [{multimesh, position, reach, full}]: reach is how
## far the farthest tree is from position, so a cell's node can be hidden
## at impostor_distance() + reach. A species of FAR_ONLY or more (see
## FAR_ONLY) gives a tree with only its impostor.
static func batches(trees: PackedFloat32Array, cell: float) -> Array[Dictionary]:
	_ensure_instanced()
	var out: Array[Dictionary] = []
	@warning_ignore("integer_division")
	var n := trees.size() / 5
	if n == 0:
		return out
	var groups := {}  # Vector3i(cell x, cell z, variant) -> PackedInt32Array
	var variant := PackedInt32Array()
	variant.resize(n)
	var far := PackedByteArray()
	far.resize(n)
	var centre := Vector3.ZERO
	for i in n:
		var x := trees[5 * i]
		var z := trees[5 * i + 2]
		var code := int(trees[5 * i + 4])
		var v := variant_at((code % FAR_ONLY) as Species, x, z)
		variant[i] = v
		far[i] = 1 if code >= FAR_ONLY else 0
		centre += Vector3(x, trees[5 * i + 1], z)
		if far[i] == 1:
			continue
		var key := Vector3i(floori(x / cell), floori(z / cell), v)
		if not groups.has(key):
			groups[key] = PackedInt32Array()
		var list: PackedInt32Array = groups[key]
		list.append(i)
		groups[key] = list
	centre /= n
	for key: Vector3i in groups:
		var list: PackedInt32Array = groups[key]
		var mid := Vector3.ZERO
		for i in list:
			mid += Vector3(trees[5 * i], trees[5 * i + 1], trees[5 * i + 2])
		mid /= list.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _instanced_meshes[key.z]
		mm.instance_count = list.size()
		var reach := 0.0
		for k in list.size():
			var i := list[k]
			var t := _tree_transform(trees, i, _meshes[key.z].get_aabb().end.y)
			t.origin -= mid
			reach = maxf(reach, Vector2(t.origin.x, t.origin.z).length())
			mm.set_instance_transform(k, t)
		out.append({multimesh = mm, position = mid, reach = reach, full = true})
	var imp := MultiMesh.new()
	imp.transform_format = MultiMesh.TRANSFORM_3D
	imp.use_custom_data = true
	imp.mesh = _impostor_quad
	imp.instance_count = n
	for i in n:
		var v := variant[i]
		var t := _tree_transform(trees, i, _meshes[v].get_aabb().end.y)
		t.basis = t.basis.scaled(Vector3.ONE * _sizes[v])
		t.origin -= centre
		imp.set_instance_transform(i, t)
		imp.set_instance_custom_data(i, Color((v + 0.5) / VARIANTS.size(), far[i], 0, 0))
	out.append({multimesh = imp, position = centre, reach = 0.0, full = false})
	if not _baked:
		_start_bake()
	_update_distance()
	return out


## Tree i of `trees` (see batches): scaled from the variant's height to the
## placement's, turned by a hash of its position.
static func _tree_transform(trees: PackedFloat32Array, i: int, mesh_height: float) -> Transform3D:
	var x := trees[5 * i]
	var z := trees[5 * i + 2]
	var yaw := float(absi(hash(Vector2i(roundi(z * 10.0), roundi(x * 10.0)))) % 3600) / 3600.0 * TAU
	var s := trees[5 * i + 3] / mesh_height
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(x, trees[5 * i + 1], z))


static func _ensure_instanced() -> void:
	_ensure_meshes()
	if not _instanced_meshes.is_empty():
		return
	for v in VARIANTS.size():
		var m := _meshes[v].duplicate() as ArrayMesh
		m.surface_set_material(0, material("instanced_pine_bark" if VARIANTS[v][0] == Species.PINE else "instanced_bark"))
		m.surface_set_material(1, material("instanced_needles" if VARIANTS[v][0] == Species.PINE else "instanced_leaves"))
		_instanced_meshes.append(m)
	_instanced_impostor = ShaderMaterial.new()
	_instanced_impostor.shader = IMPOSTOR_SHADER
	_instanced_impostor.set_shader_parameter("frames", float(FRAMES))
	_instanced_impostor.set_shader_parameter("rows", float(VARIANTS.size()))
	_instanced_impostor.set_shader_parameter("instanced", true)
	_instanced_impostor.set_shader_parameter("transmit", _impostor_transmit())
	if _atlas != null:
		_instanced_impostor.set_shader_parameter("atlas", _atlas)
		_set_normals(_instanced_impostor)
	_impostor_quad = QuadMesh.new()
	_impostor_quad.size = Vector2.ONE
	_impostor_quad.center_offset = Vector3(0, 0.5, 0)
	_impostor_quad.material = _instanced_impostor


## Until the atlas is baked the full trees show at every distance (and
## the instanced impostors nowhere).
static func _update_distance() -> void:
	RenderingServer.global_shader_parameter_set("tree_impostor_distance", impostor_distance() if _baked else 1.0e6)


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
		_grow_pine(rng, bark, leaves, seed_value % 3)
	elif species == Species.BUSH:
		_grow_bush(rng, bark, leaves)
	else:
		_grow_broadleaf(rng, bark, leaves)
	var m := ArrayMesh.new()
	bark.commit(m)
	leaves.commit(m)
	m.surface_set_material(0, material("pine_bark" if species == Species.PINE else "bark"))
	m.surface_set_material(1, material("needles" if species == Species.PINE else "leaves"))
	return m


static func _grow_broadleaf(rng: RandomNumberGenerator, bark: SurfaceTool, leaves: SurfaceTool) -> void:
	var height := rng.randf_range(9.5, 13.0)
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	# Parkland trees: a short clear trunk and a crown that comes well down
	# the tree, not a ball on a stick.
	var fork := Vector3(0, height * rng.randf_range(0.22, 0.3), 0) + lean * 0.5
	var radius := 0.22 + height * 0.012
	_tube(bark, Vector3.ZERO, fork, radius * 1.25, radius, 7)
	var top := Vector3(lean.x, height * 0.82, lean.z)
	_tube(bark, fork, top, radius, radius * 0.25, 6)
	# Two parkland shapes from reference photos: an open-grown oak, its
	# crown about as wide as the tree is tall and a little flattened, and a
	# beech, a taller dome about three quarters as wide as it is tall.
	var oak := rng.randf() < 0.6
	var centre := Vector3(lean.x * 0.7, height * (0.55 if oak else 0.6), lean.z * 0.7)
	var reach := Vector2(height * (rng.randf_range(0.5, 0.56) if oak else rng.randf_range(0.36, 0.4)),
		height * (0.33 if oak else 0.38))  # crown radii: across, up
	var count := rng.randi_range(10, 12) if oak else rng.randi_range(8, 10)
	var tips: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i in count:
		var along := rng.randf_range(0.0, 1.0)
		var start := fork.lerp(top, along * 0.75)
		var yaw := (float(i) + rng.randf_range(-0.3, 0.3)) / count * TAU
		# Low limbs reach out nearly level (and sag at the tips); high ones climb.
		var rise := lerpf(rng.randf_range(-0.05, 0.25), rng.randf_range(0.5, 0.9), along)
		var dir := Vector3(cos(yaw), rise, sin(yaw)).normalized()
		var length := reach.x * rng.randf_range(0.75, 1.0) * (1.1 - along * 0.4)
		# A real limb is no straight pole: it kinks where it forks, turning
		# up and out, tapers all the way, and carries leaves along its
		# length, so from below it vanishes into the crown.
		var base_r := radius * 0.45 * (1.0 - along * 0.4)
		var knee := start + dir * length * rng.randf_range(0.4, 0.55)
		var bend := (dir + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.15, 0.45), rng.randf_range(-0.35, 0.35))).normalized()
		var end := knee + bend * length * rng.randf_range(0.5, 0.62)
		_tube(bark, start, knee, base_r, base_r * 0.6, 5)
		_tube(bark, knee, end, base_r * 0.6, 0.03, 5)
		# The fork: a second, thinner limb from the knee, off to one side.
		var side_dir := (dir.cross(Vector3.UP).normalized() * (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.5, 0.9) + bend + Vector3.UP * 0.2).normalized()
		var fork_end := knee + side_dir * length * rng.randf_range(0.35, 0.5)
		_tube(bark, knee, fork_end, base_r * 0.42, 0.025, 4)
		tips.append(fork_end)
		for j in 3:
			var on_knee := rng.randf() < 0.5
			var a := start.lerp(knee, rng.randf_range(0.5, 0.95)) if on_knee else knee.lerp(end, rng.randf_range(0.2, 0.8))
			var twig_dir := (bend + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.0, 0.6), rng.randf_range(-0.8, 0.8))).normalized()
			var twig := a + twig_dir * length * rng.randf_range(0.25, 0.4)
			_tube(bark, a, twig, 0.045, 0.012, 3)
			tips.append(twig)
		tips.append(end)
		inner.append(knee)
	tips.append(top)
	# Sprays of small leaf cards round the branch tips, filling the crown
	# with clumps that leave gaps of sky between them.
	for tip in tips:
		_clump(leaves, rng, tip, 1.5, 16, 0.7, 1.0, centre, reach)
	# Smaller sprays round each fork hide the limbs inside the crown.
	for knee in inner:
		_clump(leaves, rng, knee, 1.1, 8, 0.6, 0.9, centre, reach)
	# A few inner cards so the crown isn't hollow when seen through, and a
	# solid shaded core behind them.
	for k in 26:
		var p := centre + _in_ball(rng) * Vector3(reach.x, reach.y, reach.x) * 0.65
		_leaf_card(leaves, rng, p, centre, reach, 1.0, 1.0, Vector3.ZERO)
	_core(leaves, rng, centre, Vector3(reach.x, reach.y, reach.x) * 0.62)


## A shrub: a few thin stems from the ground and a low, wide crown of
## small leaf sprays, close to the ground all round.
static func _grow_bush(rng: RandomNumberGenerator, bark: SurfaceTool, leaves: SurfaceTool) -> void:
	var height := rng.randf_range(1.7, 2.4)
	var reach := Vector2(height * rng.randf_range(0.6, 0.75), height * 0.5)
	var centre := Vector3(0, height * 0.52, 0)
	var tips: Array[Vector3] = []
	var stems := rng.randi_range(5, 7)
	for i in stems:
		var yaw := (float(i) + rng.randf_range(-0.3, 0.3)) / stems * TAU
		var out := Vector3(cos(yaw), 0, sin(yaw))
		var end := out * reach.x * rng.randf_range(0.5, 0.8) + Vector3(0, height * rng.randf_range(0.65, 0.9), 0)
		_tube(bark, out * 0.08, end, 0.035, 0.01, 4)
		tips.append(end)
		tips.append(out * reach.x * 0.75 + Vector3(0, height * 0.3, 0))
	tips.append(Vector3(0, height * 0.9, 0))
	for tip in tips:
		_clump(leaves, rng, tip, 0.6, 14, 0.32, 0.45, centre, reach)
	for k in 14:
		var p := centre + _in_ball(rng) * Vector3(reach.x, reach.y, reach.x) * 0.7
		_leaf_card(leaves, rng, p, centre, reach, 0.4, 0.4, Vector3.ZERO)
	_core(leaves, rng, centre, Vector3(reach.x, reach.y, reach.x) * 0.7)


## `count` leaf cards of half size `small` to `large` scattered through a
## ball of radius `radius` round `at`.
static func _clump(leaves: SurfaceTool, rng: RandomNumberGenerator, at: Vector3, radius: float, count: int,
		small: float, large: float, centre: Vector3, reach: Vector2) -> void:
	for k in count:
		var p := at + _in_ball(rng) * radius * Vector3(1.0, 0.75, 1.0)
		var size := rng.randf_range(small, large)
		_leaf_card(leaves, rng, p, centre, reach, size, size, Vector3.ZERO)


## A random point in the unit ball, denser towards the middle.
static func _in_ball(rng: RandomNumberGenerator) -> Vector3:
	var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
	return d * pow(rng.randf(), 0.6)


## A Scots pine, as in photos of heathland and parkland pines: a tall,
## bare trunk that wanders a little and turns orange up top, with a few
## dead stubs where the lower limbs fell, and a high, open crown of a
## handful of heavy limbs. Each limb climbs out and turns up at the end,
## where its needles sit in flat, layered pads with sky between them,
## darker underneath. Three forms: open-grown (a wide crown from about
## half way up), grown in a stand (a long bare trunk and a small, high
## crown), and wind-leaned.
static func _grow_pine(rng: RandomNumberGenerator, bark: SurfaceTool, leaves: SurfaceTool, form: int) -> void:
	var height := rng.randf_range(15.0, 17.0) if form != 1 else rng.randf_range(16.0, 17.5)
	var crown_base := [rng.randf_range(0.46, 0.52), rng.randf_range(0.62, 0.68), rng.randf_range(0.5, 0.56)][form] as float
	var spread := [0.31, 0.24, 0.28][form] as float  # crown radius / height
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	var lean_m := [rng.randf_range(0.3, 0.7), rng.randf_range(0.2, 0.5), rng.randf_range(1.4, 2.0)][form] as float
	# The trunk: a gentle wander through four points, leaning off the root.
	var spine: Array[Vector3] = []
	for k in 5:
		var t := float(k) / 4.0
		var wobble := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)) * (0.0 if k == 0 else 1.0)
		spine.append(Vector3(0, height * t, 0) + lean * lean_m * pow(t, 1.3) + wobble)
	var r0 := 0.12 + height * 0.009
	for k in 4:
		var t0 := float(k) / 4.0
		var t1 := float(k + 1) / 4.0
		var flare := 1.35 if k == 0 else 1.0
		_tube(bark, spine[k], spine[k + 1], r0 * (1.0 - t0 * 0.8) * flare, r0 * (1.0 - t1 * 0.8) + 0.02, 8 if k < 2 else 6)
	var trunk_at := func(t: float) -> Vector3:
		var f := clampf(t, 0.0, 1.0) * 4.0
		var k := mini(int(f), 3)
		return spine[k].lerp(spine[k + 1], f - k)
	# Dead stubs on the bare trunk, short and drooping.
	for k in rng.randi_range(3, 6):
		var t := rng.randf_range(0.25, crown_base - 0.03)
		var yaw := rng.randf() * TAU
		var a: Vector3 = trunk_at.call(t)
		_tube(bark, a, a + Vector3(cos(yaw), rng.randf_range(-0.35, 0.05), sin(yaw)) * rng.randf_range(0.3, 0.8), 0.05, 0.015, 4)
	var reach := height * spread
	var crown_mid := Vector3(lean.x * lean_m, height * (crown_base + 1.0) * 0.5, lean.z * lean_m)
	var crown_reach := Vector2(reach, height * (1.0 - crown_base) * 0.5)
	var limbs := [rng.randi_range(8, 9), rng.randi_range(6, 7), rng.randi_range(7, 8)][form] as int
	var twist := rng.randf() * TAU
	for i in limbs:
		var u := (float(i) + rng.randf_range(-0.3, 0.3)) / maxf(limbs - 1, 1)
		u = clampf(u, 0.0, 1.0)
		var t := lerpf(crown_base - 0.02, 0.88, u)
		var start: Vector3 = trunk_at.call(t)
		# Limbs go round the trunk about the golden angle, and a leaned tree
		# carries more of them on its downwind side.
		var yaw := twist + i * 2.4 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(yaw), 0, sin(yaw))
		if form == 2:
			out = (out + lean * 0.9).normalized()
		var rise := lerpf(rng.randf_range(0.2, 0.5), rng.randf_range(0.7, 1.1), u)
		var length := reach * rng.randf_range(0.8, 1.05) * (1.0 - u * 0.45)
		var dir := (out + Vector3(0, rise, 0)).normalized()
		var knee := start + dir * length * rng.randf_range(0.5, 0.6)
		var bend := (out * 0.8 + Vector3(0, rise + rng.randf_range(0.3, 0.6), 0) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))).normalized()
		var end := knee + bend * length * rng.randf_range(0.45, 0.55)
		var lr := r0 * (0.5 - u * 0.2)
		_tube(bark, start, knee, lr, lr * 0.65, 5)
		_tube(bark, knee, end, lr * 0.65, 0.03, 4)
		var pad := reach / 3.2
		_pine_pad(leaves, rng, end + Vector3(0, 0.15, 0), pad * rng.randf_range(1.15, 1.45), out, crown_mid, crown_reach)
		# Side branches from the knee, each with its own smaller pad.
		# A pad on the knee too, so the limb carries foliage along its outer half.
		_pine_pad(leaves, rng, knee + bend * 0.3 + Vector3(0, 0.2, 0), pad * rng.randf_range(0.7, 0.9), out, crown_mid, crown_reach)
		for j in 2:
			var side := out.cross(Vector3.UP) * (1.0 if j == 0 else -1.0) * rng.randf_range(0.6, 1.0)
			var sdir := (out * 0.6 + side + Vector3(0, rng.randf_range(0.1, 0.4), 0)).normalized()
			var a := start.lerp(knee, rng.randf_range(0.6, 1.0))
			var b := a + sdir * length * rng.randf_range(0.35, 0.5)
			_tube(bark, a, b, lr * 0.35, 0.02, 4)
			_pine_pad(leaves, rng, b + Vector3(0, 0.1, 0), pad * rng.randf_range(0.8, 1.05), sdir, crown_mid, crown_reach)
	# The top: a few pads round the leader make the flat-topped dome of an
	# old pine.
	var top: Vector3 = trunk_at.call(1.0)
	for k in 4:
		var yaw := twist + k * TAU / 4.0 + rng.randf_range(-0.5, 0.5)
		var off := Vector3(cos(yaw), 0, sin(yaw)) * reach * rng.randf_range(0.15, 0.35)
		_pine_pad(leaves, rng, top + off - Vector3(0, rng.randf_range(0.4, 1.0), 0), reach / 3.2 * rng.randf_range(0.9, 1.1), off.normalized(), crown_mid, crown_reach)


## A pad of pine needles: tufts on the ends of the twigs, held out and up,
## so a pad reads as a flat, layered plate of foliage with a darker
## underside, the look of a pine's crown from any distance. Normals point
## up and out of the pad (its top takes the sun); COLOR.g is how far out
## in the whole crown the pad is, so pads deep inside sit in shade.
static func _pine_pad(leaves: SurfaceTool, rng: RandomNumberGenerator, at: Vector3, radius: float, out: Vector3,
		crown_mid: Vector3, crown_reach: Vector2) -> void:
	var thick := radius * 0.5
	var light_from := at - Vector3(0, radius * 0.9, 0) - out * radius * 0.4
	var count := int(6.0 + radius * 5.5)
	var o := at - crown_mid
	var depth := clampf(Vector3(o.x / crown_reach.x, o.y / crown_reach.y, o.z / crown_reach.x).length(), 0.0, 1.0)
	for k in count:
		var q := _in_ball(rng) * Vector3(radius, thick, radius)
		var p := at + q
		var flat := Vector3(q.x, 0, q.z)
		var along := (flat.normalized() if flat.length() > 0.1 else out) + out * 0.4
		along = (along.normalized() + Vector3(0, rng.randf_range(0.15, 0.6), 0)).normalized()
		var across := along.cross(Vector3.UP).normalized()
		# Most tufts lie flat-ish; some stand up, so a pad has body from the side.
		var tilt := rng.randf_range(-0.35, 0.35) if rng.randf() < 0.6 else rng.randf_range(0.9, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0)
		across = across.rotated(along, tilt)
		var size := rng.randf_range(0.85, 1.1) * clampf(radius / 1.4, 0.7, 1.2)
		_needle_card(leaves, rng, p, light_from, depth, (q.y / thick) * 0.5 + 0.5, 0.45 * size, 0.62 * size, across, along)
	# A flat, dark core, so the gaps between tufts show foliage, not sky.
	_core(leaves, rng, at - Vector3(0, thick * 0.15, 0), Vector3(radius * 0.55, thick * 0.4, radius * 0.55))


## A needle card at `p`: normal away from `light_from`, COLOR.g from how
## deep in the crown its pad is (`depth`) and how high in its pad
## (`up`, 0 the underside).
static func _needle_card(st: SurfaceTool, rng: RandomNumberGenerator, p: Vector3, light_from: Vector3, depth: float,
		up: float, half_w: float, half_h: float, across: Vector3, along: Vector3) -> void:
	var normal := (p - light_from).normalized()
	var outer := clampf(lerpf(0.35, 1.0, depth) * lerpf(0.55, 1.0, up), 0.0, 1.0)
	var a := across.normalized() * half_w
	var b := along.normalized() * half_h
	var color := Color(rng.randf(), outer, clampf(p.y / 15.0, 0.2, 1.0) * (0.4 + 0.6 * outer), 1.0)
	var corners := [[p - a - b, Vector2(0, 1)], [p + a - b, Vector2(1, 1)], [p + a + b, Vector2(1, 0)], [p - a + b, Vector2(0, 0)]]
	for k: int in [0, 2, 1, 0, 3, 2]:
		st.set_color(color)
		st.set_normal(normal)
		st.set_uv(corners[k][1])
		st.add_vertex(corners[k][0])


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
## versions that draw plain albedo for the impostor atlas and "instanced_..."
## ones for the MultiMeshes of batches().
static func material(which: String) -> ShaderMaterial:
	if _materials.has(which):
		return _materials[which]
	var bake_normal := which.begins_with("bakenormal_")
	var bake := which.begins_with("bake_") or bake_normal
	var instanced := which.begins_with("instanced_")
	var kind := which.trim_prefix("bakenormal_").trim_prefix("bake_").trim_prefix("instanced_")
	var mat := ShaderMaterial.new()
	if kind.ends_with("bark"):
		mat.shader = BARK_SHADER
		if kind == "pine_bark":
			# A pine's trunk stands in the sun below its high crown, and the
			# bark goes from grey-brown plates at the foot to thin, flaking
			# orange up the stem (Scots pine).
			mat.set_shader_parameter("shade_from", 9.0)
			mat.set_shader_parameter("shade_to", 14.0)
			mat.set_shader_parameter("upper_tint", Vector3(1.45, 0.98, 0.72))
			mat.set_shader_parameter("upper_from", 4.0)
			mat.set_shader_parameter("upper_to", 8.5)
		var albedo := FreeAssets.tree_texture("bark_albedo.jpg")
		if albedo != null:
			mat.set_shader_parameter("bark_color", albedo)
			mat.set_shader_parameter("bark_normal", FreeAssets.tree_texture("bark_normal.jpg"))
			mat.set_shader_parameter("has_texture", true)
	else:
		mat.shader = LEAF_SHADER
		mat.set_shader_parameter("needles", kind == "needles")
		# Compatibility has no fill light from the sky. Forward+ lights the
		# crown from the sky as well, so it needs only a little fill and a
		# cooler green (under its sun the photo leaves read yellow-lime).
		# Inner leaves stay at half light or more: next to real sunlit
		# trees darker insides read as black cut-outs. The impostors are
		# baked to match.
		var fwd := GraphicsSettings.is_forward_plus()
		mat.set_shader_parameter("fill", 0.06 if fwd else 0.3)
		mat.set_shader_parameter("inner_shade", 0.5 if fwd else 0.62)
		if fwd:
			mat.set_shader_parameter("leaf_tint", Vector3(0.3, 0.5, 0.34))
			if not bake:
				mat.set_shader_parameter("transmit", TRANSMIT_FORWARD_PLUS)
		var twig := FreeAssets.tree_texture("twig_albedo.jpg")
		var twig_alpha := FreeAssets.tree_texture("twig_opacity.png")
		if twig != null and twig_alpha != null and kind == "needles":
			mat.set_shader_parameter("twig_color", twig)
			mat.set_shader_parameter("twig_opacity", twig_alpha)
			mat.set_shader_parameter("has_twig", true)
		var leaf := FreeAssets.tree_texture("leaf_albedo.png")
		var opacity := FreeAssets.tree_texture("leaf_opacity.png")
		if leaf != null and opacity != null and kind == "leaves":
			mat.set_shader_parameter("leaf_color", leaf)
			mat.set_shader_parameter("leaf_opacity", opacity)
			mat.set_shader_parameter("has_texture", true)
		var spray := FreeAssets.tree_texture("leaf_spray.png")
		if spray != null and kind == "leaves":
			mat.set_shader_parameter("leaf_spray", spray)
			mat.set_shader_parameter("has_spray", true)
	mat.set_shader_parameter("bake", bake)
	mat.set_shader_parameter("bake_normal", bake_normal)
	mat.set_shader_parameter("instanced", instanced)
	_materials[which] = mat
	return mat


static func _add_impostor(root: Node3D) -> void:
	var variant: int = root.get_meta("tree_variant")
	var distance := impostor_distance()
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
	# No sun shadow from the impostor: the shadow pass draws the quad, not
	# the tree, and it laid hard-edged dark wedges and a vertical seam
	# across the crowns behind it (Natural look on the iPad). The ground
	# under a far tree is shaded by GroundShade, like the batched impostors.
	imp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var px := frame_pixels()
	vp.size = Vector2i(FRAMES * px, rows * px)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
			mi.set_surface_override_material(0, material("bake_pine_bark" if VARIANTS[v][0] == Species.PINE else "bake_bark"))
			mi.set_surface_override_material(1, material("bake_needles" if VARIANTS[v][0] == Species.PINE else "bake_leaves"))
			mi.scale = Vector3.ONE / _sizes[v]
			mi.position = Vector3(k + 0.5 - FRAMES * 0.5, rows - 1 - v, 0)
			# Copy k shows the tree as seen from azimuth k * 360 / FRAMES.
			mi.rotation.y = -float(k) / FRAMES * TAU
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_meta("variant", v)
			vp.add_child(mi)
	tree.root.add_child.call_deferred(vp)
	# WebGL (Compatibility on the web) needs the viewport to keep drawing for
	# a few frames before the read-back holds the whole atlas: with
	# UPDATE_ONCE and three frames it came back almost empty, and the far
	# trees drew as dark wedges. It is freed straight after, so the cost is
	# a handful of frames at load.
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	# Then the same views again with each leaf's and branch's normal as its
	# colour, so the impostors take the sun clump by clump as the full
	# trees do, instead of as one flat patch of green.
	for mi in vp.get_children():
		if mi is MeshInstance3D:
			var v: int = mi.get_meta("variant")
			var pine: bool = VARIANTS[v][0] == Species.PINE
			mi.set_surface_override_material(0, material("bakenormal_pine_bark" if pine else "bakenormal_bark"))
			mi.set_surface_override_material(1, material("bakenormal_needles" if pine else "bakenormal_leaves"))
	for i in 8:
		await RenderingServer.frame_post_draw
	var normals := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		_baking = false
		return
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	_normal_atlas = null
	if normals != null and not normals.is_empty():
		# Half size: the light changes clump by clump, not leaf by leaf.
		normals.convert(Image.FORMAT_RGB8)
		@warning_ignore("integer_division")
		normals.resize(normals.get_width() / 2, normals.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		normals.generate_mipmaps()
		_normal_atlas = ImageTexture.create_from_image(normals)
	for v in rows:
		var mat := ShaderMaterial.new()
		mat.shader = IMPOSTOR_SHADER
		mat.set_shader_parameter("atlas", _atlas)
		_set_normals(mat)
		mat.set_shader_parameter("frames", float(FRAMES))
		mat.set_shader_parameter("rows", float(rows))
		mat.set_shader_parameter("row", float(v))
		mat.set_shader_parameter("transmit", _impostor_transmit())
		_impostor_mats.append(mat)
	_baked = true
	if _instanced_impostor != null:
		_instanced_impostor.set_shader_parameter("atlas", _atlas)
		_set_normals(_instanced_impostor)
	_update_distance()
	for ref in _waiting:
		var node := ref.get_ref() as Node3D
		if node != null and is_instance_valid(node):
			_add_impostor(node)
	_waiting.clear()


static func _set_normals(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("normals", _normal_atlas)
	mat.set_shader_parameter("has_normals", _normal_atlas != null)


static func _impostor_transmit() -> float:
	return TRANSMIT_FORWARD_PLUS if GraphicsSettings.is_forward_plus() else 0.0


## The baked atlas, or null before the first bake (and when headless).
static func atlas() -> ImageTexture:
	return _atlas
