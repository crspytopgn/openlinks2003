class_name StandBag
extends MeshInstance3D
## The player's own bag: a black and red stand bag standing on its legs a
## couple of paces behind the golfer, as players and their pros set it down
## (tools/props/build_stand_bag.py, docs/props.md). 88 cm tall with a 4-way
## top, a driver, 3-wood and hybrid under headcovers, nine irons and a
## putter. Low quality and the Web build use the light version (about 8k
## triangles against about 50k); Godot adds distance LODs to both.
## Not shown with a caddie (they carry the staff bag, GolfBag) or the golf
## buggy (the clubs ride on it).

const MODEL := "stand_bag"
const LITE_MODEL := "stand_bag_lite"
## Where it stands, from the ball: behind the golfer's back, a little ahead
## of the ball, out of the swing and in the TV view down the line.
const BEHIND_M := 2.3  ## along the golfer's back (the player's left of the line)
const AHEAD_M := 0.6  ## towards the target from the ball
## The bag's mouth in its own space: the top of the cuff, where a hand goes
## for a club (leaning back 20 degrees on its legs).
const MOUTH := Vector3(0.0, 0.82, -0.30)
## Furthest it looks for dry, flat ground off a green, a bunker or water.
const SEARCH_M := 30.0

static var _meshes := {}


## The woven polyester and the cuff's spacer mesh, as tiny triplanar
## bumps (no UVs needed): seen only up close, and only on the full model.
const WEAVE_M := 0.006  ## one tile of the weave pattern, four threads each way
const SPACER_M := 0.012  ## the hip pad and cuff's open spacer mesh

static var _weaves := {}


func _init(lite := false) -> void:
	name = "StandBag"
	mesh = shared_mesh(lite)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visible = false
	if not lite and mesh is ArrayMesh:
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null:
				continue
			if mat.resource_name == "fabric":
				set_surface_override_material(i, woven(mat, WEAVE_M, false))
			elif mat.resource_name == "mesh":
				set_surface_override_material(i, woven(mat, SPACER_M, true))


## A copy of the material with a woven bump, shared by every bag.
static func woven(base: StandardMaterial3D, tile_m: float, spacer: bool) -> StandardMaterial3D:
	var key := "%s:%s" % [base.resource_name, spacer]
	if _weaves.has(key):
		return _weaves[key]
	var m := base.duplicate() as StandardMaterial3D
	m.normal_enabled = true
	m.normal_texture = weave_texture(spacer)
	m.normal_scale = 0.6 if spacer else 0.35
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE / tile_m
	# Cloth: a soft sheen at grazing angles, little of a hard highlight.
	m.metallic_specular = 0.25
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.6
	_weaves[key] = m
	return m


## A 32 pixel tileable normal map: a plain weave (threads over and under),
## or the spacer mesh's raised diamond of holes.
static func weave_texture(spacer: bool) -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := float(x) / n * TAU
			var v := float(y) / n * TAU
			var h := 0.0
			if spacer:
				# Holes on a diamond grid between raised ribs.
				h = 1.0 - pow(absf(sin(u * 2.0 + v * 2.0) * sin(u * 2.0 - v * 2.0)), 0.5)
			else:
				# Four threads each way, crossing over and under.
				var over := signf(sin(u * 4.0) * sin(v * 4.0))
				h = 0.5 + 0.5 * (absf(sin(u * 8.0)) if over > 0.0 else absf(sin(v * 8.0)))
			img.set_pixel(x, y, Color(h, h, h))
	img.bump_map_to_normal_map(4.0 if spacer else 2.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The model for this quality: the light one on Low and in the browser.
static func use_lite(quality: int) -> bool:
	return quality <= GraphicsSettings.Quality.LOW or OS.has_feature("web")


## The bag's mesh, loaded once and shared; the light version if the full
## one is missing (it is left out of the Web build), then the old simple bag.
static func shared_mesh(lite := false) -> Mesh:
	var key := LITE_MODEL if lite else MODEL
	if _meshes.has(key):
		return _meshes[key]
	var m := CourseProps.mesh(key)
	if m == null and not lite:
		m = CourseProps.mesh(LITE_MODEL)
	if m == null:
		m = GolfBag.simple_mesh()
	_meshes[key] = m
	return m


## Stands the bag for a shot from `ball` towards `dir` (flat, normalised):
## behind the golfer, its pockets turned to them, on dry ground. Off the
## green for a putt or a chip from the fringe, out of bunkers and water.
func place(terrain: CourseTerrain, ball: Vector3, dir: Vector3) -> void:
	var left := Vector3.UP.cross(dir)
	var tries: Array[Vector3] = [
		ball + left * BEHIND_M + dir * AHEAD_M,
		ball + left * (BEHIND_M + 1.0) - dir * 1.0,
		ball - left * (BEHIND_M + 0.6) - dir * 1.2,
		ball - dir * (BEHIND_M + 1.0),
	]
	var spot := Vector3.INF
	for t in tries:
		if _good_ground(terrain, t):
			spot = t
			break
	if spot == Vector3.INF:
		# On or by a green: walk out from the first spot until off it.
		var out := (tries[0] - ball)
		out.y = 0.0
		out = out.normalized()
		var d := 0.0
		while d < SEARCH_M:
			var t := tries[0] + out * d
			if _good_ground(terrain, t):
				spot = t
				break
			d += 0.5
	if spot == Vector3.INF:
		visible = false
		return
	spot.y = terrain.height_at(spot.x, spot.z)
	# The pockets face the ball, the legs splay out away from it, and the
	# bag leans with the slope a little as its legs and foot find the ground.
	var face := ball - spot
	face.y = 0.0
	if face.length_squared() < 1e-4:
		face = -dir
	var b := Basis.looking_at(-face.normalized(), Vector3.UP)
	var normal := _ground_normal(terrain, spot)
	var tilt := Vector3.UP.cross(normal)
	if tilt.length_squared() > 1e-6:
		b = Basis(tilt.normalized(), Vector3.UP.angle_to(normal) * 0.6) * b
	transform = Transform3D(b, spot)
	visible = true


## Where a hand reaches into the bag for a club, in world space: for an
## animation of the golfer taking a club out.
func mouth() -> Vector3:
	return global_transform * MOUTH


static func _good_ground(terrain: CourseTerrain, p: Vector3) -> bool:
	var s := terrain.surface_at(p.x, p.z)
	return s != Surface.Type.WATER and s != Surface.Type.OUT_OF_BOUNDS and s != Surface.Type.SAND \
		and s != Surface.Type.GREEN and s != Surface.Type.FRINGE


static func _ground_normal(terrain: CourseTerrain, p: Vector3) -> Vector3:
	var e := 0.3
	var hx := terrain.height_at(p.x + e, p.z) - terrain.height_at(p.x - e, p.z)
	var hz := terrain.height_at(p.x, p.z + e) - terrain.height_at(p.x, p.z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()
