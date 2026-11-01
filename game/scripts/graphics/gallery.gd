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
## PlayerLook) without clubs, standing upright, watching the golfer. They are
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
## With `stand`, a grandstand goes up behind the green too, if there is
## room for it.
## `quality` (GraphicsSettings.Quality) sets how many crowd cards stand
## further out.
static func build(hole: HoleData, toward: Vector3, crowd: int, seed_value: int, stand := false, quality := 3) -> Gallery:
	var g := Gallery.new()
	g.name = "Gallery"
	var lines := tee_lines(hole.terrain, hole.tee, toward)
	lines.append_array(green_lines(hole.terrain, hole.pin, hole.tee))
	g._build_ropes(hole.terrain, lines)
	var people: Array = []
	if crowd > 0:
		people = g._build_crowd(hole, lines, crowd, seed_value)
	var cards := CARDS_BY_QUALITY[clampi(quality, 0, CARDS_BY_QUALITY.size() - 1)]
	if cards > 0:
		g._build_cards(hole, lines, people, cards, seed_value)
	if stand:
		var at := grandstand_spot(hole)
		if not at.is_empty():
			g._build_grandstand(hole.terrain, at[0], at[1], seed_value)
	g._add_murmur(hole)
	return g


# --- Crowd murmur ----------------------------------------------------------

## The gallery talking among itself (amb_murmur, see tools/audio), from the
## crowds at the tee and round the green, fainter the further off. It hushes
## while the player stands over the ball, as a tour crowd does, and picks up
## again a few seconds after the shot.
const MURMUR_DB := -6.0
const MURMUR_HUSH_DB := -22.0
const MURMUR_UNIT := 9.0  ## metres at which it plays at MURMUR_DB
const MURMUR_BACK := 3.0  ## seconds after the strike


func _add_murmur(hole: HoleData) -> void:
	var stream := load("res://assets/sounds/amb_murmur.ogg") as AudioStreamOggVorbis
	if stream == null:
		return
	stream.loop = true
	var spots: Array[Vector3] = [hole.tee, hole.pin]
	for i in spots.size():
		var at := spots[i]
		var p := AudioStreamPlayer3D.new()
		p.name = "Murmur%d" % i
		p.stream = stream
		p.unit_size = MURMUR_UNIT
		p.volume_db = MURMUR_DB
		p.attenuation_filter_cutoff_hz = 4000.0
		p.position = at + Vector3.UP * 1.6
		p.autoplay = true
		add_child(p)


## Fades the murmur to `db` after `delay` seconds.
func _murmur_to(db: float, delay: float) -> void:
	for c in get_children():
		var p := c as AudioStreamPlayer3D
		if p == null or not p.name.begins_with("Murmur"):
			continue
		var t := p.create_tween()
		t.tween_interval(delay)
		t.tween_property(p, "volume_db", db, 1.5)


func murmur_db() -> float:
	for c in get_children():
		if c is AudioStreamPlayer3D:
			return (c as AudioStreamPlayer3D).volume_db
	return -80.0


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
				var back := rng.randf_range(CROWD_NEAR, CROWD_FAR)
				var p := a.lerp(b, rng.randf()) + out * back
				candidates.append([p, focus, p.distance_to(focus), back < CROUCH_ROW])
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
			spots.append([Vector3(p.x, hole.terrain.height_at(p.x, p.z), p.z), c[1], c[3]])
	return spots


## Spectators don't cast sun shadows: each person is a dozen meshes, and
## drawing them all again into every shadow split costs more than the rest
## of the hole. A soft contact shadow under each pair of feet grounds them.
const CONTACT_SHADOW := 0.9  ## metres across
const CONTACT_STRENGTH := 0.45


