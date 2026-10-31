class_name GolfBag
extends MeshInstance3D
## A stand golf bag with headcovers and irons, built in code (no files): one
## mesh with three materials (fabric, trim, metal), so it costs three draw
## calls wherever it stands. The caddie stands it beside them, and a buggy
## carries one on its back.

const FABRIC := Color(0.06, 0.11, 0.22)
const TRIM := Color(0.92, 0.92, 0.9)
const METAL := Color(0.78, 0.79, 0.8)
const TILT_DEG := 14.0  ## leaning back on its stand

static var _mesh: ArrayMesh


func _init() -> void:
	mesh = shared_mesh()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The bag's mesh, built once and shared by every bag.
static func shared_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var fabric := SurfaceTool.new()
	var trim := SurfaceTool.new()
	var metal := SurfaceTool.new()
	for st in [fabric, trim, metal]:
		(st as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Basis(Vector3.RIGHT, deg_to_rad(-TILT_DEG))

	var body := CylinderMesh.new()
	body.top_radius = 0.125
	body.bottom_radius = 0.115
	body.height = 0.86
	body.radial_segments = 16
	fabric.append_from(body, 0, _at(lean, Vector3(0, 0.47, 0)))
	var pocket := BoxMesh.new()
	pocket.size = Vector3(0.15, 0.42, 0.06)
	fabric.append_from(pocket, 0, _at(lean, Vector3(0, 0.4, 0.13)))
	var strap := BoxMesh.new()
	strap.size = Vector3(0.05, 0.62, 0.02)
	fabric.append_from(strap, 0, _at(lean, Vector3(0, 0.55, -0.14), Basis(Vector3.RIGHT, deg_to_rad(6.0))))
	for y: float in [0.06, 0.88]:
		var band := CylinderMesh.new()
		band.top_radius = 0.132
		band.bottom_radius = 0.132
		band.height = 0.07
		band.radial_segments = 16
		trim.append_from(band, 0, _at(lean, Vector3(0, y, 0)))
	# Woods under headcovers, and a few irons.
	var covers := [Vector3(-0.05, 1.0, -0.04), Vector3(0.05, 0.98, -0.05), Vector3(0.0, 0.96, 0.02)]
	for i in covers.size():
		var cover := SphereMesh.new()
		cover.radius = 0.055
		cover.height = 0.15
		cover.radial_segments = 12
		cover.rings = 6
		(trim if i == 1 else fabric).append_from(cover, 0, _at(lean, covers[i]))
	for x: float in [-0.06, -0.02, 0.02, 0.06]:
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.006
		shaft.bottom_radius = 0.006
		shaft.height = 0.12
		shaft.radial_segments = 6
		metal.append_from(shaft, 0, _at(lean, Vector3(x, 0.94, 0.07)))
		var head := BoxMesh.new()
		head.size = Vector3(0.025, 0.05, 0.075)
		metal.append_from(head, 0, _at(lean, Vector3(x, 1.0, 0.09), Basis(Vector3.RIGHT, deg_to_rad(-25.0))))
	# The stand's legs, splayed out behind.
	for side: float in [-1.0, 1.0]:
		var leg := CylinderMesh.new()
		leg.top_radius = 0.007
		leg.bottom_radius = 0.007
		leg.height = 0.72
		leg.radial_segments = 6
		var b := Basis(Vector3.FORWARD, deg_to_rad(8.0 * side)) * Basis(Vector3.RIGHT, deg_to_rad(2.0 * TILT_DEG))
		metal.append_from(leg, 0, Transform3D(b, Vector3(0.08 * side, 0.36, -0.08)))

	_mesh = ArrayMesh.new()
	var mats := [_material(FABRIC, 0.8, 0.0), _material(TRIM, 0.45, 0.0), _material(METAL, 0.28, 0.9)]
	var tools := [fabric, trim, metal]
	for i in tools.size():
		var st: SurfaceTool = tools[i]
		st.commit(_mesh)
		_mesh.surface_set_material(_mesh.get_surface_count() - 1, mats[i])
	return _mesh


static func _at(lean: Basis, p: Vector3, b := Basis.IDENTITY) -> Transform3D:
	return Transform3D(lean * b, lean * p)


static func _material(c: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	m.metallic = metallic
	return m
