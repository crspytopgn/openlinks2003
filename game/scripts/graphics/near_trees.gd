class_name NearTrees
extends MultiMeshInstance3D
## The full meshes of one scanned tree variant, near the camera only.
##
## A MultiMesh draws every instance it holds, even those its shader folds
## away past the lite distance, so a course's full scans are not left in
## cells: this node keeps all their transforms and, whenever the camera has
## moved a few metres, writes just the trees within reach of it into the
## first slots and draws only those (visible_instance_count). One node per
## variant, in place of thousands of small cells.

const MOVE := 4.0  ## metres the camera moves before the set is refilled
const MARGIN := 20.0  ## metres past the lite distance a tree's base may be

var transforms: Array[Transform3D] = []  ## every tree, in this node's space
var _last := Vector3(INF, INF, INF)


func _init(mm: MultiMesh = null, all: Array[Transform3D] = []) -> void:
	name = "NearTrees"
	multimesh = mm
	transforms = all
	if mm != null:
		mm.visible_instance_count = 0


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or multimesh == null:
		return
	var at := to_local(camera.global_position)
	if at.distance_squared_to(_last) < MOVE * MOVE:
		return
	refill(at)


## Puts the trees within reach of `at` (this node's space) first and draws
## only those. Returns how many.
func refill(at: Vector3) -> int:
	_last = at
	var reach := TreeFactory.lite_distance() + MARGIN + MOVE
	var r2 := reach * reach
	var k := 0
	for t in transforms:
		var dx := t.origin.x - at.x
		var dz := t.origin.z - at.z
		if dx * dx + dz * dz <= r2:
			multimesh.set_instance_transform(k, t)
			k += 1
	multimesh.visible_instance_count = k
	return k
