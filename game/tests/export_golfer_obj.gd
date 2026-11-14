extends SceneTree
# Writes the default golfer, in his rest pose, as OBJ + MTL + PNG textures
# (for Mixamo's auto-rigger): godot --headless --path game -s res://tests/export_golfer_obj.gd -- OUT_DIR

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var g := FreeGolfer.create(PlayerLook.default_look())
	get_root().add_child(g)
	await process_frame
	await process_frame
	for sk in g.find_children("*", "Skeleton3D", true, false):
		(sk as Skeleton3D).reset_bone_poses()
	for ap in g.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	await process_frame
	# T-pose: each arm straight out to its side, palms down.
	for sk in g.find_children("*", "Skeleton3D", true, false):
		_t_pose(sk as Skeleton3D)
	# Twist and half bones (GolferTwist) follow in the modifier pass.
	for i in 3:
		await process_frame
	var obj := "mtllib golfer.mtl\n"
	var mtl := ""
	var base := 1
	var k := 0
	for node in g.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var low := String(mi.name).to_lower()
		if low.contains("club") or low.contains("driver") or low.contains("iron") or low.contains("putter") or low.contains("wedge") or low.contains("wood") or low.contains("bag") or low.contains("ball") or low.contains("tee"):
			continue
		var xf := mi.global_transform
		var sk3 := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if sk3 != null and mi.skin != null and arr[Mesh.ARRAY_BONES] != null:
				v = _skinned(v, arr, mi.skin, sk3, xf)
			var uv = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			var mat := mi.get_active_material(s)
			var name := "m%d" % k
			k += 1
			mtl += "newmtl %s\n" % name
			var tex: Texture2D = null
			if mat is BaseMaterial3D:
				tex = (mat as BaseMaterial3D).albedo_texture
			elif mat is ShaderMaterial:
				for pr in RenderingServer.get_shader_parameter_list((mat as ShaderMaterial).shader.get_rid()):
					var val = (mat as ShaderMaterial).get_shader_parameter(pr["name"])
					if val is Texture2D and (tex == null or String(pr["name"]).contains("albedo")):
						tex = val
			if tex != null:
				var img := tex.get_image()
				if img != null:
					if img.is_compressed():
						img.decompress()
					img.save_png(out.path_join(name + ".png"))
					mtl += "map_Kd %s.png\n" % name
				mtl += "Kd 1 1 1\n"
			obj += "o %s_%d\nusemtl %s\n" % [mi.name, s, name]
			for p in v:
				var w := xf * p
				obj += "v %f %f %f\n" % [w.x, w.y, w.z]
			if uv != null:
				for t in (uv as PackedVector2Array):
					obj += "vt %f %f\n" % [t.x, 1.0 - t.y]
			if idx == null:
				idx = PackedInt32Array(range(v.size()))
			var ii: PackedInt32Array = idx
			for f in range(0, ii.size(), 3):
				var a := ii[f] + base
				var b := ii[f + 2] + base
				var c2 := ii[f + 1] + base
				obj += "f %d/%d %d/%d %d/%d\n" % [a, a, b, b, c2, c2]
			base += v.size()
	var fo := FileAccess.open(out.path_join("golfer.obj"), FileAccess.WRITE)
	fo.store_string(obj)
	fo.close()
	var fm := FileAccess.open(out.path_join("golfer.mtl"), FileAccess.WRITE)
	fm.store_string(mtl)
	fm.close()
	print("exported ", k, " surfaces")
	quit()


func _t_pose(sk: Skeleton3D) -> void:
	for side in ["l", "r"]:
		var ux := sk.get_bone_global_pose(sk.find_bone("upperarm_" + side)).origin.x
		var out := Vector3(signf(ux), 0, 0)
		for bone in ["upperarm_", "lowerarm_", "hand_"]:
			var b := sk.find_bone(bone + side)
			var child := sk.find_bone({"upperarm_": "lowerarm_", "lowerarm_": "hand_", "hand_": "middle_01_"}[bone] + side)
			if b < 0 or child < 0:
				continue
			sk.force_update_all_bone_transforms()
			var gb := sk.get_bone_global_pose(b)
			var dir := (sk.get_bone_global_pose(child).origin - gb.origin).normalized()
			var turn := Quaternion(dir, out)
			var pg := sk.get_bone_global_pose(sk.get_bone_parent(b)).basis.get_rotation_quaternion()
			var new_global := turn * gb.basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(b, pg.inverse() * new_global)


func _skinned(v: PackedVector3Array, arr: Array, skin: Skin, sk: Skeleton3D, xf: Transform3D) -> PackedVector3Array:
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / v.size()
	var mats: Array[Transform3D] = []
	for i in skin.get_bind_count():
		var bi := skin.get_bind_bone(i)
		if bi < 0:
			bi = sk.find_bone(skin.get_bind_name(i))
		mats.append(sk.get_bone_global_pose(bi) * skin.get_bind_pose(i))
	var out := PackedVector3Array()
	out.resize(v.size())
	var to_local := xf.affine_inverse() * sk.global_transform
	for i in v.size():
		var p := Vector3.ZERO
		for k in per:
			var w := weights[i * per + k]
			if w > 0.0:
				p += w * (mats[bones[i * per + k]] * v[i])
		out[i] = to_local * p
	return out
