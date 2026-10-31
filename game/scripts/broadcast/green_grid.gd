class_name GreenGrid
extends MeshInstance3D
## The TV green-reading grid: lines a metre apart draped over the real
## terrain round the ball and the hole, coloured by how steep the ground is,
## with a short tick in each square pointing downhill. It reads the slopes
## the physics uses (CourseTerrain.normal_at); it doesn't predict the putt,
## so reading the break is still up to the player.

const SPACING := 1.0
const MARGIN := 4.0  ## metres past the ball and the hole
const MAX_HALF := 18.0
const LIFT := 0.03
const FLAT := Color(0.55, 0.8, 1.0, 0.55)
const MEDIUM := Color(1.0, 0.9, 0.3, 0.7)
const STEEP := Color(1.0, 0.3, 0.2, 0.85)
const STEEP_PERCENT := 4.0

var _mesh := ImmediateMesh.new()


func _init() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = mat
	visible = false


## Slope in percent (rise over run) where the ground has normal `n`.
static func slope_percent(n: Vector3) -> float:
	return 100.0 * Vector2(n.x, n.z).length() / maxf(n.y, 0.01)


static func slope_color(percent: float) -> Color:
	var f := clampf(percent / STEEP_PERCENT, 0.0, 1.0)
	return FLAT.lerp(MEDIUM, f * 2.0) if f < 0.5 else MEDIUM.lerp(STEEP, f * 2.0 - 1.0)


## Rebuilds the grid over the square that holds `ball` and `pin`.
func build(terrain: CourseTerrain, ball: Vector3, pin: Vector3) -> void:
	_mesh.clear_surfaces()
	var centre := (ball + pin) * 0.5
	var half := clampf(Vector2(ball.x - pin.x, ball.z - pin.z).length() * 0.5 + MARGIN, 6.0, MAX_HALF)
	var x0 := snappedf(centre.x - half, SPACING)
	var z0 := snappedf(centre.z - half, SPACING)
	var cells := int(ceil(half * 2.0 / SPACING))
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for a in cells + 1:
		for b in cells:
			# Line a runs along z at x = x0 + a, and along x at z = z0 + a.
			var along_z := Vector2(x0 + a * SPACING, z0 + b * SPACING)
			_segment(terrain, along_z, along_z + Vector2(0.0, SPACING))
			var along_x := Vector2(x0 + b * SPACING, z0 + a * SPACING)
			_segment(terrain, along_x, along_x + Vector2(SPACING, 0.0))
	for a in cells:
		for b in cells:
			var c := Vector2(x0 + (a + 0.5) * SPACING, z0 + (b + 0.5) * SPACING)
			var n := terrain.normal_at(c.x, c.y)
			var pct := slope_percent(n)
			if pct < 0.3:
				continue
			var down := Vector2(n.x, n.z).normalized() * SPACING * clampf(0.15 + pct * 0.08, 0.15, 0.45)
			var col := slope_color(pct)
			_vertex(terrain, c - down * 0.5, col)
			_vertex(terrain, c + down * 0.5, col)
	_mesh.surface_end()


func _segment(terrain: CourseTerrain, a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5
	var col := slope_color(slope_percent(terrain.normal_at(mid.x, mid.y)))
	_vertex(terrain, a, col)
	_vertex(terrain, b, col)


func _vertex(terrain: CourseTerrain, p: Vector2, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(Vector3(p.x, terrain.height_at(p.x, p.y) + LIFT, p.y))
