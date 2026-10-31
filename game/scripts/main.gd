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

enum State { AIM, SWING, FLIGHT, SHOT_RESULT, HOLE_DONE, ROUND_DONE, COMPUTER, DROP }

const YARDS_PER_METRE := 1.0936
const FEET_PER_METRE := 3.2808
const MAX_STROKES := 10  ## pick up after this many on a hole
const AIM_RATE_DEG := 25.0  ## per second, holding left or right
const PUTT_AIM_RATE_DEG := 6.0
const RESULT_PAUSE := 2.5
const COMPUTER_THINK := 0.8  ## shortest time a computer golfer spends planning
const COMPUTER_ADDRESS := 1.2  ## then it stands over the ball this long
const COMPUTER_HOLE_PAUSE := 4.0  ## between holes when nobody is at the keyboard
const HINT_AIM := "Left/Right: aim (Shift: fine)    Up/Down: club    Space or click: swing    D: drop    Tab: scorecard    O: objects    Esc: menu"
const HINT_FREE_DROP := "    F: free drop"
const HINT_DROP := "%s: option    Arrows: move the ball (Shift: fine, Page Down: back 10 m)    Space or click: drop here"
const HINT_DROP_CANCEL := "    Backspace: cancel"
## Courses don't say which water is a lateral (red) hazard, so every water
## hazard offers lateral relief; the Rules of Golf let a course mark them all
## red.
const LATERAL_WATER := true
const HINT_SWING := "Click 1: start    Click 2: set power    Click 3: on the white line for a straight shot"
const HINT_COMPUTER := "%s is playing    Space or click: hurry up    Tab: scorecard"
const HINT_WAIT := "Space or click: continue    R: replay    Tab: scorecard"
const HINT_DONE := "Space or click: play again    M: main menu    Esc: menu"
const MENU_SCENE := "res://scenes/boot.tscn"
## Broadcast replays: slow motion near the landing and the cup.
const REPLAY_SLOW := 0.35
const REPLAY_SLOW_SPAN := 0.9  ## seconds either side of the landing
const REPLAY_HOLD := 1.0  ## seconds held on the final picture
## Approach shots landing this close to the pin get the pin camera picture.
const PIP_RANGE := 50.0
const AUTO_REPLAY_DELAY := 1.4


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
## Taking a drop (State.DROP): the DropRules.Reason, -1 when not dropping.
var _drop_reason := -1
var _drop_zones: Array[DropRules.Zone] = []
var _drop_choice := 0
var _drop_spot := Vector3.ZERO
var _drop_from := Vector3.ZERO  ## where the ball was, to cancel
var _drop_note := ""  ## why the last move was refused
var _drop_pending := false  ## the ball is in the water; drop before play moves on
var _water_entry := Vector3.ZERO

var shot_model: ShotModel
var wind: Wind
var sounds: SoundBank
var hud: Hud
var camera: RoundCamera
var ball: MeshInstance3D
var trail: MeshInstance3D
var aim_marker: MeshInstance3D
var drop_marker: MeshInstance3D  ## the edge of the drop zone
var golfer: GolferRig
var hole_root: Node3D
var graphics: GraphicsSettings
var scenery: Scenery
var settings_panel: SettingsPanel
var pause_menu: PauseMenu
var ambience: CourseAmbience
var post: PostProcess
var dynamic_resolution: DynamicResolution
var grass: GrassField

