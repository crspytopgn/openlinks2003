class_name CourseProps
extends Node3D
## The furniture of a real course, each piece modelled from photos of the
## real thing at its real size (tools/props/build_props.py; sizes and
## sources in docs/props.md): at the side of each tee a hole sign with the
## number, par and yardage, the hole sponsor's plaque, a ball washer over a
## litter bin, and a bench; yardage plates set in the fairway 100, 150 and
## 200 yards from the green with a banded pole at the edge of the fairway at
## 150; a water station at every third tee; a "please repair ball marks"
## sign by each green; and a rake lying at the edge of the bunkers. Scenery only: nothing
## collides with them, and the ball's flight never sees them.
##
## Off in the Classic Links presentation (Links 2003 has none) and at Low
## quality. Every piece is one shared mesh with a draw call per material.

const DIR := "res://assets/props/"
## Where the tee furniture stands, on the side away from a right-handed
## golfer at address (metres along the line of the hole from the tee, and
## across it): the sign by the front of the tee, then the washer, then the
## bench behind.
const SIGN_SPOT := Vector2(-0.5, 4.6)
const SPONSOR_SPOT := Vector2(2.0, 4.3)
const WASHER_SPOT := Vector2(-2.4, 4.8)
const BENCH_SPOT := Vector2(-4.6, 5.4)
const WATER_SPOT := Vector2(-6.4, 5.0)
## A water station at every third tee, as courses space them.
const WATER_EVERY := 3
## The green's "please repair ball marks" sign: how far off the edge of the
## green, and how far round from the line back to the tee (degrees).
const GREEN_SIGN_OFF := 2.5
const GREEN_SIGN_ANGLE := 40.0
const SIGN_INK := Color(0.08, 0.3, 0.15)
## Rakes: the bunker search step (metres), how far round the hole's line it
## looks, and the most rakes per hole at each quality level.
const RAKE_STEP := 2.0
const RAKE_MARGIN := 35.0
const RAKES_BY_QUALITY: Array[int] = [0, 4, 8, 12]
const RAKE_LENGTH := 1.39  ## head to the end of the grip
## Yardage plates: yards to the green, on the line of the hole.
const PLATE_YARDS: Array[int] = [100, 150, 200]
const POLE_YARDS := 150
const YARD := 0.9144
## Made-up hole sponsors (no real businesses), one per hole in turn.
const SPONSORS := [["THE NINETEENTH", "BAR & GRILL"], ["FAIRWAY & FIELD", "CLUBMAKERS SINCE 1921"],
		["OLD COURSE MOTORS", "SALES | SERVICE"], ["HOLLOW OAK", "TIMBER & JOINERY"],
		["LINKSIDE DAIRY", "FRESH EVERY MORNING"], ["BRAMBLE & FINCH", "ESTATE AGENTS"]]
## Surfaces furniture can't stand on.
const NOT_ON := [Surface.Type.WATER, Surface.Type.SAND, Surface.Type.GREEN, Surface.Type.OUT_OF_BOUNDS]

static var _meshes := {}


## The props for `hole`: tee furniture, and rakes at up to `rakes` bunkers.
static func build(hole: HoleData, toward: Vector3, rakes: int) -> CourseProps:
	var props := CourseProps.new()
	props.name = "CourseProps"
	props._build_tee(hole, toward)
	props._build_yardages(hole)
	props._build_green_sign(hole)
	if rakes > 0:
		for r in rake_spots(hole.terrain, hole.tee, hole.pin, hole.route, rakes):
			props._add_rake(hole.terrain, r[0], r[1])
	return props


## A prop's mesh, loaded once and shared; null if the model is missing.
static func mesh(prop: String) -> Mesh:
	if _meshes.has(prop):
		return _meshes[prop]
	var m: Mesh = null
	var path := DIR + prop + ".glb"
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var node := scene.instantiate()
			var found := node.find_children("*", "MeshInstance3D", true, false)
			if node is MeshInstance3D:
				found.insert(0, node)
			if not found.is_empty():
				m = (found[0] as MeshInstance3D).mesh
			node.free()
	_meshes[prop] = m
	return m


static func instance(prop: String, shadows := true) -> MeshInstance3D:
	var m := mesh(prop)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = prop.to_pascal_case()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Where the tee furniture goes: `spot` (along, across) from the tee, on the
