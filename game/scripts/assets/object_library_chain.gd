class_name ObjectLibraryChain
extends ObjectLibrary
## Tries a primary library first, then a fallback. `aliases` renames ids on
## the way to the primary, so placeholder courses (which ask for "tree_pine")
## can show real trees from the player's object library.

var primary: ObjectLibrary
var fallback: ObjectLibrary
var aliases := {}


func _init(p_primary: ObjectLibrary, p_fallback: ObjectLibrary, p_aliases := {}) -> void:
	primary = p_primary
	fallback = p_fallback
	aliases = p_aliases


func instantiate(id: String) -> Node3D:
	var node := primary.instantiate(aliases.get(id, id))
	if node == null and fallback != null:
		node = fallback.instantiate(id)
	return node


## Aliases for the placeholder tree ids: the first catalog objects whose names
## look like a pine and a broadleaf tree.
static func tree_aliases(lib: DecodedObjectLibrary) -> Dictionary:
	var out := {}
	for cat in lib.catalog.categories:
		for o: Dictionary in cat["objects"]:
			var n := (o.name as String).to_lower()
			if not out.has("tree_pine") and n.contains("pine"):
				out["tree_pine"] = o.name
			elif not out.has("tree_broadleaf") and (n.contains("oak") or n.contains("maple") or n.contains("tree")) and not n.contains("pine"):
				out["tree_broadleaf"] = o.name
	return out