## Returns where the 3D people stand.
func _build_crowd(hole: HoleData, lines: Array[PackedVector3Array], count: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	var feet := PackedVector3Array()
	var spots := crowd_spots(hole, lines, count, seed_value)
	for spot: Array in spots:
		var look := PlayerLook.random(rng.randi())
		look.glove = false  # spectators don't wear a golf glove
		var person := FreeGolfer.create(look)
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
		# Turn them to face the play, give or take a little.
		person.global_position = at
		person.rotation.y = facing_yaw(at, focus) + rng.randf_range(-0.25, 0.25)
		person.set_meta(&"lean", rng.randf_range(-0.2, 0.2))
		feet.append(at)
		var player := person.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null:
			continue
		player.set_meta(&"stand", STAND_FRAMES[rng.randi() % STAND_FRAMES.size()])
		var skeletons := person.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			var skeleton := skeletons[0] as Skeleton3D
			var arms := CrowdArms.new(arm_pose(rng.randf()))
			skeleton.add_child(arms)
			player.set_meta(&"arms", arms)
		_stand(player)
	if feet.is_empty():
		return spots
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
	return spots


## The rig's yaw that turns a person at `at` to face `focus`. The body
## faces the rig's -z (at address the ball is in front, the target off to
## the left at -x).
static func facing_yaw(at: Vector3, focus: Vector3) -> float:
	return atan2(at.x - focus.x, at.z - focus.z)


## The crowd watches `node` (the golfer over the ball, then the ball in
## flight): heads follow it, and each spectator turns a little towards
## where it is, a moment apart from the others.
func watch(node: Node3D) -> void:
	if node == null or not is_inside_tree():
		return
	if node.name != "Focus":
		_murmur_to(MURMUR_DB, MURMUR_BACK)
	var at := node.global_position
	for c in get_children():
		var person := c as FreeGolfer
		if person == null:
			continue
		person.watch(node, randf_range(0.05, 0.5))
		var want := facing_yaw(person.global_position, at) + float(person.get_meta(&"lean", 0.0))
		var from := person.rotation.y
		var t := person.create_tween()
		t.tween_interval(randf_range(0.0, 0.6))
		t.tween_method(func(k: float) -> void: person.rotation.y = lerp_angle(from, want, k), 0.0, 1.0, randf_range(0.8, 1.4)).set_trans(Tween.TRANS_SINE)


## The crowd watches a spot (the golfer: about chest height over them).
func watch_point(at: Vector3) -> void:
	var mark := get_node_or_null("Focus") as Marker3D
	if mark == null:
		mark = Marker3D.new()
		mark.name = "Focus"
		add_child(mark)
	mark.global_position = at
	watch(mark)
	_murmur_to(MURMUR_HUSH_DB, 0.8)


# --- Crowd cards -------------------------------------------------------------

## Past the 3D people the gallery goes on as crowd cards
## (shaders/crowd_card.gdshader): flat camera-facing figures, two or three
## deep behind the ropes, hundreds in one draw call. From Low to Ultra.
const CARDS_BY_QUALITY: Array[int] = [80, 160, 260, 360]
const CARD_WIDTH := 0.62  ## metres, for a 1.8 m person
const CARD_SPACING := 0.7
const CARD_NEAR := 1.2
const CARD_FAR := 5.0
## Fallback for rigs with no idle clip: seconds into the walk where the
## feet pass under the body, an upright pose, the left or the right foot a little forward.
const STAND_FRAMES: Array[float] = [1.0, 0.35]
## How often each arm pose turns up in a gallery, from photos of tour
## galleries: arms folded most, then hanging, behind the back, in pockets.
const ARM_SHARES := {CrowdArms.Pose.FOLDED: 0.35, CrowdArms.Pose.HANGING: 0.25, CrowdArms.Pose.BEHIND: 0.22, CrowdArms.Pose.POCKETS: 0.18}
const CROUCH_ROW := 1.6  ## metres behind the rope that counts as the front row


static func card_spots(hole: HoleData, lines: Array[PackedVector3Array], people: Array, count: int, seed_value: int) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5
	var out := PackedVector3Array()
	var taken: Array[Vector3] = []
	for spot: Array in people:
		taken.append(spot[0])
	var total := 0.0
	for line in lines:
		for k in line.size() - 1:
			total += line[k].distance_to(line[k + 1])
	if total <= 0.0:
		return out
	var tries := count * 4
	while out.size() < count and tries > 0:
		tries -= 1
		# A random point along all the ropes, then back from it.
		var at := rng.randf() * total
		var a := Vector3.INF
		var b := Vector3.INF
		for l in lines:
			for j in l.size() - 1:
				var span := l[j].distance_to(l[j + 1])
				if at <= span and a == Vector3.INF:
					a = l[j]
					b = l[j + 1]
				elif a == Vector3.INF:
					at -= span
		if a == Vector3.INF:
			continue
		var span_v := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if span_v.length() < 0.1:
			continue
		var focus := hole.pin if a.distance_to(hole.pin) < GREEN_SEARCH + GREEN_MARGIN + 5.0 else hole.tee
		var outward := Vector3.UP.cross(span_v.normalized())
		var mid := (a + b) * 0.5
		if outward.dot(Vector3(mid.x - focus.x, 0.0, mid.z - focus.z)) < 0.0:
			outward = -outward
		var p := a.lerp(b, at / maxf(a.distance_to(b), 1e-3)) + outward * rng.randf_range(CARD_NEAR, CARD_FAR)
		var s := hole.terrain.surface_at(p.x, p.z)
		if s == Surface.Type.WATER or s == Surface.Type.SAND or s == Surface.Type.GREEN:
			continue
		var free := true
		for q in taken:
			if Vector2(q.x - p.x, q.z - p.z).length() < CARD_SPACING:
				free = false
				break
		if not free:
			continue
		p.y = hole.terrain.height_at(p.x, p.z)
		taken.append(p)
		out.append(p)
	return out


func _build_cards(hole: HoleData, lines: Array[PackedVector3Array], people: Array, count: int, seed_value: int) -> void:
	var spots := card_spots(hole, lines, people, count, seed_value)
	if spots.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 9
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_WIDTH / 1.8, 1.0)  # scaled by each person's height
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crowd_card.gdshader")
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = spots.size()
	var trousers := [0, 2, 3, 4, 5, 6, 1]
	for i in spots.size():
		var h := clampf(rng.randfn(1.72, 0.09), 1.5, 1.98)
		var w := rng.randf_range(0.9, 1.2)  # build: slim to broad
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(h * w, h, h)), spots[i]))
		mm.set_instance_color(i, PlayerLook.CLOTH_COLOURS[rng.randi_range(0, PlayerLook.CLOTH_COLOURS.size() - 1)][1])
		var legs: Color = PlayerLook.CLOTH_COLOURS[trousers[rng.randi_range(0, trousers.size() - 1)]][1]
		mm.set_instance_custom_data(i, Color(legs.r, legs.g, legs.b, rng.randf()))
	var node := MultiMeshInstance3D.new()
	node.name = "CrowdCards"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func card_count() -> int:
	var node := get_node_or_null("CrowdCards") as MultiMeshInstance3D
	return node.multimesh.instance_count if node != null else 0