## right of the line (looking down the hole), or the left if the right is
## water, sand or off the course. INF if neither side will do.
static func tee_spot(terrain: CourseTerrain, tee: Vector3, toward: Vector3, spot: Vector2) -> Vector3:
	var dir := Vector3(toward.x - tee.x, 0.0, toward.z - tee.z)
	dir = Vector3(0, 0, 1) if dir.length() < 0.01 else dir.normalized()
	var side := Vector3.UP.cross(dir)  # +x: the golfer's left
	for s: float in [-1.0, 1.0]:
		var p := tee + dir * spot.x + side * (s * spot.y)
		if terrain.surface_at(p.x, p.z) in NOT_ON:
			continue
		p.y = terrain.height_at(p.x, p.z)
		return p
	return Vector3.INF


func _build_tee(hole: HoleData, toward: Vector3) -> void:
	var t := hole.terrain
	var dir := Vector3(toward.x - hole.tee.x, 0.0, toward.z - hole.tee.z)
	dir = Vector3(0, 0, 1) if dir.length() < 0.01 else dir.normalized()
	var facing := atan2(dir.x, dir.z)  # yaw that turns +z down the hole

	var sign_at := tee_spot(t, hole.tee, toward, SIGN_SPOT)
	var sign := instance("tee_sign")
	if sign != null and sign_at != Vector3.INF:
		sign.position = sign_at
		# Its face towards the back of the tee, turned a little to the line.
		var right := _side_of(hole.tee, dir, sign_at)
		sign.rotation.y = facing + PI + 0.45 * right
		var yards := roundi(hole.length_m() / YARD)
		_add_text(sign, [[str(hole.number), 300, 1.17], ["PAR %d" % hole.par, 96, 0.92], ["%d YARDS" % yards, 64, 0.81]],
				0.325, 0.0135, false)
		add_child(sign)

	var sponsor_at := tee_spot(t, hole.tee, toward, SPONSOR_SPOT)
	var sponsor := instance("sponsor_sign")
	if sponsor != null and sponsor_at != Vector3.INF:
		sponsor.position = sponsor_at
		sponsor.rotation.y = facing + PI + 0.45 * _side_of(hole.tee, dir, sponsor_at)
		var words: Array = SPONSORS[(hole.number - 1) % SPONSORS.size()]
		_add_text(sponsor, [[words[0], 56, 0.865], [words[1], 30, 0.77]], 0.0, 0.0135, true)
		add_child(sponsor)

	var washer_at := tee_spot(t, hole.tee, toward, WASHER_SPOT)
	var washer := instance("ball_washer")
	if washer != null and washer_at != Vector3.INF:
		washer.position = washer_at
		washer.rotation.y = facing + PI * 0.5
		add_child(washer)

	var bench_at := tee_spot(t, hole.tee, toward, BENCH_SPOT)
	var bench := instance("tee_bench")
	if bench != null and bench_at != Vector3.INF:
		bench.position = bench_at
		# Seat facing across the tee, towards the line of play.
		var right := _side_of(hole.tee, dir, bench_at)
		bench.rotation.y = facing - PI * 0.5 * right
		add_child(bench)

	if hole.number % WATER_EVERY == 0:
		var water_at := tee_spot(t, hole.tee, toward, WATER_SPOT)
		var water := instance("water_station")
		if water != null and water_at != Vector3.INF:
			water.position = water_at
			water.rotation.y = facing - PI * 0.5 * _side_of(hole.tee, dir, water_at)
			add_child(water)


## -1 if p is right of the line from `tee` along `dir`, +1 if left.
static func _side_of(tee: Vector3, dir: Vector3, p: Vector3) -> float:
	var side := Vector3.UP.cross(dir)
	return 1.0 if (p - tee).dot(side) > 0.0 else -1.0


## Lines of raised gold lettering, [text, size, height], on the face of a
## sign at `x` across and `z` out (and on the back too unless `front_only`).
static func _add_text(sign: Node3D, lines: Array, x: float, z: float, front_only: bool) -> void:
	for face: float in ([1.0] if front_only else [1.0, -1.0]):
		for l: Array in lines:
			var label := Label3D.new()
			label.text = l[0]
			label.font_size = l[1]
			label.pixel_size = 0.0007
			label.outline_size = 0
			label.modulate = Color(0.88, 0.74, 0.46)
			label.shaded = true
			label.double_sided = false
			label.position = Vector3(x, l[2], z * face)
			if face < 0.0:
				label.rotation.y = PI
			sign.add_child(label)


