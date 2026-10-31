class_name PracticeCups
extends Node3D
## The cups of a practice green (PuttingPractice): each a cup with a short
## stick in it, as practice greens have instead of flags; the cup being
## putted to carries a small yellow pennant.

const STICK_HEIGHT := 0.55
const STICK_RADIUS := 0.012

var _white := StandardMaterial3D.new()
var _black := StandardMaterial3D.new()
var _yellow := StandardMaterial3D.new()


func _init() -> void:
	_white.albedo_color = Color(0.95, 0.95, 0.95)
	_black.albedo_color = Color(0.03, 0.03, 0.03)
	_yellow.albedo_color = Color(1.0, 0.85, 0.1)
	_yellow.cull_mode = BaseMaterial3D.CULL_DISABLED


## Rebuilds the cups, `active` marked.
func build(cups: Array[Vector3], active: int) -> void:
	for c in get_children():
		c.queue_free()
	for i in cups.size():
		var p := cups[i]
		var cup := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = BallPhysics.CUP_RADIUS * 1.6
		disc.bottom_radius = BallPhysics.CUP_RADIUS * 1.6
		disc.height = 0.02
		cup.mesh = disc
		cup.material_override = _black
		cup.position = p + Vector3(0, 0.005, 0)
		add_child(cup)
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
