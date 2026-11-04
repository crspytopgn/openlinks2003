class_name GreenGrid
extends MeshInstance3D
## The TV green-reading grid: lines a metre apart draped over the real
## terrain round the ball and the hole, coloured by how steep the ground is,
## with a short tick in each square pointing downhill. It reads the slopes
## the physics uses (CourseTerrain.normal_at); it doesn't predict the putt,
## so reading the break is still up to the player.
##
## Three looks (`style`): Links 2003's plain yellow grid, its grid coloured
## by height (low blue, high red), and the TV grid: faint white lines, as TV
## green reads and PGA Tour 2K25 draw them, warming only to a soft amber
## and then a muted red where the green gets steep, with the downhill ticks.
## The Links looks keep the game's own bright colours.
##
## The lines are thin ribbons (shaders/green_grid.gdshader) with soft,
## anti-aliased edges, drawn in short pieces that follow the turf, rather
## than one-pixel GL lines, which neither renderer smooths: those broke
## into stair steps and dashes where they dipped into the turf.

enum Style { YELLOW, HEIGHT, SLOPE }

const SPACING := 1.0
const MARGIN := 4.0  ## metres past the ball and the hole
const MAX_HALF := 18.0
const LIFT := 0.01
## Pieces each metre of line is drawn in, so it follows the turf's curve.
const PIECES := 4
## The lines' width on the turf (m); the shader keeps them a pixel or so
## wide however far off they are.
const LINE_WIDTH := 0.02
const TICK_WIDTH := 0.025
const SHADER := preload("res://shaders/green_grid.gdshader")
const FLAT := Color(1.0, 1.0, 1.0, 0.16)
const MEDIUM := Color(1.0, 0.88, 0.6, 0.3)
const STEEP := Color(0.95, 0.5, 0.38, 0.45)
const STEEP_PERCENT := 4.0
const YELLOW := Color(1.0, 0.9, 0.2, 0.7)
const LOW := Color(0.2, 0.45, 1.0, 0.75)
const MIDDLE := Color(0.35, 0.9, 0.4, 0.75)
const HIGH := Color(1.0, 0.3, 0.2, 0.8)
## Below this spread of heights (m) the height colours show it as flat.
const LEVEL_SPREAD := 0.05

var style: Style = Style.SLOPE
var _low := 0.0
var _high := 0.0

var _mesh := ImmediateMesh.new()


func _init() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("width", LINE_WIDTH)
	material_override = mat
	visible = false


## Slope in percent (rise over run) where the ground has normal `n`.
static func slope_percent(n: Vector3) -> float:
	return 100.0 * Vector2(n.x, n.z).length() / maxf(n.y, 0.01)


## Height colours: blue at the lowest point of the grid, green, red at the
## highest. `f` is 0 (lowest) to 1.
static func height_color(f: float) -> Color:
	f = clampf(f, 0.0, 1.0)
	return LOW.lerp(MIDDLE, f * 2.0) if f < 0.5 else MIDDLE.lerp(HIGH, f * 2.0 - 1.0)


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
	if style == Style.HEIGHT:
		_low = INF
		_high = -INF
		for a in cells + 1:
			for b in cells + 1:
				var y := terrain.height_at(x0 + a * SPACING, z0 + b * SPACING)
				_low = minf(_low, y)
				_high = maxf(_high, y)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in cells + 1:
		for b in cells:
			# Line a runs along z at x = x0 + a, and along x at z = z0 + a.
			var along_z := Vector2(x0 + a * SPACING, z0 + b * SPACING)
			_segment(terrain, along_z, along_z + Vector2(0.0, SPACING))
			var along_x := Vector2(x0 + b * SPACING, z0 + a * SPACING)
			_segment(terrain, along_x, along_x + Vector2(SPACING, 0.0))
	for a in (cells if style == Style.SLOPE else 0):
		for b in cells:
			var c := Vector2(x0 + (a + 0.5) * SPACING, z0 + (b + 0.5) * SPACING)
			var n := terrain.normal_at(c.x, c.y)
			var pct := slope_percent(n)
			if pct < 0.3:
				continue
			var down := Vector2(n.x, n.z).normalized() * SPACING * clampf(0.15 + pct * 0.08, 0.15, 0.45)
			var col := slope_color(pct)
			_piece(terrain, c - down * 0.5, c + down * 0.5, col, col, TICK_WIDTH / LINE_WIDTH)
	_mesh.surface_end()


func _segment(terrain: CourseTerrain, a: Vector2, b: Vector2) -> void:
	var prev := _colour_at(terrain, a)
	for i in PIECES:
		var p := a.lerp(b, float(i) / PIECES)
		var q := a.lerp(b, float(i + 1) / PIECES)
		var next := _colour_at(terrain, q)
		_piece(terrain, p, q, prev, next)
		prev = next


func _colour_at(terrain: CourseTerrain, p: Vector2) -> Color:
	match style:
		Style.SLOPE:
			return slope_color(slope_percent(terrain.normal_at(p.x, p.y)))
		Style.HEIGHT:
			var spread := _high - _low
			return MIDDLE if spread < LEVEL_SPREAD else height_color((terrain.height_at(p.x, p.y) - _low) / spread)
	return YELLOW


## One straight piece of line from `a` to `b` on the turf: a quad the
## shader widens across the screen (UV.x is the edge, -1 or +1; the normal
## carries the way the line runs, UV.y how much wider than LINE_WIDTH).
func _piece(terrain: CourseTerrain, a: Vector2, b: Vector2, col_a: Color, col_b: Color, wide := 1.0) -> void:
	var pa := Vector3(a.x, terrain.height_at(a.x, a.y) + LIFT, a.y)
	var pb := Vector3(b.x, terrain.height_at(b.x, b.y) + LIFT, b.y)
	var run := (pb - pa).normalized()
	for v: Array in [[pa, col_a, -1.0], [pa, col_a, 1.0], [pb, col_b, 1.0], [pa, col_a, -1.0], [pb, col_b, 1.0], [pb, col_b, -1.0]]:
		_mesh.surface_set_color(v[1])
		_mesh.surface_set_normal(run)
		_mesh.surface_set_uv(Vector2(v[2], wide))
		_mesh.surface_add_vertex(v[0])