## A small resin sign by the green, on the side players walk on from:
## "PLEASE REPAIR BALL MARKS", facing them.
func _build_green_sign(hole: HoleData) -> void:
	var t := hole.terrain
	var back := Vector3(hole.tee.x - hole.pin.x, 0.0, hole.tee.z - hole.pin.z)
	back = Vector3(0, 0, -1) if back.length() < 0.01 else back.normalized()
	var d := back.rotated(Vector3.UP, deg_to_rad(GREEN_SIGN_ANGLE))
	var r := Gallery._green_edge(t, hole.pin, d) + GREEN_SIGN_OFF
	var p := hole.pin + d * r
	if t.surface_at(p.x, p.z) in NOT_ON:
		return
	var sign := instance("course_sign", false)
	if sign == null:
		return
	p.y = t.height_at(p.x, p.z)
	sign.position = p
	sign.rotation.y = atan2(d.x, d.z)  # its face (+z) out, away from the green
	for face: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = "PLEASE REPAIR\nBALL MARKS"
		label.font_size = 40
		label.pixel_size = 0.0008
		label.outline_size = 0
		label.line_spacing = -6.0
		label.modulate = SIGN_INK
		label.shaded = true
		label.double_sided = false
		label.position = Vector3(0, 0.1, 0.0075 * face)
		if face < 0.0:
			label.rotation.y = PI
		sign.add_child(label)
	add_child(sign)


## The point on the hole's line `metres` short of the pin (walking back from
## the pin along the route to the tee), and the line's direction there
## (towards the pin). [INF, ZERO] if the hole is shorter than that.
static func point_back_from_pin(tee: Vector3, pin: Vector3, route: PackedVector2Array, metres: float) -> Array:
	var pts: Array[Vector2] = [Vector2(pin.x, pin.z)]
	for k in range(route.size() - 1, -1, -1):
		pts.append(route[k])
	pts.append(Vector2(tee.x, tee.z))
	var left := metres
	for k in pts.size() - 1:
		var seg := pts[k].distance_to(pts[k + 1])
		if seg >= left and seg > 0.0:
			var p := pts[k].lerp(pts[k + 1], left / seg)
			var d := (pts[k] - pts[k + 1]).normalized()
			return [Vector3(p.x, 0.0, p.y), Vector3(d.x, 0.0, d.y)]
		left -= seg
	return [Vector3.INF, Vector3.ZERO]


## Plates in the fairway at 100, 150 and 200 yards from the green, and the
## 150 yard pole at the right-hand edge of the fairway.
func _build_yardages(hole: HoleData) -> void:
	var t := hole.terrain
	var tee_to_pin := Vector2(hole.tee.x, hole.tee.z).distance_to(Vector2(hole.pin.x, hole.pin.z))
	for yards in PLATE_YARDS:
		var at := point_back_from_pin(hole.tee, hole.pin, hole.route, yards * YARD)
		var p: Vector3 = at[0]
		if p == Vector3.INF or tee_to_pin < yards * YARD + 40.0:
			continue
		var dir: Vector3 = at[1]
		if t.surface_at(p.x, p.z) == Surface.Type.FAIRWAY:
			var plate := instance("yardage_plate", false)
			if plate != null:
				# Flush with the turf, following its slope.
				p.y = t.height_at(p.x, p.z) + 0.006
				var up := t.normal_at(p.x, p.z)
				var across := up.cross(dir).normalized()
				plate.transform = Transform3D(Basis(across, up, across.cross(up).normalized()), p)
				var label := Label3D.new()
				label.text = str(yards)
				label.font_size = 160
				label.pixel_size = 0.00055
				label.outline_size = 0
				label.modulate = Color(0.72, 0.56, 0.26)
				label.shaded = true
				label.rotation.x = -PI * 0.5
				label.rotation.z = PI  # read from the tee side
				label.position = Vector3(0, 0.003, 0)
				plate.add_child(label)
				add_child(plate)
		if yards == POLE_YARDS:
			var edge := fairway_edge(t, p, dir)
			var pole := instance("yardage_pole")
			if pole != null and edge != Vector3.INF:
				pole.position = edge
				add_child(pole)


## Where the fairway gives way to rough on the right of the line at `p`
## (the left if the right runs into hazards), a metre into the rough. INF
## if neither side has rough within 45 m.
static func fairway_edge(t: CourseTerrain, p: Vector3, dir: Vector3) -> Vector3:
	var side := Vector3.UP.cross(dir).normalized()
	for s: float in [-1.0, 1.0]:
		var d := 1.0
		while d < 45.0:
			var q := p + side * (s * d)
			var surf := t.surface_at(q.x, q.z)
			if surf == Surface.Type.ROUGH or surf == Surface.Type.DEEP_ROUGH:
				q += side * s
				q.y = t.height_at(q.x, q.z)
				return q
			if surf != Surface.Type.FAIRWAY and surf != Surface.Type.FRINGE:
				break
			d += 1.0
	return Vector3.INF


