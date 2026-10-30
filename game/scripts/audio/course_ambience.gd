class_name CourseAmbience
extends Node
## The course's own background sound (birds, wind, distant traffic): the
## `EnvSound` entry of a .CRZ lists sound kinds, each with one or more WAVs
## stored in the course, and emitters placed round the course. See
## docs/formats/crz.md.
##
## For each hole this loops the nearest looping emitter's sound, and now and
## then plays one of the short ones. The course WAVs are long Microsoft ADPCM
## files that are slow to decode in GDScript, so only the start of the loop
## is decoded (on a thread where there is one) and its ends are crossfaded.

## Emitters whose kind field holds this value loop; the others are short
## one-off sounds. Read from the six CD2 courses; the meaning of the field
## is a guess.
const LOOPING_KIND := 29997.0
const LOOP_SECONDS := 30.0
const LOOP_SECONDS_NO_THREADS := 12.0
const CROSSFADE_SECONDS := 1.5
const VOLUME_DB := -10.0
const ONE_SHOT_GAP := Vector2(14.0, 40.0)  ## seconds between short sounds

var _read: Callable
var _defs: Array[Dictionary] = []
var _emitters: Array[Dictionary] = []
var _loop: AudioStreamPlayer
var _one_shot: AudioStreamPlayer
var _loop_file := ""
var _streams := {}  ## file -> AudioStreamWAV
var _task := -1
var _pending := {}
var _next_one_shot := 0.0
var _hole_position := Vector3.ZERO


## Null when the course has no ambient sounds.
static func create(read: Callable) -> CourseAmbience:
	var parsed := parse_env_sound(read.call("EnvSound"))
	if parsed.is_empty() or (parsed.emitters as Array).is_empty():
		return null
	var a := CourseAmbience.new()
	a.name = "Ambience"
	a._read = read
	a._defs.assign(parsed.defs)
	a._emitters.assign(parsed.emitters)
	return a


## `EnvSound`: {defs: [{name, files}], emitters: [{def, position, radius,
## volume, looping}]}. Empty on error.
static func parse_env_sound(b: PackedByteArray) -> Dictionary:
	if b.size() < 8:
		return {}
	var pos := 0
	var count := b.decode_u32(pos)
	pos += 4
	var defs: Array[Dictionary] = []
	for i in count:
		var text := _string(b, pos)
		if text.is_empty():
			return {}
		pos = text.end + 4  # then a u32 (the kind's own index)
		if pos + 4 > b.size():
			return {}
		var n := b.decode_u32(pos)
		pos += 4
		var files := PackedStringArray()
		for j in n:
			var f := _string(b, pos)
			if f.is_empty():
				return {}
			files.append(f.value)
			pos = f.end
		defs.append({"name": text.value, "files": files})
	if pos + 4 > b.size():
		return {}
	var emitter_count := b.decode_u32(pos)
	pos += 4
	var emitters: Array[Dictionary] = []
	for i in emitter_count:
		if pos + 36 > b.size():
			return {}
		var def := b.decode_u32(pos)
		var p := CrzCourseLoader.to_godot(b.decode_float(pos + 4), b.decode_float(pos + 8), b.decode_float(pos + 12))
		emitters.append({
			"def": def,
			"position": p,
			"looping": is_equal_approx(b.decode_float(pos + 16), LOOPING_KIND),
			"radius": b.decode_float(pos + 20) * CrzCourseLoader.FEET,
			"volume": b.decode_float(pos + 24),
		})
		pos += 36
	return {"defs": defs, "emitters": emitters}


## A u32 length then that many bytes (NUL-padded): {value, end}, or {}.
static func _string(b: PackedByteArray, pos: int) -> Dictionary:
	if pos + 4 > b.size():
		return {}
	var n := b.decode_u32(pos)
	if n == 0 or n > 256 or pos + 4 + n > b.size():
		return {}
	return {"value": b.slice(pos + 4, pos + 4 + n).get_string_from_ascii(), "end": pos + 4 + n}


func _ready() -> void:
	_loop = AudioStreamPlayer.new()
	_loop.volume_db = VOLUME_DB
	add_child(_loop)
	_one_shot = AudioStreamPlayer.new()
	_one_shot.volume_db = VOLUME_DB - 4.0
	add_child(_one_shot)


