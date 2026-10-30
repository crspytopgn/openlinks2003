class_name GolfRound
extends Node3D
## One round of golf: aim, swing, watch the ball, hole out, next hole.
##
## Courses, objects, the golfer and sounds come from AssetProviders
## (placeholders until the decoders land) and the ball physics from a
## ShotModel, so none of them is wired in here.

enum State { AIM, SWING, FLIGHT, SHOT_RESULT, HOLE_DONE, ROUND_DONE }

const YARDS_PER_METRE := 1.0936
const FEET_PER_METRE := 3.2808
const MAX_STROKES := 10  ## pick up after this many on a hole
const AIM_RATE_DEG := 25.0  ## per second, holding left or right
const PUTT_AIM_RATE_DEG := 6.0
const RESULT_PAUSE := 2.5
const HINT_AIM := "Left/Right: aim (Shift: fine)    Up/Down: club    Space or click: swing    Tab: scorecard    O: objects    Esc: settings"
const HINT_SWING := "Click 1: start    Click 2: set power    Click 3: on the white line for a straight shot"
const HINT_WAIT := "Space or click: continue    Tab: scorecard"

## Course to load; empty plays the placeholder course.
@export var course_path := ""
## Set by the boot screen's course picker before it opens this scene.
static var chosen_course := ""

var state: State = State.AIM
var course: CourseData
var hole: HoleData
var hole_index := 0
var card: Scorecard
var clubs: Array[Club] = []
var club_index := 0
var strokes := 0
var ball_at := Vector3.ZERO
var lie: int = Surface.Type.TEE
var aim_deg := 0.0
var shot: ShotResult
var shot_from := Vector3.ZERO
var shot_time := 0.0
var result_timer := 0.0

var shot_model: ShotModel
var wind: Wind
var sounds: SoundBank
var hud: Hud
var camera: Camera3D
var ball: MeshInstance3D
var trail: MeshInstance3D
var aim_marker: MeshInstance3D
var golfer: GolferRig
var hole_root: Node3D
var graphics: GraphicsSettings
var scenery: Scenery
var settings_panel: SettingsPanel

var _trail_mesh := ImmediateMesh.new()
var _ball_base := Vector3.ZERO  ## bottom of the ball, as the physics sees it
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_look_now := Vector3.ZERO


func _ready() -> void:
	AssetProviders.ensure_defaults()
	shot_model = AssetProviders.shot_model
	clubs = Club.standard_set()
	graphics = GraphicsSettings.load_saved()
	_build_world()
	_apply_graphics()
	sounds = AssetProviders.create_sound_bank()
	add_child(sounds)
	hud.meter.backswing_started.connect(_on_backswing_started)
	hud.meter.swing_finished.connect(_on_swing_finished)
	start_round()


func start_round() -> void:
	if course_path.is_empty():
		course_path = chosen_course
	course = AssetProviders.load_course(course_path)
	card = Scorecard.new(course.pars())
	wind = Wind.new(graphics.wind)
	hud.scorecard.visible = false
	start_hole(0)


func start_hole(index: int) -> void:
	hole_index = index
	hole = course.holes[index]
	if hole_root:
		hole_root.queue_free()
	hole_root = Node3D.new()
	hole_root.name = "Hole%d" % hole.number
	add_child(hole_root)
	hole_root.add_child(hole.terrain.build_visual())
	if course.objects != null:
		hole_root.add_child(course.objects.build_visual(hole))
	for o in hole.objects:
		var node := AssetProviders.object_library.instantiate(o.id)
		if node == null:
			continue
		node.position = o.position
		node.rotation_degrees.y = o.yaw_deg
		node.scale = Vector3.ONE * o.scale
		hole_root.add_child(node)
	_add_flag()
	_add_tee_markers()
	golfer = AssetProviders.golfer_assets.create_golfer()
	hole_root.add_child(golfer)

	strokes = 0
	wind.start_hole()
	ball_at = hole.tee
	ball.visible = true
	_clear_trail()
	hud.scorecard.visible = false
	hud.show_message("Hole %d    Par %d    %d yards" % [hole.number, hole.par, roundi(hole.length_m() * YARDS_PER_METRE)], 3.0)
	_prepare_shot(true)


