class_name Gallery
extends Node3D
## A tournament gallery for the Broadcast presentation: gallery ropes on
## stakes down both sides of the tee and around the back of the green, and
## spectators standing behind them, close enough to the cameras to be seen
## in the tee shot and the approach, as on tour coverage.
##
## Real scale, from tour photos: the stakes are about 1.1 m tall, 4 m
## apart, and carry a 12 mm rope hung at about 0.85 m that sags a few
## centimetres between stakes. On the tee the ropes run 7 m either side of
## the line, from just behind the markers to 30 m down the hole; at the
## green they stand about 5 m off the putting surface, round the back.
## The spectators are the player creator's people (FreeGolfer with a random
## PlayerLook) without clubs, standing idle, facing the play. They are
## scenery only: nothing collides with them or the ropes.

const STAKE_HEIGHT := 1.1
const STAKE_RADIUS := 0.022
const STAKE_GAP := 4.0
const ROPE_HEIGHT := 0.85
const ROPE_RADIUS := 0.01
const ROPE_SAG := 0.06
## The tee gallery: how far either side of the line, and how far it runs.
const TEE_SIDE := 7.0
const TEE_FROM := -4.0
const TEE_TO := 30.0
## The green gallery: how far past the edge of the putting surface, and how
## much of the way round the back of the green it goes (degrees).
const GREEN_MARGIN := 5.0
const GREEN_ARC := 200.0
const GREEN_SEARCH := 45.0
## Spectators stand this far behind the rope, at least this far apart.
const CROWD_NEAR := 1.0
const CROWD_FAR := 3.2
const CROWD_SPACING := 0.9
## How many spectators each quality level draws: they are full people, so
## the count is kept to the ones near the cameras.
const CROWD_BY_QUALITY: Array[int] = [0, 10, 18, 28]

const STAKE_COLOUR := Color(0.13, 0.22, 0.14)
const ROPE_COLOUR := Color(0.92, 0.9, 0.84)


## Builds the gallery for `hole`, with up to `crowd` spectators.
static func build(hole: HoleData, toward: Vector3, crowd: int, seed_value: int) -> Gallery:
	var g := Gallery.new()
	g.name = "Gallery"
	var lines := tee_lines(hole.terrain, hole.tee, toward)
	lines.append_array(green_lines(hole.terrain, hole.pin, hole.tee))
	g._build_ropes(hole.terrain, lines)
	if crowd > 0:
		g._build_crowd(hole, lines, crowd, seed_value)
	return g


## The two rope lines down the sides of the tee, as stake positions, each
## broken where a stake would stand in water, sand or on a green.
static func tee_lines(terrain: CourseTerrain, tee: Vector3, toward: Vector3) -> Array[PackedVector3Array]:
	var dir := Vector3(toward.x - tee.x, 0.0, toward.z - tee.z)
	dir = Vector3(0, 0, 1) if dir.length() < 0.01 else dir.normalized()
	var side := Vector3.UP.cross(dir)
	var lines: Array[PackedVector3Array] = []
	for s: float in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var along := TEE_FROM
		while along <= TEE_TO + 0.01:
			pts.append(tee + dir * along + side * (s * TEE_SIDE))
			along += STAKE_GAP
		lines.append_array(_split(terrain, pts))
	return lines


## The rope round the back of the green: an arc GREEN_MARGIN off the edge
## of the putting surface, on the far side from where the hole is played.
static func green_lines(terrain: CourseTerrain, pin: Vector3, tee: Vector3) -> Array[PackedVector3Array]:
	var back := Vector3(pin.x - tee.x, 0.0, pin.z - tee.z)
	back = Vector3(0, 0, 1) if back.length() < 0.01 else back.normalized()
	var centre_angle := atan2(back.x, back.z)
	var pts := PackedVector3Array()
	var half := deg_to_rad(GREEN_ARC * 0.5)
	var a := -half
	while a <= half + 1e-4:
		var d := Vector3(sin(centre_angle + a), 0.0, cos(centre_angle + a))
		var r := _green_edge(terrain, pin, d) + GREEN_MARGIN
		pts.append(pin + d * r)
		# Step round so the stakes stay about STAKE_GAP apart.
		a += STAKE_GAP / maxf(r, 4.0)
	return _split(terrain, pts)


