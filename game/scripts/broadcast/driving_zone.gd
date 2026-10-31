class_name DrivingZone
extends MeshInstance3D
## The tour graphics' driving zone: a fan drawn on the ground from the ball
## out to the club's reach, split into miss left, hit the fairway and miss
## right, with the chance of each and the score the player can expect from
## there. The chances come from a spread of start lines around the aim (a
## guess per swing skill, SPREAD_DEG); the scores from the computer
## golfers' own expected-strokes table (OpponentSkill.expected_strokes).

const MAX_DEG := 30.0  ## widest line looked at, either side of the aim
const STEP_DEG := 0.5
## How far (one standard deviation, degrees) a human's start line wanders
## at each swing skill, easiest first. Our guess, not Links data.
const SPREAD_DEG := [2.5, 3.5, 4.5, 5.5]
const HIT := Color(0.35, 0.85, 0.55)
const MISS := Color(0.92, 0.32, 0.28)
const RINGS := 14
const LIFT := 0.3  ## metres above the ground

var _mesh := ImmediateMesh.new()


func _init() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 1
	material_override = mat


## The zone for a shot from `from` aimed at `aim_deg` that should finish
## `reach_m` away. Empty when no line in range finds the fairway. Keys: lo,
## hi (the fairway's edges, degrees from the aim, + is left), reach, chance
## and score for "left", "hit" and "right", and "anchors" (world points for
## each label, in that order).
static func compute(hole: HoleData, from: Vector3, aim_deg: float, reach_m: float, strokes: int, spread_deg: float) -> Dictionary:
	var n := roundi(MAX_DEG * 2.0 / STEP_DEG) + 1
	var surfaces: Array[int] = []
	var values: Array[float] = []
	for i in n:
		var a := -MAX_DEG + i * STEP_DEG
		var p := _point(from, aim_deg + a, reach_m)
		var s := hole.terrain.surface_at(p.x, p.z)
		surfaces.append(s)
		values.append(strokes + 1 + _expected(hole, from, p, s))
	# The run of fairway closest to the aim line.
	var best := -1
	for i in n:
		if _is_hit(surfaces[i]) and (best < 0 or absi(i - n / 2) < absi(best - n / 2)):
			best = i
	if best < 0:
		return {}
	var lo_i := best
	var hi_i := best
	while lo_i > 0 and _is_hit(surfaces[lo_i - 1]):
		lo_i -= 1
	while hi_i < n - 1 and _is_hit(surfaces[hi_i + 1]):
		hi_i += 1
	var lo := -MAX_DEG + lo_i * STEP_DEG - STEP_DEG * 0.5
	var hi := -MAX_DEG + hi_i * STEP_DEG + STEP_DEG * 0.5
	var sd := maxf(spread_deg, 0.5)
	var p_right := _cdf(lo / sd)
	var p_left := 1.0 - _cdf(hi / sd)
	var p_hit := 1.0 - p_left - p_right
	# Each zone's score, weighted by how likely each line in it is.
	var sums := [0.0, 0.0, 0.0]
	var weights := [0.0, 0.0, 0.0]
	for i in n:
		var a := -MAX_DEG + i * STEP_DEG
		var zone := 1 if i >= lo_i and i <= hi_i else (0 if a > 0.0 else 2)
		var w := exp(-0.5 * (a / sd) * (a / sd))
		sums[zone] += values[i] * w
		weights[zone] += w
	var scores: Array[float] = []
	for z in 3:
		scores.append(sums[z] / weights[z] if weights[z] > 1e-6 else values[n - 1 if z == 0 else 0])
	var left_mid := minf(hi + sd * 1.5, MAX_DEG)
	var right_mid := maxf(lo - sd * 1.5, -MAX_DEG)
	var far := reach_m * 1.12
	var anchors: Array[Vector3] = []
	for a: float in [left_mid, (lo + hi) * 0.5, right_mid]:
		var p := _point(from, aim_deg + a, far)
		p.y = hole.terrain.height_at(p.x, p.z) + LIFT
		anchors.append(p)
	return {
		"lo": lo, "hi": hi, "reach": reach_m, "spread": sd,
		"left": p_left, "hit": p_hit, "right": p_right,
		"score_left": scores[0], "score_hit": scores[1], "score_right": scores[2],
		"anchors": anchors,
	}


