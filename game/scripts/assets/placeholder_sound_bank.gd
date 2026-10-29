class_name PlaceholderSoundBank
extends SoundBank
## Tiny synthesised sounds so the game isn't silent.

const MIX_RATE := 22050

var _players := {}


func _ready() -> void:
	_add(&"hit", _click(0.05, 1800.0, 0.9))
	_add(&"putt", _click(0.04, 900.0, 0.5))
	_add(&"land", _click(0.06, 300.0, 0.4))
	_add(&"cup", _rattle())
	_add(&"splash", _noise(0.45, 0.5))
	_add(&"applause", _noise(1.6, 0.25))


func play(event: StringName) -> void:
	var p: AudioStreamPlayer = _players.get(event)
	if p:
		p.play()


func _add(event: StringName, stream: AudioStreamWAV) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	_players[event] = p


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


## A short decaying tone with a noisy attack.
func _click(length: float, freq: float, gain: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 60.0)
		s[i] = gain * env * (0.6 * sin(TAU * freq * t) + 0.4 * randf_range(-1.0, 1.0))
	return _wav(s)


func _rattle() -> AudioStreamWAV:
	var n := int(0.35 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in 3:
		var start := int((0.02 + k * 0.09) * MIX_RATE)
		for i in range(start, mini(n, start + int(0.05 * MIX_RATE))):
			var t := float(i - start) / MIX_RATE
			s[i] += 0.5 * exp(-t * 80.0) * sin(TAU * (2400.0 - k * 300.0) * t)
	return _wav(s)


func _noise(length: float, gain: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var smooth := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		smooth = lerpf(smooth, randf_range(-1.0, 1.0), 0.3)
		s[i] = gain * smooth * sin(PI * t / length)
	return _wav(s)