var _trail_mesh := ImmediateMesh.new()
## Broadcast presentation pieces (GraphicsSettings.presentation).
var broadcast := false
var tracer: BallTracer
var green_grid: GreenGrid
var grid_on := true
var _replaying := false
var _replay_time := 0.0
var _replay_count := 0
var _ball_was_visible := true
var _shot_from_pin := 0.0
var _replay_delay := -1.0  ## counts down to an automatic replay
var _pip := false
var _commentary_rng := RandomNumberGenerator.new()
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
	_stop_replay()
	round_setup = setup
	if round_setup == null:
		round_setup = RoundSetup.single(course_path if not course_path.is_empty() else chosen_course)
	if course_path.is_empty():
		course_path = round_setup.course_path
	course = AssetProviders.load_course(course_path)
	holes.clear()
	var pars: Array[int] = []
	var numbers: Array[int] = []
	var stroke_index: Array[int] = []
	for i in round_setup.hole_indices(course.holes.size()):
		var h := course.holes[i]
		if h.tees.size() > 1:
			h.tee = h.tees[round_setup.tee_index(h.tees.size())]
		holes.append(h)
		pars.append(h.par)
		numbers.append(h.number)
		stroke_index.append(h.stroke_index)
	scoring = RoundScoring.new(round_setup, pars, numbers, stroke_index)
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
	_drop_pending = false
	_drop_reason = -1
	drop_marker.visible = false
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
	if grass.terrain != hole.terrain:
		grass.setup(hole.terrain, graphics.grass)
	if ambience != null:
		ambience.start_hole(hole.tee)

	wind.start_hole()
	_update_wind_shaders()
	for p in players:
		p.at = hole.tee
		p.strokes = 0
		p.holed = false
		p.picked_up = false
	_clear_trail()
	hud.scorecard.visible = false
	_begin_turn(_next_player(), true)
	var text := "Hole %d    Par %d    %d yards" % [hole.number, hole.par, roundi(hole.length_m() * YARDS_PER_METRE)]
	if broadcast:
		text = ""
		hud.overlay.wipe()
		hud.overlay.hole_card({"number": hole.number, "par": hole.par,
			"yards": roundi(hole.length_m() * YARDS_PER_METRE), "name": course.course_name}, HoleMap.make(hole))
		camera.start_flyover(hole)
	if players.size() > 1:
		text += ("\n" if not text.is_empty() else "") + "%s has the honour" % scoring.names[current]
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
	if broadcast:
		var thru := card.holes_played()
		hud.overlay.lower_third(scoring.names[current], "%s    THRU %d    SHOT %d    %s TO THE PIN" % [
			"E" if thru == 0 else Scorecard.format_to_par(card.to_par()), thru, strokes + 1, _pin_text().to_upper()])


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
		golfer.set_shot(club, _flat_distance(ball_at, hole.pin), power)
		golfer.play(&"putt" if club.is_putter else &"swing")
	sounds.play(&"putt" if club.is_putter else &"hit")
	shot_from = ball_at
	_shot_from_pin = _flat_distance(ball_at, hole.pin)
	var start := shot_model.launch(club, power, accuracy, aim_deg, lie, ball_at)
	shot = shot_model.simulate(start, hole.terrain, hole.pin, wind.velocity())
	wind.next_shot()
	_update_wind_shaders()
	shot_time = 0.0
	_land_time = RoundCamera.time_near(shot, shot.first_landing) if shot.bounces > 0 else INF
	camera.follow(shot, hole.pin, club.is_putter)
	aim_marker.visible = false
	green_grid.visible = false
	if broadcast:
		hud.overlay.hide_lower_third()
		hud.overlay.hide_shot_card()
		hud.overlay.set_status(_status(false))
		_pip = not club.is_putter and graphics.quality >= GraphicsSettings.Quality.MEDIUM \
			and shot.carry_m > 40.0 and _flat_distance(shot.first_landing, hole.pin) < PIP_RANGE
		if _pip:
			_place_pip_camera()
		hud.overlay.show_pip(_pip)
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
		State.DROP:
			_finish_drop()
		State.HOLE_DONE:
			_next_hole()


