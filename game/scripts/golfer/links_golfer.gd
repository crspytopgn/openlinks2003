class_name LinksGolfer
extends GolferRig
## A golfer from the player's own POLYANI/<golfer>.L3: the textured, skinned
## model driven by the original animation clips, holding the driver (or the
## putter on the green) from CLUBS.L3. Falls back to a stick figure of the
## skeleton if the model has no skinned mesh.
##
## Clip names and timings come from the archive's SCRIPT.TXT
## (docs/formats/golfer-script.md).

const FEET := 0.3048
const BALL_DISTANCE := 0.75  ## GolferRig puts the ball this far in front
const LIMB_RADIUS := 0.09  ## feet
const EVENT_TOP_OF_BACKSWING := 0

var _archive: LsArchiveFile
var _script := {}  ## section -> key -> value
var _nodes: Array[Dictionary] = []
var _index_by_hash := {}
var _clips := {}  ## clip name (upper case) -> clip dictionary, or {} if missing
var _body: Node3D
var _bones: Array[MeshInstance3D] = []
var _bone_nodes := PackedInt32Array()  ## child node per bone
var _head: MeshInstance3D
var _head_node := -1
var _meshes: Array[Dictionary] = []
var _skeleton: Skeleton3D
var _clubs := {}  ## "driver"/"putter" -> Node3D
var _textures := {}  ## file name (upper case) -> Texture2D or null

var _clip: Dictionary = {}
var _frame := 0.0
var _end_frame := 0.0
var _loop := false
var _then: Array[String] = []  ## clips to play after this one (the last loops)


## Null if the archive or its skeleton can't be read.
static func load_from(archive_path: String) -> LinksGolfer:
	var archive := LsArchiveFile.open(archive_path)
	if archive == null or not archive.has("SCRIPT.TXT"):
		return null
	var golfer := LinksGolfer.new()
	golfer._archive = archive
	golfer._script = parse_script(archive.read("SCRIPT.TXT").get_string_from_ascii())
	var skl: String = golfer._script.get("file_locations", {}).get("golfer.skl", "")
	if skl.is_empty() or not archive.has(skl):
		return null
	var skl_bytes := archive.read(skl)
	golfer._nodes = GolferAnimData.read_skeleton(skl_bytes)
	if golfer._nodes.is_empty():
		return null
	golfer._meshes = GolferAnimData.read_meshes(skl_bytes)
	golfer._build()
	golfer._build_clubs(archive_path.get_base_dir())
	return golfer


## INI-style sections with ';' comments; keys are kept as written.
static func parse_script(text: String) -> Dictionary:
	var sections := {}
	var current := {}
	for raw in text.split("\n"):
		var line := raw.split(";")[0].strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			current = {}
			sections[line.substr(1, line.length() - 2)] = current
		elif line.contains("="):
			var kv := line.split("=", true, 1)
			current[kv[0].strip_edges()] = kv[1].strip_edges()
	return sections


