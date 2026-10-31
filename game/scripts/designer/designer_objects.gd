class_name DesignerObjects
extends RefCounted
## What the course designer can place: the built-in trees and bush, plus every
## object in the player's own OBJECT.LIB (trees, bushes, buildings,
## grandstands, crowds...) when their game files are loaded. Courses store
## an object by its catalog file name and saves its measured size, so a
## course made with the game's objects shows them on any machine that has
## the game files; elsewhere it still plays the same, with built-in trees
## standing in for the game's trees.

const BUILT_IN := [["tree_pine", "Pine"], ["tree_broadleaf", "Broadleaf"], ["bush", "Bush"]]


## The player's decoded object library, or null without game files.
static func library() -> DecodedObjectLibrary:
	var lib := AssetProviders.object_library
	if lib is DecodedObjectLibrary:
		return lib
	if lib is ObjectLibraryChain and (lib as ObjectLibraryChain).primary is DecodedObjectLibrary:
		return (lib as ObjectLibraryChain).primary
	return null


## [{name: String, items: [[id, label], ...]}, ...]: the built-in trees
## first, then the catalog's own categories.
static func categories() -> Array:
	var out: Array = [{"name": "Basic trees and bushes", "items": BUILT_IN}]
	var lib := library()
	if lib == null:
		return out
	for cat: Dictionary in lib.catalog.categories:
		var items: Array = []
		for o: Dictionary in cat.objects:
			items.append([str(o.name), str(o.name).get_basename()])
		if not items.is_empty():
			out.append({"name": str(cat.name), "items": items})
	return out


## The measured size of a library object (from the node the library builds
## for it, at scale 1), plus how the ball treats it, as saved in a course's
## `object_info`: {kind, size: [x, y, z], centre: [x, y, z]}. `kind` is
## "model" for 3D objects; for billboards it follows the catalog's collision
## value: "tree" (0), "solid" (1) or "soft" (2, the ball passes through).
## Empty for built-in trees and for objects the player's files don't have.
static var _measured := {}


static func measure(id: String) -> Dictionary:
	if _measured.has(id):
		return _measured[id]
	if is_built_in(id):
		return {}
	var lib := library()
	if lib == null:
		return {}
	var o := lib.find(id)
	if o.is_empty():
		return {}
	var node := lib.instantiate(id)
	if node == null:
		return {}
	var box := _bounds(node, Transform3D.IDENTITY)
	node.free()
	if box.size == Vector3.ZERO:
		return {}
	var kind := "model"
	if int(o.kind) != ObjectCatalog.KIND_MODEL:
		kind = ["tree", "solid", "soft"][clampi(int(o.collision), 0, 2)]
	var c := box.get_center()
	var d := {"kind": kind, "size": [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)],
		"centre": [snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)]}
	_measured[id] = d
	return d


static func is_built_in(id: String) -> bool:
	for item: Array in BUILT_IN:
		if item[0] == id:
			return true
	return false


## What's known about `id`: measured now if the player's files have it,
## otherwise what the course saved (`saved` is its object_info).
static func info_for(id: String, saved: Dictionary) -> Dictionary:
	var m := measure(id)
	if not m.is_empty():
		return m
	var s: Variant = saved.get(id, {})
	return s if s is Dictionary else {}


## The object to draw for `o`: itself when it can be drawn here, a built-in
## tree of about the same height for a library tree the player's files
## don't have, or null for anything else they don't have.
static func stand_in(o: PlacedObject, saved: Dictionary) -> PlacedObject:
	var copy := PlacedObject.new(o.id, o.position, o.yaw_deg, o.scale)
	if is_built_in(o.id) or not measure(o.id).is_empty():
		return copy
	var info := info_for(o.id, saved)
	if str(info.get("kind", "")) != "tree":
		return null
	var size: Array = info.get("size", [0, 10, 0])
	copy.id = "tree_broadleaf"
	copy.scale = o.scale * clampf(float(size[1]) / 10.0, 0.2, 4.0)
	return copy


## Adds what the ball can hit for object `o` standing on ground height `y`.
## Built-in trees match the placeholder tree meshes. Library objects use
## their measured size (`saved` is the course's object_info, for objects the
## player's files don't have): models are a box the size of the model, trees
## a trunk and a canopy, solid billboards a column, soft ones nothing.
static func add_obstacles(field: ObstacleField, o: PlacedObject, y: float, saved := {}) -> void:
	var x := o.position.x
	var z := o.position.z
	var s := o.scale
	match o.id:
		"tree_pine":
			field.add_cylinder(x, z, 0.28 * s, y - 1.0, y + 3.0 * s, ObstacleField.Kind.SOLID)
			field.add_cylinder(x, z, 2.0 * s, y + 2.5 * s, y + 11.5 * s, ObstacleField.Kind.CANOPY)
			return
		"tree_broadleaf":
			field.add_cylinder(x, z, 0.28 * s, y - 1.0, y + 3.5 * s, ObstacleField.Kind.SOLID)
			field.add_cylinder(x, z, 3.2 * s, y + 3.0 * s, y + 10.0 * s, ObstacleField.Kind.CANOPY)
			return
		"bush":
			# Leaves to the ground: it slows the ball like a canopy.
			field.add_cylinder(x, z, 1.1 * s, y, y + 1.5 * s, ObstacleField.Kind.CANOPY)
			return
	var info := info_for(o.id, saved)
	if info.is_empty():
		field.add_cylinder(x, z, 0.3 * s, y - 1.0, y + 4.0 * s, ObstacleField.Kind.SOLID)
		return
	var size_a: Array = info.get("size", [1, 1, 1])
	var centre_a: Array = info.get("centre", [0, 0.5, 0])
	var size := Vector3(float(size_a[0]), float(size_a[1]), float(size_a[2])) * s
	var centre := Vector3(float(centre_a[0]), float(centre_a[1]), float(centre_a[2])) * s
	var w := maxf(size.x, size.z)
	var h := size.y
	match str(info.get("kind", "")):
		"model":
			var axes := Basis(Vector3.UP, deg_to_rad(o.yaw_deg))
			var half := (size * 0.5).max(Vector3.ONE * 0.1)
			field.add_box(Vector3(x, y, z) + axes * centre, axes, half, ObstacleField.Kind.SOLID)
		"tree":
			if h >= 1.5:
				field.add_cylinder(x, z, clampf(0.02 * h, 0.1, 0.45), y - 1.0, y + h * 0.4, ObstacleField.Kind.SOLID)
				field.add_cylinder(x, z, 0.4 * w, y + h * 0.35, y + h * 0.97, ObstacleField.Kind.CANOPY)
			elif h >= 0.5:
				field.add_cylinder(x, z, 0.4 * w, y - 0.5, y + h * 0.9, ObstacleField.Kind.CANOPY)
		"solid":
			field.add_cylinder(x, z, maxf(0.4 * w, 0.1), y - 1.0, y + h * 0.9, ObstacleField.Kind.SOLID)


## Bounds of every visual under `node`, in the frame `xf` puts it in.
static func _bounds(node: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var here := xf * (node as Node3D).transform if node is Node3D else xf
	if node is VisualInstance3D:
		var b := here * (node as VisualInstance3D).get_aabb()
		box = b
		first = false
	for child in node.get_children():
		var b := _bounds(child, here)
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return box