func _process(delta: float) -> void:
	if _replaying:
		_process_replay(delta)
	else:
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
	if _replay_delay >= 0.0 and not _replaying:
		_replay_delay -= delta
		if _replay_delay < 0.0:
			start_replay()
	camera.update(delta, _replay_time if _replaying else shot_time, _ball_base)
	grass.update_around(camera.global_position)
	_update_ball_size()
	if broadcast:
		var playing := _replaying or state == State.FLIGHT
		hud.overlay.set_cam_tag(camera.director.cam_name(_replay_time if _replaying else shot_time) if playing and camera.director != null else "")
		if _pip and playing:
			hud.overlay.pip_camera.look_at(_ball_base)


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
	if state == State.DROP and event is InputEventKey and (event as InputEventKey).pressed:
		if _drop_key(event as InputEventKey):
			get_viewport().set_input_as_handled()
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
					SceneFade.change_scene(get_tree(), "res://scenes/object_viewer.tscn")
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
					SceneFade.change_scene(get_tree(), "res://scenes/course_viewer.tscn")
					return
				KEY_R:
					start_replay()
					return
				KEY_G:
					grid_on = not grid_on
					_update_green_grid()
					return
				KEY_D:
					if state == State.AIM and opponents[current] == null:
						_start_drop(DropRules.Reason.UNPLAYABLE)
					return
				KEY_F:
					if state == State.AIM and opponents[current] == null and hole.terrain.free_drop_at(ball_at.x, ball_at.z):
						_start_drop(DropRules.Reason.FREE_RELIEF)
					return
	var swing_pressed := event.is_action_pressed("swing")
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		swing_pressed = swing_pressed or (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT)
	if swing_pressed:
		get_viewport().set_input_as_handled()
		_on_swing_pressed()


func _on_swing_pressed() -> void:
	if _replaying:
		_stop_replay()
		return
	if state == State.AIM and camera.flying():
		camera.end_flyover()
		return
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
		State.DROP:
			_finish_drop()
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
	_place_golfer()  # the golfer takes the new club
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
	if hole.terrain.free_drop_at(ball_at.x, ball_at.z):
		hud.hint.text += HINT_FREE_DROP
	_place_ball(ball_at)
	_place_golfer()
	_update_aim_marker()
	_update_hud()
	_aim_camera(snap_camera)
	_update_green_grid()
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
	if broadcast:
		_report_shot()
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
			ball_at = shot.rest
			_water_entry = DropRules.water_entry(shot.points, hole.terrain)
			_drop_pending = true
			msg = "Water hazard. One-stroke penalty, take a drop."
		ShotResult.Outcome.OUT_OF_BOUNDS:
			strokes += 1
			ball_at = shot_from
			msg = "Out of bounds. Stroke and distance."
		_:
			ball_at = shot.rest
			var s := hole.terrain.surface_at(ball_at.x, ball_at.z)
			if broadcast:
				msg = ""
			elif clubs[club_index].is_putter:
				msg = "%d ft to go" % roundi(_flat_distance(ball_at, hole.pin) * FEET_PER_METRE)
			else:
				msg = "%s    Carry %d yd    Total %d yd" % [Surface.name_of(s), roundi(shot.carry_m * YARDS_PER_METRE), roundi(shot.total_m * YARDS_PER_METRE)]
	if strokes >= MAX_STROKES:
		_hole_out(true)
		return
	if players.size() > 1 and not msg.is_empty():
		msg = scoring.names[current] + ": " + msg
	if not msg.is_empty() or not broadcast:
		hud.show_message(msg)
	hud.hint.text = HINT_WAIT
	state = State.SHOT_RESULT
	result_timer = RESULT_PAUSE


func _after_result() -> void:
	_stop_replay()
	hud.show_message("")
	_clear_trail()
	if _drop_pending:
		_drop_pending = false
		_begin_drop(DropRules.Reason.WATER)
		return
	_pass_turn()