## Plays a shot with the current club and aim. The swing meter calls this;
## tests call it directly.
func play_shot(power: float, accuracy: float) -> void:
	var club := clubs[club_index]
	if golfer:
		golfer.play(&"putt" if club.is_putter else &"swing")
	sounds.play(&"putt" if club.is_putter else &"hit")
	shot_from = ball_at
	var start := shot_model.launch(club, power, accuracy, aim_deg, lie, ball_at)
	shot = shot_model.simulate(start, hole.terrain, hole.pin, wind.velocity())
	wind.next_shot()
	shot_time = 0.0
	aim_marker.visible = false
	hud.show_message("")
	hud.hint.text = "Space or click: skip"
	state = State.FLIGHT


## Advances the game one step without input, playing sensible shots: used by
## the headless tests to play a whole round.
func auto_play_step() -> void:
	match state:
		State.AIM, State.SWING:
			var club := clubs[club_index]
			var target := _aim_target()
			var d := _flat_distance(ball_at, target)
			var power := 1.0
			if club.is_putter:
				var v := sqrt(2.0 * Surface.rolling_resistance(Surface.Type.GREEN) * BallPhysics.GRAVITY * (d + 0.3))
				power = clampf(v / club.ball_speed_mps, 0.03, 1.0)
			else:
				power = clampf(d / _club_reach(), 0.3, 1.0)
			hud.meter.reset()
			play_shot(power, 0.0)
		State.FLIGHT:
			_complete_flight()
		State.SHOT_RESULT:
			_after_result()
		State.HOLE_DONE:
			_next_hole()


func _process(delta: float) -> void:
	match state:
		State.AIM:
			_process_aim(delta)
		State.FLIGHT:
			_process_flight(delta)
		State.SHOT_RESULT:
			result_timer -= delta
			if result_timer <= 0.0:
				_after_result()
	_update_camera(delta)
	_update_ball_size()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_ESCAPE:
					if settings_panel.visible:
						settings_panel.close()
					else:
						settings_panel.open(graphics)
					get_viewport().set_input_as_handled()
					return
				KEY_F11:
					graphics.fullscreen = not graphics.fullscreen
					graphics.save()
					_apply_graphics()
					return
	if settings_panel.visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_O:
					get_tree().change_scene_to_file("res://scenes/object_viewer.tscn")
					return
				KEY_TAB:
					if hud.scorecard.visible:
						hud.scorecard.visible = false
					else:
						hud.scorecard.show_card(card, course.course_name)
					return
				KEY_UP:
					_change_club(-1)
					return
				KEY_DOWN:
					_change_club(1)
					return
				KEY_C:
					get_tree().change_scene_to_file("res://scenes/course_viewer.tscn")
					return
	var swing_pressed := event.is_action_pressed("swing")
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		swing_pressed = swing_pressed or (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT)
	if swing_pressed:
		get_viewport().set_input_as_handled()
		_on_swing_pressed()


func _on_swing_pressed() -> void:
	match state:
		State.AIM:
			hud.scorecard.visible = false
			state = State.SWING
			hud.hint.text = HINT_SWING
			hud.meter.click()
		State.SWING:
			hud.meter.click()
		State.FLIGHT:
			_complete_flight()
		State.SHOT_RESULT:
			_after_result()
		State.HOLE_DONE:
			_next_hole()
		State.ROUND_DONE:
			start_round()


func _on_backswing_started() -> void:
	if golfer and not clubs[club_index].is_putter:
		golfer.play(&"backswing")


func _on_swing_finished(power: float, accuracy: float) -> void:
	if state == State.SWING:
		play_shot(power, accuracy)


func _change_club(step: int) -> void:
	if state != State.AIM:
		return
	club_index = clampi(club_index + step, 0, clubs.size() - 1)
	_update_aim_marker()
	_update_hud()
	_aim_camera(false)


# --- Shot flow ---------------------------------------------------------------

func _prepare_shot(snap_camera: bool) -> void:
	state = State.AIM
	lie = hole.terrain.surface_at(ball_at.x, ball_at.z)
	_auto_club()
	var target := _aim_target()
	aim_deg = rad_to_deg(atan2(target.x - ball_at.x, target.z - ball_at.z))
	hud.meter.reset()
	hud.hint.text = HINT_AIM
	_place_ball(ball_at)
	_place_golfer()
	_update_aim_marker()
	_update_hud()
	_aim_camera(snap_camera)


