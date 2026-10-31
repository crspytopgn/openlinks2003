class_name GolfRound
extends Node3D
## One round of golf: aim, swing, watch the ball, hole out, next hole.
## Up to four players share the round (hot seat): everyone tees off in order
## of the honour, then whoever is furthest from the hole plays next. The game
## mode (RoundSetup, RoundScoring) decides what the cards mean. Any player can
## be a computer golfer (ComputerGolfer), which plans through the same
## ShotModel and swings with the mistakes of its level.
##
## Courses, objects, the golfer and sounds come from AssetProviders
## (placeholders until the decoders land) and the ball physics from a
## ShotModel, so none of them is wired in here.

enum State { AIM, SWING, FLIGHT, SHOT_RESULT, HOLE_DONE, ROUND_DONE, COMPUTER }

const YARDS_PER_METRE := 1.0936
const FEET_PER_METRE := 3.2808
const MAX_STROKES := 10  ## pick up after this many on a hole
const AIM_RATE_DEG := 25.0  ## per second, holding left or right
const PUTT_AIM_RATE_DEG := 6.0
const RESULT_PAUSE := 2.5
const COMPUTER_THINK := 0.8  ## shortest time a computer golfer spends planning
const COMPUTER_ADDRESS := 1.2  ## then it stands over the ball this long
const COMPUTER_HOLE_PAUSE := 4.0  ## between holes when nobody is at the keyboard
const HINT_AIM := "Left/Right: aim (Shift: fine)    Up/Down: club    Space or click: swing    Tab: scorecard    O: objects    Esc: menu"
const HINT_SWING := "Click 1: start    Click 2: set power    Click 3: on the white line for a straight shot"
const HINT_WAIT := "Space or click: continue    Tab: scorecard"
const HINT_COMPUTER := "%s is playing    Space or click: hurry up    Tab: scorecard"
const HINT_DONE := "Space or click: play again    M: main menu    Esc: menu"
const MENU_SCENE := "res://scenes/boot.tscn"


## One player's ball on the current hole.
class PlayerBall:
	var at := Vector3.ZERO
	var strokes := 0
	var holed := false
	var picked_up := false
	var marker: MeshInstance3D

	func done() -> bool:
		return holed or picked_up

## Course to load; empty plays the placeholder course.
@export var course_path := ""
## Set by the boot screen's course picker before it opens this scene.
static var chosen_course := ""
## Set by the round setup menu; null plays one player, stroke play, on
## `course_path` or `chosen_course`.
static var setup: RoundSetup
## Seeds the wind; 0 gives different conditions each round. Tests set it so
## their rounds play the same way every run.
static var wind_seed := 0

var state: State = State.AIM
var course: CourseData
## The holes being played, in order (all of the course, or a nine).
var holes: Array[HoleData] = []
var hole: HoleData
var hole_index := 0
var round_setup: RoundSetup
var scoring: RoundScoring
var players: Array[PlayerBall] = []
## Each player's computer golfer, or null for a person.
var opponents: Array[ComputerGolfer] = []
var current := 0  ## whose turn it is
var honour: Array[int] = []  ## tee-off order for this hole
## The current player's card.
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
var _land_time := INF  ## when the ball first lands; INF once the sound has played
## One line per shot on the current hole (who, club, lie, distances and
## outcome), for the tests and for tuning.
var shot_log := PackedStringArray()
var _computer_timer := 0.0
var _computer_ready := false  ## the computer has its plan and is addressing the ball
var _computer_backswing := false

var shot_model: ShotModel
var wind: Wind
var sounds: SoundBank
var hud: Hud
var camera: RoundCamera
var ball: MeshInstance3D
var trail: MeshInstance3D
var aim_marker: MeshInstance3D
var golfer: GolferRig
var hole_root: Node3D
var graphics: GraphicsSettings
var scenery: Scenery
var settings_panel: SettingsPanel
var pause_menu: PauseMenu
var ambience: CourseAmbience