# --- Crowd reactions ------------------------------------------------------

## Spectators react to a shot the way the crowd sounds (Commentary.Crowd):
## a roar has everyone celebrating, a cheer most of them, polite applause
## a few, a groan or an "ooh" some of them in dismay. Each reacts a moment
## apart, then settles back to standing.
func react(crowd: int) -> void:
	var clip := &"celebrate"
	var share := 0.0
	match crowd:
		Commentary.Crowd.ROAR:
			share = 1.0
		Commentary.Crowd.CHEER:
			share = 0.6
		Commentary.Crowd.POLITE:
			share = 0.25
		Commentary.Crowd.GROAN, Commentary.Crowd.OOH:
			clip = &"upset"
			share = 0.45
	if share <= 0.0 or not is_inside_tree():
		return
	for c in get_children():
		if not c is FreeGolfer or randf() > share:
			continue
		var player := c.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null or not player.has_animation(clip):
			continue
		get_tree().create_timer(randf_range(0.1, 0.9)).timeout.connect(_react_one.bind(player, clip))


static func _react_one(player: AnimationPlayer, clip: StringName) -> void:
	if not is_instance_valid(player):
		return
	if player.has_meta(&"arms"):
		(player.get_meta(&"arms") as CrowdArms).set_on(false)  # the clip has its own
	player.speed_scale = 1.0
	player.play(clip, 0.25)
	if not player.animation_finished.is_connected(_on_reacted):
		player.animation_finished.connect(_on_reacted.bind(player))


static func _on_reacted(_clip: StringName, player: AnimationPlayer) -> void:
	_stand(player)


## Stands a spectator upright: the rig's standing idle (weight shifts and
## breathing), or, for a rig without one, a still frame of the walk where
## the feet pass.
## The arm pose for a draw `u` in [0, 1), by ARM_SHARES.
static func arm_pose(u: float) -> CrowdArms.Pose:
	var total := 0.0
	for p: CrowdArms.Pose in ARM_SHARES:
		total += ARM_SHARES[p]
		if u < total:
			return p
	return CrowdArms.Pose.HANGING


static func _stand(player: AnimationPlayer) -> void:
	if player.has_meta(&"arms"):
		(player.get_meta(&"arms") as CrowdArms).set_on(true)
	# The rig's own standing clip (upright, weight shifts, breathing), each
	# spectator at their own point in it and pace, so the crowd doesn't
	# sway in step.
	if player.has_animation(&"idle"):
		player.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
		player.play(&"idle", 0.3)
		player.seek(randf() * player.current_animation_length, true)
		player.speed_scale = randf_range(0.85, 1.15)
		return
	if not player.has_animation(&"walk"):
		return
	# Held still with a zero speed rather than paused, so the pose still
	# applies when the crowd is built before it joins the scene.
	player.play(&"walk", 0.0)
	player.seek(float(player.get_meta(&"stand", STAND_FRAMES[0])), true)
	player.speed_scale = 0.0


