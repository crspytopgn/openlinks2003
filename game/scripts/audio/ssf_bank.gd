class_name SsfBank
extends RefCounted
## Reads a Links 2003 .SSF sound bank (docs/formats/ssf.md) and turns its
## waves into AudioStreamWAV resources.
##
## Temporary GDScript port of libs/olcore/src/ssf.cpp and wav.cpp so sounds
## play without a compiled extension. It will be replaced by the C++ library
## via GDExtension; keep the two in sync until then.

const FILE_HEADER_SIZE := 0x1c
const CHUNK_HEADER_SIZE := 16
const EVENT_NAME_BYTES := 64
const EVENT_MAX_WAVES := 50
const WAVE_FORMAT_PCM := 1
const WAVE_FORMAT_MS_ADPCM := 2
const ADPCM_ADAPTATION: Array[int] = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]

## Each event: {"name": String, "chance": int, "type": int, "waves": PackedInt32Array}
var events: Array[Dictionary] = []
var wave_names: PackedStringArray = PackedStringArray()

var _data: PackedByteArray
var _wave_offsets: PackedInt32Array = PackedInt32Array()
var _wave_sizes: PackedInt32Array = PackedInt32Array()
var _streams: Dictionary = {}


## Returns null if the file is missing or not an SSF bank.
static func load_file(path: String) -> SsfBank:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < FILE_HEADER_SIZE:
		return null
	var bank := SsfBank.new()
	if not bank._parse(bytes):
		return null
	return bank


func find_event(event_name: String) -> Dictionary:
	for e in events:
		if e["name"] == event_name:
			return e
	return {}


func wave_count() -> int:
	return _wave_offsets.size()


## A random take of the event, or null if it has none.
func random_stream(event_name: String) -> AudioStreamWAV:
	var e := find_event(event_name)
	var waves: PackedInt32Array = e.get("waves", PackedInt32Array())
	if waves.is_empty():
		return null
	return get_stream(waves[randi() % waves.size()])


func get_stream(index: int) -> AudioStreamWAV:
	if _streams.has(index):
		return _streams[index]
	var stream: AudioStreamWAV = null
	if index >= 0 and index < _wave_offsets.size() and _wave_sizes[index] > 0:
		stream = _wav_to_stream(_data.slice(_wave_offsets[index], _wave_offsets[index] + _wave_sizes[index]))
	_streams[index] = stream
	return stream


func _parse(bytes: PackedByteArray) -> bool:
	if bytes.slice(0, 4) != PackedByteArray([0x53, 0x53, 0x46, 0]):
		return false
	_data = bytes
	var event_count := bytes.decode_u32(0x14)
	var pos := FILE_HEADER_SIZE
	while pos + CHUNK_HEADER_SIZE <= bytes.size():
		var tag := bytes.slice(pos, pos + 4)
		var size := bytes.decode_u32(pos + 4)
		var body := pos + CHUNK_HEADER_SIZE
		if body + size > bytes.size():
			return false
		if tag == PackedByteArray([0x45, 0x56, 0x45, 0]):  # EVE
			var waves := PackedInt32Array()
			var count := mini(bytes.decode_u32(body + 0x58), EVENT_MAX_WAVES)
			for i in count:
				waves.append(bytes.decode_u16(body + 0x5c + i * 2))
			events.append({
				"name": _utf16(bytes, body + 4, EVENT_NAME_BYTES),
				"chance": bytes.decode_u32(body + 0x44),
				"type": bytes.decode_u32(body + 0x48),
				"waves": waves,
			})
		elif tag == PackedByteArray([0x57, 0x4e, 0x44, 0]):  # WND
			var p := body
			while p + 2 <= body + size:
				var start := p
				while p + 2 <= body + size and bytes.decode_u16(p) != 0:
					p += 2
				wave_names.append(bytes.slice(start, p).get_string_from_utf16())
				p += 2
		elif tag[0] == 0x57 and tag != PackedByteArray([0x57, 0x53, 0x54, 0]):  # W + index
			var index := tag[1] | (tag[2] << 8)
			if _wave_offsets.size() <= index:
				_wave_offsets.resize(index + 1)
				_wave_sizes.resize(index + 1)
			_wave_offsets[index] = body
			_wave_sizes[index] = size
		pos = body + size
	return events.size() == event_count


static func _utf16(bytes: PackedByteArray, offset: int, max_bytes: int) -> String:
	var end := offset
	while end + 2 <= offset + max_bytes and bytes.decode_u16(end) != 0:
		end += 2
	return bytes.slice(offset, end).get_string_from_utf16()


