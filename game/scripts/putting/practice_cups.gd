class_name PracticeCups
extends Node3D
## The cups of a practice green (PuttingPractice): each a cup with a junior
## flagstick in it, as practice greens have (a 24 in white stick with a small
## flag, tools/props/build_props.py); the cup being putted to flies a yellow
## flag, the others white.

const STICK_HEIGHT := 0.55
const STICK_RADIUS := 0.012

var _white := StandardMaterial3D.new()
var _yellow := StandardMaterial3D.new()
var _cup := ShaderMaterial.new()


func _init() -> void:
	_white.albedo_color = Color(0.95, 0.95, 0.95)
	_yellow.albedo_color = Color(1.0, 0.85, 0.1)
	_yellow.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cup.shader = load("res://shaders/cup.gdshader")


## Rebuilds the cups, `active` marked.
func build(cups: Array[Vector3], active: int) -> void:
	for c in get_children():
		c.queue_free()
	for i in cups.size():
		var p := cups[i]
		# The hole at its real size, liner and all, as on the course
		# (shaders/cup.gdshader): not a black disc on top of the grass.
		var cup := MeshInstance3D.new()
		var disc := PlaneMesh.new()
		disc.size = Vector2.ONE * BallPhysics.CUP_RADIUS * 2.0
		cup.mesh = disc
		cup.material_override = _cup
		cup.position = p + Vector3(0, 0.004, 0)
		cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cup)
		var model := _flag(i == active)
		if model != null:
			model.position = p
			model.rotation.y = 0.7 * i
			add_child(model)
			continue
		var stick := MeshInstance3D.new()
		var rod := CylinderMesh.new()
		rod.top_radius = STICK_RADIUS
		rod.bottom_radius = STICK_RADIUS
		rod.height = STICK_HEIGHT
		stick.mesh = rod
		stick.material_override = _white
		stick.position = p + Vector3(0, STICK_HEIGHT * 0.5, 0)
		add_child(stick)
		if i == active:
			var pennant := MeshInstance3D.new()
			var cloth := BoxMesh.new()
			cloth.size = Vector3(0.01, 0.12, 0.18)
			pennant.mesh = cloth
			pennant.material_override = _yellow
			pennant.position = p + Vector3(0, STICK_HEIGHT - 0.07, 0.095)
			add_child(pennant)


## The junior flagstick model, its flag yellow if `active`; null without it.
func _flag(active: bool) -> MeshInstance3D:
	var m := CourseProps.instance("practice_flag")
	if m == null:
		return null
	if active:
		for k in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(k) as StandardMaterial3D
			if mat != null and mat.resource_name == "flag":
				var yellow := mat.duplicate() as StandardMaterial3D
				yellow.albedo_color = Color(1.0, 0.85, 0.1)
				m.set_surface_override_material(k, yellow)
	return m