var _trail_mesh := ImmediateMesh.new()
var _ball_base := Vector3.ZERO  ## bottom of the ball, as the physics sees it


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
	round_setup = setup
	if round_setup == null:
		round_setup = RoundSetup.single(course_path if not course_path.is_empty() else chosen_course)
	if course_path.is_empty():
		course_path = round_setup.course_path
	course = AssetProviders.load_course(course_path)
	holes.clear()
	var pars: Array[int] = []
	var numbers: Array[int] = []
	for i in round_setup.hole_indices(course.holes.size()):
		var h := course.holes[i]
		if h.tees.size() > 1:
			h.tee = h.tees[round_setup.tee_index(h.tees.size())]
		holes.append(h)
		pars.append(h.par)
		numbers.append(h.number)
	scoring = RoundScoring.new(round_setup, pars, numbers)
	for p in players:
		if p.marker:
			p.marker.queue_free()
	players.clear()
	opponents.clear()
	honour.clear()
	for i in scoring.player_count():
		var cpu: ComputerGolfer = null
		if round_setup.is_computer(i):
			cpu = ComputerGolfer.new(round_setup.computer_level(i), wind_seed * 31 + i + 1 if wind_seed != 0 else 0)
		opponents.append(cpu)
		var p := PlayerBall.new()
		p.marker = _make_ball_mesh()
		p.marker.visible = false
		add_child(p.marker)
		players.append(p)
		honour.append(i)
	current = 0
	card = scoring.cards[0]
	scenery.set_backdrop(course.horizon)
	if ambience != null:
		ambience.queue_free()
		ambience = null
	if course.read_entry.is_valid():
		ambience = CourseAmbience.create(course.read_entry)
		if ambience != null:
			add_child(ambience)
	wind = Wind.new(graphics.wind, wind_seed)
	hud.scorecard.visible = false
	start_hole(0)


func _round_name() -> String:
	var title := course.course_name
	if holes.size() < course.holes.size():
		title += "  (%s)" % RoundSetup.HOLES_NAMES[round_setup.holes].to_lower()
	if scoring.player_count() > 1 or round_setup.mode != GameModes.Mode.STROKE:
		title += "    " + GameModes.MODE_NAMES[round_setup.mode]
	return title


func start_hole(index: int) -> void:
	hole_index = index
	shot_log.clear()
	hole = holes[index]
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
	camera.terrain = hole.terrain
	if ambience != null:
		ambience.start_hole(hole.tee)

	wind.start_hole()
	for p in players:
		p.at = hole.tee
		p.strokes = 0
		p.holed = false
		p.picked_up = false
	_clear_trail()
	hud.scorecard.visible = false
	_begin_turn(_next_player(), true)
	var text := "Hole %d    Par %d    %d yards" % [hole.number, hole.par, roundi(hole.length_m() * YARDS_PER_METRE)]
	if players.size() > 1:
		text += "\n%s has the honour" % scoring.names[current]
	hud.show_message(text, 3.0)


## Who plays next: tee shots in order of the honour, then whoever is furthest
## from the hole. -1 once everyone has holed out or picked up.
func _next_player() -> int:
	for i in honour:
		if players[i].strokes == 0 and not players[i].done():
			return i
	var best := -1
	var best_d := -1.0
	for i in players.size():
		if players[i].done():
			continue
		var d := _flat_distance(players[i].at, hole.pin)
		if d > best_d:
			best = i
			best_d = d
	return best


func _begin_turn(index: int, snap_camera: bool) -> void:
	current = index
	var p := players[index]
	ball_at = p.at
	strokes = p.strokes
	card = scoring.cards[index]
	ball.visible = true
	_update_markers()
	_prepare_shot(snap_camera)


## Shows the other players' balls where they lie.
func _update_markers() -> void:
	for i in players.size():
		var p := players[i]
		p.marker.visible = i != current and p.strokes > 0 and not p.done()
		if p.marker.visible:
			_size_ball(p.marker, p.at)


## Keeps the current player's ball and strokes in their PlayerBall.
func _store_turn() -> void:
	players[current].at = ball_at
	players[current].strokes = strokes


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
	_land_time = RoundCamera.time_near(shot, shot.first_landing) if shot.bounces > 0 else INF
	camera.follow(shot)
	aim_marker.visible = false
	hud.show_message("")
	hud.hint.text = "Space or click: skip"
	state = State.FLIGHT


## Advances the game one step without input, playing sensible shots: used by
## the headless tests to play a whole round.
func auto_play_step() -> void:
	match state:
		State.COMPUTER:
			opponents[current].finish()
			_show_computer_plan()
			_computer_swing()
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
		State.COMPUTER:
			_process_computer(delta)
		State.HOLE_DONE:
			if round_setup.all_computer() and not pause_menu.visible and not settings_panel.visible:
				result_timer -= delta
				if result_timer <= 0.0:
					_next_hole()
	camera.update(delta, shot_time, _ball_base)
	_update_ball_size()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_ESCAPE:
					if settings_panel.visible:
						settings_panel.close()
						pause_menu.open()
					elif pause_menu.visible:
						pause_menu.close()
					else:
						pause_menu.open()
					get_viewport().set_input_as_handled()
					return
				KEY_F11:
					graphics.fullscreen = not graphics.fullscreen
					graphics.save()
					_apply_graphics()
					return
	if settings_panel.visible or pause_menu.visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_M:
					if state == State.ROUND_DONE:
						_quit_to_menu()
						return
				KEY_O:
					get_tree().change_scene_to_file("res://scenes/object_viewer.tscn")
					return
				KEY_TAB:
					if hud.scorecard.visible:
						hud.scorecard.visible = false
					else:
						hud.scorecard.show_round(scoring, _round_name())
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
		State.COMPUTER:
			# Hurry up: finish the plan and swing now.
			opponents[current].finish()
			_show_computer_plan()
			_computer_swing()
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
	# The first shot is played from the teeing ground, whatever mown grass
	# the course paints there.
	if strokes == 0 and ball_at.distance_to(hole.tee) < 0.5 and lie == Surface.Type.FAIRWAY:
		lie = Surface.Type.TEE
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
	if opponents[current] != null:
		_start_computer_turn()


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
	if shot_time >= _land_time:
		_land_time = INF
		sounds.play(&"land")
	if shot_time >= shot.time_s:
		_complete_flight()