## "DriverSwing( 0@29 1@32 2@46),IronHalfSwing( 2@42)" ->
## [{"clip": "DriverSwing", "events": {0: 29, 1: 32, 2: 46}}, ...]
static func parse_clip_list(value: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var re := RegEx.create_from_string("([A-Za-z0-9_]+)\\s*(?:\\(([^)]*)\\))?")
	for m in re.search_all(value):
		var events := {}
		for ev in m.get_string(2).split(" ", false):
			var parts := ev.split("@")
			if parts.size() == 2:
				events[int(parts[0])] = int(parts[1])
		result.append({"clip": m.get_string(1), "events": events})
	return result


func play(animation: StringName) -> void:
	var shot := "Putter" if animation == &"putt" else "Driver"
	_show_club("putter" if animation == &"putt" else "driver")
	var section: Dictionary = _script.get(shot, {})
	var swing := parse_clip_list(section.get("Swing", ""))
	match animation:
		&"address":
			var idle := parse_clip_list(section.get("PreSwing", ""))
			_start(section.get("Address", ""), 0, -1, [idle[0]["clip"]] if not idle.is_empty() else [])
		&"backswing":
			if not swing.is_empty():
				var top: int = swing[0]["events"].get(EVENT_TOP_OF_BACKSWING, -1)
				_start(swing[0]["clip"], 0, top, [])
		&"swing":
			if not swing.is_empty():
				var top: int = swing[0]["events"].get(EVENT_TOP_OF_BACKSWING, 0)
				var from := _frame if _clip_is(swing[0]["clip"]) else float(top)
				_start(swing[0]["clip"], from, -1, [section.get("FinishBreath", "")])
		&"putt":
			if not swing.is_empty():
				_start(swing[0]["clip"], 0, -1, [section.get("FinishBreath", "")])
		&"celebrate":
			for r in parse_clip_list(section.get("PostFlightReactions", "")):
				if "InHole" in r["clip"]:
					_start(r["clip"], 0, -1, [section.get("NeutralBreath", "")])
					break


func _clip_is(clip_name: String) -> bool:
	return not _clip.is_empty() and str(_clip["name"]).to_upper() == clip_name.to_upper()


func _load_clip(clip_name: String) -> Dictionary:
	var key := clip_name.to_upper()
	if not _clips.has(key):
		var bytes := _archive.read(key + ".CLP") if _archive else PackedByteArray()
		_clips[key] = GolferAnimData.read_clip(bytes) if not bytes.is_empty() else {}
	return _clips[key]


## Plays frames [from, to] of a clip (to = -1: the last frame), then the
## clips in `then` in turn, looping the last one.
func _start(clip_name: String, from: float, to: int, then: Array) -> void:
	var clip := _load_clip(clip_name)
	if clip.is_empty():
		return
	_clip = clip
	_frame = from
	_end_frame = float(clip["frames"] - 1 if to < 0 else mini(to, clip["frames"] - 1))
	_loop = false
	_then.clear()
	for c in then:
		if not str(c).is_empty():
			_then.append(str(c))
	_apply_pose()


func _process(delta: float) -> void:
	if _clip.is_empty():
		return
	_frame += delta * GolferAnimData.FRAMES_PER_SECOND
	if _frame >= _end_frame:
		if _loop:
			_frame = fmod(_frame, maxf(_end_frame, 1.0))
		elif not _then.is_empty():
			var next: String = _then.pop_front()
			var clip := _load_clip(next)
			if not clip.is_empty():
				_clip = clip
				_frame = 0.0
				_end_frame = float(clip["frames"] - 1)
				_loop = _then.is_empty()
		else:
			_frame = _end_frame
	_apply_pose()


func _build() -> void:
	for i in _nodes.size():
		_index_by_hash[_nodes[i]["hash"]] = i
	# Clip space is feet with the ball at the origin and the golfer facing +x
	# with the target towards -z; GolferRig wants metres, facing -z, target -x.
	_body = Node3D.new()
	_body.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)).scaled(Vector3.ONE * FEET),
			Vector3(0, 0, -BALL_DISTANCE))
	add_child(_body)
	if _has_skinned_mesh():
		_build_model()
	else:
		_build_stick_figure()
	_apply_pose()


func _has_skinned_mesh() -> bool:
	for m in _meshes:
		var bones: PackedInt32Array = m["bones"]
		if not bones.is_empty():
			return true
	return false


## The skeleton as a Skeleton3D with the skinned meshes under it.
func _build_model() -> void:
	_skeleton = Skeleton3D.new()
	_body.add_child(_skeleton)
	var first_bone := {}  ## node name -> bone index
	for i in _nodes.size():
		var n := _nodes[i]
		var bone_name := "%s#%d" % [n["name"], i] if first_bone.has(n["name"]) else str(n["name"])
		_skeleton.add_bone(bone_name)
		if not first_bone.has(n["name"]):
			first_bone[n["name"]] = i
		if int(n["parent"]) >= 0:
			_skeleton.set_bone_parent(i, n["parent"])
		_skeleton.set_bone_rest(i, GolferAnimData.local_transform(n, n["rotate"], n["translate"]))
	for m in _meshes:
		var bones: PackedInt32Array = m["bones"]
		var instance := MeshInstance3D.new()
		instance.mesh = _array_mesh(m, _archive)
		if bones.is_empty():
			# A rigid part rides on the transform named by the mesh.
			var attach := BoneAttachment3D.new()
			_skeleton.add_child(attach)
			attach.bone_idx = first_bone.get(m["transform"], 0)
			attach.add_child(instance)
			continue
		var skin := Skin.new()
		var names: PackedStringArray = m["skin_joints"]
		var binds: Array[Transform3D] = m["inverse_bind"]
		for j in names.size():
			skin.add_bind(first_bone.get(names[j], 0), binds[j] if first_bone.has(names[j]) else Transform3D.IDENTITY)
		instance.skin = skin
		_skeleton.add_child(instance)
		instance.skeleton = NodePath("..")


