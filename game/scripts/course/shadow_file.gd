class_name ShadowFile
extends RefCounted
## A course's `.SHA` shadow file: the ground shadow of each 3D object and
## each billboard type (tree, bush) seen from above, and how much light
## reaches each billboard. Ports libs/olcore/src/shadow_file.cpp; change
## both together. See docs/formats/sha.md.

const MAGIC := "VER5JDHSHADOW"
const NAME_OFFSET := 14
const NAME_SIZE := 256
const COUNTS_OFFSET := 0x11A
const MAX_SHAPE_SIDE := 4096


## {course, course_size, stamp, model_count, billboard_type_count,
## model_placement_count, billboard_count, object_shapes, billboard_light,
## shapes}: per 3D object mesh and per billboard type an Image (FORMAT_L8,
## more = more shadow) or null for none; billboard_light holds per 2DPlant
## placement how much light reaches it (1 = in the open). With
## `with_cells`, also placement_cells and billboard_cells: {start, cells}
## (PackedInt32Arrays; caster i's RayEngine cells are cells[start[i] ..
## start[i + 1])). Empty on error.
static func parse(d: PackedByteArray, with_cells := false) -> Dictionary:
	if d.size() < COUNTS_OFFSET + 20 or d.slice(0, MAGIC.length()).get_string_from_ascii() != MAGIC or d[MAGIC.length()] != 0:
		return {}
	var out := {
		"course": d.slice(NAME_OFFSET, NAME_OFFSET + NAME_SIZE).get_string_from_ascii(),
		"course_size": d.decode_u32(0x10E),
		"stamp": d.decode_u32(COUNTS_OFFSET),
		"model_count": d.decode_u32(COUNTS_OFFSET + 4),
		"billboard_type_count": d.decode_u32(COUNTS_OFFSET + 8),
		"model_placement_count": d.decode_u32(COUNTS_OFFSET + 12),
		"billboard_count": d.decode_u32(COUNTS_OFFSET + 16),
	}
	var at := [COUNTS_OFFSET + 20]  # read position, shared with the helpers
	var places: int = out.model_placement_count
	var billboards: int = out.billboard_count
	if 8 * billboards > d.size() or 4 * places > d.size():
		return {}
	var objects: Variant = _shapes(d, at, out.model_count)
	if objects == null:
		return {}
	var placement_cells: Variant = _cells(d, at, places, with_cells)
	if placement_cells == null or at[0] + 4 * billboards > d.size():
		return {}
	var light := d.slice(at[0], at[0] + 4 * billboards).to_float32_array()
	at[0] += 4 * billboards
	var shapes: Variant = _shapes(d, at, out.billboard_type_count)
	if shapes == null:
		return {}
	var billboard_cells: Variant = _cells(d, at, billboards, with_cells)
	if billboard_cells == null or at[0] != d.size():
		return {}
	out.object_shapes = objects
	out.billboard_light = light
	out.shapes = shapes
	if with_cells:
		out.placement_cells = placement_cells
		out.billboard_cells = billboard_cells
	return out


## `count` shape records from at[0]: an Image or null each. Null on error.
static func _shapes(d: PackedByteArray, at: Array, count: int) -> Variant:
	var out: Array = []
	var o: int = at[0]
	for _i in count:
		if o + 8 > d.size():
			return null
		var w := d.decode_u32(o)
		var h := d.decode_u32(o + 4)
		o += 8
		if w > MAX_SHAPE_SIDE or h > MAX_SHAPE_SIDE or o + w * h > d.size():
			return null
		if w == 0 or h == 0:
			out.append(null)
			continue
		out.append(Image.create_from_data(w, h, false, Image.FORMAT_L8, d.slice(o, o + w * h)))
		o += w * h
	at[0] = o
	return out


## `count` list lengths, then the lists (byte offsets into a table of
## 8-byte cells). Returns {start, cells} when `keep`, else {} (the lists
## are only skipped). Null on error.
static func _cells(d: PackedByteArray, at: Array, count: int, keep: bool) -> Variant:
	var o: int = at[0]
	if o + 4 * count > d.size():
		return null
	var lengths := d.slice(o, o + 4 * count).to_int32_array()
	o += 4 * count
	var start := PackedInt32Array()
	start.resize(count + 1)
	var total := 0
	for i in count:
		start[i] = total
		total += lengths[i]
		if lengths[i] < 0 or o + 4 * total > d.size():
			return null
	start[count] = total
	var out := {}
	if keep:
		var cells := d.slice(o, o + 4 * total).to_int32_array()
		for i in cells.size():
			cells[i] = cells[i] >> 3
		out = {"start": start, "cells": cells}
	at[0] = o + 4 * total
	return out