func _complete_flight() -> void:
	shot_time = shot.time_s
	_place_ball(shot.rest)
	_draw_trail(shot.points.size() - 1, shot.rest)
	strokes += 1
	shot_log.append("%s %d: %s from %s %.0f m, %s, %.1f m left on %s" % [
		scoring.names[current], strokes, clubs[club_index].short_name, Surface.name_of(lie),
		_flat_distance(shot_from, hole.pin), ShotResult.Outcome.keys()[shot.outcome],
		_flat_distance(shot.rest, hole.pin), Surface.name_of(hole.terrain.surface_at(shot.rest.x, shot.rest.z))])
	var msg := ""
	match shot.outcome:
		ShotResult.Outcome.HOLED:
			sounds.play(&"cup")
			ball.visible = false
			_hole_out(false)
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
		_hole_out(true)
		return
	if players.size() > 1:
		msg = scoring.names[current] + ": " + msg
	hud.show_message(msg)
	hud.hint.text = HINT_WAIT
	state = State.SHOT_RESULT
	result_timer = RESULT_PAUSE


func _after_result() -> void:
	hud.show_message("")
	_clear_trail()
	_store_turn()
	var next := _next_player()
	if next < 0:
		_finish_hole()
		return
	if next == current:
		_prepare_shot(false)
	else:
		_begin_turn(next, true)
		if players.size() > 1:
			hud.show_message("%s to play" % scoring.names[current], 1.5)


## The current player is done with the hole: holed, or picked up after
## MAX_STROKES. The hole ends when everyone is.
func _hole_out(picked_up: bool) -> void:
	_store_turn()
	var p := players[current]
	p.holed = not picked_up
	p.picked_up = picked_up
	var title := "Picked up" if picked_up else Scorecard.score_name(strokes, hole.par)
	if not picked_up and strokes < hole.par:
		sounds.play(&"applause")
		if golfer:
			golfer.play(&"celebrate")
	if _next_player() < 0:
		_finish_hole()
		return
	_update_markers()
	hud.show_message("%s: %s!   %d on the par %d." % [scoring.names[current], title, strokes, hole.par])
	hud.hint.text = HINT_WAIT
	state = State.SHOT_RESULT
	result_timer = RESULT_PAUSE


func _finish_hole() -> void:
	for i in players.size():
		scoring.cards[i].record(hole_index, players[i].strokes)
	state = State.HOLE_DONE
	if players.size() == 1:
		var p := players[0]
		var title := "Picked up" if p.picked_up else Scorecard.score_name(p.strokes, hole.par)
		hud.show_message("%s!   %d on the par %d.   Round: %s" % [title, p.strokes, hole.par, Scorecard.format_to_par(card.to_par())])
	else:
		var parts: Array[String] = []
		for i in players.size():
			var p := players[i]
			parts.append("%s %d%s" % [scoring.names[i], p.strokes, " (picked up)" if p.picked_up else ""])
		var text := "   ".join(parts)
		var result := scoring.hole_result(hole_index)
		if not result.is_empty():
			text += "\n" + result
		hud.show_message(text)
	_update_honour()
	_update_markers()
	hud.scorecard.show_round(scoring, _round_name())
	hud.hint.text = HINT_WAIT
	result_timer = COMPUTER_HOLE_PAUSE
	_update_hud()


## The lowest score on the hole tees off first on the next; ties keep their
## order.
func _update_honour() -> void:
	var order := honour.duplicate()
	order.sort_custom(_tees_off_before)
	honour = order


func _tees_off_before(a: int, b: int) -> bool:
	var sa := players[a].strokes
	var sb := players[b].strokes
	return sa < sb or (sa == sb and honour.find(a) < honour.find(b))


func _next_hole() -> void:
	if hole_index + 1 < holes.size() and not scoring.decided():
		start_hole(hole_index + 1)
		return
	state = State.ROUND_DONE
	for p in players:
		p.marker.visible = false
	if players.size() == 1 and round_setup.mode == GameModes.Mode.STROKE:
		hud.show_message("Round complete: %d (%s)." % [card.total_strokes(), Scorecard.format_to_par(card.to_par())])
	else:
		hud.show_message("Round complete. " + scoring.winner_text())
	hud.scorecard.show_round(scoring, _round_name(), "Final")
	hud.hint.text = HINT_DONE


