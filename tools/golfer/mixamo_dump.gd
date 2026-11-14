# Dumps a Mixamo FBX animation to JSON for mixamo_take.py:
#   godot --headless -s mixamo_dump.gd -- in.fbx out.json
# (run from any Godot project; Godot 4.3+ reads FBX itself)
extends SceneTree
func _init():
	call_deferred("_run")


func _run():
	var args := OS.get_cmdline_user_args()
	var doc := FBXDocument.new()
	var st := FBXState.new()
	var err := doc.append_from_file(args[0], st)
	if err != OK:
		print("ERR ", err); quit(); return
	var root: Node = doc.generate_scene(st)
	get_root().add_child(root)
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var names := ap.get_animation_list()
	print("anims ", names)
	var pick: String = names[0]
	for a in names:
		print(a, " ", ap.get_animation(a).length, " tracks ", ap.get_animation(a).get_track_count())
		if ap.get_animation(a).get_track_count() > ap.get_animation(pick).get_track_count():
			pick = a
	var anim := ap.get_animation(pick)
	var chain := Transform3D()
	var nd: Node = sk
	while nd != null and nd != root:
		if nd is Node3D:
			chain = (nd as Node3D).transform * chain
		nd = nd.get_parent()
	print("chain ", chain)
	print("length ", anim.length, " step ", anim.step)
	var fps := 30.0
	var n := int(round(anim.length * fps)) + 1
	var bones := []
	for b in sk.get_bone_count():
		bones.append(sk.get_bone_name(b))
	var parents := []
	for b in sk.get_bone_count():
		parents.append(sk.get_bone_parent(b))
	ap.play(pick)
	var frames := []
	for f in n:
		ap.seek(f / fps, true)
		sk.force_update_all_bone_transforms()
		var fr := []
		for b in sk.get_bone_count():
			var t: Transform3D = chain * sk.get_bone_global_pose(b)
			var bs := t.basis
			fr.append([bs.x.x, bs.x.y, bs.x.z, bs.y.x, bs.y.y, bs.y.z, bs.z.x, bs.z.y, bs.z.z, t.origin.x, t.origin.y, t.origin.z])
		frames.append(fr)
	var out := {"fps": fps, "bones": bones, "parents": parents, "frames": frames}
	var fa := FileAccess.open(args[1], FileAccess.WRITE)
	fa.store_string(JSON.stringify(out))
	fa.close()
	print("frames ", n, " bones ", bones.size())
	quit()