## Metres from the pin to the edge of the green (and fringe) along `d`.
static func _green_edge(terrain: CourseTerrain, pin: Vector3, d: Vector3) -> float:
	var r := 0.5
	while r < GREEN_SEARCH:
		var p := pin + d * r
		var s := terrain.surface_at(p.x, p.z)
		if s != Surface.Type.GREEN and s != Surface.Type.FRINGE:
			return r
		r += 0.5
	return GREEN_SEARCH


## Splits a run of stakes where one would stand somewhere a stake can't go,
## and drops any piece too short to carry a rope.
static func _split(terrain: CourseTerrain, pts: PackedVector3Array) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var run := PackedVector3Array()
	for p in pts:
		var s := terrain.surface_at(p.x, p.z)
		if s == Surface.Type.WATER or s == Surface.Type.SAND or s == Surface.Type.GREEN:
			if run.size() >= 2:
				out.append(run)
			run = PackedVector3Array()
			continue
		run.append(Vector3(p.x, terrain.height_at(p.x, p.z), p.z))
	if run.size() >= 2:
		out.append(run)
	return out


## The rope's height above the ground `t` (0..1) of the way between stakes:
## highest at the stakes, sagging ROPE_SAG at the middle.
static func rope_drop(t: float) -> float:
	return ROPE_SAG * 4.0 * t * (1.0 - t)


func _build_ropes(terrain: CourseTerrain, lines: Array[PackedVector3Array]) -> void:
	var count := 0
	for line in lines:
		count += line.size()
	if count == 0:
		return
	# The stakes: one instanced mesh for the whole gallery.
	var stake := CylinderMesh.new()
	stake.top_radius = STAKE_RADIUS
	stake.bottom_radius = STAKE_RADIUS
	stake.height = STAKE_HEIGHT
	stake.radial_segments = 6
	stake.rings = 1
	var stake_mat := StandardMaterial3D.new()
	stake_mat.albedo_color = STAKE_COLOUR
	stake_mat.roughness = 0.7
	stake.material = stake_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stake
	mm.instance_count = count
	var i := 0
	for line in lines:
		for p in line:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p + Vector3.UP * (STAKE_HEIGHT * 0.5 - 0.05)))
			i += 1
	var stakes := MultiMeshInstance3D.new()
	stakes.name = "Stakes"
	stakes.multimesh = mm
	add_child(stakes)
	# The rope: a thin four-sided tube through every span, in one mesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for line in lines:
		var path := PackedVector3Array()
		for k in line.size() - 1:
			var a := line[k]
			var b := line[k + 1]
			for j in 6:
				var t := j / 6.0
				var p := a.lerp(b, t)
				# Follow the ground between stakes, so the rope never dips into a rise.
				var ground := lerpf(a.y, b.y, t)
				ground = maxf(ground, terrain.height_at(p.x, p.z))
				path.append(Vector3(p.x, ground + ROPE_HEIGHT - rope_drop(t), p.z))
		var last := line[line.size() - 1]
		path.append(last + Vector3.UP * ROPE_HEIGHT)
		_tube(st, path)
	st.generate_normals()
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = ROPE_COLOUR
	rope_mat.roughness = 0.85
	st.set_material(rope_mat)
	var rope := MeshInstance3D.new()
	rope.name = "Rope"
	rope.mesh = st.commit()
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rope)


static func _tube(st: SurfaceTool, path: PackedVector3Array) -> void:
	var n := path.size()
	for k in n - 1:
		var a := path[k]
		var b := path[k + 1]
		var fwd := (b - a).normalized()
		var s := fwd.cross(Vector3.UP).normalized() * ROPE_RADIUS
		var u := Vector3.UP * ROPE_RADIUS
		var ring_a := [a + u, a + s, a - u, a - s]
		var ring_b := [b + u, b + s, b - u, b - s]
		for q in 4:
			var q2 := (q + 1) % 4
			st.add_vertex(ring_a[q])
			st.add_vertex(ring_b[q])
			st.add_vertex(ring_b[q2])
			st.add_vertex(ring_a[q])
			st.add_vertex(ring_b[q2])
			st.add_vertex(ring_a[q2])