## Draws `zone` (from compute) on the ground, from `from` along `aim_deg`.
func show_zone(zone: Dictionary, hole: HoleData, from: Vector3, aim_deg: float) -> void:
	_mesh.clear_surfaces()
	if zone.is_empty():
		visible = false
		return
	visible = true
	var lo: float = zone.lo
	var hi: float = zone.hi
	var sd: float = zone.spread
	var far: float = zone.reach * 1.12
	var left_edge := minf(hi + sd * 2.5, MAX_DEG)
	var right_edge := maxf(lo - sd * 2.5, -MAX_DEG)
	_wedge(hole, from, aim_deg, hi, left_edge, far, MISS)
	_wedge(hole, from, aim_deg, lo, hi, far, HIT)
	_wedge(hole, from, aim_deg, right_edge, lo, far, MISS)
	# Bright edges on the fairway wedge.
	_edge(hole, from, aim_deg + lo, far)
	_edge(hole, from, aim_deg + hi, far)


func clear() -> void:
	_mesh.clear_surfaces()
	visible = false


func _wedge(hole: HoleData, from: Vector3, aim_deg: float, a0: float, a1: float, far: float, col: Color) -> void:
	if a1 - a0 < 0.05:
		return
	var cols := maxi(2, ceili((a1 - a0) / 1.0))
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in RINGS:
		var r0 := far * float(r) / RINGS
		var r1 := far * float(r + 1) / RINGS
		# Faint at the ball, strongest at the far end.
		var c0 := Color(col, 0.06 + 0.45 * float(r) / RINGS)
		var c1 := Color(col, 0.06 + 0.45 * float(r + 1) / RINGS)
		for c in cols:
			var b0 := aim_deg + lerpf(a0, a1, float(c) / cols)
			var b1 := aim_deg + lerpf(a0, a1, float(c + 1) / cols)
			var p00 := _ground(hole, from, b0, r0)
			var p01 := _ground(hole, from, b1, r0)
			var p10 := _ground(hole, from, b0, r1)
			var p11 := _ground(hole, from, b1, r1)
			for v: Array in [[p00, c0], [p10, c1], [p11, c1], [p00, c0], [p11, c1], [p01, c0]]:
				_mesh.surface_set_color(v[1])
				_mesh.surface_add_vertex(v[0])
	_mesh.surface_end()


func _edge(hole: HoleData, from: Vector3, deg: float, far: float) -> void:
	var side := Vector3(cos(deg_to_rad(deg)), 0.0, -sin(deg_to_rad(deg))) * maxf(0.25, far * 0.004)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for r in RINGS + 1:
		var p := _ground(hole, from, deg, far * float(r) / RINGS)
		var c := Color(1, 1, 1, 0.2 + 0.7 * float(r) / RINGS)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - side)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + side)
	_mesh.surface_end()


static func _ground(hole: HoleData, from: Vector3, deg: float, r: float) -> Vector3:
	var p := _point(from, deg, r)
	p.y = hole.terrain.height_at(p.x, p.z) + LIFT
	return p


static func _point(from: Vector3, deg: float, r: float) -> Vector3:
	var a := deg_to_rad(deg)
	return from + Vector3(sin(a), 0.0, cos(a)) * r


static func _is_hit(s: int) -> bool:
	return s == Surface.Type.FAIRWAY or s == Surface.Type.FRINGE or s == Surface.Type.GREEN


## Strokes still to play from where a line ends, as the computer golfers
## value it.
static func _expected(hole: HoleData, from: Vector3, p: Vector3, s: int) -> float:
	var to_pin := Vector2(p.x - hole.pin.x, p.z - hole.pin.z).length()
	match s:
		Surface.Type.WATER:
			return 1.0 + OpponentSkill.expected_strokes(to_pin, Surface.Type.ROUGH)
		Surface.Type.OUT_OF_BOUNDS:
			var back := Vector2(from.x - hole.pin.x, from.z - hole.pin.z).length()
			return 1.0 + OpponentSkill.expected_strokes(back, Surface.Type.TEE)
	return OpponentSkill.expected_strokes(to_pin, s)


## The standard normal distribution function.
static func _cdf(x: float) -> float:
	# Abramowitz and Stegun 7.1.26, good to about 1e-7.
	var t := 1.0 / (1.0 + 0.3275911 * absf(x) / sqrt(2.0))
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x / 2.0)
	return 0.5 * (1.0 + (y if x >= 0.0 else -y))
