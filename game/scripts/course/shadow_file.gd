class_name ShadowFile
extends RefCounted
## A course's `.SHA` shadow file: the shadow each billboard type (tree,
## bush) casts on the ground, seen from above. Ports
## libs/olcore/src/shadow_file.cpp; change both together. See
## docs/formats/sha.md.

const MAGIC := "VER5JDHSHADOW"
const NAME_OFFSET := 14
const NAME_SIZE := 256
const COUNTS_OFFSET := 0x11E
const HEADER_SIZE := 0x136
const SHAPE_SIZES: Array[int] = [32, 64, 128, 256]


## {course, course_size, model_count, billboard_type_count,
## model_placement_count, billboard_count, shapes}: per billboard type an
## Image (FORMAT_L8, 255 = full shadow) or null for types that cast none.
## Empty on error.
static func parse(d: PackedByteArray) -> Dictionary:
	if d.size() < HEADER_SIZE or d.slice(0, MAGIC.length()).get_string_from_ascii() != MAGIC or d[MAGIC.length()] != 0:
		return {}
	var out := {
		"course": d.slice(NAME_OFFSET, NAME_OFFSET + NAME_SIZE).get_string_from_ascii(),
		"course_size": d.decode_u32(0x10E),
		"model_count": d.decode_u32(COUNTS_OFFSET),
		"billboard_type_count": d.decode_u32(COUNTS_OFFSET + 4),
		"model_placement_count": d.decode_u32(COUNTS_OFFSET + 8),
		"billboard_count": d.decode_u32(COUNTS_OFFSET + 12),
	}
	var types: int = out.billboard_type_count
	var lw := d.decode_u32(COUNTS_OFFSET + 16)
	var lh := d.decode_u32(COUNTS_OFFSET + 20)
	# One light map per model, then sections not decoded yet, then the
	# shapes. Their start isn't stored: it is the first run of `types`
	# valid shape records, where types without a shadow (0 x 0) may come
	# first.
	var models: int = out.model_count
	var at := HEADER_SIZE + models * lw * lh
	if types == 0 or at > d.size():
		return {}
	var start := -1
	while at + 8 <= d.size():
		var w := d.decode_u32(at)
		if w in SHAPE_SIZES and d.decode_u32(at + 4) == w:
			var empty := types - _walk(d, at, types)
			if at >= HEADER_SIZE + empty * 8:
				var zeros := true
				for i in range(at - empty * 8, at):
					if d[i] != 0:
						zeros = false
						break
				if zeros:
					start = at - empty * 8
					break
		at += 4
	if start < 0:
		return {}
	var shapes: Array = []
	var o := start
	for _t in types:
		var w := d.decode_u32(o)
		var h := d.decode_u32(o + 4)
		o += 8
		if w == 0 or h == 0:
			shapes.append(null)
			continue
		shapes.append(Image.create_from_data(w, h, false, Image.FORMAT_L8, d.slice(o, o + w * h)))
		o += w * h
	out.shapes = shapes
	return out


## How many valid shape records (up to `limit`) start at `at`.
static func _walk(d: PackedByteArray, at: int, limit: int) -> int:
	var n := 0
	while n < limit and at + 8 <= d.size():
		var w := d.decode_u32(at)
		var h := d.decode_u32(at + 4)
		if w != h or (w != 0 and not w in SHAPE_SIZES) or at + 8 + w * h > d.size():
			break
		at += 8 + w * h
		n += 1
	return n
