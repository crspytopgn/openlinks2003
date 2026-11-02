extends SceneTree
## Dumps a Microsoft Rocketbox avatar (FBX) for tools/golfer/rocketbox.py:
## each skinned surface's vertices, normals, uvs, triangles, bones and
## weights, in the scene's world frame (+y up, metres), plus every bone's
## world rest position and parent, as JSON and raw little-endian arrays.
##
##   godot --headless --path game -s res://../tools/golfer/rocketbox_dump.gd -- in.fbx out_prefix
## (writes out_prefix.json and out_prefix.bin)

var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var doc := FBXDocument.new()
	var state := FBXState.new()
	var err := doc.append_from_file(args[0], state)
	if err != OK:
		printerr("cannot read ", args[0], ": ", err)
		quit(1)
		return
	_scene = doc.generate_scene(state)
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	var scene := _scene
	var out := {"bones": [], "surfaces": []}
	var blob := PackedByteArray()
	var skel: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var sk_world := skel.global_transform
	for i in skel.get_bone_count():
		var rest := sk_world * skel.get_bone_global_rest(i)
		out.bones.append({"name": skel.get_bone_name(i), "parent": skel.get_bone_parent(i),
			"origin": [rest.origin.x, rest.origin.y, rest.origin.z],
			"basis": [rest.basis.x.x, rest.basis.x.y, rest.basis.x.z, rest.basis.y.x, rest.basis.y.y, rest.basis.y.z, rest.basis.z.x, rest.basis.z.y, rest.basis.z.z]})
	for node in scene.find_children("*", "ImporterMeshInstance3D", true, false):
		var mi := node as ImporterMeshInstance3D
		var skin := mi.skin
		# Bind index -> skeleton bone index.
		var bind_bone := PackedInt32Array()
		for b in skin.get_bind_count():
			var bn := skin.get_bind_name(b)
			bind_bone.append(skel.find_bone(bn) if bn != "" else skin.get_bind_bone(b))
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.get_surface_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var per := bones.size() / verts.size()
			# Rest-pose world positions: skin with the bind poses at rest.
			var pos := PackedFloat32Array()
			var nrm := PackedFloat32Array()
			for v in verts.size():
				var p := Vector3.ZERO
				var n := Vector3.ZERO
				var wsum := 0.0
				for k in per:
					var w := weights[v * per + k]
					if w <= 0.0:
						continue
					var b := bones[v * per + k]
					var t := sk_world * skel.get_bone_global_rest(bind_bone[b]) * skin.get_bind_pose(b)
					p += (t * verts[v]) * w
					n += (t.basis * norms[v]) * w
					wsum += w
				if wsum > 0.0:
					p /= wsum
				else:
					p = mi.global_transform * verts[v]
					n = mi.global_transform.basis * norms[v]
				n = n.normalized()
				pos.append_array([p.x, p.y, p.z])
				nrm.append_array([n.x, n.y, n.z])
			var sb := PackedInt32Array()
			for k in bones.size():
				sb.append(bind_bone[bones[k]])
			var mat := mi.mesh.get_surface_material(s)
			var entry := {"material": mat.resource_name if mat != null else "", "count": verts.size(), "per": per}
			for pair: Array in [["positions", pos.to_byte_array()], ["normals", nrm.to_byte_array()],
					["uvs", uvs.to_byte_array()], ["bones", sb.to_byte_array()], ["weights", weights.to_byte_array()],
					["indices", idx.to_byte_array()]]:
				entry[pair[0]] = [blob.size(), (pair[1] as PackedByteArray).size()]
				blob.append_array(pair[1])
			out.surfaces.append(entry)
	var f := FileAccess.open(args[1] + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	f = FileAccess.open(args[1] + ".bin", FileAccess.WRITE)
	f.store_buffer(blob)
	f.close()
	print("dumped ", out.surfaces.size(), " surfaces, ", out.bones.size(), " bones")
	quit(0)
	return true
