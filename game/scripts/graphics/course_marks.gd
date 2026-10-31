class_name CourseMarks
extends Node3D
## The marks a round leaves on the course, as on TV: iron divots ahead of
## where the ball sat, pitch marks where approach shots hit the green, and
## craters where balls land in sand (with a scoop where they're splashed
## out), and footprints where golfers walk into bunkers. They stay for the hole and go with it. Looks only: they don't
## touch the ball or the game's physics.
##
## Each mark is one small lit quad (shaders/course_mark.gdshader), so even a
## busy hole adds only a few dozen tiny draw calls.

enum Kind { DIVOT, PITCH_MARK, SAND_CRATER, FOOTPRINT }

const MAX_MARKS := 48  ## the oldest go first on a very long hole
const LIFT := 0.012  ## metres above the ground, so the quad never sinks into it
## A ball has to come in at least this fast (m/s) to dent a green; putts
## and soft chips rolling on don't mark it.
const PITCH_MARK_SPEED := 10.0
const SAND_CRATER_SPEED := 4.0

static var _materials: Array[ShaderMaterial] = []
static var _quad: QuadMesh

var _rng := RandomNumberGenerator.new()


## A divot's size in metres (x along the swing, y across), or zero for no
## divot. Irons and wedges are struck descending, ball first, and take turf;
## woods and hybrids sweep the ball. Off a tee peg an iron only nicks the
## ground. Shorter clubs are swung more steeply and take longer divots.
static func divot_size(club: Club, lie: int, chip := false) -> Vector2:
	if club == null or club.is_putter:
		return Vector2.ZERO
	var s := club.short_name
	if s.ends_with("W") and s.length() == 2 and s[0].is_valid_int():
		return Vector2.ZERO  # fairway woods
	if s == "Dr" or s.ends_with("H"):
		return Vector2.ZERO
	match lie:
		Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.DEEP_ROUGH, Surface.Type.FRINGE:
			pass
		Surface.Type.TEE:
			if chip:
				return Vector2.ZERO
		Surface.Type.SAND:
			# Splashed out of a bunker: a long, wide scoop of sand.
			return Vector2(0.32, 0.16)
		_:
			return Vector2.ZERO
	# Loft runs from about 11 degrees (4 iron) to 34 (lob wedge).
	var steep := clampf((club.launch_deg - 11.0) / 23.0, 0.0, 1.0)
	var size := Vector2(lerpf(0.10, 0.17, steep), lerpf(0.05, 0.075, steep))
	if lie == Surface.Type.TEE:
		size *= 0.5
	if chip:
		size *= 0.45
	return size


## Where a divot's centre goes: just ahead of the ball along the swing,
## since a good iron strike hits the ball first and the ground after.
static func divot_centre(ball: Vector3, aim_dir: Vector3, size: Vector2) -> Vector3:
	return ball + aim_dir.normalized() * (0.03 + size.x * 0.5)


## The mark a landing leaves, as [Kind, diameter in metres], or [] for none.
static func landing_mark(surface: int, speed: float) -> Array:
	if surface == Surface.Type.GREEN and speed >= PITCH_MARK_SPEED:
		# A soft wedge leaves a coin-sized dent, a long iron a bigger one.
		return [Kind.PITCH_MARK, clampf(0.03 + (speed - PITCH_MARK_SPEED) * 0.0012, 0.03, 0.05)]
	if surface == Surface.Type.SAND and speed >= SAND_CRATER_SPEED:
		return [Kind.SAND_CRATER, clampf(0.07 + speed * 0.002, 0.07, 0.13)]
	return []


func _init() -> void:
	name = "CourseMarks"
	_rng.randomize()


## Adds the divot (if any) for a shot struck from `ball` along `aim_dir`.
func add_divot(terrain: CourseTerrain, ball: Vector3, aim_dir: Vector3, club: Club, lie: int, chip := false) -> void:
	var size := divot_size(club, lie, chip)
	if size == Vector2.ZERO:
		return
	var at := divot_centre(ball, aim_dir, size)
	var kind := Kind.SAND_CRATER if lie == Surface.Type.SAND else Kind.DIVOT
	# Divots never come out quite straight.
	var dir := aim_dir.normalized().rotated(Vector3.UP, deg_to_rad(_rng.randf_range(-6.0, 6.0)))
	_add(terrain, kind, at, dir, size)