func _process_aim(delta: float) -> void:
	var turn := 0.0
	if Input.is_action_pressed("ui_left"):
		turn += 1.0
	if Input.is_action_pressed("ui_right"):
		turn -= 1.0
	if turn == 0.0:
		return
	var rate := PUTT_AIM_RATE_DEG if clubs[club_index].is_putter else AIM_RATE_DEG
	if Input.is_key_pressed(KEY_SHIFT):
		rate *= 0.2
	aim_deg = wrapf(aim_deg + turn * rate * delta, -180.0, 180.0)
	_place_golfer()
	_update_aim_marker()
	_update_hud()
	_aim_camera(false)


func _process_flight(delta: float) -> void:
	shot_time += delta
	var p := shot.position_at(shot_time)
	_place_ball(p)
	_draw_trail(shot.sample_index_at(shot_time), p)
	_follow_camera(p)
	if shot_time >= shot.time_s:
		_complete_flight()


func _complete_flight() -> void:
	shot_time = shot.time_s
	_place_ball(shot.rest)
	_draw_trail(shot.points.size() - 1, shot.rest)
	_follow_camera(shot.rest)
	strokes += 1
	var msg := ""
	match shot.outcome:
		ShotResult.Outcome.HOLED:
			sounds.play(&"cup")
			ball.visible = false
			_finish_hole(false)
			return
		ShotResult.Outcome.WATER:
			sounds.play(&"splash")
			strokes += 1
			ball_at = _water_drop(shot.rest, shot_from)
			msg = "Water hazard. One-stroke penalty, take a drop."
		ShotResult.Outcome.OUT_OF_BOUNDS:
			strokes += 1
			ball_at = shot_from
			msg = "Out of bounds. Stroke and distance."
		_:
			ball_at = shot.rest
			var s := hole.terrain.surface_at(ball_at.x, ball_at.z)
			if clubs[club_index].is_putter:
				msg = "%d ft to go" % roundi(_flat_distance(ball_at, hole.pin) * FEET_PER_METRE)
			else:
				msg = "%s    Carry %d yd    Total %d yd" % [Surface.name_of(s), roundi(shot.carry_m * YARDS_PER_METRE), roundi(shot.total_m * YARDS_PER_METRE)]
	if strokes >= MAX_STROKES:
		_finish_hole(true)
		return
	hud.show_message(msg)
	hud.hint.text = HINT_WAIT
	state = State.SHOT_RESULT
	result_timer = RESULT_PAUSE


func _after_result() -> void:
	hud.show_message("")
	_clear_trail()
	_prepare_shot(false)


func _finish_hole(picked_up: bool) -> void:
	card.record(hole_index, strokes)
	state = State.HOLE_DONE
	var title := "Picked up" if picked_up else Scorecard.score_name(strokes, hole.par)
	if not picked_up and strokes < hole.par:
		sounds.play(&"applause")
		if golfer:
			golfer.play(&"celebrate")
	hud.show_message("%s!   %d on the par %d.   Round: %s" % [title, strokes, hole.par, Scorecard.format_to_par(card.to_par())])
	hud.scorecard.show_card(card, course.course_name)
	hud.hint.text = HINT_WAIT
	_update_hud()


func _next_hole() -> void:
	if hole_index + 1 < course.holes.size():
		start_hole(hole_index + 1)
		return
	state = State.ROUND_DONE
	hud.show_message("Round complete: %d (%s). Click to play again." % [card.total_strokes(), Scorecard.format_to_par(card.to_par())])
	hud.scorecard.show_card(card, course.course_name, "Final")
	hud.hint.text = "Space or click: new round"


## Drop point for a ball in water: back along the line of flight to dry land,
## then two more metres, never further back than where the shot started.
func _water_drop(entry: Vector3, from: Vector3) -> Vector3:
	var dir := Vector3(from.x - entry.x, 0.0, from.z - entry.z)
	var span := dir.length()
	if span < 0.5:
		return from
	dir /= span
	var t := hole.terrain
	var travelled := 0.0
	while travelled < span:
		var p := entry + dir * travelled
		var s := t.surface_at(p.x, p.z)
		if s != Surface.Type.WATER and s != Surface.Type.OUT_OF_BOUNDS:
			break
		travelled += 1.0
	travelled += 2.0
	if travelled >= span:
		return from
	var drop := entry + dir * travelled
	drop.y = t.height_at(drop.x, drop.z)
	return drop


