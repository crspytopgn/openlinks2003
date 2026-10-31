class_name GroundShade
extends RefCounted
## Baked tree shadows and ambient occlusion on the ground, once per hole.
## Billboards and impostors cast no real-time shadows, and the real-time
## ones stop at the shadow distance, so every tree, bush, rock and model
## near the hole stamps a soft shadow (along the sun) and a soft dark patch
## at its foot (AO) into one top-down map. The stamps are drawn on the GPU:
## one MultiMesh of soft ellipses multiplied into a white off-screen
## viewport, read back once. The terrain and grass shaders darken the ground
## by it through global uniforms: R is the sun shadow, G the AO.
##
## The sun shadow fades out inside `ground_shade_near` of the camera, where
## the full 3D trees cast real ones. Headless runs render nothing and keep
## the ground unshaded.

const STAMP_SHADER := preload("res://shaders/ground_shade_stamp.gdshader")
const MARGIN := 250.0  ## metres around the hole's tee, route and pin
const MAX_PIXELS := 1536
const MIN_TEXEL := 0.5  ## metres per pixel at most this fine
const SHADOW := 0.45  ## how much of the light a crown's shadow takes
const AO := 0.3
const MAX_SLANT := 3.0  ## longest shadow per metre of height (low sun)
const CASTER_SIZE := 7  ## floats per caster, see stamps()
const STAMP_SIZE := 8  ## floats per stamp, see stamps()
const SHAPE_CELL := 64  ## pixels per shadow shape in the atlas
const SHAPE_COLUMNS := 16

static var _atlas: ImageTexture
static var _atlas_of: Array = []  ## the shapes _atlas was built from

static var _generation := 0


## The part of the course to bake for `hole`: its tee, route and pin with
## MARGIN around them.
static func hole_rect(hole: HoleData) -> Rect2:
	var r := Rect2(Vector2(hole.tee.x, hole.tee.z), Vector2.ZERO)
	for p in hole.route:
		r = r.expand(p)
	r = r.expand(Vector2(hole.pin.x, hole.pin.z))
	return r.grow(MARGIN)