## Mirrors olcore::parse_wav and olcore::decode_pcm16.
static func _wav_to_stream(wav: PackedByteArray) -> AudioStreamWAV:
	if wav.size() < 12 or wav.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var format := 0
	var channels := 0
	var rate := 0
	var block_align := 0
	var bits := 0
	var samples_per_block := 0
	var coefficients := PackedInt32Array()
	var data_offset := -1
	var data_size := 0
	var pos := 12
	while pos + 8 <= wav.size():
		var id := wav.slice(pos, pos + 4).get_string_from_ascii()
		var size := wav.decode_u32(pos + 4)
		var body := pos + 8
		if id == "fmt " and body + 16 <= wav.size():
			format = wav.decode_u16(body)
			channels = wav.decode_u16(body + 2)
			rate = wav.decode_u32(body + 4)
			block_align = wav.decode_u16(body + 12)
			bits = wav.decode_u16(body + 14)
			if format == WAVE_FORMAT_MS_ADPCM and body + 22 <= wav.size():
				samples_per_block = wav.decode_u16(body + 18)
				var pairs := wav.decode_u16(body + 20)
				for i in pairs * 2:
					if body + 22 + i * 2 + 2 <= wav.size():
						coefficients.append(wav.decode_s16(body + 22 + i * 2))
		elif id == "data":
			data_offset = body
			data_size = mini(size, wav.size() - body)
		pos = body + size + (size & 1)
	if data_offset < 0 or channels < 1 or channels > 2:
		return null

	var pcm: PackedByteArray
	if format == WAVE_FORMAT_PCM and bits == 16:
		pcm = wav.slice(data_offset, data_offset + data_size)
	elif format == WAVE_FORMAT_MS_ADPCM and coefficients.size() >= 2 and block_align >= 7 * channels:
		pcm = _decode_ms_adpcm(wav, data_offset, data_size, channels, block_align, samples_per_block, coefficients)
	else:
		return null

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels == 2
	stream.data = pcm
	return stream


## Microsoft ADPCM to little-endian 16-bit PCM. Mirrors decode_ms_adpcm in
## libs/olcore/src/wav.cpp.
static func _decode_ms_adpcm(wav: PackedByteArray, offset: int, size: int, channels: int, block_align: int,
		samples_per_block: int, coefficients: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	var pairs := coefficients.size() / 2
	var coef1 := [0, 0]
	var coef2 := [0, 0]
	var delta := [0, 0]
	var s1 := [0, 0]
	var s2 := [0, 0]
	var block := 0
	while block + 7 * channels <= size:
		var p := offset + block
		var end := offset + mini(block + block_align, size)
		for c in channels:
			var pred: int = wav[p + c] if wav[p + c] < pairs else 0
			coef1[c] = coefficients[pred * 2]
			coef2[c] = coefficients[pred * 2 + 1]
			delta[c] = wav.decode_s16(p + channels + c * 2)
			s1[c] = wav.decode_s16(p + 3 * channels + c * 2)
			s2[c] = wav.decode_s16(p + 5 * channels + c * 2)
		var block_out := PackedByteArray()
		var limit := (samples_per_block - 2) * channels if samples_per_block > 0 else (end - p - 7 * channels) * 2
		block_out.resize((limit + 2 * channels) * 2)
		var n := 0
		for c in channels:
			block_out.encode_s16(n * 2, s2[c])
			n += 1
		for c in channels:
			block_out.encode_s16(n * 2, s1[c])
			n += 1
		var produced := 0
		var i := p + 7 * channels
		while i < end and produced < limit:
			for half in 2:
				if produced >= limit:
					break
				var c: int = half if channels == 2 else 0
				var nibble: int = (wav[i] >> 4) if half == 0 else (wav[i] & 0x0f)
				var signed_nibble: int = nibble - 16 if nibble >= 8 else nibble
				# Integer division truncates toward zero, like the C++ version.
				var predicted: int = (s1[c] * coef1[c] + s2[c] * coef2[c]) / 256
				var sample: int = clampi(predicted + signed_nibble * delta[c], -32768, 32767)
				s2[c] = s1[c]
				s1[c] = sample
				delta[c] = maxi((ADPCM_ADAPTATION[nibble] * delta[c]) >> 8, 16)
				block_out.encode_s16(n * 2, sample)
				n += 1
				produced += 1
			i += 1
		block_out.resize(n * 2)
		out.append_array(block_out)
		block += block_align
	return out
