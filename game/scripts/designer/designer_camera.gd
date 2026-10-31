class_name DesignerCamera
extends Camera3D
## The course designer's camera: orbits a point on the ground.
## Right drag: turn and tilt.  Middle drag (or Shift + right drag): pan.
## Wheel: zoom.  WASD / arrow keys: move.  Q / E: turn.  T: top-down view.

const MIN_DISTANCE := 15.0
const MAX_DISTANCE := 2500.0
const MIN_PITCH := 8.0
const MAX_PITCH := 89.0

var terrain: CourseTerrain
var bounds := Rect2(-500, -500, 1000, 1000)
var target := Vector3.ZERO
var yaw := 0.0  ## degrees; 0 looks down +z
var pitch := 50.0  ## degrees above the horizon
var distance := 400.0

var _turning := false
var _panning := false
var _saved_pitch := 50.0


func _ready() -> void:
	near = 0.5
	far = 6000.0
	_apply()


## Looks at `p` from the current angle.
func focus(p: Vector2, p_distance := -1.0) -> void:
	target = Vector3(p.x, 0, p.y)
	if p_distance > 0.0:
		distance = clampf(p_distance, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func toggle_top_view() -> void:
	if pitch < MAX_PITCH - 1.0:
		_saved_pitch = pitch
		pitch = MAX_PITCH
	else:
		pitch = _saved_pitch
	_apply()


## Flat forward and right directions on the ground.
func ground_axes() -> Array[Vector2]:
	var fwd := Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
	return [fwd, Vector2(-fwd.y, fwd.x)]


## Returns true if it used the event.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_turning = mb.pressed and not mb.shift_pressed
				_panning = mb.pressed and mb.shift_pressed
				return false  # tools may use right clicks too
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
				return true
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = maxf(MIN_DISTANCE, distance / 1.15)
					_apply()
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = minf(MAX_DISTANCE, distance * 1.15)
					_apply()
				return true
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _turning:
			yaw -= mm.relative.x * 0.3
			pitch = clampf(pitch + mm.relative.y * 0.25, MIN_PITCH, MAX_PITCH)
			_apply()
			return true
		if _panning:
			var axes := ground_axes()
			# Grab the ground: it follows the mouse.
			var k := distance * 0.0015
			var move: Vector2 = (axes[0] * mm.relative.y - axes[1] * mm.relative.x) * k
			target += Vector3(move.x, 0, move.y)
			_apply()
			return true
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_T:
			toggle_top_view()
			return true
	return false


## Keyboard movement; call every frame unless a text field has focus.
func process_keys(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x -= 1.0
	var turn := 0.0
	if Input.is_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_key_pressed(KEY_E):
		turn -= 1.0
	if move == Vector2.ZERO and turn == 0.0:
		return
	var axes := ground_axes()
	var speed := distance * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var step: Vector2 = (axes[0] * move.y - axes[1] * move.x) * speed * delta
	target += Vector3(step.x, 0, step.y)
	yaw += turn * 70.0 * delta
	_apply()


func _apply() -> void:
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
	if terrain != null:
		target.y = terrain.height_at(target.x, target.z)
	var p := deg_to_rad(pitch)
	var y := deg_to_rad(yaw)
	var back := Vector3(-sin(y) * cos(p), sin(p), -cos(y) * cos(p))
	var eye := target + back * distance
	if terrain != null:
		eye.y = maxf(eye.y, terrain.height_at(eye.x, eye.z) + 3.0)
	position = eye
	# Straight down needs another up vector.
	look_at(target, Vector3.UP if pitch < 89.5 else Vector3(sin(y), 0, cos(y)))
