class_name BuggySound
extends Node3D
## The golf buggy's sounds, made in code so they need no files and play the
## same on every platform (the web build too: plain looping clips whose
## pitch and volume follow the cart, nothing streamed or generated live).
##
## - The AC motor's whine, which rises with road speed and is loudest
##   under power or regenerating, and silent when stopped (an electric
##   cart makes no sound at a standstill).
## - Tyre noise: a hiss on cart paths, a softer swish on grass and a deeper
##   rumble in the rough, rising with speed.
## - The automatic park brake: a clack as it lets go when you press the
##   pedal and as it sets when the cart stops.

const RATE := 22050
const WHINE_HZ := 220.0  ## the clip's pitch; played slower or faster with speed
const WHINE_DB := -15.0
const TYRE_DB := -13.0
const CLACK_DB := -8.0

var _whine: AudioStreamPlayer3D
var _tyres: AudioStreamPlayer3D
var _clack: AudioStreamPlayer3D
var _parked := true

static var _whine_clip: AudioStreamWAV
static var _tyre_clip: AudioStreamWAV
static var _clack_clip: AudioStreamWAV


func _init() -> void:
	name = "BuggySound"
	if _whine_clip == null:
		_whine_clip = whine_clip()
		_tyre_clip = tyre_clip()
		_clack_clip = clack_clip()
	_whine = _player(_whine_clip)
	_tyres = _player(_tyre_clip)
	_clack = _player(_clack_clip)
	_clack.volume_db = CLACK_DB


func _player(stream: AudioStreamWAV) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = 6.0
	p.max_distance = 80.0
	p.volume_db = -80.0
	add_child(p)
	return p


## Follows the cart: `speed` in m/s, `pedal` -1 to 1, `rough` 0 on paths
## to about 1.5 in deep rough.
func update(speed: float, pedal: float, rough: float) -> void:
	var v := absf(speed)
	var moving := v > 0.05 or absf(pedal) > 0.05
	if moving == _parked:
		_parked = not moving
		if is_inside_tree():
			_clack.play()
	var whine := clampf(v / BuggyDrive.GOVERNED, 0.0, 1.2)
	var effort := clampf(absf(pedal), 0.0, 1.0)
	var whine_level := whine * (0.35 + 0.65 * effort)
	_level(_whine, WHINE_DB + linear_to_db(maxf(whine_level, 1e-4)), 0.3 + 0.75 * whine)
	var tyre_level := clampf(v / BuggyDrive.GOVERNED, 0.0, 1.2) * (0.6 + 0.4 * rough)
	_level(_tyres, TYRE_DB + linear_to_db(maxf(tyre_level, 1e-4)), clampf(1.25 - 0.35 * rough, 0.5, 1.3) * (0.7 + 0.3 * whine))


## Stopped and quiet at once, with no clack (the cart was moved, not driven).
func silence() -> void:
	_parked = true
	for p: AudioStreamPlayer3D in [_whine, _tyres]:
		p.volume_db = -80.0
		p.stop()


func _level(p: AudioStreamPlayer3D, db: float, pitch: float) -> void:
	p.pitch_scale = maxf(pitch, 0.05)
	p.volume_db = db
	var on := db > -60.0
	if not is_inside_tree():
		return
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


## How rough the ground is for the tyres: 0 on paths, more in the rough.
static func roughness(terrain: CourseTerrain, p: Vector3) -> float:
	if terrain.free_drop_at(p.x, p.z):
		return 0.0
	match terrain.surface_at(p.x, p.z):
		Surface.Type.ROUGH, Surface.Type.OUT_OF_BOUNDS:
			return 1.0
		Surface.Type.DEEP_ROUGH:
			return 1.5
	return 0.4


# --- The clips -----------------------------------------------------------------


## One second of motor whine: the fundamental and its harmonics (whole
## cycles, so it loops without a click), a faint inverter tone and a little
## noise for texture.
static func whine_clip() -> AudioStreamWAV:
	var n := RATE
	var rng := RandomNumberGenerator.new()
	rng.seed = 2003
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var x := 0.55 * sin(TAU * WHINE_HZ * t) + 0.25 * sin(TAU * 2.0 * WHINE_HZ * t) \
				+ 0.12 * sin(TAU * 3.0 * WHINE_HZ * t + 0.6) + 0.05 * sin(TAU * 1100.0 * t)
		s[i] = x + 0.04 * rng.randf_range(-1.0, 1.0)
	return _loop_clip(s)


## Two seconds of tyre noise: white noise through two low-pass stages,
## cross-faded at the ends so it loops smoothly.
static func tyre_clip() -> AudioStreamWAV:
	var n := RATE * 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	var s := PackedFloat32Array()
	s.resize(n)
	var a := 0.0
	var b := 0.0
	for i in n:
		a += 0.25 * (rng.randf_range(-1.0, 1.0) - a)
		b += 0.35 * (a - b)
		s[i] = b * 2.6
	var fade := RATE / 10
	for i in fade:
		var k := float(i) / fade
		s[i] = s[i] * k + s[n - fade + i] * (1.0 - k)
	s.resize(n - fade)
	return _loop_clip(s)


## The park brake: a sharp click and a short low thump.
static func clack_clip() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 180.0) * 0.8 + sin(TAU * 95.0 * t) * exp(-t * 40.0) * 0.6
	var clip := _clip(s)
	clip.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return clip


static func _loop_clip(s: PackedFloat32Array) -> AudioStreamWAV:
	var clip := _clip(s)
	clip.loop_mode = AudioStreamWAV.LOOP_FORWARD
	clip.loop_begin = 0
	clip.loop_end = s.size()
	return clip


static func _clip(s: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0
	for x in s:
		peak = maxf(peak, absf(x))
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] / maxf(peak, 1e-6) * 0.9, -1.0, 1.0) * 32767.0))
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = RATE
	clip.stereo = false
	clip.data = data
	return clip