## The current player's shot is over: whoever plays next takes over.
func _pass_turn() -> void:
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
	_drop_pending = false
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
	_stop_replay()
	if hole_index + 1 < holes.size() and not scoring.decided():
		start_hole(hole_index + 1)
		return
	state = State.ROUND_DONE
	for p in players:
		p.marker.visible = false
	var text := "Round complete. " + scoring.winner_text()
	if players.size() == 1 and round_setup.mode == GameModes.Mode.STROKE:
		text = "Round complete: %d (%s)." % [card.total_strokes(), Scorecard.format_to_par(card.to_par())]
		if scoring.handicaps:
			var net := scoring.scored_card(0)
			text += "  Net %d (%s)." % [net.total_strokes(), Scorecard.format_to_par(net.to_par())]
	var records := _record_rounds()
	if not records.is_empty():
		text += "\n" + records
	hud.show_message(text)
	hud.scorecard.show_round(scoring, _round_name(), "Final")
	hud.hint.text = HINT_DONE


## Adds each finished card to the player's profile and says what it did to
## their handicap index. Rounds that stop early, or are shorter than nine
## holes, don't count.
func _record_rounds() -> String:
	var profiles := PlayerProfiles.load_saved()
	var date := Time.get_date_string_from_system()
	var lines: Array[String] = []
	for i in scoring.player_count():
		var player := scoring.names[i]
		var before := profiles.index_of(player)
		if not profiles.record_round(player, scoring.cards[i], scoring.ranks, course.course_name, date):
			continue
		var after := profiles.index_of(player)
		if after == Handicap.NONE:
			var left := 3 - profiles.rounds(player).size()
			lines.append("%s: %d more round%s for a handicap index." % [player, left, "" if left == 1 else "s"])
		elif before == Handicap.NONE or before == after:
			lines.append("%s's handicap index: %s." % [player, Handicap.format(after)])
		else:
			lines.append("%s's handicap index: %s (was %s)." % [player, Handicap.format(after), Handicap.format(before)])
	if not lines.is_empty():
		profiles.save()
	return "\n".join(lines)


func _quit_to_menu() -> void:
	SceneFade.change_scene(get_tree(), MENU_SCENE)


# --- Drops -------------------------------------------------------------------
# Water, an unplayable lie (D) and free relief from a cart path (F), with the
# options and zones of DropRules. The player picks an option, can move the
# ball inside the zone and drops; computer golfers take the default.

## A drop the player asks for while aiming.
func _start_drop(reason: int) -> void:
	if reason == DropRules.Reason.UNPLAYABLE:
		if lie == Surface.Type.TEE:
			hud.show_message("You can't drop on the tee.", 2.0)
			return
		if lie == Surface.Type.GREEN:
			hud.show_message("The ball is never unplayable on the green.", 2.0)
			return
	_begin_drop(reason)


func _begin_drop(reason: int) -> void:
	var reference := _water_entry if reason == DropRules.Reason.WATER else ball_at
	var in_sand := reason == DropRules.Reason.UNPLAYABLE and lie == Surface.Type.SAND
	_drop_reason = reason
	_drop_from = ball_at
	_drop_note = ""
	_drop_zones.clear()
	for option in DropRules.options(reason, LATERAL_WATER):
		_drop_zones.append(DropRules.zone(option, reference, shot_from, hole.pin, in_sand, hole.terrain))
	if reason == DropRules.Reason.FREE_RELIEF and not _drop_zones[0].found:
		_drop_reason = -1
		hud.show_message("There's no relief from the path near here.", 2.0)
		return
	_drop_choice = DropRules.best(_drop_zones, hole.pin)
	_drop_spot = _drop_zones[_drop_choice].spot
	if opponents[current] != null:
		_finish_drop()
		return
	state = State.DROP
	aim_marker.visible = false
	green_grid.visible = false
	if golfer:
		golfer.visible = false
	var keys := "1" if _drop_zones.size() == 1 else "1-%d" % _drop_zones.size()
	hud.hint.text = HINT_DROP % keys
	if reason != DropRules.Reason.WATER:
		hud.hint.text += HINT_DROP_CANCEL
	_show_drop()


func _select_drop(i: int) -> void:
	_drop_choice = i
	_drop_spot = _drop_zones[i].spot
	_drop_note = "" if _drop_zones[i].found else "There's nowhere to drop that way."
	_show_drop()