## One surface per mesh part, holding just that part's vertex range.
func _array_mesh(m: Dictionary, archive: LsArchiveFile) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var positions: PackedVector3Array = m["positions"]
	var normals: PackedVector3Array = m["normals"]
	var uvs: PackedVector2Array = m["uvs"]
	var bones: PackedInt32Array = m["bones"]
	var weights: PackedFloat32Array = m["weights"]
	for part in m["parts"]:
		var first: int = part["first_vertex"]
		var last: int = mini(part["last_vertex"], positions.size() - 1)
		var indices := GolferAnimData.strip_to_triangles(part["strip"], 0)
		if indices.is_empty() or last < first:
			continue
		var flipped_uvs := PackedVector2Array()
		for v in range(first, last + 1):
			flipped_uvs.append(Vector2(uvs[v].x, 1.0 - uvs[v].y))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions.slice(first, last + 1)
		arrays[Mesh.ARRAY_NORMAL] = normals.slice(first, last + 1)
		arrays[Mesh.ARRAY_TEX_UV] = flipped_uvs
		if not bones.is_empty():
			arrays[Mesh.ARRAY_BONES] = bones.slice(first * 4, (last + 1) * 4)
			arrays[Mesh.ARRAY_WEIGHTS] = weights.slice(first * 4, (last + 1) * 4)
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(part, archive))
	return mesh


func _material(part: Dictionary, archive: LsArchiveFile) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var texture := _texture(str(part["texture"]), archive)
	if texture:
		mat.albedo_texture = texture
		if texture.get_image().detect_alpha() != Image.ALPHA_NONE:
			# Hair, lashes and visors are alpha-tested cards seen from both sides.
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.5
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		mat.albedo_color = part["diffuse"]
	return mat


func _texture(file_name: String, archive: LsArchiveFile) -> Texture2D:
	var key := file_name.to_upper()
	if key.is_empty() or archive == null:
		return null
	if not _textures.has(key):
		var image := Image.new()
		var bytes := archive.read(key)
		var texture: Texture2D = null
		if not bytes.is_empty() and image.load_tga_from_buffer(bytes) == OK:
			texture = ImageTexture.create_from_image(image)
		_textures[key] = texture
	return _textures[key]


## The driver and putter from CLUBS.L3, held at clubJoint.
func _build_clubs(folder: String) -> void:
	if _skeleton == null:
		return
	var grip := -1
	for i in _nodes.size():
		if str(_nodes[i]["name"]) == "clubJoint":
			grip = i
	if grip < 0:
		return
	var locations: Dictionary = _script.get("file_locations", {})
	for club in ["driver", "putter"]:
		var where := str(locations.get(club + ".skl", "")).split("|")
		if where.size() != 2:
			continue
		var archive := LsArchiveFile.open(_find_file(folder, where[0]))
		if archive == null or not archive.has(where[1]):
			continue
		var attach := BoneAttachment3D.new()
		_skeleton.add_child(attach)
		attach.bone_idx = grip
		for m in GolferAnimData.read_meshes(archive.read(where[1])):
			var instance := MeshInstance3D.new()
			instance.mesh = _array_mesh(m, archive)
			attach.add_child(instance)
		_clubs[club] = attach
	_show_club("driver")


func _show_club(club: String) -> void:
	for c in _clubs:
		var node: Node3D = _clubs[c]
		node.visible = c == club


