class_name DesignerObjects
extends RefCounted
## What the course designer can place: the two built-in trees, plus every
## object in the player's own OBJECT.LIB (trees, bushes, buildings,
## grandstands, crowds...) when their game files are loaded. Courses store
## an object by its catalog file name, so a course made with the game's
## objects shows them on any machine that has the game files, and nothing
## (but still plays) on one that doesn't.

const BUILT_IN := [["tree_pine", "Pine"], ["tree_broadleaf", "Broadleaf"]]


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
	var out: Array = [{"name": "Basic trees", "items": BUILT_IN}]
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


## Adds what the ball can hit for object `o` standing on ground height `y`.
## Built-in trees match the placeholder tree meshes; catalog models are
## solid, catalog billboards get a trunk and a canopy like course plants.
## Sizes for catalog objects are guesses from their height.
static func add_obstacles(field: ObstacleField, o: PlacedObject, y: float) -> void:
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
	var lib := library()
	var info: Dictionary = lib.find(o.id) if lib != null else {}
	if info.is_empty():
		field.add_cylinder(x, z, 0.3 * s, y - 1.0, y + 4.0 * s, ObstacleField.Kind.SOLID)
		return
	var h := lib.height_m(o.id) * s
	if h < 0.5:
		return
	if int(info.kind) == ObjectCatalog.KIND_MODEL:
		field.add_cylinder(x, z, clampf(0.3 * h, 0.5, 8.0), y - 1.0, y + h, ObstacleField.Kind.SOLID)
	elif h >= 1.5:
		field.add_cylinder(x, z, clampf(0.02 * h, 0.1, 0.45), y - 1.0, y + h * 0.4, ObstacleField.Kind.SOLID)
		field.add_cylinder(x, z, 0.25 * h, y + h * 0.35, y + h * 0.97, ObstacleField.Kind.CANOPY)
	else:
		field.add_cylinder(x, z, 0.3 * h, y - 0.5, y + h * 0.9, ObstacleField.Kind.CANOPY)