func _show_drop() -> void:
	var z := _drop_zones[_drop_choice]
	_place_ball(_drop_spot)
	var radius := z.radius if z.option != DropRules.Option.BACK_ON_LINE else DropRules.CLUB_LENGTH
	var centre := z.reference if z.option != DropRules.Option.BACK_ON_LINE else _drop_spot
	drop_marker.visible = z.found and z.option != DropRules.Option.STROKE_AND_DISTANCE
	drop_marker.position = Vector3(centre.x, hole.terrain.height_at(centre.x, centre.z) + 0.05, centre.z)
	drop_marker.scale = Vector3(radius, 1.0, radius)
	var to_pin := Vector3(hole.pin.x - _drop_spot.x, 0.0, hole.pin.z - _drop_spot.z)
	camera.aim(_drop_spot, to_pin.normalized() if to_pin.length() > 0.01 else Vector3.FORWARD, false)
	var titles := ["Water hazard: one-stroke penalty.", "Unplayable lie: one-stroke penalty.", "Free drop from the path."]
	var lines: Array[String] = []
	if players.size() > 1:
		lines.append(scoring.names[current])
	lines.append(titles[_drop_reason])
	for i in _drop_zones.size():
		lines.append("%s %d  %s" % [">" if i == _drop_choice else " ", i + 1, DropRules.OPTION_NAMES[_drop_zones[i].option]])
	if not _drop_note.is_empty():
		lines.append(_drop_note)
	hud.show_message("\n".join(lines))


## Moves the ball inside the zone: `back` metres away from the pin, `left`
## metres to the left as the camera sees it.
func _move_drop(back: float, left: float) -> void:
	var z := _drop_zones[_drop_choice]
	if z.option == DropRules.Option.STROKE_AND_DISTANCE or not z.found:
		return
	var side := Vector3(-z.direction.z, 0.0, z.direction.x)
	var p := _drop_spot + z.direction * back + side * left
	var c := DropRules.check(z, p, hole.pin, hole.terrain)
	if c == DropRules.Check.OK:
		_drop_spot = Vector3(p.x, hole.terrain.height_at(p.x, p.z), p.z)
		_drop_note = ""
	else:
		_drop_note = DropRules.CHECK_TEXT[c]
	_show_drop()


## Keys while dropping; true if the key was used.
func _drop_key(key: InputEventKey) -> bool:
	var step := 0.25 if key.shift_pressed else 1.0
	match key.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			var i := int(key.keycode - KEY_1)
			if not key.echo and i < _drop_zones.size():
				_select_drop(i)
		KEY_UP:
			_move_drop(-step, 0.0)
		KEY_DOWN:
			_move_drop(step, 0.0)
		KEY_PAGEDOWN:
			_move_drop(10.0, 0.0)
		KEY_LEFT:
			_move_drop(0.0, step * 0.5)
		KEY_RIGHT:
			_move_drop(0.0, -step * 0.5)
		KEY_BACKSPACE, KEY_D, KEY_F:
			if not key.echo:
				_cancel_drop()
		_:
			return false
	return true


func _cancel_drop() -> void:
	if _drop_reason == DropRules.Reason.WATER:
		return
	_drop_reason = -1
	drop_marker.visible = false
	ball_at = _drop_from
	hud.show_message("")
	_prepare_shot(false)


