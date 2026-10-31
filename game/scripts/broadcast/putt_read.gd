class_name PuttRead
extends MeshInstance3D
## The tour graphics' putt read: the line to aim along and the path the
## ball would take, drawn on the green, with the distance, the slope and how
## far to aim off the hole. The read is the computer golfers' own putt plan
## (ComputerGolfer), run through the round's physics, so it reads the green
## exactly as the ball will roll on a perfect stroke.

const AIM_COLOR := Color(0.42, 0.86, 0.72)
const PATH_COLOR := Color(1, 1, 1)
const LIFT := 0.02
const WIDTH := 0.035

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


## Reads a putt from `from`. Keys: aim_deg, power, distance_m, rise_m (up to
## the hole), aim_off_m (+ is left of the hole), aim_point, path (the ball's
## path), holed. Empty if the planner found no putt.
static func read(model: ShotModel, clubs: Array[Club], hole: HoleData, from: Vector3, lie: int) -> Dictionary:
	var cpu := ComputerGolfer.new(OpponentSkill.Level.CLUB, 1)
	cpu.plan(model, clubs, hole, from, lie, Vector3.ZERO)
	cpu.finish()
	if not cpu.is_putt():
		return {}
	var start := model.launch(clubs[cpu.club_index], cpu.power, 0.0, cpu.aim_deg, lie, from)
	var r := model.simulate(start, hole.terrain, hole.pin, Vector3.ZERO)
	var dist := Vector2(hole.pin.x - from.x, hole.pin.z - from.z).length()
	var heading := rad_to_deg(atan2(hole.pin.x - from.x, hole.pin.z - from.z))
	var off_deg := wrapf(cpu.aim_deg - heading, -180.0, 180.0)
	var a := deg_to_rad(cpu.aim_deg)
	var aim_point := from + Vector3(sin(a), 0.0, cos(a)) * dist
	aim_point.y = hole.terrain.height_at(aim_point.x, aim_point.z)
	return {
		"aim_deg": cpu.aim_deg, "power": cpu.power, "distance_m": dist,
		"rise_m": hole.pin.y - from.y, "aim_off_m": dist * tan(deg_to_rad(off_deg)),
		"aim_point": aim_point, "path": r.points, "holed": r.outcome == ShotResult.Outcome.HOLED,
	}


## "4' 9\" left", "Straight" and the like, from a sideways offset in metres.
static func aim_text(aim_off_m: float) -> String:
	var inches := roundi(absf(aim_off_m) * 39.3701)
	if inches < 2:
		return "Straight"
	var side := "left" if aim_off_m > 0.0 else "right"
	if inches < 12:
		return "%d\" %s" % [inches, side]
	return "%d' %d\" %s" % [inches / 12, inches % 12, side]


## "2.1% uphill", "Flat" and the like.
static func slope_text(rise_m: float, distance_m: float) -> String:
	if distance_m < 0.1:
		return "Flat"
	var pct := rise_m / distance_m * 100.0
	if absf(pct) < 0.3:
		return "Flat"
	return "%.1f%% %s" % [absf(pct), "uphill" if pct > 0.0 else "downhill"]


func show_read(r: Dictionary, from: Vector3) -> void:
	_mesh.clear_surfaces()
	if r.is_empty():
		visible = false
		return
	visible = true
	# The aim line, straight from the ball to the aim point.
	_ribbon(PackedVector3Array([from, r.aim_point]), AIM_COLOR, 1.0, false)
	# The ball's path, dashed.
	var path: PackedVector3Array = r.path
	_ribbon(path, PATH_COLOR, 0.7, true)


func clear() -> void:
	_mesh.clear_surfaces()
	visible = false


func _ribbon(points: PackedVector3Array, col: Color, scale: float, dashed: bool) -> void:
	if points.size() < 2:
		return
	# Resample evenly, every 10 cm.
	var even := PackedVector3Array([points[0]])
	var carry := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := a.distance_to(b)
		var t := 0.1 - carry
		while t <= seg:
			even.append(a.lerp(b, t / seg))
			t += 0.1
		carry = seg - (t - 0.1)
	if even.size() < 2:
		even.append(points[points.size() - 1])
	var w := WIDTH * scale
	var n := even.size()
	var c := Color(col, 0.9)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n - 1:
		if dashed and k % 5 >= 3:
			continue  # three pieces on, two off
		var a := even[k] + Vector3.UP * LIFT
		var b := even[k + 1] + Vector3.UP * LIFT
		var d := b - a
		d.y = 0.0
		if d.length_squared() < 1e-10:
			continue
		var side := Vector3(d.z, 0.0, -d.x).normalized() * w
		for v: Vector3 in [a - side, b - side, b + side, a - side, b + side, a + side]:
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(v)
	_mesh.surface_end()