## The stamps of the shadow casters `casters` (per caster: base x, y, z,
## crown bottom and top above the base, crown radius, shadow shape or -1,
## as from CourseObjects.shade_casters) for a sun shining along
## `sun_travel` (the way its light goes, pointing down). Per stamp: centre
## x, z, half length along the shadow, half width, the shadow's direction
## (radians about +y), how dark in R and in G, and the shadow shape (a
## cell of the shape atlas, see shape_atlas) or -1 for a soft ellipse.
static func stamps(casters: PackedFloat32Array, sun_travel: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	@warning_ignore("integer_division")
	var n := casters.size() / CASTER_SIZE
	var down := maxf(-sun_travel.y, 0.05)
	var slant := Vector2(sun_travel.x, sun_travel.z) / down  # ground offset per metre of height
	if slant.length() > MAX_SLANT:
		slant = slant.normalized() * MAX_SLANT
	var angle := atan2(slant.x, slant.y)
	out.resize(n * 2 * STAMP_SIZE)
	var o := 0
	for i in n:
		var c := CASTER_SIZE * i
		var x := casters[c]
		var z := casters[c + 2]
		var bottom := casters[c + 3]
		var top := casters[c + 4]
		var r := casters[c + 5]
		var shape := casters[c + 6]
		var mid := slant * (bottom + top) * 0.5
		var values := [
			# Shadow of the crown, stretched along the sun.
			x + mid.x, z + mid.y, r + slant.length() * (top - bottom) * 0.5, r, angle, SHADOW, 0.0, shape,
			# Occlusion at the foot.
			x, z, r * 1.3, r * 1.3, 0.0, 0.0, AO, -1.0,
		]
		for v in values:
			out[o] = v
			o += 1
	return out


## Bakes the map for `hole` and points the shaders at it. Call after the
## hole's objects are built; a newer call wins over one still baking.
static func bake(hole: HoleData, objects: CourseObjects, sun_travel: Vector3) -> void:
	_generation += 1
	var generation := _generation
	clear()
	if DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var rect := hole_rect(hole)
	var casters := objects.shade_casters(rect) if objects != null else PackedFloat32Array()
	casters.append_array(placed_casters(hole))
	if casters.is_empty():
		return
	var texel := maxf(MIN_TEXEL, maxf(rect.size.x, rect.size.y) / MAX_PIXELS)
	var size := Vector2i(ceili(rect.size.x / texel), ceili(rect.size.y / texel))
	var vp := SubViewport.new()
	vp.name = "GroundShadeBake"
	vp.own_world_3d = true
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = size.y * texel
	cam.near = 1.0
	cam.far = 20.0
	# Looking straight down with +x to the right and +z down the image.
	cam.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(rect.get_center().x, 10.0, rect.get_center().y))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.WHITE
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	vp.add_child(cam)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _stamp_multimesh(stamps(casters, sun_travel), shape_atlas(CourseObjects.shadow_shapes))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(mi)
	tree.root.add_child.call_deferred(vp)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if generation != _generation or img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	RenderingServer.global_shader_parameter_set("ground_shade", ImageTexture.create_from_image(img))
	RenderingServer.global_shader_parameter_set("ground_shade_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))


## No shading until the next bake.
static func clear() -> void:
	RenderingServer.global_shader_parameter_set("ground_shade_rect", Vector4.ZERO)


## How close to the camera the baked sun shadow fades out (where the full
## 3D trees cast real-time shadows), in metres.
static func set_near(distance: float) -> void:
	RenderingServer.global_shader_parameter_set("ground_shade_near", distance)


## Casters for the objects placed on the hole (the placeholder course's
## and designed courses' trees and rocks), sizes by kind.
static func placed_casters(hole: HoleData) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for o in hole.objects:
		var s := o.scale
		var p := o.position
		if o.id.begins_with("tree_pine"):
			out.append_array(PackedFloat32Array([p.x, p.y, p.z, 2.0 * s, 13.0 * s, 2.6 * s, -1]))
		elif o.id.begins_with("tree"):
			out.append_array(PackedFloat32Array([p.x, p.y, p.z, 4.0 * s, 12.0 * s, 3.8 * s, -1]))
		elif o.id.begins_with("bush"):
			out.append_array(PackedFloat32Array([p.x, p.y, p.z, 0.0, 1.5 * s, 1.2 * s, -1]))
		elif o.id.begins_with("rock"):
			out.append_array(PackedFloat32Array([p.x, p.y, p.z, 0.0, 1.0 * s, 1.0 * s, -1]))
	return out


## The shadow shapes (per billboard type an L8 Image or null) packed into
## one texture, SHAPE_COLUMNS cells of SHAPE_CELL pixels a row, a type's
## shape in cell number type. Null without any.
static func shape_atlas(shapes: Array) -> ImageTexture:
	if shapes.is_empty():
		return null
	if _atlas != null and is_same(_atlas_of, shapes):
		return _atlas
	@warning_ignore("integer_division")
	var rows := (shapes.size() + SHAPE_COLUMNS - 1) / SHAPE_COLUMNS
	var img := Image.create(SHAPE_COLUMNS * SHAPE_CELL, rows * SHAPE_CELL, false, Image.FORMAT_L8)
	for t in shapes.size():
		var shape: Image = shapes[t]
		if shape == null:
			continue
		var cell := shape.duplicate() as Image
		cell.resize(SHAPE_CELL, SHAPE_CELL, Image.INTERPOLATE_BILINEAR)
		@warning_ignore("integer_division")
		img.blit_rect(cell, Rect2i(0, 0, SHAPE_CELL, SHAPE_CELL), Vector2i(t % SHAPE_COLUMNS, t / SHAPE_COLUMNS) * SHAPE_CELL)
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	_atlas_of = shapes
	return _atlas


static func _stamp_multimesh(st: PackedFloat32Array, atlas: ImageTexture) -> MultiMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = STAMP_SHADER
	if atlas != null:
		mat.set_shader_parameter("shapes", atlas)
		mat.set_shader_parameter("shape_grid", Vector2(atlas.get_size()) / SHAPE_CELL)
	plane.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	@warning_ignore("integer_division")
	var n := st.size() / STAMP_SIZE
	mm.instance_count = n
	for i in n:
		var o := STAMP_SIZE * i
		var b := Basis(Vector3.UP, st[o + 4]).scaled(Vector3(st[o + 3] * 2.0, 1.0, st[o + 2] * 2.0))
		mm.set_instance_transform(i, Transform3D(b, Vector3(st[o], 0.0, st[o + 1])))
		var shape := st[o + 7] if atlas != null else -1.0
		mm.set_instance_custom_data(i, Color(st[o + 5], st[o + 6], shape + 1.0, 0.0))
	return mm