func _finish_drop() -> void:
	var z := _drop_zones[_drop_choice]
	if not z.found:
		_drop_note = "There's nowhere to drop that way. Pick another option."
		_show_drop()
		return
	var reason := _drop_reason
	_drop_reason = -1
	drop_marker.visible = false
	ball_at = _drop_spot
	# The water penalty was counted when the ball went in.
	if reason != DropRules.Reason.WATER:
		strokes += DropRules.penalty(reason)
	var what := DropRules.OPTION_NAMES[z.option]
	if reason == DropRules.Reason.UNPLAYABLE:
		what = "Unplayable: " + what.to_lower()
	shot_log.append("%s: %s, %.0f m left" % [scoring.names[current], what, _flat_distance(ball_at, hole.pin)])
	if strokes >= MAX_STROKES:
		_hole_out(true)
		return
	var msg := what + "."
	if players.size() > 1:
		msg = scoring.names[current] + ": " + msg
	if reason == DropRules.Reason.WATER:
		_pass_turn()
	else:
		_prepare_shot(false)
	hud.show_message(msg, 2.0)


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
	tracer = BallTracer.new()
	add_child(tracer)
	green_grid = GreenGrid.new()
	add_child(green_grid)

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

	drop_marker = MeshInstance3D.new()
	var drop_ring := TorusMesh.new()
	drop_ring.inner_radius = 0.96
	drop_ring.outer_radius = 1.0
	drop_marker.mesh = drop_ring
	var drop_mat := StandardMaterial3D.new()
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.albedo_color = Color(1.0, 1.0, 1.0)
	drop_marker.material_override = drop_mat
	drop_marker.visible = false
	add_child(drop_marker)

	camera = RoundCamera.new()
	camera.far = 3000.0
	add_child(camera)

	grass = GrassField.new()
	add_child(grass)
	post = PostProcess.new()
	add_child(post)
	dynamic_resolution = DynamicResolution.new()
	add_child(dynamic_resolution)

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
	post.apply(graphics)
	dynamic_resolution.setup(get_viewport(), graphics)
	camera.fov = graphics.fov
	camera.attributes = _camera_attributes()
	RenderingServer.global_shader_parameter_set("foliage_sway", 1.0 if graphics.foliage_wind else 0.0)
	if grass.level != graphics.grass and hole != null:
		grass.setup(hole.terrain, graphics.grass)
	broadcast = graphics.broadcast()
	camera.broadcast = broadcast
	hud.set_broadcast(broadcast)
	trail.visible = not broadcast
	tracer.visible = broadcast
	if not broadcast:
		hud.overlay.show_pip(false)
		camera.end_flyover()
	if hole != null and state == State.AIM:
		_update_green_grid()
	if wind != null:
		wind.set_level(graphics.wind)
		_update_wind_shaders()
		if hole != null:
			_update_hud()


## Depth of field (Forward+ only): the far distance goes softly out of
## focus, like a camera lens on a bright day; null for none.
func _camera_attributes() -> CameraAttributes:
	if not graphics.dof or not GraphicsSettings.is_forward_plus():
		return null
	var a := CameraAttributesPractical.new()
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = 260.0
	a.dof_blur_far_transition = 400.0
	a.dof_blur_amount = 0.05 if graphics.look == GraphicsSettings.Look.CINEMATIC else 0.03
	return a


## Tells the grass, trees and water which way the wind blows.
func _update_wind_shaders() -> void:
	var v := wind.velocity()
	RenderingServer.global_shader_parameter_set("wind_vector", Vector2(v.x, v.z))


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
	golfer.set_shot(clubs[club_index], _flat_distance(ball_at, hole.pin))
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
	if broadcast:
		hud.overlay.set_status(_status(state == State.AIM or state == State.SWING))


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
	tracer.clear()


func _draw_trail(upto: int, head: Vector3) -> void:
	_trail_mesh.clear_surfaces()
	if shot == null or upto < 1:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in upto + 1:
		_trail_mesh.surface_add_vertex(shot.points[i] + Vector3.UP * 0.05)
	_trail_mesh.surface_add_vertex(head + Vector3.UP * 0.05)
	_trail_mesh.surface_end()
	if broadcast:
		tracer.draw(shot.points, upto, head, camera.global_position)


# --- Camera ------------------------------------------------------------------

## Behind the ball, looking down the aim line. Links cuts straight to the
## new view rather than gliding, so this always snaps.
func _aim_camera(_snap: bool) -> void:
	camera.aim(ball_at, _aim_dir(), clubs[club_index].is_putter)


# --- Broadcast presentation ---------------------------------------------------

