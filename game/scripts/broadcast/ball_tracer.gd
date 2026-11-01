class_name BallTracer
extends MeshInstance3D
## The TV shot tracer: a glowing ribbon along the ball's path that always
## faces the camera, widening with distance so it reads from anywhere, and
## fading towards the tail. A soft halo that falls off to nothing at its
## edges, a hot core and a flare at the ball, as TV and PGA Tour 2K25
## tracers draw it. Plain unshaded vertex colours blended over the picture
## (added light washes out to white against a bright sky), so it draws the
## same on Forward+ and Compatibility; the core goes a little past full so
## the Forward+ glow blooms it.

const COLOR := Color(1.0, 0.32, 0.18)
const CORE := Color(1.0, 0.85, 0.55)
## Width grows with distance from the camera, so the line keeps the same
## few pixels on screen near and far, as TV tracers do (about a 4 px core in
## a 14 px halo at 720p). The floor only stops it vanishing right at the
## lens; a wide floor drew a thick bar up the middle of the chase cam.
const MIN_WIDTH := 0.004
const WIDTH_PER_METRE := 0.003  ## half-width of the core, per metre from the camera
const HALO := 3.0  ## the halo's half-width, in core half-widths
const HEAD_FLARE := 3.0  ## the flare's radius at the ball, in core half-widths
const MIN_STEP_M := 0.05  ## closer samples are dropped (they flip the ribbon)
const MAX_POINTS := 400  ## older samples are skipped evenly beyond this

## The ribbon's colours and width; set_style changes them (the Tour
## presentation draws a taller teal tracer).
var color := COLOR
var core := CORE
var width_scale := 1.0
var _mesh := ImmediateMesh.new()


func _init() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	material_override = mat


func set_style(tour: bool) -> void:
	color = Color(0.15, 0.85, 0.8) if tour else COLOR
	core = Color(0.75, 1.0, 0.95) if tour else CORE
	width_scale = 1.6 if tour else 1.0


func clear() -> void:
	_mesh.clear_surfaces()


## Draws the path through `points[0..upto]` and on to `head`, as seen from
## `eye`.
## `forward` is the camera's view direction: the ribbon is widened across
## it, so it stays flat to the screen even where the ball flies at the lens.
func draw(points: PackedVector3Array, upto: int, head: Vector3, eye: Vector3, forward := Vector3.ZERO) -> void:
	_mesh.clear_surfaces()
	if upto < 1 or points.size() < 2:
		return
	var path := PackedVector3Array()
	var step := maxi(1, ceili(float(upto + 1) / MAX_POINTS))
	for i in range(0, mini(upto, points.size() - 1) + 1, step):
		_add_point(path, points[i] + Vector3.UP * 0.05)
	_add_point(path, head + Vector3.UP * 0.05)
	var n := path.size()
	if n < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# The halo, then the core over it: each a strip three vertices wide,
	# bright along the middle and black (nothing, when added) at the edges.
	_ribbon(path, eye, forward, HALO * width_scale, Color(color, 0.42))
	_ribbon(path, eye, forward, width_scale, Color(core * 1.25, 1.0))
	_flare(head + Vector3.UP * 0.05, eye)
	_mesh.surface_end()


static func _add_point(path: PackedVector3Array, p: Vector3) -> void:
	if path.is_empty() or path[path.size() - 1].distance_to(p) >= MIN_STEP_M:
		path.append(p)


## The core's half-width at `p` seen from `eye`.
static func half_width(p: Vector3, eye: Vector3) -> float:
	return maxf(MIN_WIDTH, p.distance_to(eye) * WIDTH_PER_METRE)


func _ribbon(path: PackedVector3Array, eye: Vector3, forward: Vector3, scale: float, tint: Color) -> void:
	var n := path.size()
	var prev_side := Vector3.ZERO
	var prev_mid := Vector3.ZERO
	var prev_c := Color.TRANSPARENT
	for i in n:
		var p := path[i]
		var tangent := path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]
		var view := forward if forward != Vector3.ZERO else p - eye
		var side := tangent.cross(view)
		if side.length_squared() < 1e-6 * tangent.length_squared() * view.length_squared():
			side = prev_side if prev_side != Vector3.ZERO else Vector3.RIGHT
		side = side.normalized() * half_width(p, eye) * scale
		# Keep the ribbon from twisting where the path turns past the eye.
		if prev_side != Vector3.ZERO and side.dot(prev_side) < 0.0:
			side = -side
		var fade := float(i) / float(n - 1)
		var c := Color(tint, tint.a * (0.15 + 0.85 * fade * fade))
		var edge := Color(tint, 0.0)
		if i > 0:
			var prev_edge := Color(prev_c, 0.0)
			_quad(prev_mid - prev_side, prev_mid, p - side, p, prev_edge, prev_c, edge, c)
			_quad(prev_mid, prev_mid + prev_side, p, p + side, prev_c, prev_edge, c, edge)
		prev_side = side
		prev_mid = p
		prev_c = c


## A round glow at the ball, facing the camera.
func _flare(at: Vector3, eye: Vector3) -> void:
	var to_eye := (eye - at).normalized()
	var right := to_eye.cross(Vector3.UP)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(to_eye).normalized()
	var r := half_width(at, eye) * HEAD_FLARE * width_scale
	var centre := Color(core * 1.4, 0.95)
	var rim := Color(core, 0.0)
	var segments := 16
	for k in segments:
		var a0 := TAU * k / segments
		var a1 := TAU * (k + 1) / segments
		_mesh.surface_set_color(centre)
		_mesh.surface_add_vertex(at)
		_mesh.surface_set_color(rim)
		_mesh.surface_add_vertex(at + (right * cos(a0) + up * sin(a0)) * r)
		_mesh.surface_set_color(rim)
		_mesh.surface_add_vertex(at + (right * cos(a1) + up * sin(a1)) * r)


## Two triangles: a0-a1 along the near end, b0-b1 along the far end.
func _quad(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, ca0: Color, ca1: Color, cb0: Color, cb1: Color) -> void:
	for v: Array in [[a0, ca0], [a1, ca1], [b1, cb1], [a0, ca0], [b1, cb1], [b0, cb0]]:
		_mesh.surface_set_color(v[1])
		_mesh.surface_add_vertex(v[0])
