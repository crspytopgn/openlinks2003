class_name PlaceholderGolfer
extends GolferRig
## A capsule with a stick for a club, swung with tweens.

const BACKSWING_TIME := 0.9

var _club_pivot: Node3D
var _tween: Tween


func _init() -> void:
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = Color(0.85, 0.85, 0.9)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.2
	capsule.height = 1.45
	capsule.material = shirt
	body.mesh = capsule
	body.position.y = 0.75
	add_child(body)

	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.66, 0.5)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.material = skin
	head.mesh = sphere
	head.position.y = 1.62
	add_child(head)

	# Hands at the pivot; the club hangs from it towards the ball.
	_club_pivot = Node3D.new()
	_club_pivot.position = Vector3(0, 1.15, -0.25)
	add_child(_club_pivot)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.2, 0.2, 0.22)
	var shaft := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 1.05, 0.025)
	box.material = steel
	shaft.mesh = box
	shaft.position = Vector3(0, -0.52, 0)
	_club_pivot.add_child(shaft)
	# Tilt the shaft out towards the ball.
	_club_pivot.rotation.x = -0.45


func play(animation: StringName) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	match animation:
		&"address":
			_tween.tween_property(_club_pivot, "rotation:z", 0.0, 0.2)
		&"backswing":
			_tween.tween_property(_club_pivot, "rotation:z", 2.4, BACKSWING_TIME).set_ease(Tween.EASE_OUT)
		&"swing":
			_tween.tween_property(_club_pivot, "rotation:z", -2.3, 0.18).set_ease(Tween.EASE_IN)
			_tween.tween_interval(0.8)
			_tween.tween_property(_club_pivot, "rotation:z", 0.0, 0.5)
		&"putt":
			_tween.tween_property(_club_pivot, "rotation:z", 0.35, 0.4)
			_tween.tween_property(_club_pivot, "rotation:z", -0.35, 0.25)
			_tween.tween_interval(0.6)
			_tween.tween_property(_club_pivot, "rotation:z", 0.0, 0.3)
		&"celebrate":
			_tween.tween_property(self, "position:y", position.y + 0.3, 0.15)
			_tween.tween_property(self, "position:y", position.y, 0.15)