func _quit_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


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


# --- Computer golfers --------------------------------------------------------

func _start_computer_turn() -> void:
	state = State.COMPUTER
	_computer_timer = 0.0
	_computer_ready = false
	_computer_backswing = false
	opponents[current].plan(shot_model, clubs, hole, ball_at, lie, wind.velocity())
	hud.hint.text = HINT_COMPUTER % scoring.names[current]


## Plans over a few frames, lines up, then swings.
func _process_computer(delta: float) -> void:
	if pause_menu.visible or settings_panel.visible:
		return
	_computer_timer += delta
	var cpu := opponents[current]
	if not _computer_ready:
		if cpu.step() and _computer_timer >= COMPUTER_THINK:
			_show_computer_plan()
		return
	if not _computer_backswing and _computer_timer >= COMPUTER_ADDRESS - 0.5:
		_computer_backswing = true
		if golfer and not cpu.is_putt():
			golfer.play(&"backswing")
	if _computer_timer >= COMPUTER_ADDRESS:
		_computer_swing()


## Takes the club and line the computer chose and shows them.
func _show_computer_plan() -> void:
	var cpu := opponents[current]
	_computer_ready = true
	_computer_timer = 0.0
	club_index = cpu.club_index
	aim_deg = cpu.aim_deg
	_place_golfer()
	_update_aim_marker()
	_update_hud()
	_aim_camera(false)


func _computer_swing() -> void:
	var made := opponents[current].swing()
	aim_deg = made[2]
	hud.meter.reset()
	play_shot(made[0], made[1])


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

	ball = _make_ball_mesh()
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

	camera = RoundCamera.new()
	camera.far = 3000.0
	add_child(camera)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Hud.new()
	canvas.add_child(hud)
	hud.use_art(HudArt.load_from_game())
	settings_panel = SettingsPanel.new()
	canvas.add_child(settings_panel)
	settings_panel.changed.connect(_apply_graphics)
	pause_menu = PauseMenu.new()
	canvas.add_child(pause_menu)
	pause_menu.resume_pressed.connect(pause_menu.close)
	pause_menu.scorecard_pressed.connect(_on_pause_scorecard)
	pause_menu.settings_pressed.connect(_on_pause_settings)
	pause_menu.restart_pressed.connect(_on_pause_restart)
	pause_menu.menu_pressed.connect(_quit_to_menu)


func _make_ball_mesh() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	m.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.25, 0.25)
	m.material_override = mat
	return m


func _on_pause_scorecard() -> void:
	pause_menu.close()
	hud.scorecard.show_round(scoring, _round_name())


func _on_pause_settings() -> void:
	pause_menu.close()
	settings_panel.open(graphics)


func _on_pause_restart() -> void:
	pause_menu.close()
	start_round()


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


## Draws the balls bigger with distance so they stay visible, as Links does.
func _update_ball_size() -> void:
	if ball.visible:
		_size_ball(ball, _ball_base)
	for p in players:
		if p.marker.visible:
			_size_ball(p.marker, p.at)


func _size_ball(m: MeshInstance3D, base: Vector3) -> void:
	var d := camera.position.distance_to(base)
	var r := maxf(BallPhysics.RADIUS, d * 0.0045)
	m.scale = Vector3.ONE * r
	m.position = base + Vector3.UP * r


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
	var text := "%s    Hole %d    Par %d    %d yd\n" % [course.course_name, hole.number, hole.par, roundi(hole.length_m() * YARDS_PER_METRE)]
	if players.size() > 1 or opponents[current] != null:
		text += "%s    " % _player_label(current)
	text += "Stroke %d    To pin %s    Lie: %s\nClub: %s    Wind: %s\nRound: %s thru %d" % [
		strokes + 1, pin_text, Surface.name_of(lie), club_text, wind.describe(aim_deg), total, thru]
	var status := scoring.status_text()
	if not status.is_empty():
		text += "\n" + status
	hud.info.text = text
	hud.wind.show_wind(wind, aim_deg)


## The player's name, with the level of a computer golfer unless the name
## already says it.
func _player_label(i: int) -> String:
	var cpu := opponents[i]
	var label := scoring.names[i]
	if cpu != null and not label.begins_with(cpu.skill.level_name()):
		label += " (%s)" % cpu.skill.level_name()
	return label


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

## Behind the ball, looking down the aim line. Links cuts straight to the
## new view rather than gliding, so this always snaps.
func _aim_camera(_snap: bool) -> void:
	camera.aim(ball_at, _aim_dir(), clubs[club_index].is_putter)