## Up to `count` places for a rake: one per bunker near the hole's line,
## nearest the pin first. Each is [head position, handle direction]: the
## head just inside the sand at the bunker's edge on the side facing the
## line of play, the handle pointing out over the grass.
static func rake_spots(terrain: CourseTerrain, tee: Vector3, pin: Vector3, route: PackedVector2Array, count: int) -> Array:
	var pts: Array[Vector2] = [Vector2(tee.x, tee.z)]
	for r in route:
		pts.append(r)
	pts.append(Vector2(pin.x, pin.z))
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	lo -= Vector2.ONE * RAKE_MARGIN
	hi += Vector2.ONE * RAKE_MARGIN
	var nx := int((hi.x - lo.x) / RAKE_STEP) + 1
	var nz := int((hi.y - lo.y) / RAKE_STEP) + 1
	if nx * nz > 60000:
		return []
	var sand := PackedByteArray()
	sand.resize(nx * nz)
	for j in nz:
		for i in nx:
			var x := lo.x + i * RAKE_STEP
			var z := lo.y + j * RAKE_STEP
			sand[j * nx + i] = 1 if terrain.surface_at(x, z) == Surface.Type.SAND else 0
	# Each bunker: its cells, flood filled.
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var bunkers: Array = []
	for start in nx * nz:
		if sand[start] == 0 or seen[start] == 1:
			continue
		var cells: Array[int] = [start]
		seen[start] = 1
		var k := 0
		while k < cells.size():
			var c := cells[k]
			k += 1
			var ci := c % nx
			var cj := c / nx
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := ci + d.x
				var nj := cj + d.y
				if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
					continue
				var n := nj * nx + ni
				if sand[n] == 1 and seen[n] == 0:
					seen[n] = 1
					cells.append(n)
		if cells.size() >= 3:
			bunkers.append(cells)
	# One rake per bunker, at the edge cell nearest the hole's line.
	var found: Array = []
	for cells: Array in bunkers:
		var best := Vector3.INF
		var best_out := Vector2.ZERO
		var best_d := INF
		for c: int in cells:
			var ci := c % nx
			var cj := c / nx
			var out := Vector2.ZERO
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := ci + d.x
				var nj := cj + d.y
				if ni < 0 or nj < 0 or ni >= nx or nj >= nz or sand[nj * nx + ni] == 0:
					out += Vector2(d)
			if out == Vector2.ZERO:
				continue
			var p := Vector2(lo.x + ci * RAKE_STEP, lo.y + cj * RAKE_STEP)
			var d_line := _distance_to_path(p, pts)
			if d_line < best_d:
				best_d = d_line
				best = Vector3(p.x, 0.0, p.y)
				best_out = out.normalized()
		if best == Vector3.INF:
			continue
		# Slide the head out to the last bit of sand before the edge.
		var head := Vector2(best.x, best.z)
		for _i in 8:
			var next := head + best_out * 0.25
			if terrain.surface_at(next.x, next.y) != Surface.Type.SAND:
				break
			head = next
		head -= best_out * 0.35
		found.append([Vector3(head.x, terrain.height_at(head.x, head.y), head.y), Vector3(best_out.x, 0.0, best_out.y),
				Vector2(head.x, head.y).distance_to(Vector2(pin.x, pin.z))])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	return found.slice(0, count)


static func _distance_to_path(p: Vector2, pts: Array[Vector2]) -> float:
	var best := INF
	for k in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])))
	return best


func _add_rake(terrain: CourseTerrain, head: Vector3, out: Vector3) -> void:
	var rake := instance("bunker_rake", false)
	if rake == null:
		return
	# Lying on the ground: the handle runs out over the edge of the bunker,
	# turned a little off square as a rake is dropped.
	var dir := out.rotated(Vector3.UP, deg_to_rad(float(int(head.x * 7.0 + head.z * 13.0) % 40 - 20)))
	var end := head + dir * RAKE_LENGTH
	end.y = terrain.height_at(end.x, end.z)
	var along := (end - head).normalized()
	var across := Vector3.UP.cross(along).normalized()
	var up := along.cross(across).normalized()
	if up.y < 0.0:
		up = -up
	rake.transform = Transform3D(Basis(across, up, along).orthonormalized(), head - Vector3(0, 0.01, 0))
	add_child(rake)