func _pin_text() -> String:
	var to_pin := _flat_distance(ball_at, hole.pin)
	if lie == Surface.Type.GREEN or to_pin < 20.0:
		return "%d ft" % roundi(to_pin * FEET_PER_METRE)
	return "%d yd" % roundi(to_pin * YARDS_PER_METRE)


## What the broadcast graphics show for the current player and shot.
func _status(aiming: bool) -> Dictionary:
	var club := clubs[club_index]
	var thru := card.holes_played()
	var club_text := club.full_name
	if not club.is_putter:
		club_text += "  (%d yd)" % roundi(_club_reach() * YARDS_PER_METRE)
	var rise := (hole.pin.y - ball_at.y) * FEET_PER_METRE
	var elev := "Level" if absf(rise) < 1.0 else "%s%d ft" % ["+" if rise > 0.0 else "", roundi(rise)]
	return {
		"hole": hole.number, "par": hole.par, "yards": roundi(hole.length_m() * YARDS_PER_METRE),
		"player": scoring.names[current], "to_par": "E" if thru == 0 else Scorecard.format_to_par(card.to_par()),
		"thru": thru, "stroke": strokes + 1, "club": club_text, "to_pin": _pin_text(),
		"lie": Surface.name_of(lie), "wind": wind.describe(aim_deg), "elevation": elev,
		"ticker": _ticker_text(), "aiming": aiming,
	}


## The scrolling line along the bottom: the leaderboard with more than one
## player, otherwise the round so far.
func _ticker_text() -> String:
	var parts: Array[String] = []
	if scoring.player_count() > 1:
		parts.append("LEADERBOARD")
		var pos := 1
		for row: Array in scoring.standings():
			parts.append("%d. %s  %s" % [pos, str(row[0]).to_upper(), row[1]])
			pos += 1
	else:
		parts.append(course.course_name.to_upper())
		parts.append(GameModes.MODE_NAMES[round_setup.mode].to_upper())
		parts.append("HOLE %d OF %d" % [hole_index + 1, holes.size()])
		var thru := card.holes_played()
		if thru > 0:
			parts.append("ROUND %d (%s) THRU %d" % [card.total_strokes(), Scorecard.format_to_par(card.to_par()), thru])
		parts.append("WIND %s" % wind.describe(aim_deg).to_upper())
	return "      \u00b7      ".join(parts)


## The shot card, a caption and the crowd after a shot (strokes already
## counted). Great shots get an automatic replay.
func _report_shot() -> void:
	var putting := clubs[club_index].is_putter
	var surface := hole.terrain.surface_at(shot.rest.x, shot.rest.z)
	var to_pin := _flat_distance(shot.rest, hole.pin)
	if shot.outcome == ShotResult.Outcome.HOLED:
		to_pin = 0.0
	hud.overlay.show_pip(false)
	var line: Array = Commentary.pick(shot, surface, putting, to_pin, _shot_from_pin, _commentary_rng)
	match line[1]:
		Commentary.Crowd.POLITE:
			sounds.play(&"applause")
		Commentary.Crowd.CHEER:
			sounds.play(&"crowd_cheer")
		Commentary.Crowd.ROAR:
			sounds.play(&"crowd_roar")
		Commentary.Crowd.GROAN:
			sounds.play(&"crowd_groan")
		Commentary.Crowd.OOH:
			sounds.play(&"crowd_ooh")
		_:
			# Spectators round the tee applaud a tee shot that finds the short grass.
			if strokes == 1 and not putting and (surface == Surface.Type.FAIRWAY or surface == Surface.Type.GREEN):
				sounds.play(&"crowd_tee")
	if not str(line[0]).is_empty():
		hud.show_message(line[0], 4.0)
	var where := "In the hole" if shot.outcome == ShotResult.Outcome.HOLED else Surface.name_of(surface)
	if shot.outcome == ShotResult.Outcome.WATER:
		where = "Water"
	elif shot.outcome == ShotResult.Outcome.OUT_OF_BOUNDS:
		where = "Out of bounds"
	var left := "-" if to_pin == 0.0 else ("%d ft" % roundi(to_pin * FEET_PER_METRE) if to_pin < 20.0 else "%d yd" % roundi(to_pin * YARDS_PER_METRE))
	var unit := FEET_PER_METRE if putting else YARDS_PER_METRE
	var u := " ft" if putting else " yd"
	hud.overlay.shot_card({
		"title": "%s  shot %d" % [clubs[club_index].full_name, strokes],
		"carry": "-" if putting else "%d%s" % [roundi(shot.carry_m * unit), u],
		"roll": "%d%s" % [roundi(maxf(0.0, shot.total_m - shot.carry_m) * unit), u],
		"total": "%d%s" % [roundi(shot.total_m * unit), u],
		"height": "-" if putting else "%d ft" % roundi(shot.apex_m * FEET_PER_METRE),
		"lie": where, "to_pin": left,
	})
	var great := shot.outcome == ShotResult.Outcome.HOLED and (not putting or _shot_from_pin > 9.0)
	great = great or (not putting and to_pin < 2.0 and _shot_from_pin > 60.0)
	if great:
		_replay_delay = AUTO_REPLAY_DELAY


