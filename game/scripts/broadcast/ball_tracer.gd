class_name BallTracer
extends MeshInstance3D
## The TV shot tracer: a glowing ribbon along the ball's path that always
## faces the camera, widening with distance so it reads from anywhere, and
## fading towards the tail. Plain unshaded vertex colours, so it draws the
## same on Forward+ and Compatibility.

const COLOR := Color(1.0, 0.32, 0.18)
const CORE := Color(1.0, 0.85, 0.55)
## Width grows with distance from the camera, so the line keeps the same
## few pixels on screen near and far, as TV tracers do (about a 3 px core in
## a 7 px glow at 720p). The floor only stops it vanishing right at the lens;
## a wide floor drew a thick bar up the middle of the chase cam.
const MIN_WIDTH := 0.004
const WIDTH_PER_METRE := 0.0025  ## of distance from the camera
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
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
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
func draw(points: PackedVector3Array, upto: int, head: Vector3, eye: Vector3) -> void:
	_mesh.clear_surfaces()
	if upto < 1 or points.size() < 2:
		return
	var path := PackedVector3Array()
	var step := maxi(1, ceili(float(upto + 1) / MAX_POINTS))
	for i in range(0, upto + 1, step):
		path.append(points[i] + Vector3.UP * 0.05)
	path.append(head + Vector3.UP * 0.05)
	var n := path.size()
	if n < 2:
		return
	# Two passes: a wide soft glow and a thin bright core.
	for pass_i in 2:
		var scale := (1.8 if pass_i == 0 else 0.8) * width_scale
		var tint := color if pass_i == 0 else core
		var strength := 0.45 if pass_i == 0 else 0.9
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in n:
			var p := path[i]
			var tangent := path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]
			var to_eye := eye - p
			var side := tangent.cross(to_eye)
			if side.length_squared() < 1e-8:
				side = Vector3.RIGHT
			var w := maxf(MIN_WIDTH, to_eye.length() * WIDTH_PER_METRE) * scale
			side = side.normalized() * w
			var fade := float(i) / float(n - 1)
			var c := tint * (strength * (0.15 + 0.85 * fade))
			c.a = 1.0
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(p - side)
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(p + side)
		_mesh.surface_end()
