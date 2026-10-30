class_name LinksAero
extends RefCounted
## The ball flight model of Links 2003: a GDScript port of
## libs/olcore/src/links_flight.cpp; change both together. The drag and lift
## coefficient tables are read from the player's own executable. See
## docs/formats/physics.md.

const SPEED_COUNT := 11
const SPIN_COUNT := 14
const TABLE_BYTES := 8 + 4 * (SPEED_COUNT + SPIN_COUNT) + 12 + 4 * SPEED_COUNT * SPIN_COUNT

const FEET_PER_METRE := 1.0 / 0.3048
const GRAVITY_FPS2 := 32.152
const DRAG_SCALE := 0.004735  ## per foot
const LIFT_SCALE := 0.0057443  ## per foot
const SPIN_KEPT_PER_FRAME := 0.9994
const FRAME_RATE := 60.0
const WIND_SCALE := 0.5  ## the game blows the air at this fraction of the wind

## Each table: "speeds" (ft/s), "spins" (rev/s), "values" (rows by speed).
var drag: Dictionary
var lift: Dictionary


## Finds the tables in the bytes of LINKSM_1.EXE or LinksMMIII.exe; null if
## they are not there. Mirrors olcore::find_links_aero.
static func from_exe(exe: PackedByteArray) -> LinksAero:
	var found_drag := {}
	var found_lift := {}
	var off := 0
	while off + TABLE_BYTES <= exe.size():
		# Jump to the next byte that could start the row count.
		off = exe.find(SPEED_COUNT, off)
		if off < 0:
			break
		if off % 4 == 0 and off + TABLE_BYTES <= exe.size() and exe.decode_u32(off) == SPEED_COUNT:
			var t := _table_at(exe, off)
			if not t.is_empty():
				var values: PackedFloat64Array = t.values
				var no_spin_no_lift := true
				for r in SPEED_COUNT:
					no_spin_no_lift = no_spin_no_lift and values[r * SPIN_COUNT] == 0.0
				var lowest := values[0]
				for v in values:
					lowest = minf(lowest, v)
				if no_spin_no_lift and found_lift.is_empty():
					found_lift = t
				elif not no_spin_no_lift and found_drag.is_empty() and lowest > 0.0:
					found_drag = t
				if not found_drag.is_empty() and not found_lift.is_empty():
					var aero := LinksAero.new()
					aero.drag = found_drag
					aero.lift = found_lift
					return aero
		off += 1
	return null


## Reads the executable from the configured game folder, if there is one.
static func from_game_folder() -> LinksAero:
	var path := GameFolder.find_file(PackedStringArray(CrzCourseLoader.EXE_NAMES))
	if path.is_empty():
		return null
	return from_exe(FileAccess.get_file_as_bytes(path))


## Bilinear lookup, clamped to the grid. Mirrors CoefficientTable::at.
static func coefficient(t: Dictionary, speed_fps: float, spin_rps: float) -> float:
	var speeds: PackedFloat64Array = t.speeds
	var spins: PackedFloat64Array = t.spins
	var values: PackedFloat64Array = t.values
	var s := clampf(speed_fps, speeds[0], speeds[speeds.size() - 1])
	var w := clampf(spin_rps, spins[0], spins[spins.size() - 1])
	var i := _cell(speeds, s)
	var j := _cell(spins, w)
	var fs := (s - speeds[i]) / (speeds[i + 1] - speeds[i])
	var fw := (w - spins[j]) / (spins[j + 1] - spins[j])
	var n := spins.size()
	var lo := values[i * n + j] + (values[(i + 1) * n + j] - values[i * n + j]) * fs
	var hi := values[i * n + j + 1] + (values[(i + 1) * n + j + 1] - values[i * n + j + 1]) * fs
	return lo + (hi - lo) * fw


## Mirrors olcore::links_acceleration. `wind` is before WIND_SCALE.
func acceleration(vel: Vector3, spin: Vector3, wind: Vector3) -> Vector3:
	var a := Vector3(0.0, -GRAVITY_FPS2 / FEET_PER_METRE, 0.0)
	var air := vel - wind * WIND_SCALE
	var speed := air.length()
	if speed < 1e-9:
		return a
	var speed_fps := speed * FEET_PER_METRE
	var spin_rate := spin.length()
	var spin_rps := spin_rate / TAU
	a -= air * (DRAG_SCALE * FEET_PER_METRE * coefficient(drag, speed_fps, spin_rps) * speed)
	if spin_rate > 1e-9:
		a += (spin / spin_rate).cross(air) * (LIFT_SCALE * FEET_PER_METRE * coefficient(lift, speed_fps, spin_rps) * speed)
	return a


## Mirrors olcore::links_step_flight.
func step_flight(s: BallState, dt: float, wind: Vector3) -> BallState:
	var out := BallState.new()
	out.velocity = s.velocity + acceleration(s.velocity, s.spin, wind) * dt
	out.position = s.position + (s.velocity + out.velocity) * (0.5 * dt)
	out.spin = s.spin * pow(SPIN_KEPT_PER_FRAME, FRAME_RATE * dt)
	return out


static func _table_at(exe: PackedByteArray, off: int) -> Dictionary:
	if exe.decode_u32(off) != SPEED_COUNT or exe.decode_u32(off + 4) != SPIN_COUNT:
		return {}
	var q := off + 8
	var speeds := PackedFloat64Array()
	var spins := PackedFloat64Array()
	for i in SPEED_COUNT:
		speeds.append(exe.decode_float(q))
		q += 4
	for i in SPIN_COUNT:
		spins.append(exe.decode_float(q))
		q += 4
	if not _ascending_from_zero(speeds) or not _ascending_from_zero(spins):
		return {}
	q += 12
	var values := PackedFloat64Array()
	for i in SPEED_COUNT * SPIN_COUNT:
		var v := exe.decode_float(q)
		if is_nan(v) or is_inf(v) or absf(v) > 5.0:
			return {}
		values.append(v)
		q += 4
	return {"speeds": speeds, "spins": spins, "values": values}


static func _ascending_from_zero(v: PackedFloat64Array) -> bool:
	if v.is_empty() or v[0] != 0.0:
		return false
	for i in range(1, v.size()):
		if not (v[i] > v[i - 1]):
			return false
	return true


static func _cell(axis: PackedFloat64Array, x: float) -> int:
	var i := 0
	while i + 2 < axis.size() and x >= axis[i + 1]:
		i += 1
	return i