## Switches to the sound of the area round `where` (the tee of a new hole).
func start_hole(where: Vector3) -> void:
	_hole_position = where
	_next_one_shot = randf_range(ONE_SHOT_GAP.x, ONE_SHOT_GAP.y) * 0.5
	var e := _nearest(where, true)
	if e.is_empty():
		return
	var files: PackedStringArray = _defs[e.def].files if e.def < _defs.size() else PackedStringArray()
	if files.is_empty() or files[0] == _loop_file:
		return
	_loop_file = files[0]
	_load_async(_loop_file, true)


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_finish_load()
	_next_one_shot -= delta
	if _next_one_shot <= 0.0:
		_next_one_shot = randf_range(ONE_SHOT_GAP.x, ONE_SHOT_GAP.y)
		var e := _nearest(_hole_position, false)
		if not e.is_empty() and e.def < _defs.size():
			var files: PackedStringArray = _defs[e.def].files
			if not files.is_empty():
				var f := files[randi() % files.size()]
				if _streams.has(f):
					_one_shot.stream = _streams[f]
					_one_shot.play()
				elif _task < 0:
					_load_async(f, false)


func _nearest(where: Vector3, looping: bool) -> Dictionary:
	var best := {}
	var best_d := INF
	for e in _emitters:
		if e.looping != looping:
			continue
		var d := where.distance_squared_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _load_async(file: String, looping: bool) -> void:
	if _streams.has(file):
		_pending = {"file": file, "looping": looping, "stream": _streams[file]}
		_finish_load()
		return
	if _task >= 0:
		return
	var bytes: PackedByteArray = _read.call(file)
	if bytes.is_empty():
		return
	var seconds := LOOP_SECONDS if OS.has_feature("threads") else LOOP_SECONDS_NO_THREADS
	_pending = {"file": file, "looping": looping, "bytes": bytes, "seconds": seconds if looping else 8.0}
	if OS.has_feature("threads"):
		_task = WorkerThreadPool.add_task(_decode_pending)
	else:
		_decode_pending()
		_finish_load()


func _decode_pending() -> void:
	var stream := decode_clip(_pending.bytes, _pending.seconds)
	if stream != null and _pending.looping:
		make_loop(stream, CROSSFADE_SECONDS)
	_pending.stream = stream


func _finish_load() -> void:
	var stream: AudioStreamWAV = _pending.get("stream")
	if stream == null:
		return
	_streams[_pending.file] = stream
	if _pending.looping:
		if _pending.file == _loop_file:
			_loop.stream = stream
			_loop.play()
	else:
		_one_shot.stream = stream
		_one_shot.play()
	_pending = {}


## The first `seconds` of a WAV (PCM or MS ADPCM) as a stream.
static func decode_clip(wav: PackedByteArray, seconds: float) -> AudioStreamWAV:
	# Find the data chunk and cut it short before decoding: the rate and
	# block size give how many bytes hold `seconds` of sound.
	var pos := 12
	var byte_rate := 0
	while pos + 8 <= wav.size():
		var id := wav.slice(pos, pos + 4).get_string_from_ascii()
		var size := wav.decode_u32(pos + 4)
		if id == "fmt " and pos + 20 <= wav.size():
			byte_rate = wav.decode_u32(pos + 16)
		elif id == "data":
			if byte_rate > 0:
				wav = wav.slice(0, mini(wav.size(), pos + 8 + int(byte_rate * seconds)))
			break
		pos += 8 + size + (size & 1)
	return SsfBank.wav_to_stream(wav)


## Crossfades the stream's last `seconds` into its start and makes it loop.
static func make_loop(stream: AudioStreamWAV, seconds: float) -> void:
	var data := stream.data
	var channels := 2 if stream.stereo else 1
	var frames := data.size() / (2 * channels)
	var fade := mini(int(seconds * stream.mix_rate), frames / 3)
	if fade < 2:
		return
	var keep := frames - fade
	for i in fade:
		var t := float(i) / fade
		for c in channels:
			var head := (i * channels + c) * 2
			var tail := ((keep + i) * channels + c) * 2
			var v := data.decode_s16(head) * t + data.decode_s16(tail) * (1.0 - t)
			data.encode_s16(head, clampi(roundi(v), -32768, 32767))
	data.resize(keep * channels * 2)
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = keep
