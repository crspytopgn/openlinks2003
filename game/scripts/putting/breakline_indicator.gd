class_name BreaklineIndicator
extends MeshInstance3D
## Links 2003's Breakline Indicator: a yellow line standing at the foot of
## the aiming marker, leaning the way the green falls there, taller the
## steeper the slope, with a short arrow on the ground pointing downhill.
## Optional (Settings > Breakline indicator), at every skill level, as in
## the game. Sizes are ours.

const COLOR := Color(1.0, 0.86, 0.1, 0.95)
const MIN_HEIGHT := 0.08
const HEIGHT_PER_PERCENT := 0.09  ## metres of line per percent of slope
const MAX_HEIGHT := 0.9
const WIDTH := 0.025
const ARROW := 0.45
const LIFT := 0.02

var _mesh := ImmediateMesh.new()


func _init() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	visible = false


## The line's height for a slope of `percent`.
static func height_for(percent: float) -> float:
	return clampf(MIN_HEIGHT + percent * HEIGHT_PER_PERCENT, MIN_HEIGHT, MAX_HEIGHT)


## Shows the indicator on the ground at `at` (x, z; y is taken from the
## terrain).
func show_at(terrain: CourseTerrain, at: Vector3) -> void:
	_mesh.clear_surfaces()
	var f := GreenRead.fall(terrain, at.x, at.z)
	var pct := f.length() * 100.0
	var base := Vector3(at.x, terrain.height_at(at.x, at.z) + LIFT, at.z)
	var down := Vector3(f.x, 0.0, f.y).normalized() if pct >= GreenRead.FLAT_PERCENT else Vector3.ZERO
	var h := height_for(pct)
	var top := base + Vector3.UP * h + down * h * 0.35
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# The standing line, as two crossed strips so it reads from any side.
	var across := Vector3(down.z, 0.0, -down.x) if down != Vector3.ZERO else Vector3.RIGHT
	for side: Vector3 in [across * WIDTH, down * WIDTH if down != Vector3.ZERO else Vector3.BACK * WIDTH]:
		_quad(base - side, base + side, top + side, top - side)
	if down != Vector3.ZERO:
		# The arrow on the ground, pointing downhill.
		var tip := Vector3(base.x, 0.0, base.z) + down * ARROW
		tip.y = terrain.height_at(tip.x, tip.z) + LIFT
		var neck := base.lerp(tip, 0.65)
		var w := across * WIDTH
		_quad(base - w, neck - w, neck + w, base + w)
		_tri(neck - across * WIDTH * 3.5, tip, neck + across * WIDTH * 3.5)
	_mesh.surface_end()
	visible = true


func clear() -> void:
	_mesh.clear_surfaces()
	visible = false


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(a, b, c)
	_tri(a, c, d)


func _tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	for v: Vector3 in [a, b, c]:
		_mesh.surface_set_color(COLOR)
		_mesh.surface_add_vertex(v)