## Where the spectators stand: behind each rope, away from the play, the
## nearest to the tee and the green first. Each is [position, the point
## they face].
static func crowd_spots(hole: HoleData, lines: Array[PackedVector3Array], count: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var candidates: Array = []
	for line in lines:
		var near_green := line[0].distance_to(hole.pin) < GREEN_SEARCH + GREEN_MARGIN + 5.0
		var focus := hole.pin if near_green else hole.tee
		for k in line.size() - 1:
			var a := line[k]
			var b := line[k + 1]
			var span := Vector3(b.x - a.x, 0.0, b.z - a.z)
			if span.length() < 0.1:
				continue
			var out := Vector3.UP.cross(span.normalized())
			# Outward is away from what the gallery is watching.
			var mid := (a + b) * 0.5
			if out.dot(Vector3(mid.x - focus.x, 0.0, mid.z - focus.z)) < 0.0:
				out = -out
			for j in 3:
				var p := a.lerp(b, rng.randf()) + out * rng.randf_range(CROWD_NEAR, CROWD_FAR)
				candidates.append([p, focus, p.distance_to(focus)])
	candidates.sort_custom(func(x: Array, y: Array) -> bool: return x[2] < y[2])
	var spots: Array = []
	for c: Array in candidates:
		if spots.size() >= count:
			break
		var p: Vector3 = c[0]
		var s := hole.terrain.surface_at(p.x, p.z)
		if s == Surface.Type.WATER or s == Surface.Type.SAND or s == Surface.Type.GREEN:
			continue
		var free := true
		for other: Array in spots:
			if (other[0] as Vector3).distance_to(p) < CROWD_SPACING:
				free = false
				break
		if free:
			spots.append([Vector3(p.x, hole.terrain.height_at(p.x, p.z), p.z), c[1]])
	return spots


## Spectators don't cast sun shadows: each person is a dozen meshes, and
## drawing them all again into every shadow split costs more than the rest
## of the hole. A soft contact shadow under each pair of feet grounds them.
const CONTACT_SHADOW := 0.9  ## metres across
const CONTACT_STRENGTH := 0.45


func _build_crowd(hole: HoleData, lines: Array[PackedVector3Array], count: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	var feet := PackedVector3Array()
	for spot: Array in crowd_spots(hole, lines, count, seed_value):
		var person := FreeGolfer.create(PlayerLook.random(rng.randi()))
		if person == null:
			break  # no golfer model or look pack: ropes only
		person.walk_in = false
		for node in person.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.name.begins_with("Driver") or mi.name.begins_with("Putter") or mi.name.begins_with("Iron"):
				mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var at: Vector3 = spot[0]
		var focus: Vector3 = spot[1]
		add_child(person)
		# The rig faces -x at address (the target is -x); turn them to face
		# the play, give or take a little.
		var yaw := atan2(focus.x - at.x, focus.z - at.z) + PI * 0.5 + rng.randf_range(-0.35, 0.35)
		person.global_position = at
		person.rotation.y = yaw
		feet.append(at)
		var player := person.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null and player.has_animation(&"idle"):
			player.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
			player.play(&"idle")
			player.seek(rng.randf() * player.current_animation_length, true)
			player.speed_scale = rng.randf_range(0.85, 1.1)
	if feet.is_empty():
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2(CONTACT_SHADOW, CONTACT_SHADOW)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ball_shadow.gdshader")
	mat.set_shader_parameter("strength", CONTACT_STRENGTH)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = feet.size()
	for i in feet.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, feet[i] + Vector3.UP * 0.02))
	var shadows := MultiMeshInstance3D.new()
	shadows.name = "ContactShadows"
	shadows.multimesh = mm
	shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadows)


func crowd_count() -> int:
	var n := 0
	for c in get_children():
		if c is FreeGolfer:
			n += 1
	return n