## Adds the mark (if any) a ball landing at `at` with `speed` leaves.
## `travel` is the ball's direction over the ground as it came in.
func add_landing(terrain: CourseTerrain, at: Vector3, travel: Vector3, speed: float) -> void:
	var mark := landing_mark(terrain.surface_at(at.x, at.z), speed)
	if mark.is_empty():
		return
	var d: float = mark[1]
	_add(terrain, mark[0], at, travel, Vector2(d, d) if mark[0] != Kind.SAND_CRATER else Vector2(d * 1.3, d))


## Footprints for a golfer in a bunker: the two feet of the stance beside
## the ball, and the walk in from behind it, stride by stride, up to where
## the sand ends. `left` is the golfer's side of the ball.
func add_footprints(terrain: CourseTerrain, ball: Vector3, aim_dir: Vector3, left: Vector3, stance := STANCE_WOOD) -> void:
	for spot in footprint_spots(terrain, ball, aim_dir, left, stance):
		var turn := deg_to_rad(_rng.randf_range(-12.0, 12.0))
		_add(terrain, Kind.FOOTPRINT, spot[0], (spot[1] as Vector3).rotated(Vector3.UP, turn), FOOT_SIZE)


const FOOT_SIZE := Vector2(0.30, 0.11)  ## a shoe, heel to toe and across
const STRIDE := 0.38  ## metres between one print and the next
const MAX_STEPS := 18
## How far the golfer's feet stand from the ball, across the line, matching
## the golfer thread's address poses: long clubs stand further off.
const STANCE_WOOD := 0.72
const STANCE_IRON := 0.57
const STANCE_PUTT := 0.45


## The stance distance for `club`: the driver, woods and hybrids stand
## further from the ball than the irons and wedges.
static func stance_for(club: Club) -> float:
	match SoundBank.club_kind(club):
		&"putter":
			return STANCE_PUTT
		&"driver", &"wood":
			return STANCE_WOOD
	return STANCE_IRON


## Where the prints go, as [position, direction the toe points], all on sand.
static func footprint_spots(terrain: CourseTerrain, ball: Vector3, aim_dir: Vector3, left: Vector3, stance_m := STANCE_WOOD) -> Array:
	var spots: Array = []
	var aim := Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
	var side := Vector3(left.x, 0.0, left.z).normalized()
	var stance := ball + side * stance_m
	# Standing square to the line, feet shoulder-width apart, toes to the ball.
	for f: float in [-0.25, 0.25]:
		var at := stance + aim * f
		if terrain.surface_at(at.x, at.z) == Surface.Type.SAND:
			spots.append([at, -side])
	# The walk in, from behind the ball, alternating feet.
	for i in range(1, MAX_STEPS + 1):
		var at := stance - aim * (0.25 + i * STRIDE) + side * (0.25 + (0.09 if i % 2 == 0 else -0.09))
		if terrain.surface_at(at.x, at.z) != Surface.Type.SAND:
			break
		spots.append([at, aim])
	return spots


func mark_count() -> int:
	return get_child_count()


func _add(terrain: CourseTerrain, kind: int, at: Vector3, along: Vector3, size: Vector2) -> void:
	while get_child_count() >= MAX_MARKS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.free()
	var up := terrain.normal_at(at.x, at.z)
	var fwd := Vector3(along.x, 0.0, along.z)
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var side := fwd.cross(up).normalized()  # right-handed: side x fwd = up
	var m := MeshInstance3D.new()
	m.mesh = _quad_mesh()
	m.material_override = _material(kind)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad's local x runs across the mark and its y along it; it is laid
	# flat on the ground (local z is the ground's up).
	m.transform = Transform3D(Basis(side * size.y, fwd * size.x, up), \
		Vector3(at.x, terrain.height_at(at.x, at.z) + LIFT, at.z))
	add_child(m)


static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


static func _material(kind: int) -> ShaderMaterial:
	if _materials.is_empty():
		var shader: Shader = load("res://shaders/course_mark.gdshader")
		for k in Kind.size():
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("kind", k)
			_materials.append(mat)
	return _materials[kind]