# --- Grandstand ------------------------------------------------------------

## A temporary tournament grandstand, the kind built behind the 18th green
## and round par 3s: aluminium bleacher rows on a scaffold, a dark green
## skirt round the sides and front, and a rail along the back. Real scale
## from tour photos and bleacher specs: rows 0.85 m deep rising 0.42 m, the
## first row 1.0 m up behind the front hoarding, 24 m wide.
const STAND_ROWS := 8
const STAND_TREAD := 0.85
const STAND_RISE := 0.42
const STAND_FIRST := 1.0
const STAND_WIDTH := 24.0
const STAND_RAIL := 1.05
## How far behind the green rope the front of the stand stands.
const STAND_BACK := 6.0
const STAND_SEAT := 0.55  ## seat width per spectator
const STAND_FULL := 0.8  ## share of seats taken
const STEP_COLOUR := Color(0.78, 0.79, 0.8)
const SKIRT_COLOUR := Color(0.13, 0.3, 0.19)


static func stand_depth() -> float:
	return STAND_ROWS * STAND_TREAD


## Where a grandstand fits behind the green: [front centre, facing
## direction (toward the pin)], or empty if water, sand, a green or a tree
## is in the way whichever way it is tried.
static func grandstand_spot(hole: HoleData) -> Array:
	var t := hole.terrain
	var back := Vector3(hole.pin.x - hole.tee.x, 0.0, hole.pin.z - hole.tee.z)
	back = Vector3(0, 0, 1) if back.length() < 0.01 else back.normalized()
	for turn_deg: float in [0.0, 25.0, -25.0, 50.0, -50.0]:
		var d := back.rotated(Vector3.UP, deg_to_rad(turn_deg))
		var front := hole.pin + d * (_green_edge(t, hole.pin, d) + GREEN_MARGIN + STAND_BACK)
		if _stand_clear(hole, front, -d):
			return [Vector3(front.x, t.height_at(front.x, front.z), front.z), -d]
	return []


static func _stand_clear(hole: HoleData, front: Vector3, facing: Vector3) -> bool:
	var side := Vector3.UP.cross(facing)
	var depth := stand_depth() + 1.0
	for i in 5:
		for j in 3:
			var p := front + side * ((i / 4.0 - 0.5) * STAND_WIDTH) - facing * (j / 2.0 * depth)
			var s := hole.terrain.surface_at(p.x, p.z)
			if s == Surface.Type.WATER or s == Surface.Type.SAND or s == Surface.Type.GREEN:
				return false
	var centre := front - facing * (depth * 0.5)
	var reach := Vector2(STAND_WIDTH * 0.5, depth * 0.5).length() + 3.0
	for o in hole.objects:
		if Vector2(o.position.x - centre.x, o.position.z - centre.z).length() < reach:
			return false
	return true


