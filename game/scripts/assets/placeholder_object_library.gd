class_name PlaceholderObjectLibrary
extends ObjectLibrary
## Simple primitive trees standing in for the original object library, or
## photo-textured 3D trees (TreeFactory) when the graphics settings ask.

var _trunk_mesh: CylinderMesh
var _pine_mesh: CylinderMesh
var _broadleaf_mesh: SphereMesh


func _init() -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.25, 0.15)
	_trunk_mesh = CylinderMesh.new()
	_trunk_mesh.top_radius = 0.18
	_trunk_mesh.bottom_radius = 0.28
	_trunk_mesh.height = 4.0
	_trunk_mesh.radial_segments = 8
	_trunk_mesh.material = bark

	var needles := StandardMaterial3D.new()
	needles.albedo_color = Color(0.10, 0.30, 0.14)
	_pine_mesh = CylinderMesh.new()
	_pine_mesh.top_radius = 0.0
	_pine_mesh.bottom_radius = 3.2
	_pine_mesh.height = 9.0
	_pine_mesh.radial_segments = 10
	_pine_mesh.material = needles

	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.20, 0.40, 0.15)
	_broadleaf_mesh = SphereMesh.new()
	_broadleaf_mesh.radius = 4.0
	_broadleaf_mesh.height = 7.0
	_broadleaf_mesh.radial_segments = 12
	_broadleaf_mesh.rings = 6
	_broadleaf_mesh.material = leaves


func instantiate(id: String) -> Node3D:
	if TreeFactory.enabled():
		match id:
			"tree_pine":
				return TreeFactory.instance(TreeFactory.Species.PINE)
			"tree_broadleaf":
				return TreeFactory.instance(TreeFactory.Species.BROADLEAF)
	var root := Node3D.new()
	root.name = id
	var trunk := MeshInstance3D.new()
	trunk.mesh = _trunk_mesh
	trunk.position.y = 2.0
	root.add_child(trunk)
	var crown := MeshInstance3D.new()
	match id:
		"tree_pine":
			crown.mesh = _pine_mesh
			crown.position.y = 7.0
		"tree_broadleaf":
			crown.mesh = _broadleaf_mesh
			crown.position.y = 6.5
		_:
			root.free()
			return null
	root.add_child(crown)
	return root
