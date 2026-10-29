class_name ObjectLibrary
extends RefCounted
## Makes the scene node for a placed object (tree, building, crowd). The
## OBJECT.LIB decoder plugs in here: subclass this and register it with
## AssetProviders.object_library.


## Returns a new node for `id`, or null if the library has no such object.
## The node's origin is the object's base; the caller positions it.
func instantiate(_id: String) -> Node3D:
	return null