# --- Clubs and aim -----------------------------------------------------------

func _auto_club() -> void:
	var to_pin := _flat_distance(ball_at, hole.pin)
	if lie == Surface.Type.GREEN or (lie == Surface.Type.FRINGE and to_pin < 15.0):
		club_index = clubs.size() - 1
		return
	var power := Surface.lie_power(lie)
	var target := hole.aim_point(ball_at, clubs[0].total_m * power)
	var d := _flat_distance(ball_at, target)
	club_index = 0
	for i in clubs.size():
		if not clubs[i].is_putter and clubs[i].total_m * power >= d:
			club_index = i


## Where the auto-aim points with the current club.
func _aim_target() -> Vector3:
	if clubs[club_index].is_putter:
		return hole.pin
	return hole.aim_point(ball_at, _club_reach())


## Full-power total distance with the current club from the current lie.
func _club_reach() -> float:
	var club := clubs[club_index]
	if club.is_putter:
		return club.total_m
	return club.total_m * Surface.lie_power(lie)


func _aim_dir() -> Vector3:
	var a := deg_to_rad(aim_deg)
	return Vector3(sin(a), 0.0, cos(a))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- World and presentation --------------------------------------------------

func _build_world() -> void:
	scenery = Scenery.new()
	add_child(scenery)

	ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	ball.mesh = sphere
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color.WHITE
	ball_mat.emission_enabled = true
	ball_mat.emission = Color(0.25, 0.25, 0.25)
	ball.material_override = ball_mat
	add_child(ball)

	trail = MeshInstance3D.new()
	trail.mesh = _trail_mesh
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.albedo_color = Color(1, 1, 0.6)
	trail.material_override = trail_mat
	add_child(trail)

	aim_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.8
	ring.outer_radius = 1.0
	aim_marker.mesh = ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.9, 0.2)
	aim_marker.material_override = ring_mat
	add_child(aim_marker)

	camera = Camera3D.new()
	camera.far = 3000.0
	add_child(camera)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Hud.new()
	canvas.add_child(hud)
	settings_panel = SettingsPanel.new()
	canvas.add_child(settings_panel)
	settings_panel.changed.connect(_apply_graphics)


func _apply_graphics() -> void:
	graphics.apply_display(get_viewport())
	scenery.apply(graphics)
	camera.fov = graphics.fov
	if wind != null:
		wind.set_level(graphics.wind)
		if hole != null:
			_update_hud()


func _add_flag() -> void:
	var pin := hole.pin
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.04
	pole_mesh.bottom_radius = 0.04
	pole_mesh.height = 2.4
	pole.mesh = pole_mesh
	pole.position = pin + Vector3(0, 1.2, 0)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)
	pole.material_override = white
	hole_root.add_child(pole)

	var flag := MeshInstance3D.new()
	var cloth := BoxMesh.new()
	cloth.size = Vector3(0.02, 0.5, 0.8)
	flag.mesh = cloth
	flag.position = pin + Vector3(0, 2.15, 0.42)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.1, 0.1)
	red.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = red
	hole_root.add_child(flag)

	var cup := MeshInstance3D.new()
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = BallPhysics.CUP_RADIUS * 1.6
	cup_mesh.bottom_radius = BallPhysics.CUP_RADIUS * 1.6
	cup_mesh.height = 0.02
	cup.mesh = cup_mesh
	cup.position = pin + Vector3(0, 0.005, 0)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.03, 0.03)
	cup.material_override = black
	hole_root.add_child(cup)


func _add_tee_markers() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.15, 0.15)
	for side: float in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.12
		s.height = 0.24
		m.mesh = s
		m.material_override = mat
		var p: Vector3 = hole.tee + Vector3(3.5 * side, 0.0, 1.0)
		p.y = hole.terrain.height_at(p.x, p.z) + 0.1
		m.position = p
		hole_root.add_child(m)


func _place_ball(p: Vector3) -> void:
	_ball_base = p
	_update_ball_size()


## Draws the ball bigger with distance so it stays visible, as Links does.
func _update_ball_size() -> void:
	if not ball.visible:
		return
	var d := camera.position.distance_to(_ball_base)
	var r := maxf(BallPhysics.RADIUS, d * 0.0045)
	ball.scale = Vector3.ONE * r
	ball.position = _ball_base + Vector3.UP * r