func _build_grandstand(terrain: CourseTerrain, front: Vector3, facing: Vector3, seed_value: int) -> void:
	var side := Vector3.UP.cross(facing)
	var depth := stand_depth()
	# Level on the highest ground under it, so no corner sinks into a slope.
	var base := front.y
	var low := front.y
	for i in 3:
		for j in 3:
			var p := front + side * ((i / 2.0 - 0.5) * STAND_WIDTH) - facing * (j / 2.0 * depth)
			var h := terrain.height_at(p.x, p.z)
			base = maxf(base, h)
			low = minf(low, h)
	var stand := Node3D.new()
	stand.name = "Grandstand"
	add_child(stand)
	stand.transform = Transform3D(Basis(side, Vector3.UP, -facing), Vector3(front.x, base, front.z))
	# In the stand's frame: x across, y up, +z back (away from the green).
	var w := STAND_WIDTH * 0.5
	var floor_y := low - base - 0.3
	var top := STAND_FIRST + (STAND_ROWS - 1) * STAND_RISE
	var steps := SurfaceTool.new()
	steps.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in STAND_ROWS:
		var y := STAND_FIRST + r * STAND_RISE
		var z0 := r * STAND_TREAD
		# The tread and, below it, the riser down to the row in front.
		_quad(steps, Vector3(-w, y, z0), Vector3(w, y, z0), Vector3(w, y, z0 + STAND_TREAD), Vector3(-w, y, z0 + STAND_TREAD))
		_quad(steps, Vector3(-w, y - STAND_RISE, z0), Vector3(w, y - STAND_RISE, z0), Vector3(w, y, z0), Vector3(-w, y, z0))
	steps.generate_normals()
	stand.add_child(_mesh(steps, STEP_COLOUR, 0.45))
	var skirt := SurfaceTool.new()
	skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The front hoarding, the back wall and the rail.
	_quad(skirt, Vector3(-w, floor_y, -0.02), Vector3(w, floor_y, -0.02), Vector3(w, STAND_FIRST + 0.1, -0.02), Vector3(-w, STAND_FIRST + 0.1, -0.02))
	_quad(skirt, Vector3(w, floor_y, depth), Vector3(-w, floor_y, depth), Vector3(-w, top + STAND_RAIL, depth), Vector3(w, top + STAND_RAIL, depth))
	# The two sides, stepped with the rows.
	for sx: float in [-w, w]:
		for r in STAND_ROWS:
			var y := STAND_FIRST + r * STAND_RISE
			var z0 := r * STAND_TREAD
			var a := Vector3(sx, floor_y, z0)
			var b := Vector3(sx, floor_y, z0 + STAND_TREAD)
			var c := Vector3(sx, y + 0.12, z0 + STAND_TREAD)
			var d := Vector3(sx, y + 0.12, z0)
			if sx < 0.0:
				_quad(skirt, b, a, d, c)
			else:
				_quad(skirt, a, b, c, d)
	skirt.generate_normals()
	stand.add_child(_mesh(skirt, SKIRT_COLOUR, 0.8))
	_seat_crowd(stand, seed_value)


func _seat_crowd(stand: Node3D, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3
	var seats: Array[Vector3] = []
	var per_row := int(STAND_WIDTH / STAND_SEAT) - 1
	for r in STAND_ROWS:
		for k in per_row:
			if rng.randf() < STAND_FULL:
				var x := (k + 0.5 - per_row * 0.5) * STAND_SEAT + rng.randf_range(-0.06, 0.06)
				seats.append(Vector3(x, STAND_FIRST + r * STAND_RISE, r * STAND_TREAD + 0.35))
	if seats.is_empty():
		return
	# Seated people, seen from the green: a torso in the shirt's colour and
	# a head, as one instanced mesh each. At grandstand distance from the
	# cameras that reads as a crowd without paying for full people.
	var torso := CapsuleMesh.new()
	torso.radius = 0.2
	torso.height = 0.62
	torso.radial_segments = 8
	torso.rings = 2
	var head := SphereMesh.new()
	head.radius = 0.11
	head.height = 0.24
	head.radial_segments = 8
	head.rings = 4
	var torsos := _instances(torso, seats.size())
	var heads := _instances(head, seats.size())
	for i in seats.size():
		var at := seats[i]
		var lean := Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.05)).scaled(Vector3(1.0, 1.0, 0.7))
		torsos.set_instance_transform(i, Transform3D(lean, at + Vector3(0, 0.33, 0)))
		torsos.set_instance_color(i, PlayerLook.CLOTH_COLOURS[rng.randi_range(0, PlayerLook.CLOTH_COLOURS.size() - 1)][1])
		heads.set_instance_transform(i, Transform3D(Basis.IDENTITY, at + Vector3(rng.randf_range(-0.02, 0.02), 0.78, -0.02)))
		var cap := rng.randf() < 0.4
		var skin: Color = PlayerLook.SKIN_TONES[rng.randi_range(0, PlayerLook.SKIN_TONES.size() - 1)][1]
		heads.set_instance_color(i, PlayerLook.CLOTH_COLOURS[rng.randi_range(0, PlayerLook.CLOTH_COLOURS.size() - 1)][1] if cap else skin)
	for mm in [torsos, heads]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stand.add_child(mi)


static func _instances(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	return mm


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, c, b, a, d, c]:
		st.add_vertex(v)


static func _mesh(st: SurfaceTool, colour: Color, roughness: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


func seated_count() -> int:
	var stand := get_node_or_null("Grandstand")
	if stand == null:
		return 0
	for c in stand.get_children():
		if c is MultiMeshInstance3D:
			return (c as MultiMeshInstance3D).multimesh.instance_count
	return 0


func crowd_count() -> int:
	var n := 0
	for c in get_children():
		if c is FreeGolfer:
			n += 1
	return n