## Replays the last shot from new camera angles, slowing down round the
## landing. Works between shots and after holing out; a click ends it.
func start_replay() -> bool:
	if shot == null or _replaying or not (state == State.SHOT_RESULT or state == State.HOLE_DONE):
		return false
	_replaying = true
	_replay_count += 1
	_replay_time = 0.0
	_ball_was_visible = ball.visible
	ball.visible = true
	hud.overlay.set_replay(true)
	hud.overlay.hide_shot_card()
	_clear_trail()
	var putting := clubs[club_index].is_putter
	camera.aim(shot_from, _aim_dir(), putting)
	camera.follow(shot, hole.pin, putting, _replay_count * 3 + 1)
	if golfer:
		golfer.play(&"putt" if putting else &"swing")
	sounds.play(&"putt" if putting else &"hit")
	return true


func _process_replay(delta: float) -> void:
	var t_land := RoundCamera.time_near(shot, shot.first_landing) if shot.bounces > 0 else -100.0
	var slow := absf(_replay_time - t_land) < REPLAY_SLOW_SPAN
	slow = slow or (shot.outcome == ShotResult.Outcome.HOLED and _replay_time > shot.time_s - 1.2)
	_replay_time += delta * (REPLAY_SLOW if slow else 1.0)
	var p := shot.position_at(_replay_time)
	_place_ball(p)
	_draw_trail(shot.sample_index_at(_replay_time), p)
	if shot.outcome == ShotResult.Outcome.HOLED and _replay_time >= shot.time_s:
		ball.visible = false
	if _replay_time >= shot.time_s + REPLAY_HOLD:
		_stop_replay()


func _stop_replay() -> void:
	_replay_delay = -1.0
	if not _replaying:
		return
	_replaying = false
	hud.overlay.set_replay(false)
	hud.overlay.wipe()
	ball.visible = _ball_was_visible
	_place_ball(shot.rest)
	_draw_trail(shot.points.size() - 1, shot.rest)
	result_timer = RESULT_PAUSE


func _place_pip_camera() -> void:
	var start := shot.points[0]
	var back := Vector3(hole.pin.x - start.x, 0.0, hole.pin.z - start.z).normalized()
	var p := hole.pin + back * 9.0 + Vector3.UP * 2.0
	p.y = maxf(p.y, hole.terrain.height_at(p.x, p.z) + 1.5)
	var cam := hud.overlay.pip_camera
	cam.position = p
	cam.look_at(hole.pin + Vector3.UP * 0.5)


func _update_green_grid() -> void:
	var on := broadcast and grid_on and state == State.AIM and clubs[club_index].is_putter \
		and (lie == Surface.Type.GREEN or lie == Surface.Type.FRINGE)
	green_grid.visible = on
	if on:
		green_grid.build(hole.terrain, ball_at, hole.pin)