func _place_golfer() -> void:
	if golfer == null:
		return
	var dir := _aim_dir()
	var left := Vector3.UP.cross(dir)
	golfer.basis = Basis.looking_at(-left, Vector3.UP)
	golfer.position = ball_at + left * 0.75
	golfer.visible = true
	golfer.play(&"address")


func _update_aim_marker() -> void:
	var club := clubs[club_index]
	var dir := _aim_dir()
	var reach := 0.0
	var size := 1.0
	if club.is_putter:
		reach = minf(_flat_distance(ball_at, hole.pin), club.total_m)
		size = 0.25
	else:
		reach = club.carry_m * Surface.lie_power(lie)
		size = clampf(reach * 0.02, 1.0, 4.0)
	var p := ball_at + dir * reach
	p.y = hole.terrain.height_at(p.x, p.z) + 0.08
	aim_marker.position = p
	aim_marker.scale = Vector3(size, 1.0, size)
	aim_marker.visible = true


func _update_hud() -> void:
	var club := clubs[club_index]
	var to_pin := _flat_distance(ball_at, hole.pin)
	var pin_text := "%d yd" % roundi(to_pin * YARDS_PER_METRE)
	if lie == Surface.Type.GREEN or to_pin < 20.0:
		pin_text = "%d ft" % roundi(to_pin * FEET_PER_METRE)
	var club_text := club.full_name
	if not club.is_putter:
		club_text += " (%d yd)" % roundi(_club_reach() * YARDS_PER_METRE)
	var thru := card.holes_played()
	var total := "E" if thru == 0 else Scorecard.format_to_par(card.to_par())
	hud.info.text = "%s    Hole %d    Par %d    %d yd\nStroke %d    To pin %s    Lie: %s\nClub: %s    Wind: %s\nRound: %s thru %d" % [
		course.course_name, hole.number, hole.par, roundi(hole.length_m() * YARDS_PER_METRE),
		strokes + 1, pin_text, Surface.name_of(lie),
		club_text, wind.describe(aim_deg),
		total, thru,
	]
	hud.wind.show_wind(wind, aim_deg)


func _clear_trail() -> void:
	_trail_mesh.clear_surfaces()


func _draw_trail(upto: int, head: Vector3) -> void:
	_trail_mesh.clear_surfaces()
	if shot == null or upto < 1:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in upto + 1:
		_trail_mesh.surface_add_vertex(shot.points[i] + Vector3.UP * 0.05)
	_trail_mesh.surface_add_vertex(head + Vector3.UP * 0.05)
	_trail_mesh.surface_end()


# --- Camera ------------------------------------------------------------------

## Behind the ball, looking down the aim line.
func _aim_camera(snap: bool) -> void:
	var dir := _aim_dir()
	var putting := clubs[club_index].is_putter
	var back := 3.5 if putting else 7.5
	var up := 1.5 if putting else 2.6
	_cam_pos = ball_at - dir * back + Vector3.UP * up
	_cam_look = ball_at + dir * (8.0 if putting else 60.0) + Vector3.UP * (0.0 if putting else 3.0)
	_keep_above_ground()
	if snap:
		camera.position = _cam_pos
		_cam_look_now = _cam_look
		camera.look_at(_cam_look_now)


## Holds at the tee for a moment, then chases the ball.
func _follow_camera(p: Vector3) -> void:
	_cam_look = p
	if shot_time < 0.6 and not clubs[club_index].is_putter:
		return
	var dir := _aim_dir()
	var putting := clubs[club_index].is_putter
	_cam_pos = p - dir * (4.0 if putting else 16.0) + Vector3.UP * (1.8 if putting else 6.0)
	_keep_above_ground()


func _keep_above_ground() -> void:
	var ground := hole.terrain.height_at(_cam_pos.x, _cam_pos.z)
	_cam_pos.y = maxf(_cam_pos.y, ground + 1.0)


func _update_camera(delta: float) -> void:
	camera.position = camera.position.lerp(_cam_pos, 1.0 - exp(-delta * 2.5))
	_cam_look_now = _cam_look_now.lerp(_cam_look, 1.0 - exp(-delta * 6.0))
	var to_look := _cam_look_now - camera.position
	if to_look.length() > 0.1 and absf(to_look.normalized().y) < 0.99:
		camera.look_at(_cam_look_now)