## The file in `folder` whose name matches regardless of case.
static func _find_file(folder: String, file_name: String) -> String:
	for f in DirAccess.get_files_at(folder):
		if f.to_lower() == file_name.to_lower():
			return folder.path_join(f)
	return folder.path_join(file_name)


func _build_stick_figure() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.66, 0.5)
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = Color(0.9, 0.9, 0.95)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.25, 0.25, 0.28)
	var limb := CylinderMesh.new()
	limb.top_radius = LIMB_RADIUS
	limb.bottom_radius = LIMB_RADIUS
	limb.height = 1.0
	limb.radial_segments = 8
	limb.rings = 1
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.03
	shaft.bottom_radius = 0.03
	shaft.height = 1.0
	shaft.radial_segments = 6
	shaft.rings = 1
	for i in _nodes.size():
		var n := _nodes[i]
		var p: int = n["parent"]
		if p < 0:
			continue
		var name_lower := str(n["name"]).to_lower()
		# The shaft runs from the grip (clubJoint) to the locator under it at
		# the club head.
		var club := name_lower.begins_with("clubjoint|") and str(_nodes[p]["name"]).to_lower() == "clubjoint"
		if name_lower.contains("shape"):
			continue
		if not club and not (n["joint"] and _nodes[p]["joint"]):
			continue
		if str(n["name"]) == "HeadEnd":
			_head_node = i
			continue
		var bone := MeshInstance3D.new()
		bone.mesh = shaft if club else limb
		bone.material_override = steel if club else (skin if _is_skin(name_lower) else shirt)
		_body.add_child(bone)
		_bones.append(bone)
		_bone_nodes.append(i)
	_head = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.38
	sphere.height = 0.76
	_head.mesh = sphere
	_head.material_override = skin
	_body.add_child(_head)


func _is_skin(name_lower: String) -> bool:
	for part in ["wrist", "hand", "knuckle", "first", "second", "thumb", "neck", "head"]:
		if part in name_lower:
			return true
	return false


func _apply_pose() -> void:
	var rot: Array[Vector3] = []
	var tr: Array[Vector3] = []
	for n in _nodes:
		rot.append(n["rotate"])
		tr.append(n["translate"])
	if not _clip.is_empty():
		var f0 := int(floor(_frame))
		var f1 := mini(f0 + 1, int(_clip["frames"]) - 1)
		var t := _frame - f0
		var hashes: PackedInt64Array = _clip["node_hashes"]
		var attrs: PackedInt32Array = _clip["attributes"]
		for c in hashes.size():
			var idx: int = _index_by_hash.get(hashes[c], -1)
			var attr := attrs[c]
			if idx < 0 or attr < 0:
				continue
			var v := lerpf(GolferAnimData.clip_value(_clip, c, f0), GolferAnimData.clip_value(_clip, c, f1), t)
			if attr < 3:
				var t3 := tr[idx]
				t3[attr] = v
				tr[idx] = t3
			else:
				var r3 := rot[idx]
				r3[attr - 3] = v
				rot[idx] = r3
	if _skeleton:
		for i in _nodes.size():
			var pose := GolferAnimData.local_transform(_nodes[i], rot[i], tr[i])
			_skeleton.set_bone_pose_position(i, pose.origin)
			_skeleton.set_bone_pose_rotation(i, pose.basis.get_rotation_quaternion())
		return
	var world: Array[Transform3D] = []
	for i in _nodes.size():
		var local := GolferAnimData.local_transform(_nodes[i], rot[i], tr[i])
		var p: int = _nodes[i]["parent"]
		world.append(world[p] * local if p >= 0 else local)
	for b in _bones.size():
		var i := _bone_nodes[b]
		_place_bone(_bones[b], world[_nodes[i]["parent"]].origin, world[i].origin)
	if _head_node >= 0:
		var head_base: Vector3 = world[_nodes[_head_node]["parent"]].origin
		_head.position = head_base.lerp(world[_head_node].origin, 0.5)


func _place_bone(bone: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := d.length()
	if length < 1e-4:
		bone.visible = false
		return
	bone.visible = true
	var y := d / length
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	bone.transform = Transform3D(Basis(x, y * length, z), from + d * 0.5)
