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

## REMOTE: an online round waits for another player's shot or drop.
enum State { AIM, SWING, FLIGHT, SHOT_RESULT, HOLE_DONE, ROUND_DONE, COMPUTER, DROP, DRIVE, REMOTE }

const YARDS_PER_METRE := 1.0936
const FEET_PER_METRE := 3.2808
const MAX_STROKES := 10  ## pick up after this many on a hole
const FEET_IN_SAND := 0.03  ## metres a golfer works his feet into a bunker
const CHIP_RANGE_M := 30.48  ## the game picks a Chip within 100 ft of the hole
const CLOUD_SHADOW := 0.32  ## how much light a passing cloud's shadow takes
const AIM_RATE_DEG := 25.0  ## per second, holding left or right
const PUTT_AIM_RATE_DEG := 6.0
const RESULT_PAUSE := 2.5
const COMPUTER_THINK := 0.8  ## shortest time a computer golfer spends planning
const COMPUTER_ADDRESS := 1.2  ## then it stands over the ball this long
const COMPUTER_HOLE_PAUSE := 4.0  ## between holes when nobody is at the keyboard
const HINT_AIM := "Left/Right or right-click: aim (Shift: fine)    Up/Down: club    Q/E/W/S: shape    %s    D: drop    Tab: scorecard%s    Esc: menu"
## The object viewer needs the game folder, which browsers can't read.
const HINT_OBJECTS := "    O: objects"
const HINT_AIM_METER := "Space or click: swing"
const HINT_AIM_MOUSE := "Hold the left button: mouse swing    Space: meter"
const HINT_PRACTICE := "Left/Right: aim (Shift: fine)    %s    V: read    N: new spot    [ ]: distance    L: slope    P: drill    T: next cup    H: next green    Esc: menu"
const HINT_FREE_DROP := "    F: free drop"
const HINT_DROP := "%s: option    Arrows: move the ball (Shift: fine, Page Down: back 10 m)    Space or click: drop here"
const HINT_DROP_CANCEL := "    Backspace: cancel"
## Courses don't say which water is a lateral (red) hazard, so every water
## hazard offers lateral relief; the Rules of Golf let a course mark them all
## red.
const LATERAL_WATER := true
const HINT_SWING := "Click 1: start    Click 2: set power    Click 3: on the white line for a straight shot"
const HINT_MOUSE_SWING := "Keep holding: pull the mouse back, then push it forward briskly and straight"
const HINT_AIM_TOUCH := "Swipe down, then flick up briskly and straight: swing    Tap: meter    Buttons: menu, club, aim"
const HINT_TOUCH_SWING := "Keep your finger down: drag it back, then flick it up briskly and straight"
const HINT_AIM_PAD := "    Pad: right stick swing, A meter, D-pad club, LB fine aim"
const HINT_STICK_SWING := "Right stick: pull it back, then push it forward briskly and straight    B: call it off"
const HINT_COMPUTER := "%s is playing    Space or click: hurry up    Tab: scorecard"
const HINT_DRIVE := "Up/Down or W/S: drive    Left/Right or A/D: steer    Space or click: skip to the ball    %d yd to go"
const HINT_DRIVE_TOUCH := "Hold and drag up to drive, down to reverse, sideways to steer    Tap: skip to the ball    %d yd to go"
const DRIVE_STICK_PX := 90.0  ## a drag this far is full pedal or full lock
const DRIVE_TAP_PX := 14.0  ## a touch that moves less than this is a tap
const DRIVE_MIN_M := 40.0  ## closer than this, the player walks
const DRIVE_ARRIVE_M := 14.0  ## stopped this close, they get out and play
const DRIVE_ARRIVE_GREEN_M := 40.0  ## the cart stays off the green
const HINT_WAIT := "Space or click: continue    R: replay    Tab: scorecard"
const HINT_REMOTE := "%s is playing    Tab: scorecard"
const HINT_DONE := "Space or click: play again    X: copy result code    M: main menu    Esc: menu"
const HINT_CAREER_DONE := "Space or click: back to your career    X: copy result code    Esc: menu"
const MENU_SCENE := "res://scenes/boot.tscn"
## Broadcast replays: slow motion near the landing and the cup.
const REPLAY_SLOW := 0.35
const REPLAY_SLOW_SPAN := 0.9  ## seconds either side of the landing
const REPLAY_HOLD := 1.0  ## seconds held on the final picture
## Approach shots landing this close to the pin get the pin camera picture.
const PIP_RANGE := 50.0
const AUTO_REPLAY_DELAY := 1.4


## One player's ball on the current hole.
## In scramble and alternate shot a team shares one: its first member's, and
## the partners' own balls sit out the hole.
class PlayerBall:
	var at := Vector3.ZERO
	var strokes := 0
	var holed := false
	var picked_up := false
	var marker: MeshInstance3D
	var inactive := false  ## a partner's ball in a shared-ball mode
	## Who plays this ball: the player, or the team in a shared-ball mode.
	var members: Array[int] = []
	var shots := 0  ## swings on this hole, for alternate shot's turns
	## Scramble: members who have hit from here this round of shots, and the
	## best of their shots so far ({at, add, score, by}).
	var round_turn := 0
	var round_best := {}
	## This hole's stats: tee shot on the fairway (-1 on a par 3), green in
	## regulation, putts.
	var fairway := -1
	var gir := false
	var putts := 0

	func done() -> bool:
		return holed or picked_up or inactive

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
## Keep finished rounds in RoundRecord.folder.
static var record_rounds := true
## A saved round to carry on with (SavedRound.load_state); start_round uses it
## once and clears it.
static var resume := {}
## An online round for the next GolfRound to play (the lobby sets it).
static var next_online: OnlineRound

var state: State = State.AIM
var course: CourseData
## The holes being played, in order (all of the course, or a nine).
var holes: Array[HoleData] = []
var hole: HoleData
var hole_index := 0
var round_setup: RoundSetup
## A Career round's title ("Kauri Classic, round 2") and the event
## leaderboard before it, for the ticker; empty otherwise.
var _career_title := ""
var _career_board: Array[String] = []
var scoring: RoundScoring
var players: Array[PlayerBall] = []
## Each player's computer golfer, or null for a person.
var opponents: Array[ComputerGolfer] = []
var current := 0  ## whose ball is being played
var shooter := 0  ## who is hitting it (a partner, in a shared-ball mode)
## The last person to play, for the hot-seat hand-over; -1 at the start.
var _last_human := -1
## The ball each player plays: their own, or their team's in a shared-ball mode.
var ball_of: Array[int] = []
## Each player's stats over the holes finished so far (PlayerProfiles.STATS).
var round_stats: Array[Dictionary] = []
var honour: Array[int] = []  ## tee-off order for this hole
## The current player's card.
var card: Scorecard
var clubs: Array[Club] = []
var club_index := 0
var strokes := 0
var ball_at := Vector3.ZERO
var lie: int = Surface.Type.TEE
var aim_deg := 0.0
## Draw, fade, high or low for the next shot (Links 2003's shot setup).
var shape := ShotShape.new()
## The practice range (RoundSetup.practice): the launch monitor and the
## session's shots.
var monitor_panel: LaunchMonitorPanel = null
var practice_session := LaunchMonitor.Session.new()
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
## The shot is a Chip (Links 2003's shot type): picked as the game does it,
## within 100 ft of the hole off the green and out of sand. Chips swing on
## their own meter and take their own power.
var _chip := false
## What is driving the mouse swing: the mouse, a finger or a thumbstick.
enum SwingInput { MOUSE, TOUCH, STICK }
var _swing_input := SwingInput.MOUSE
## A touch or stick swing's movement turned into the mouse's (AnalogSwing).
var _analog: AnalogSwing.Tracker = null
## The finger that touched down while aiming (-1 none) and where.
var _touch_index := -1
## Driving the buggy by touch: the finger, where it went down, and the stick it makes.
var _drive_touch := -1
var _drive_touch_from := Vector2.ZERO
var _drive_touch_moved := false
var _drive_stick := Vector2.ZERO
var _touch_from := Vector2.ZERO
## That finger's touch started the PowerStroke meter; dragging it back
## instead turns the meter off and swings with the swipe.
var _touch_started_meter := false
## When a finger last touched the screen (Time msec). The mouse clicks the
## engine and the browser make up from a touch arrive just after it.
var _touch_ms := -100000
## Mouse clicks this soon after a touch are taken as made up from it.
const TOUCH_MOUSE_IGNORE_MS := 800
## A shot's flight can't be skipped this early, so the tap or click that
## struck the ball (or a made-up copy of it) doesn't skip straight to the
## landing.
const FLIGHT_SKIP_GRACE_S := 0.8
## The right stick as the last motion events left it, and its pad.
var _stick_raw := Vector2.ZERO
var _stick_device := -1
## A new stick swing waits for the stick to come back to rest first.
var _stick_armed := true
## The game's swing-help count per player (the mouse swing's help option).
var _swing_help: Array[LinksMouse.Help] = []
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
const AIM_FLAT := 0.1  ## height of the aim ring over its width
const AIM_LIFT := 0.03  ## metres the ring floats above the grass
var drop_marker: MeshInstance3D  ## the edge of the drop zone
var golfer: GolferRig  ## the golfer playing now: one of _golfers
## Each player's golfer this hole; players who look the same share one.
var _golfers: Array[GolferRig] = []
## Each player's look (PlayerLook), or null to use the game's own golfer.
var _looks: Array = []
var hole_root: Node3D
var marks: CourseMarks  ## divots, pitch marks and sand craters on this hole
var graphics: GraphicsSettings
var scenery: Scenery
var settings_panel: SettingsPanel
var pause_menu: PauseMenu
var ambience: CourseAmbience
var free_ambience: FreeAmbience  ## for courses with no sounds of their own
var voice: GolferVoice
## Golfer voice lines still to come during the shot playing now.
var _voice_flight := ""
var _voice_flight_at := INF
var _voice_landing := ""
var post: PostProcess
var caddie: Caddie  ## Settings > Caddie; null when off
var buggy: GolfBuggy  ## Settings > Golf buggy; null when off
var _drive_to := -1  ## the ball the buggy is driving to
var dynamic_resolution: DynamicResolution
var grass: GrassField

var _trail_mesh := ImmediateMesh.new()
## Broadcast presentation pieces (GraphicsSettings.presentation).
var broadcast := false
var tracer: BallTracer
var green_grid: GreenGrid
## The Tour presentation (GraphicsSettings.Presentation.TOUR): the tour
## graphics package on top of Broadcast.
var tour := false
var driving_zone: DrivingZone
var putt_read: PuttRead
var _tour_map: HoleMap
var _tour_dots: Array = []  ## [where a shot finished, player] this hole
var _putt := {}
var _putt_from := Vector3.INF
var grid_on := true
## Green reading and the practice green (GreenRead, PuttingPractice).
var breakline: BreaklineIndicator
var assistant: PuttRead  ## Links 2003's Putting Assistant
var _assist := {}
var _assist_from := Vector3.INF
var read_view := 0  ## GreenRead.View
var practice: PuttingPractice  ## the putting green (RoundSetup.putting); null otherwise
var practice_cups: PracticeCups
var putting_panel: PuttingPanel
var _home_pins := {}  ## HoleData -> its own pin, while practising
var _replaying := false
var _cloud_offset := Vector2.ZERO  ## metres the cloud shadows have drifted
var _replay_time := 0.0
var _replay_count := 0
var _ball_was_visible := true
var _shot_from_pin := 0.0
var _replay_delay := -1.0  ## counts down to an automatic replay
var _pip := false
var _commentary_rng := RandomNumberGenerator.new()
var _ball_base := Vector3.ZERO  ## bottom of the ball, as the physics sees it
var _strike_sound := {}  ## the last shot's club, lie and power, for its replay
## Every random draw in the round comes from this (wind_seed, or a new seed).
var round_seed := 1
## The round's shots and drops, so it can be played again and checked
## (RoundReplay, docs/online-play.md).
var record: RoundRecord
var _holes_started := 0
## The PowerStroke mouse stroke for the shot being played, or null (play_shot
## uses it once).
var _mouse_stroke: LinksMouse.Stroke = null
## The swing help count before that stroke.
var _mouse_help: LinksMouse.Help = null
## The online round this game is part of, or null (OnlineRound).
var online: OnlineRound
## Another player's shot being played here, to check against theirs.
var _incoming: ShotRecord = null


func _ready() -> void:
	AssetProviders.ensure_defaults()
	shot_model = AssetProviders.shot_model
	clubs = Club.standard_set()
	graphics = GraphicsSettings.load_saved()
	_build_world()
	_apply_graphics()
	sounds = AssetProviders.create_sound_bank()
	add_child(sounds)
	var assets := AssetProviders.golfer_assets
	voice = GolferVoice.from_game_folder((assets as LinksGolferAssets).archive_path() if assets is LinksGolferAssets else "")
	if voice != null:
		add_child(voice)
		voice.spoke.connect(_caption_voice)
	var menu_sounds := MenuSounds.from_game_folder(false)
	if menu_sounds != null:
		add_child(menu_sounds)
	hud.meter.backswing_started.connect(_on_backswing_started)
	hud.meter.swing_finished.connect(_on_swing_finished)
	hud.mouse_swing.backswing_started.connect(_on_backswing_started)
	hud.mouse_swing.stroke_finished.connect(_on_mouse_stroke)
	hud.mouse_swing.stroke_cancelled.connect(_on_mouse_stroke_cancelled)
	hud.touch_pad.club_pressed.connect(_change_club)
	hud.touch_pad.menu_pressed.connect(_escape)
	if online == null:
		online = next_online
	next_online = null
	start_round()


func start_round() -> void:
	_stop_replay()
	round_setup = setup
	if round_setup == null:
		round_setup = RoundSetup.single(course_path if not course_path.is_empty() else chosen_course)
	if course_path.is_empty():
		course_path = round_setup.course_path
	course = AssetProviders.load_course(course_path)
	round_setup.course_name = course.course_name
	if round_setup.putting:
		round_setup.trim_for_practice()
	round_seed = wind_seed if wind_seed != 0 else (randi() & 0x7fffffff) | 1
	# A friend's round: the same wind, shot for shot.
	if round_setup.round_seed != 0:
		round_seed = round_setup.round_seed
	var versus := round_setup.challenge
	if versus != null:
		round_seed = versus.round_seed
	practice = PuttingPractice.new(round_seed) if round_setup.putting else null
	for h: HoleData in _home_pins:
		h.pin = _home_pins[h]  # the last practice moved them
	_home_pins.clear()
	holes.clear()
	if round_setup.pin_seed == 0 or resume.is_empty():
		round_setup.pin_seed = round_seed
	var pars: Array[int] = []
	var numbers: Array[int] = []
	var stroke_index: Array[int] = []
	for i in round_setup.hole_indices(course.holes.size()):
		var h := course.holes[i]
		if h.tees.size() > 1:
			h.tee = h.tees[round_setup.tee_index(h.tees.size())]
		h.pin = RoundSetup.pick_pin(h, round_setup.pins if versus == null else versus.pins, round_setup.pin_seed)
		holes.append(h)
		pars.append(h.par)
		numbers.append(h.number)
		stroke_index.append(h.stroke_index)
	scoring = RoundScoring.new(round_setup, pars, numbers, stroke_index)
	_career_title = ""
	_career_board.clear()
	if not round_setup.career.is_empty():
		var c := Career.load_saved()
		if c != null and c.round_id() == round_setup.career:
			_career_title = "%s, round %d" % [c.schedule[c.event].name, c.rounds_played() + 1]
			if c.rounds_played() > 0:
				_career_board.append("AFTER ROUND %d" % c.rounds_played())
				for line in c.leaderboard_lines(5):
					_career_board.append(line.to_upper())
	for p in players:
		if p.marker:
			p.marker.queue_free()
	players.clear()
	opponents.clear()
	honour.clear()
	ball_of.clear()
	var shared := GameModes.shared_ball(round_setup.mode)
	for i in scoring.player_count():
		ball_of.append(scoring.team_members(scoring.teams[i])[0] if shared else i)
	for i in scoring.player_count():
		var cpu: ComputerGolfer = null
		if round_setup.is_computer(i):
			cpu = ComputerGolfer.new(round_setup.computer_level(i), round_seed * 31 + i + 1)
		opponents.append(cpu)
		var p := PlayerBall.new()
		p.marker = _make_ball_mesh()
		p.marker.visible = false
		add_child(p.marker)
		players.append(p)
		if ball_of[i] == i:
			honour.append(i)
	for i in scoring.player_count():
		players[ball_of[i]].members.append(i)
	_choose_looks()
	current = 0
	shooter = 0
	_last_human = -1
	hud.hand_over.close()
	card = scoring.cards[0]
	scenery.set_backdrop(course.horizon, course.sky)
	if ambience != null:
		ambience.queue_free()
		ambience = null
	if course.read_entry.is_valid():
		ambience = CourseAmbience.create(course.read_entry)
		if ambience != null:
			add_child(ambience)
	if free_ambience != null:
		free_ambience.queue_free()
		free_ambience = null
	if ambience == null:
		free_ambience = FreeAmbience.create(course)
		add_child(free_ambience)
	var wind_level := graphics.wind
	if round_setup.wind_level >= 0:
		wind_level = round_setup.wind_level
	if versus != null:
		wind_level = versus.wind_level
	wind = Wind.new(wind_level, round_seed)
	_holes_started = 0
	record = RoundRecord.begin(round_setup, round_seed, "links" if shot_model is LinksShotModel else "standard", wind_level)
	record.course_hash = RoundRecord.file_hash(course_path)
	record.course_file = course_path.get_file()
	hud.scorecard.visible = false
	round_stats.clear()
	_undo = {}
	_mulligans_taken.clear()
	for _i in scoring.player_count():
		round_stats.append(PlayerProfiles.empty_stats())
	_setup_practice()
	var saved := {} if round_setup.practice else resume
	resume = {}
	record.resumed = not saved.is_empty()
	if saved.is_empty():
		start_hole(0)
	else:
		_restore(saved)


## Carries on with a saved round: the cards, the honour, then the hole with
## each ball where it lay.
func _restore(saved: Dictionary) -> void:
	var saved_cards: Array = saved.get("cards", [])
	for i in mini(saved_cards.size(), scoring.cards.size()):
		var row: Array = Array(saved_cards[i])
		for h in mini(row.size(), holes.size()):
			scoring.cards[i].record(h, int(row[h]))
	var saved_stats: Array = saved.get("stats", [])
	for i in mini(saved_stats.size(), round_stats.size()):
		var st: Dictionary = saved_stats[i]
		for key: String in round_stats[i]:
			round_stats[i][key] = int(st.get(key, 0))
	var order: Array = Array(saved.get("honour", []))
	var sorted := order.duplicate()
	sorted.sort()
	var expected := honour.duplicate()
	expected.sort()
	if sorted == expected:
		honour.clear()
		for i in order:
			honour.append(int(i))
	start_hole(clampi(int(saved.get("hole", 0)), 0, holes.size() - 1))
	var balls: Array = saved.get("balls", [])
	if balls.size() != players.size():
		return
	for i in players.size():
		var b: Dictionary = balls[i]
		players[i].at = b.get("at", hole.tee)
		players[i].strokes = int(b.get("strokes", 0))
		players[i].holed = b.get("holed", false) == true
		players[i].picked_up = b.get("picked_up", false) == true
		players[i].shots = int(b.get("shots", 0))
		players[i].round_turn = int(b.get("round_turn", 0))
		players[i].round_best = b.get("round_best", {})
		players[i].fairway = int(b.get("fairway", -1))
		players[i].gir = b.get("gir", false) == true
		players[i].putts = int(b.get("putts", 0))
	current = clampi(int(saved.get("current", 0)), 0, players.size() - 1)
	var next := _next_player()
	if next < 0:
		# Saved on the end-of-hole screen: the stats already count the hole.
		_finish_hole(false)
		return
	_begin_turn(next, true)
	hud.show_message("Round resumed: %s to play" % scoring.names[shooter], 2.5)


## Saves where the round stands (SavedRound), so it can be resumed.
func _save_progress() -> void:
	if state == State.ROUND_DONE or practice != null or round_setup.practice:
		return
	var saved_cards: Array = []
	for c in scoring.cards:
		saved_cards.append(PackedInt32Array(c.strokes))
	var balls: Array = []
	for p in players:
		balls.append({"at": p.at, "strokes": p.strokes, "holed": p.holed, "picked_up": p.picked_up,
			"shots": p.shots, "round_turn": p.round_turn, "round_best": p.round_best,
			"fairway": p.fairway, "gir": p.gir, "putts": p.putts})
	SavedRound.save(round_setup, {
		"hole": hole_index, "number": hole.number, "current": current,
		"honour": PackedInt32Array(honour), "cards": saved_cards, "balls": balls,
		"stats": round_stats,
	})


## The object and course viewers (O, C) come back to a new round scene, so
## the round is carried over as if resumed. Only between shots: a shot in
## the air would be lost.
func _visit(scene: String) -> void:
	if round_setup.practice:
		return
	if not (state == State.AIM or state == State.HOLE_DONE or state == State.ROUND_DONE):
		return
	prepare_return()
	SceneFade.change_scene(get_tree(), scene)


## Saves the round and keeps it to carry on with when this scene opens again.
func prepare_return() -> void:
	_save_progress()
	resume = SavedRound.load_state() if state != State.ROUND_DONE else {}


func _round_name() -> String:
	if not _career_title.is_empty():
		return _career_title
	var title := course.course_name
	if holes.size() < course.holes.size():
		title += "  (%s)" % RoundSetup.HOLES_NAMES[round_setup.holes].to_lower()
	if scoring.player_count() > 1 or round_setup.mode != GameModes.Mode.STROKE:
		title += "    " + GameModes.MODE_NAMES[round_setup.mode]
	return title


func start_hole(index: int) -> void:
	hole_index = index
	shot_log.clear()
	_undo = {}
	_drop_pending = false
	_drop_reason = -1
	drop_marker.visible = false
	hole = holes[index]
	# Courses that limit each hole to its own ground judge out of bounds by it.
	hole.terrain.hole_number = hole.number
	var practice_spot := Vector3.INF
	if practice != null:
		# The practice green's cups are cut round the hole's own pin; the one
		# being putted to is the pin while practising.
		if not _home_pins.has(hole):
			_home_pins[hole] = hole.pin
		hole.pin = _home_pins[hole]
		practice_spot = practice.setup(hole)
		hole.pin = practice.cup_position()
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
	if practice != null:
		practice_cups = PracticeCups.new()
		hole_root.add_child(practice_cups)
		practice_cups.build(practice.cups, practice.cup)
	else:
		_add_flag()
	_add_tee_markers()
	marks = CourseMarks.new()
	hole_root.add_child(marks)
	if scenery.sun != null:
		# The sun moves on through the round with that time of day.
		scenery.set_round_progress(float(index) / maxf(holes.size() - 1, 1))
		GroundShade.bake(hole, course.objects, -scenery.sun.global_transform.basis.z)
	_make_golfers()
	camera.terrain = hole.terrain
	if grass.terrain != hole.terrain:
		grass.setup(hole.terrain, graphics.grass)
	if ambience != null:
		ambience.start_hole(hole.tee)

	wind.start_hole()
	_holes_started += 1
	_update_wind_shaders()
	if free_ambience != null:
		free_ambience.start_hole(hole, wind.velocity().length())
	for i in players.size():
		var p := players[i]
		p.at = hole.tee if practice == null else practice_spot
		p.strokes = 0
		p.holed = false
		p.picked_up = false
		p.inactive = ball_of[i] != i
		p.shots = 0
		p.round_turn = 0
		p.round_best = {}
		p.fairway = -1
		p.gir = false
		p.putts = 0
		_tint_ball(p.marker, i)
	_clear_trail()
	hud.scorecard.visible = false
	if buggy != null:
		buggy.set_bags(players.size())
		_park_buggy(hole.tee)
	_begin_turn(_next_player(), true)
	var text := "Hole %d    Par %d    %d yards" % [hole.number, hole.par, roundi(hole.length_m() * YARDS_PER_METRE)]
	if practice != null:
		text = "Practice green: hole %d\n%s" % [hole.number, PuttingPractice.DRILL_HELP[practice.drill]]
	if broadcast and practice == null:
		text = ""
		hud.overlay.wipe()
		_tour_dots.clear()
		_putt_from = Vector3.INF
		_tour_map = HoleMap.build(hole) if tour else null
		hud.overlay.hole_card({"number": hole.number, "par": hole.par,
			"yards": roundi(hole.length_m() * YARDS_PER_METRE), "name": course.course_name}, HoleMap.make(hole))
		camera.start_flyover(hole)
	if players.size() > 1:
		text += ("\n" if not text.is_empty() else "") + "%s has the honour" % _side_name(current)
	hud.show_message(text, 3.0)


## Who plays next: tee shots in order of the honour, then whoever is furthest
## from the hole. -1 once everyone has holed out or picked up.
func _next_player() -> int:
	# Scramble: the rest of the team hits from the same spot first.
	if current < players.size() and players[current].round_turn > 0 and not players[current].done():
		return current
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
	shooter = _shooter_of(index)
	_use_golfer(shooter)
	_tint_ball(ball, index)
	var p := players[index]
	ball_at = p.at
	strokes = p.strokes
	card = scoring.cards[shooter]
	ball.visible = true
	_update_markers()
	_prepare_shot(snap_camera)
	sounds.play(&"footsteps")  # stepping up to the ball
	if broadcast:
		var thru := card.holes_played()
		hud.overlay.lower_third(scoring.names[shooter], "%s    THRU %d    SHOT %d    %s TO THE PIN" % [
			"E" if thru == 0 else Scorecard.format_to_par(card.to_par()), thru, strokes + 1, _pin_text().to_upper()])
	_hand_over()


## Hot seat: when the next swing is a different person's from the last one,
## dim the screen until they're at the keyboard. Computer golfers don't need
## it, and a person playing against them alone never sees it.
func _hand_over() -> void:
	if opponents[shooter] != null or online != null:
		return
	if _last_human >= 0 and _last_human != shooter:
		var detail := "Hole %d    Shot %d    %s to the pin" % [hole.number, strokes + 1, _pin_text()]
		if players[current].members.size() > 1:
			detail = "For %s    %s" % [_side_name(current), detail]
		hud.hand_over.open(scoring.names[shooter], detail)
	_last_human = shooter


## Shows the other players' balls where they lie.
func _update_markers() -> void:
	for i in players.size():
		var p := players[i]
		p.marker.visible = i != current and p.strokes > 0 and not p.done()
		if p.marker.visible:
			_size_ball(p.marker, p.at)


## Who hits ball `b` next: its player, or in a shared-ball mode the partner
## whose turn it is (alternate shot swaps every swing and on each tee).
func _shooter_of(b: int) -> int:
	var p := players[b]
	var n := p.members.size()
	if n <= 1:
		return b
	if round_setup.mode == GameModes.Mode.SCRAMBLE:
		return p.members[p.round_turn % n]
	return p.members[(p.shots + hole_index) % n]


## The player, or the team in a shared-ball mode, playing ball `b`.
func _side_name(b: int) -> String:
	if players[b].members.size() > 1:
		return scoring.team_name(scoring.teams[b])
	return scoring.names[b]


## Keeps the current player's ball and strokes in their PlayerBall.
func _store_turn() -> void:
	players[current].at = ball_at
	players[current].strokes = strokes


## Plays a shot with the current club and aim. The swing meter calls this;
## tests call it directly.
## `monitor` is a real swing from a launch monitor (OpenConnect), played as
## measured; power and accuracy then only drive the animation.
func play_shot(power: float, accuracy: float, monitor: OpenConnect.Launch = null) -> void:
	var club := clubs[club_index]
	if caddie != null:
		caddie.quiet()
	players[current].shots += 1
	if golfer:
		golfer.set_shot(club, _flat_distance(ball_at, hole.pin), power)
		golfer.play(&"putt" if club.is_putter else &"swing")
		golfer.watch(ball, 0.7 if club.is_putter else 0.3)
	_strike_sound = {"club": club, "lie": lie, "power": power}
	sounds.play_detail(&"hit", _strike_sound)
	shot_from = ball_at
	_shot_from_pin = _flat_distance(ball_at, hole.pin)
	var p := players[current]
	_undo = {"strokes": strokes, "putts": p.putts, "fairway": p.fairway, "gir": p.gir, "shots": p.shots - 1,
		"lie": lie, "from": ball_at, "drive": int(round_stats[shooter].get("longest_drive_yd", 0)) if shooter < round_stats.size() else 0,
		"record": record.shots.size()}
	var rec := ShotRecord.new()
	rec.index = record.shots.size()
	rec.player = shooter
	rec.ball = current
	rec.hole = hole_index
	rec.holes_started = _holes_started
	rec.club = club_index
	rec.club_name = club.short_name
	rec.aim_deg = aim_deg
	rec.power = power
	rec.accuracy = accuracy
	rec.lie = lie
	rec.from = ball_at
	rec.skill = graphics.skill
	rec.computer = round_setup != null and round_setup.is_computer(shooter)
	# A computer's swing or putt makes Links 2003's own computer misses.
	if rec.computer and opponents[shooter] != null:
		rec.cpu_rating = opponents[shooter].skill.links_rating
		rec.to_hole_m = ball_at.distance_to(hole.pin) if club.is_putter else _shot_from_pin
	rec.chip = _chip and not club.is_putter
	rec.stroke = null if rec.computer else _mouse_stroke
	rec.help = null if rec.computer else _mouse_help
	if not rec.computer and not club.is_putter:
		var setup := shape.to_setup(club.short_name)
		rec.ball_position = setup.ball_position
		rec.face = setup.face
		rec.stance = setup.stance
	if monitor != null:
		rec.monitor = monitor.to_array()
		rec.stroke = null
		rec.help = null
	rec.wind_level = wind.level
	rec.wind = wind.velocity()
	if _incoming != null:
		rec.skill = _incoming.skill
	_mouse_stroke = null
	_mouse_help = null
	shot = RoundReplay.run_shot(shot_model, rec, club, hole.terrain, hole.pin, rec.wind, round_seed)
	rec.rest = shot.rest
	rec.outcome = shot.outcome
	record.shots.append(rec)
	if marks != null:
		marks.add_divot(hole.terrain, ball_at, _aim_dir(), club, lie, _chip and not club.is_putter)
	if online != null:
		if _incoming == null:
			online.send_shot(rec)
		elif rec.outcome != _incoming.outcome or rec.rest.distance_to(_incoming.rest) > RoundReplay.REST_TOLERANCE_M:
			online.report_mismatch(online.seq - 1)
			hud.show_message("%s's shot stopped somewhere else here: the round is marked not agreed." % scoring.names[shooter], 3.0)
	wind.next_shot()
	_update_wind_shaders()
	if free_ambience != null:
		free_ambience.set_wind(wind.velocity().length())
	shot_time = 0.0
	_land_time = RoundCamera.time_near(shot, shot.first_landing) if shot.bounces > 0 else INF
	camera.follow(shot, hole.pin, club.is_putter)
	_plan_voice(power, accuracy)
	aim_marker.visible = false
	green_grid.visible = false
	_hide_green_aids()
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
	_update_tour()


## Advances the game one step without input, playing sensible shots: used by
## the headless tests to play a whole round.
func auto_play_step() -> void:
	hud.hand_over.close()
	match state:
		State.COMPUTER:
			opponents[shooter].finish()
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
		State.DRIVE:
			_skip_drive()
		State.HOLE_DONE:
			_next_hole()
		State.REMOTE:
			_poll_online()
			_apply_remote()


func _process(delta: float) -> void:
	_drift_clouds(delta)
	_update_wind_shaders()
	# The pause menu and settings stop the round: the swing meter, the ball
	# in the air and the countdowns all wait.
	var paused := pause_menu.visible or settings_panel.visible
	hud.meter.set_process(not paused)
	# The meter would sit on top of the drop options and means nothing there.
	hud.meter.visible = state != State.DROP
	if state != State.AIM and hud.overlay != null:
		hud.overlay.end_hole_card()  # the hole card must not sit over the shot
	if online != null:
		_poll_online()
	if paused:
		pass
	elif _replaying:
		_process_replay(delta)
	else:
		match state:
			State.AIM:
				if not hud.hand_over.visible:
					_process_aim(delta)
			State.FLIGHT:
				_process_flight(delta)
			State.SHOT_RESULT:
				result_timer -= delta
				if result_timer <= 0.0:
					_after_result()
			State.COMPUTER:
				_process_computer(delta)
			State.DRIVE:
				_process_drive(delta)
			State.REMOTE:
				_apply_remote()
			State.HOLE_DONE:
				# Online, every game moves on by itself so nobody waits.
				if (round_setup.all_computer() or online != null) and not pause_menu.visible and not settings_panel.visible:
					result_timer -= delta
					if result_timer <= 0.0:
						_next_hole()
	if _replay_delay >= 0.0 and not _replaying and not paused:
		_replay_delay -= delta
		if _replay_delay < 0.0:
			start_replay()
	if state != State.DRIVE:
		camera.update(delta, _replay_time if _replaying else shot_time, _ball_base)
	grass.update_around(camera.global_position)
	_update_ball_size()
	if broadcast:
		var playing := _replaying or state == State.FLIGHT
		hud.overlay.set_cam_tag(camera.director.cam_name(_replay_time if _replaying else shot_time) if playing and camera.director != null else "")
		if _pip and playing:
			var pc := hud.overlay.pip_camera
			pc.look_at(pip_target(pc.global_position, _ball_base))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed and jb.button_index == JOY_BUTTON_START:
			_escape()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_ESCAPE:
					_escape()
					get_viewport().set_input_as_handled()
					return
				KEY_F11:
					graphics.fullscreen = not graphics.fullscreen
					graphics.save()
					_apply_graphics()
					return
	if settings_panel.visible or pause_menu.visible:
		return
	if hud.hand_over.visible and not (event is InputEventKey and (event as InputEventKey).keycode == KEY_TAB):
		var go := event.is_action_pressed("swing") or event.is_action_pressed("ui_accept")
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			go = go or (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT)
		if go:
			hud.hand_over.close()
			get_viewport().set_input_as_handled()
		return
	if state == State.DROP and event is InputEventKey and (event as InputEventKey).pressed:
		if _drop_key(event as InputEventKey):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if _putting_key(key.keycode):
				get_viewport().set_input_as_handled()
				return
			match key.keycode:
				KEY_M:
					if state == State.ROUND_DONE:
						_quit_to_menu()
						return
				KEY_X:
					if state == State.ROUND_DONE:
						DisplayServer.clipboard_set(record.to_code())
						hud.show_message("Result code copied. Send it to a friend: their game checks it and can play the same course and wind.", 4.0)
						return
				KEY_O:
					if _objects_viewable():
						_visit("res://scenes/object_viewer.tscn")
					return
				KEY_TAB:
					if hud.scorecard.visible:
						hud.scorecard.visible = false
					else:
						hud.scorecard.show_round(scoring, _round_name())
					return
				KEY_U:
					if state == State.SHOT_RESULT and _can_mulligan():
						_take_mulligan()
					return
				KEY_N, KEY_B:
					if round_setup.practice and state == State.AIM and holes.size() > 1:
						var step := 1 if key.keycode == KEY_N else -1
						start_hole(posmod(hole_index + step, holes.size()))
					return
				KEY_Q, KEY_E, KEY_W, KEY_S:
					_shape_key(key.keycode)
					return
				KEY_UP:
					_change_club(-1)
					return
				KEY_DOWN:
					_change_club(1)
					return
				KEY_C:
					_visit("res://scenes/course_viewer.tscn")
					return
				KEY_R:
					start_replay()
					return
				KEY_G:
					if key.ctrl_pressed:
						_cycle_grid_style()
					elif not _grid_allowed():
						hud.show_message("No grid at Elite skill, as in Links 2003", 2.0)
					else:
						grid_on = not grid_on
						_update_green_grid()
					return
				KEY_D:
					if state == State.AIM and opponents[shooter] == null and practice == null:
						_start_drop(DropRules.Reason.UNPLAYABLE)
					return
				KEY_F:
					if state == State.AIM and opponents[shooter] == null and practice == null and hole.terrain.free_drop_at(ball_at.x, ball_at.z):
						_start_drop(DropRules.Reason.FREE_RELIEF)
					return
	if state == State.DRIVE and _drive_touch_input(event):
		get_viewport().set_input_as_handled()
		return
	if _stick_swing_input(event) or _pad_button(event):
		get_viewport().set_input_as_handled()
		return
	if _click_aim_input(event):
		get_viewport().set_input_as_handled()
		return
	if _mouse_swing_input(event):
		get_viewport().set_input_as_handled()
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
			hud.meter.mode = _meter_mode()
			hud.meter.click()
		State.SWING:
			# Space mid mouse swing would start the meter on top of it.
			if not hud.mouse_swing.is_swinging():
				hud.meter.click()
		State.FLIGHT:
			if shot_time >= FLIGHT_SKIP_GRACE_S:
				_complete_flight()
		State.SHOT_RESULT:
			_after_result()
		State.DROP:
			_finish_drop()
		State.DRIVE:
			_skip_drive()
		State.COMPUTER:
			# Hurry up: finish the plan and swing now.
			opponents[shooter].finish()
			_show_computer_plan()
			_computer_swing()
		State.HOLE_DONE:
			_next_hole()
		State.ROUND_DONE:
			if online != null or not round_setup.career.is_empty():
				_quit_to_menu()
			else:
				start_round()


## Esc (Start on a pad, the menu button on a touch screen): back out of the
## settings, close the pause menu, or open it.
func _escape() -> void:
	if settings_panel.visible:
		settings_panel.close()
		pause_menu.open()
	elif pause_menu.visible:
		pause_menu.close()
	else:
		open_pause_menu()


## Esc: the pause menu. A mouse swing in progress is called off, since the
## menu takes the button's release.
func open_pause_menu() -> void:
	if hud.mouse_swing.is_swinging():
		hud.mouse_swing.reset()
		_on_mouse_stroke_cancelled()
	_touch_index = -1
	hud.touch_pad.release_all()
	pause_menu.open()


## Links 2003's mouse swing: holding the left button while aiming starts
## it (with the mouse swing chosen); Space still uses the meter.
func _mouse_swing_input(event: InputEvent) -> bool:
	var ms := hud.mouse_swing
	if event is InputEventMouse and _made_from_touch(event as InputEventMouse):
		# The mouse events a touch screen makes up (the engine's, and on
		# iPad Safari's own): the finger has its own swing and meter taps,
		# so while aiming, swinging or watching the flight only the touch
		# counts. Otherwise one tap would click the meter twice.
		return state == State.AIM or state == State.SWING or state == State.FLIGHT \
			or ms.is_swinging() or _touch_index >= 0
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if ms.is_swinging():
			if not mb.pressed and _swing_input == SwingInput.MOUSE:
				ms.release()
			return true
		if mb.pressed and graphics.swing_method == 1 and _can_start_swing():
			_begin_mouse_swing(SwingInput.MOUSE)
			return true
	elif event is InputEventMouseMotion and ms.is_swinging():
		if _swing_input == SwingInput.MOUSE:
			ms.motion((event as InputEventMouseMotion).screen_relative)
		return true
	return false


## Right-click on the course: aim at that spot and take the club that
## reaches it (ClickAim). Putts only turn the aim.
func _click_aim_input(event: InputEvent) -> bool:
	if not event is InputEventMouseButton:
		return false
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed or mb.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if state != State.AIM or _replaying or camera.flying() or opponents[shooter] != null:
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var hit: Variant = ClickAim.ray_ground(hole.terrain, cam.project_ray_origin(mb.position), cam.project_ray_normal(mb.position))
	if hit == null:
		return true
	aim_at(hit as Vector3)
	return true


## Aims at `spot`, and away from the green takes the club whose full swing
## reaches it.
func aim_at(spot: Vector3) -> void:
	if _flat_distance(ball_at, spot) < 0.5:
		return
	aim_deg = rad_to_deg(atan2(spot.x - ball_at.x, spot.z - ball_at.z))
	if not clubs[club_index].is_putter and not _chip:
		var reaches: Array[float] = []
		for c in clubs:
			reaches.append(-1.0 if c.is_putter else c.total_m * shot_model.reach_scale(c) * Surface.lie_power(lie))
		var pick := ClickAim.club_for(reaches, _flat_distance(ball_at, spot))
		if pick != club_index:
			club_index = pick
			sounds.play(&"club")
			_tell_monitor()
			_place_golfer()
	hud.show_message("%d yd to the target" % roundi(_flat_distance(ball_at, spot) * YARDS_PER_METRE), 1.5)
	_update_aim_marker()
	_update_hud()
	_aim_camera(false)
	_update_green_grid()
	_update_green_aids()


## Settings > Captions: the golfer's spoken line.
func _caption_voice(event_name: String) -> void:
	if graphics.captions:
		hud.show_sound_caption(SoundCaptions.voice(event_name, "Golfer" if players.size() == 1 else scoring.names[shooter]))


## Settings > Captions: the crowd after a broadcast shot.
func _caption_crowd(crowd: int) -> void:
	if not graphics.captions:
		return
	var sound: StringName = {Commentary.Crowd.POLITE: &"applause", Commentary.Crowd.CHEER: &"crowd_cheer",
		Commentary.Crowd.ROAR: &"crowd_roar", Commentary.Crowd.GROAN: &"crowd_groan",
		Commentary.Crowd.OOH: &"crowd_ooh"}.get(crowd, &"")
	var text := SoundCaptions.crowd(sound)
	if not text.is_empty():
		hud.show_sound_caption(text)


## Whether the player may start a swing now.
func _can_start_swing() -> bool:
	return state == State.AIM and not _replaying and not camera.flying() and not hud.mouse_swing.is_swinging()


## Starts Links 2003's mouse swing, driven by the mouse, a finger or a stick.
func _begin_mouse_swing(source: SwingInput) -> void:
	hud.scorecard.visible = false
	state = State.SWING
	hud.meter.reset()
	var club := clubs[club_index]
	var number := LinksMouse.PUTTER
	if not club.is_putter:
		number = LinksLaunch.CLUB_INDEX.get(club.short_name, 0)
	var chip := _chip and not club.is_putter
	_swing_input = source
	hud.mouse_swing.begin(number, graphics.skill, chip, source == SwingInput.MOUSE)
	var shot := LinksMouse.Shot.FULL
	if club.is_putter:
		shot = LinksMouse.Shot.PUTT
	elif chip:
		shot = LinksMouse.Shot.CHIP
	_analog = AnalogSwing.Tracker.new(AnalogSwing.reach_px(shot, number))
	match source:
		SwingInput.TOUCH:
			hud.hint.text = HINT_TOUCH_SWING
		SwingInput.STICK:
			hud.hint.text = HINT_STICK_SWING
		_:
			hud.hint.text = HINT_MOUSE_SWING


## Whether a mouse event was made up from a touch: by the engine, or by the
## browser just after a touch ended.
func _made_from_touch(e: InputEventMouse) -> bool:
	if e.device == InputEvent.DEVICE_ID_EMULATION:
		return true
	return e is InputEventMouseButton and Time.get_ticks_msec() - _touch_ms < TOUCH_MOUSE_IGNORE_MS


## Touches reach the swing before the HUD does, so a tap anywhere but on a
## button counts at once: over the info panels or the meter as well.
func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	_touch_ms = Time.get_ticks_msec()
	if settings_panel.visible or pause_menu.visible or hud.hand_over.visible:
		return
	if _touch_swing_input(event):
		get_viewport().set_input_as_handled()


## Whether `at` is on a button (the touch pad's, the putting panel's...),
## which takes the tap instead of the swing.
func _over_button(at: Vector2) -> bool:
	if hud.touch_pad.covers(at):
		return true
	for n: Node in hud.find_children("*", "BaseButton", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(at):
			return true
	return false


## A finger on a touch screen. Each tap is a PowerStroke click the moment the
## finger lands: the first starts the meter, the second sets the power and
## the third the accuracy, as Links 2003's clicks. Dragging back from the
## first touch instead turns it into the mouse swing (AnalogSwing turns the
## drag into the mouse's movement). While the ball flies, a tap skips to the
## landing, but not straight after the strike.
func _touch_swing_input(event: InputEvent) -> bool:
	var ms := hud.mouse_swing
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _touch_index >= 0 or _over_button(t.position):
				return false
			match state:
				State.AIM:
					if _can_start_swing():
						_touch_index = t.index
						_touch_from = t.position
					_on_swing_pressed()  # or ends a flyover or replay
					_touch_started_meter = _touch_index >= 0 and hud.meter.is_swinging()
					return true
				State.SWING:
					if not ms.is_swinging():
						hud.meter.click()
					return true
				State.FLIGHT:
					_on_swing_pressed()
					return true
			return false
		if t.index != _touch_index:
			return false
		_touch_index = -1
		_touch_started_meter = false
		if ms.is_swinging() and _swing_input == SwingInput.TOUCH:
			ms.release()  # before the downswing this calls the swing off
		return true
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index != _touch_index:
			return false
		var at := AnalogSwing.touch(_touch_from, d.position, get_viewport().get_visible_rect().size.y)
		if not ms.is_swinging():
			if not _touch_started_meter or at.y <= AnalogSwing.START:
				return true
			# Dragged back, not tapped: the meter the touch started gives
			# way to the swipe swing, before the power is set.
			_touch_started_meter = false
			if hud.meter.phase != SwingMeter.Phase.BACKSWING or hud.meter.power_position != 0:
				return true
			hud.meter.reset()
			state = State.AIM
			if not _can_start_swing():
				return true
			_begin_mouse_swing(SwingInput.TOUCH)
		if _swing_input == SwingInput.TOUCH:
			ms.motion(_analog.feed(at))
		return true
	return false


## The right stick on a game pad: pulling it back while aiming starts the
## mouse swing and pushing it forward swings the club down (AnalogSwing).
## B calls it off before the downswing.
func _stick_swing_input(event: InputEvent) -> bool:
	var ms := hud.mouse_swing
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed and jb.button_index == JOY_BUTTON_B and ms.is_swinging() and _swing_input == SwingInput.STICK:
			ms.release()
			return true
		return false
	if not (event is InputEventJoypadMotion):
		return false
	var m := event as InputEventJoypadMotion
	if m.axis != JOY_AXIS_RIGHT_X and m.axis != JOY_AXIS_RIGHT_Y:
		return false
	if m.device != _stick_device:
		_stick_device = m.device
		_stick_raw = Vector2.ZERO
	if m.axis == JOY_AXIS_RIGHT_X:
		_stick_raw.x = m.axis_value
	else:
		_stick_raw.y = m.axis_value
	var at := AnalogSwing.stick(_stick_raw)
	if not ms.is_swinging():
		if at.y <= 0.0:
			_stick_armed = true
		if not _stick_armed or at.y <= AnalogSwing.START or not _can_start_swing():
			return true
		_stick_armed = false
		_begin_mouse_swing(SwingInput.STICK)
	if _swing_input == SwingInput.STICK:
		ms.motion(_analog.feed(at))
	return true


## A game pad's other buttons while playing: the D-pad changes club (left
## and right aim, as the arrow keys) and Back shows the scorecard.
func _pad_button(event: InputEvent) -> bool:
	if not (event is InputEventJoypadButton) or not (event as InputEventJoypadButton).pressed:
		return false
	match (event as InputEventJoypadButton).button_index:
		JOY_BUTTON_DPAD_UP:
			_change_club(-1)
		JOY_BUTTON_DPAD_DOWN:
			_change_club(1)
		JOY_BUTTON_BACK:
			if hud.scorecard.visible:
				hud.scorecard.visible = false
			else:
				hud.scorecard.show_round(scoring, _round_name())
		_:
			return false
	return true


## The club met the ball: Links 2003's mouse maths make the swing (the
## LinksShotModel uses it; the standard model gets a power and an accuracy).
func _on_mouse_stroke(stroke: LinksMouse.Stroke) -> void:
	if state != State.SWING:
		return
	while _swing_help.size() <= shooter:
		_swing_help.append(LinksMouse.Help.new())
	var help := _swing_help[shooter]
	help.enabled = graphics.swing_help
	# The swing's draws come from the round seed and the help count is kept
	# as it was before the swing, so a replay makes the same swing.
	_mouse_help = RoundReplay.copy_help(help)
	var mw := RoundReplay.mouse_outcome(stroke, round_seed, record.shots.size(), help)
	_mouse_stroke = stroke
	var inputs := RoundReplay.mouse_inputs(stroke, mw)
	play_shot(inputs.x, inputs.y)


func _on_mouse_stroke_cancelled() -> void:
	if state == State.SWING:
		state = State.AIM
		hud.hint.text = _aim_hint()
		if golfer:
			golfer.play(&"address")


func _on_backswing_started() -> void:
	if caddie != null:
		caddie.quiet()
	if golfer and not clubs[club_index].is_putter:
		golfer.play(&"backswing")


func _on_swing_finished(power: float, accuracy: float) -> void:
	if state == State.SWING:
		if _chip and not clubs[club_index].is_putter:
			# A chip's meter position reads its own power table.
			power = LinksPowerStroke.chip_power(hud.meter.power_position) / 100.0
		play_shot(power, accuracy)


func _change_club(step: int) -> void:
	if state != State.AIM:
		return
	var before := club_index
	club_index = clampi(club_index + step, 0, clubs.size() - 1)
	if club_index != before:
		sounds.play(&"club")
		_tell_monitor()
	_place_golfer()  # the golfer takes the new club
	_update_aim_marker()
	_update_hud()
	_aim_camera(false)
	_update_green_grid()
	_update_green_aids()


## Q/E draw and fade, W/S high and low, for a person's full swing or chip.
func _shape_key(keycode: Key) -> void:
	if state != State.AIM or opponents[shooter] != null or clubs[club_index].is_putter:
		return
	var changed := false
	match keycode:
		KEY_Q:
			changed = shape.nudge_curve(-1)
		KEY_E:
			changed = shape.nudge_curve(1)
		KEY_W:
			changed = shape.nudge_height(1)
		KEY_S:
			changed = shape.nudge_height(-1)
	if changed:
		sounds.play(&"club")
		_update_hud()


## A driver from the tee that stays in play counts for the longest drive.
func _note_drive(strokes_before: int) -> void:
	if strokes_before != 0 or clubs[club_index].short_name != "Dr" or shot.outcome != ShotResult.Outcome.REST:
		return
	if shooter >= round_stats.size():
		return
	var yd := roundi(shot.total_m * YARDS_PER_METRE)
	round_stats[shooter]["longest_drive_yd"] = maxi(int(round_stats[shooter].get("longest_drive_yd", 0)), yd)


# --- Launch monitor ------------------------------------------------------------
# Settings > Launch monitor (desktop): a launch monitor app sends real shots
# over OpenConnect, and the person's next shot is played as measured.

var monitor_server: OpenConnectServer = null


func _set_monitor(on: bool) -> void:
	if on == (monitor_server != null):
		return
	if not on:
		monitor_server.stop()
		monitor_server.queue_free()
		monitor_server = null
		return
	monitor_server = OpenConnectServer.new()
	add_child(monitor_server)
	if not monitor_server.start():
		hud.show_message("Launch monitor: port %d is in use (is another simulator open?)." % OpenConnect.PORT, 4.0)
		monitor_server.queue_free()
		monitor_server = null
		return
	monitor_server.shot_received.connect(_on_monitor_shot)
	monitor_server.connected_changed.connect(func(c: bool) -> void:
		hud.show_message("Launch monitor connected." if c else "Launch monitor disconnected.", 2.5))
	_tell_monitor()


## The launch monitor app hears which club is up.
func _tell_monitor() -> void:
	if monitor_server != null and not clubs.is_empty():
		monitor_server.send_player(true, clubs[club_index].short_name)


func _on_monitor_shot(launch: OpenConnect.Launch) -> void:
	if _replaying or pause_menu.visible or settings_panel.visible:
		return
	if state != State.AIM or opponents[shooter] != null:
		return
	if camera.flying():
		camera.end_flyover()
	hud.hand_over.close()
	hud.scorecard.visible = false
	var club := clubs[club_index]
	var full := club.ball_speed_mps if club.ball_speed_mps > 0.0 else 1.0
	var power := clampf(launch.speed_mph * OpenConnect.MPS_PER_MPH / full, 0.05, 1.0)
	hud.meter.reset()
	play_shot(power, 0.0, launch)


# --- Mulligans ----------------------------------------------------------------
# Settings > Mulligans: right after a shot, U takes it again as if it never
# happened. The shot stays in the record, marked, and off the card.

## The state before the last shot, for a mulligan.
var _undo := {}
## Each player's mulligans so far: the hole index of each.
var _mulligans_taken: Array = []


func _can_mulligan() -> bool:
	if graphics.mulligans == 0 or _undo.is_empty() or round_setup.practice or not _house_rules():
		return false
	if GameModes.shared_ball(round_setup.mode) or opponents[shooter] != null or shot == null:
		return false
	if players[current].done() or state == State.HOLE_DONE:
		return false
	if shot.outcome == ShotResult.Outcome.HOLED or int(_undo.record) != record.shots.size() - 1:
		return false
	while _mulligans_taken.size() <= shooter:
		_mulligans_taken.append([])
	for h: int in _mulligans_taken[shooter]:
		if graphics.mulligans == 2 and h == hole_index:
			return false
		if graphics.mulligans == 1 and h / 9 == hole_index / 9:
			return false
	return true


func _take_mulligan() -> void:
	(_mulligans_taken[shooter] as Array).append(hole_index)
	var rec: ShotRecord = record.shots[int(_undo.record)]
	rec.mulligan = true
	var p := players[current]
	strokes = int(_undo.strokes)
	p.putts = int(_undo.putts)
	p.fairway = int(_undo.fairway)
	p.gir = bool(_undo.gir)
	p.shots = int(_undo.shots)
	if shooter < round_stats.size():
		round_stats[shooter]["longest_drive_yd"] = int(_undo.drive)
	_drop_pending = false
	ball_at = _undo.from
	_undo = {}
	_clear_trail()
	ball.visible = true
	_place_ball(ball_at)
	hud.show_message("%sMulligan: take it again." % ["" if players.size() == 1 else scoring.names[shooter] + ": "], 2.0)
	_prepare_shot(false)


# --- Pick up -----------------------------------------------------------------

## The score at which `par`'s hole is picked up for Settings > Pick up
## (GraphicsSettings.pickup), never past MAX_STROKES.
static func pickup_limit(setting: int, par: int) -> int:
	match setting:
		1:
			return mini(MAX_STROKES, 2 * par)
		2:
			return mini(MAX_STROKES, par + 3)
	return MAX_STROKES


## This hole's pick-up score. A friend's round keeps the usual limit so the
## result codes compare.
func _pickup_at() -> int:
	if not _house_rules():
		return MAX_STROKES
	return pickup_limit(graphics.pickup, hole.par)


## Whether this game's own Settings (mulligans, gimmes, pick up) apply. Not
## in a friend's round, so result codes compare, nor online, where each game
## must end every hole on the same shot as the others.
func _house_rules() -> bool:
	return round_setup.challenge == null and online == null


# --- Gimmes -------------------------------------------------------------------

## Settings > Gimmes: the ball stopped on the green close enough to concede.
## Not in a friend's round (the codes must play the same) or a scramble
## (whose best ball is picked after everyone has played).
func _gimme_now() -> bool:
	var feet: float = GraphicsSettings.GIMME_FEET[graphics.gimme]
	if feet <= 0.0 or shot.outcome != ShotResult.Outcome.REST or not _house_rules():
		return false
	if round_setup.mode == GameModes.Mode.SCRAMBLE:
		return false
	if hole.terrain.surface_at(shot.rest.x, shot.rest.z) != Surface.Type.GREEN:
		return false
	return _flat_distance(shot.rest, hole.pin) * FEET_PER_METRE <= feet


## The conceded putt counts one stroke, kept with the drops so the replay
## checker adds it to the card.
func _concede_putt() -> void:
	strokes += 1
	players[current].putts += 1
	record.drops.append({"ball": current, "hole": hole_index, "reason": -1, "penalty": 1, "gimme": true})
	shot_log.append("%s: gimme from %.1f ft" % [scoring.names[shooter], _flat_distance(shot.rest, hole.pin) * FEET_PER_METRE])
	hud.show_message("%sThat's a gimme." % ["" if players.size() == 1 else scoring.names[shooter] + ": "], 2.0)
	_hole_out(false)


# --- Practice range ----------------------------------------------------------
# RoundSetup.practice: one person hits from the tee as often as they like; the
# ball comes back each time and the launch monitor shows the shot. No scores,
# stats or saved progress.

func _setup_practice() -> void:
	if monitor_panel != null:
		monitor_panel.queue_free()
		monitor_panel = null
	practice_session = LaunchMonitor.Session.new()
	if not round_setup.practice:
		return
	monitor_panel = LaunchMonitorPanel.new()
	monitor_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	monitor_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	monitor_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	monitor_panel.position.x -= 16
	hud.add_child(monitor_panel)


func _practice_shot_done() -> void:
	var club := clubs[club_index]
	var reading := LaunchMonitor.read(club.full_name, shot, shot_from, aim_deg)
	practice_session.add(reading)
	if monitor_panel != null:
		monitor_panel.show_reading(reading, practice_session.summary(club.full_name))
	var msg := "Carry %d yd    Total %d yd    %s" % [roundi(reading.carry_yd), roundi(reading.total_yd),
		Surface.name_of(hole.terrain.surface_at(shot.rest.x, shot.rest.z))]
	match shot.outcome:
		ShotResult.Outcome.HOLED:
			sounds.play(&"cup")
			msg = "In the hole!"
		ShotResult.Outcome.WATER:
			sounds.play(&"splash")
			msg = "In the water."
		ShotResult.Outcome.OUT_OF_BOUNDS:
			msg = "Out of bounds."
	hud.show_message(msg)
	hud.hint.text = HINT_WAIT
	state = State.SHOT_RESULT
	result_timer = RESULT_PAUSE * 2.0


## The ball comes back to the tee for the next practice shot.
func _practice_reset() -> void:
	ball.visible = true
	ball_at = hole.tee
	_place_ball(ball_at)
	strokes = 0
	_prepare_shot(false)


# --- Shot flow ---------------------------------------------------------------

func _prepare_shot(snap_camera: bool) -> void:
	state = State.AIM
	lie = hole.terrain.surface_at(ball_at.x, ball_at.z)
	# Shots from the teeing ground (the first, or again after out of bounds
	# or a stroke-and-distance drop) are teed up, whatever mown grass the
	# course paints there.
	if ball_at.distance_to(hole.tee) < 0.5 and lie == Surface.Type.FAIRWAY:
		lie = Surface.Type.TEE
	shape.reset()
	_auto_club()
	_tell_monitor()
	var target := _aim_target()
	aim_deg = rad_to_deg(atan2(target.x - ball_at.x, target.z - ball_at.z))
	hud.meter.reset()
	hud.mouse_swing.reset()
	hud.hint.text = _aim_hint()
	if hole.terrain.free_drop_at(ball_at.x, ball_at.z):
		hud.hint.text += HINT_FREE_DROP
	_place_ball(ball_at)
	_place_golfer()
	read_view = GreenRead.View.PLAY
	if lie == Surface.Type.SAND and marks != null and ball_at.distance_to(_footprints_at) > 0.01:
		_footprints_at = ball_at
		marks.add_footprints(hole.terrain, ball_at, _aim_dir(), Vector3.UP.cross(_aim_dir()), CourseMarks.stance_for(clubs[club_index]))
	_update_aim_marker()
	_update_hud()
	_aim_camera(snap_camera)
	_update_green_grid()
	_update_green_aids()
	_save_progress()
	if _is_remote():
		_wait_remote()
		return
	_caddie_read()
	if opponents[shooter] != null:
		_start_computer_turn()


## The caddie (if on) reads the player's shot; computer golfers go without.
func _caddie_read() -> void:
	if caddie == null:
		return
	if opponents[shooter] != null or state != State.AIM:
		caddie.step_aside()
		return
	caddie.advise(shot_model, clubs, hole, ball_at, lie, wind.velocity(), graphics.skill, _aim_dir())


## Settings > Caddie switched on or off.
func _set_caddie(on: bool) -> void:
	if on == (caddie != null):
		return
	if not on:
		caddie.note.queue_free()
		caddie.queue_free()
		caddie = null
		return
	caddie = Caddie.new()
	add_child(caddie)
	hud.add_child(caddie.note)
	if hole != null and state == State.AIM:
		_caddie_read()


## The aiming keys, with the swing the settings chose.
func _aim_hint() -> String:
	if hud.touch_pad.visible:
		return HINT_AIM_TOUCH
	var swing: String = HINT_AIM_MOUSE if graphics.swing_method == 1 else HINT_AIM_METER
	if practice != null:
		return HINT_PRACTICE % swing
	var extra := HINT_OBJECTS if _objects_viewable() else ""
	if round_setup != null and round_setup.practice:
		extra = "    N/B: next/previous hole"
	var text := HINT_AIM % [swing, extra]
	if not Input.get_connected_joypads().is_empty():
		text += HINT_AIM_PAD
	return text


static func _objects_viewable() -> bool:
	return not OS.has_feature("web")


func _process_aim(delta: float) -> void:
	var turn := 0.0
	if Input.is_action_pressed("ui_left"):
		turn += 1.0
	if Input.is_action_pressed("ui_right"):
		turn -= 1.0
	if turn == 0.0:
		return
	var rate := PUTT_AIM_RATE_DEG if clubs[club_index].is_putter else AIM_RATE_DEG
	if Input.is_key_pressed(KEY_SHIFT) or _pad_held(JOY_BUTTON_LEFT_SHOULDER):
		rate *= 0.2
	aim_deg = wrapf(aim_deg + turn * rate * delta, -180.0, 180.0)
	_place_golfer()
	_update_aim_marker()
	_update_hud()
	_aim_camera(false)


static func _pad_held(button: JoyButton) -> bool:
	for pad in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(pad, button):
			return true
	return false


func _process_flight(delta: float) -> void:
	shot_time += delta
	var p := shot.position_at(shot_time)
	_place_ball(p)
	_draw_trail(shot.sample_index_at(shot_time), p)
	if shot_time >= _voice_flight_at:
		_voice_flight_at = INF
		if voice != null:
			voice.say(_voice_flight)
	if shot_time >= _land_time:
		_land_time = INF
		_play_landing()
		if voice != null:
			voice.say(_voice_landing)
	if shot_time >= shot.time_s:
		_complete_flight()


## The ball's first bounce, by the ground it lands on and how hard.
func _play_landing() -> void:
	var t := RoundCamera.time_near(shot, shot.first_landing)
	var speed := (shot.position_at(t) - shot.position_at(t - 0.05)).length() / 0.05
	_play_heard(&"land", {
		"surface": hole.terrain.surface_at(shot.first_landing.x, shot.first_landing.z), "speed": speed},
		shot.first_landing)
	if marks != null:
		var came := shot.position_at(t) - shot.position_at(t - 0.05)
		marks.add_landing(hole.terrain, shot.first_landing, Vector3(came.x, 0.0, came.z), speed)


## Plays a sound made at `at` as it would be heard where the camera
## stands: late by the time sound takes to get there, and fainter with
## distance (SoundBank.heard_from). From the tee a drive's bounce arrives
## most of a second after you see it; from a camera beside the green it's
## instant.
func _play_heard(event: StringName, detail: Dictionary, at: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var heard := SoundBank.heard_from(cam.global_position.distance_to(at) if cam != null else 0.0)
	detail["gain_db"] = heard.gain_db
	if heard.delay_s < 0.03:
		sounds.play_detail(event, detail)
	else:
		get_tree().create_timer(heard.delay_s).timeout.connect(sounds.play_detail.bind(event, detail))


func _complete_flight() -> void:
	shot_time = shot.time_s
	_place_ball(shot.rest)
	_draw_trail(shot.points.size() - 1, shot.rest)
	if practice != null:
		_practice_result()
		return
	if round_setup.practice:
		_practice_shot_done()
		return
	var strokes_before := strokes
	strokes += 1
	_count_stats(strokes_before)
	_note_drive(strokes_before)
	shot_log.append("%s %d: %s from %s %.0f m, %s, %.1f m left on %s" % [
		scoring.names[shooter], strokes, clubs[club_index].short_name, Surface.name_of(lie),
		_flat_distance(shot_from, hole.pin), ShotResult.Outcome.keys()[shot.outcome],
		_flat_distance(shot.rest, hole.pin), Surface.name_of(hole.terrain.surface_at(shot.rest.x, shot.rest.z))])
	if voice != null:
		var rest_pin := _flat_distance(shot.rest, hole.pin)
		var past := Vector2(shot.rest.x - hole.pin.x, shot.rest.z - hole.pin.z).dot(Vector2(hole.pin.x - shot_from.x, hole.pin.z - shot_from.z)) > 0.0
		voice.say(GolferVoice.event_for(shot, hole.terrain.surface_at(shot.rest.x, shot.rest.z), clubs[club_index].is_putter,
			strokes == 1, hole.par, strokes, rest_pin, _shot_from_pin, past))
	if broadcast:
		_report_shot()
	if tour:
		_tour_dots.append([shot.rest, shooter])
	var msg := ""
	match shot.outcome:
		ShotResult.Outcome.HOLED:
			_play_heard(&"cup", {}, hole.pin)
			ball.visible = false
			_hole_out(false)
			return
		ShotResult.Outcome.WATER:
			_play_heard(&"splash", {}, shot.rest)
			strokes += 1
			ball_at = shot.rest
			_water_entry = DropRules.water_entry(shot.points, hole.terrain)
			_drop_pending = true
			msg = "Water hazard. One-stroke penalty, take a drop."
			if golfer:
				golfer.play(&"upset")
		ShotResult.Outcome.OUT_OF_BOUNDS:
			strokes += 1
			ball_at = shot_from
			msg = "Out of bounds. Stroke and distance."
			if golfer:
				golfer.play(&"upset")
		_:
			ball_at = shot.rest
			var s := hole.terrain.surface_at(ball_at.x, ball_at.z)
			if broadcast:
				msg = ""
			elif clubs[club_index].is_putter:
				msg = "%d ft to go" % roundi(_flat_distance(ball_at, hole.pin) * FEET_PER_METRE)
			else:
				msg = "%s    Carry %d yd    Total %d yd" % [Surface.name_of(s), roundi(shot.carry_m * YARDS_PER_METRE), roundi(shot.total_m * YARDS_PER_METRE)]
	if _gimme_now():
		_concede_putt()
		return
	if round_setup.mode == GameModes.Mode.SCRAMBLE and players[current].members.size() > 1:
		msg = _scramble_shot(strokes_before, msg)
	if strokes >= _pickup_at():
		_hole_out(true)
		return
	if players.size() > 1 and not msg.is_empty():
		msg = scoring.names[shooter] + ": " + msg
	if not msg.is_empty() or not broadcast:
		hud.show_message(msg)
	hud.hint.text = HINT_WAIT
	state = State.SHOT_RESULT
	result_timer = RESULT_PAUSE
	if _can_mulligan():
		hud.hint.text = HINT_WAIT + "    U: mulligan"
		result_timer = RESULT_PAUSE * 2.0


## Fairways, greens in regulation and putts for the ball just played:
## `strokes_before` is its score before this shot.
func _count_stats(strokes_before: int) -> void:
	var p := players[current]
	if lie == Surface.Type.GREEN:
		p.putts += 1
	var holed := shot.outcome == ShotResult.Outcome.HOLED
	var on_ground := holed or not (shot.outcome == ShotResult.Outcome.WATER or shot.outcome == ShotResult.Outcome.OUT_OF_BOUNDS)
	var rest: int = hole.terrain.surface_at(shot.rest.x, shot.rest.z) if on_ground else Surface.Type.WATER
	if strokes_before == 0 and hole.par >= 4:
		p.fairway = 1 if holed or (on_ground and rest == Surface.Type.FAIRWAY) else 0
	# On the green (or in the hole) with two putts left for par.
	if strokes_before + 1 <= hole.par - 2 and (holed or (on_ground and rest == Surface.Type.GREEN)):
		p.gir = true


## Scramble: keeps this shot if it is the team's best so far. Until everyone
## has hit, the next partner plays from the same spot; then the team moves to
## the best ball and the round of shots counts once (with that shot's
## penalty, if it had one).
func _scramble_shot(strokes_before: int, msg: String) -> String:
	var p := players[current]
	# A shot in the water is dropped where the rules put it best, so the team
	# compares (and may play) a ball on dry land. The drop is never taken
	# from a spot the team doesn't keep.
	if _drop_pending:
		_drop_pending = false
		var zones := _drop_zones_for(DropRules.Reason.WATER, _water_entry, false)
		ball_at = zones[DropRules.best(zones, hole.pin)].spot
		msg = "Water hazard. One-stroke penalty, dropped."
	var add := strokes - strokes_before
	var s := hole.terrain.surface_at(ball_at.x, ball_at.z)
	var score := add + OpponentSkill.expected_strokes(_flat_distance(ball_at, hole.pin), s)
	if p.round_best.is_empty() or score < float(p.round_best.score):
		p.round_best = {"at": ball_at, "add": add, "score": score, "by": shooter}
	p.round_turn += 1
	if p.round_turn < p.members.size():
		strokes = strokes_before
		ball_at = shot_from
		return msg
	strokes = strokes_before + int(p.round_best.add)
	ball_at = p.round_best.at
	var by: int = p.round_best.by
	p.round_turn = 0
	p.round_best = {}
	var pick := "The team plays %s's ball." % scoring.names[by]
	return pick if msg.is_empty() else msg + "\n" + pick


func _after_result() -> void:
	_stop_replay()
	hud.show_message("")
	_clear_trail()
	if practice != null:
		_practice_drop()
		return
	if round_setup.practice:
		_practice_reset()
		return
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
	if _start_drive(next):
		return
	_take_turn(next)


func _take_turn(next: int) -> void:
	if next == current and _shooter_of(next) == shooter:
		_prepare_shot(false)
	else:
		_begin_turn(next, true)
		if players.size() > 1:
			hud.show_message("%s to play" % scoring.names[shooter], 1.5)


# --- Golf buggy --------------------------------------------------------------

## Settings > Golf buggy switched on or off.
func _set_buggy(on: bool) -> void:
	if on == (buggy != null):
		return
	if not on:
		if state == State.DRIVE:
			_skip_drive()
		buggy.queue_free()
		buggy = null
		return
	buggy = GolfBuggy.new()
	add_child(buggy)
	buggy.set_bags(players.size())
	if hole != null:
		_park_buggy(ball_at)


## Leaves the buggy beside `p`, off the line to the pin.
func _park_buggy(p: Vector3) -> void:
	var spot := BuggyDrive.parking_spot(hole.terrain, p, hole.pin)
	buggy.park(spot, rad_to_deg(atan2(hole.pin.x - spot.x, hole.pin.z - spot.z)), hole.terrain)


## Drives to ball `next` if the buggy is on, a person plays it and it is
## far enough away; false to play on at once.
func _start_drive(next: int) -> bool:
	if buggy == null or opponents[_shooter_of(next)] != null:
		return false
	# Online, only the player's own game drives them to their ball.
	if online != null and not online.owns(_shooter_of(next)):
		return false
	var to := players[next].at
	if _flat_distance(buggy.drive.position, to) < DRIVE_MIN_M:
		return false
	_drive_to = next
	state = State.DRIVE
	# The golfer (and caddie) are aboard.
	if golfer:
		golfer.visible = false
	if caddie != null:
		caddie.step_aside()
	aim_marker.position = Vector3(to.x, hole.terrain.height_at(to.x, to.z) + AIM_LIFT, to.z)
	aim_marker.scale = _aim_marker_scale(2.5)
	aim_marker.visible = true
	ball.visible = true
	hud.show_message("")
	return true


func _process_drive(delta: float) -> void:
	# Arrows, WASD, a pad's stick or d-pad (analog), or a finger dragged on the screen.
	var throttle := Input.get_axis("ui_down", "ui_up") - _drive_stick.y
	if Input.is_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_key_pressed(KEY_S):
		throttle -= 1.0
	var steer := Input.get_axis("ui_right", "ui_left") - _drive_stick.x
	if Input.is_key_pressed(KEY_A):
		steer += 1.0
	if Input.is_key_pressed(KEY_D):
		steer -= 1.0
	throttle = clampf(throttle, -1.0, 1.0)
	steer = clampf(steer, -1.0, 1.0)
	buggy.step(delta, throttle, steer, hole.terrain)
	var view: Array = buggy.chase(delta, hole.terrain)
	camera.position = view[0]
	camera.look_at(view[1])
	var to := players[_drive_to].at
	var left := _flat_distance(buggy.drive.position, to)
	hud.hint.text = (HINT_DRIVE_TOUCH if hud.touch_pad.visible else HINT_DRIVE) % roundi(left * YARDS_PER_METRE)
	var s := hole.terrain.surface_at(to.x, to.z)
	var arrive := DRIVE_ARRIVE_GREEN_M if s == Surface.Type.GREEN or s == Surface.Type.FRINGE else DRIVE_ARRIVE_M
	if left < arrive and absf(buggy.drive.speed) < 0.5 and throttle <= 0.0:
		_end_drive()


## A finger on the screen while driving is a stick: drag up from where it
## went down to drive, down to reverse, sideways to steer. A tap skips the
## drive. Clicks the platform makes up from touches are ignored, so a drag
## doesn't also skip.
func _drive_touch_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and (event as InputEventMouseButton).device == InputEvent.DEVICE_ID_EMULATION:
		return true
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _drive_touch >= 0 or hud.touch_pad.covers(t.position):
				return false
			_drive_touch = t.index
			_drive_touch_from = t.position
			_drive_touch_moved = false
			return true
		if t.index != _drive_touch:
			return false
		_drive_touch = -1
		_drive_stick = Vector2.ZERO
		if not _drive_touch_moved:
			_skip_drive()
		return true
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index != _drive_touch:
			return false
		var off := d.position - _drive_touch_from
		if off.length() > DRIVE_TAP_PX:
			_drive_touch_moved = true
		_drive_stick = (off / DRIVE_STICK_PX).clamp(-Vector2.ONE, Vector2.ONE)
		return true
	return false


## Space during a drive: the buggy is parked by the ball and play goes on.
func _skip_drive() -> void:
	_park_buggy(players[_drive_to].at)
	_end_drive()


func _end_drive() -> void:
	var next := _drive_to
	_drive_to = -1
	_drive_touch = -1
	_drive_stick = Vector2.ZERO
	state = State.SHOT_RESULT  # in between, until the turn begins
	_take_turn(next)


## The current player is done with the hole: holed, or picked up at the
## pick-up score (_pickup_at). The hole ends when everyone is.
func _hole_out(picked_up: bool) -> void:
	_store_turn()
	_drop_pending = false
	var p := players[current]
	p.holed = not picked_up
	p.picked_up = picked_up
	var title := "Picked up" if picked_up else Scorecard.score_name(strokes, hole.par)
	if not picked_up and strokes < hole.par:
		sounds.play(&"applause")
		_caption_crowd(Commentary.Crowd.POLITE)
		if golfer:
			golfer.play(&"celebrate")
	if _next_player() < 0:
		_finish_hole()
		return
	_update_markers()
	hud.show_message("%s: %s!   %d on the par %d." % [_side_name(current), title, strokes, hole.par])
	hud.hint.text = HINT_WAIT
	state = State.SHOT_RESULT
	result_timer = RESULT_PAUSE


func _finish_hole(add_stats := true) -> void:
	for i in players.size():
		var p := players[ball_of[i]]
		scoring.cards[i].record(hole_index, p.strokes)
		if not add_stats:
			continue
		var st := round_stats[i]
		if p.fairway >= 0:
			st.fairway_holes += 1
			st.fairways += p.fairway
		st.gir += 1 if p.gir else 0
		st.putts += p.putts
		st.holes += 1
	state = State.HOLE_DONE
	if players.size() == 1:
		var p := players[0]
		var title := "Picked up" if p.picked_up else Scorecard.score_name(p.strokes, hole.par)
		hud.show_message("%s!   %d on the par %d.   Round: %s" % [title, p.strokes, hole.par, Scorecard.format_to_par(card.to_par())])
	else:
		var parts: Array[String] = []
		for i in players.size():
			var p := players[i]
			if p.inactive:
				continue
			parts.append("%s %d%s" % [_side_name(i), p.strokes, " (picked up)" if p.picked_up else ""])
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
	_save_progress()


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
	SavedRound.clear()
	for p in players:
		p.marker.visible = false
	var text := "Round complete. " + scoring.winner_text()
	if players.size() == 1 and round_setup.mode == GameModes.Mode.STROKE:
		text = "Round complete: %d (%s)." % [card.total_strokes(), Scorecard.format_to_par(card.to_par())]
		if scoring.handicaps:
			var net := scoring.scored_card(0)
			text += "  Net %d (%s)." % [net.total_strokes(), Scorecard.format_to_par(net.to_par())]
	var records := _record_rounds()
	_save_record()
	if round_setup.challenge != null:
		text += "\nTheir round: " + round_setup.challenge.summary()
	if not records.is_empty():
		text += "\n" + records
	if not round_setup.career.is_empty():
		var report := _record_career()
		if not report.is_empty():
			text = report + "\n" + text
	hud.show_message(text)
	hud.scorecard.show_round(scoring, _round_name(), "Final")
	hud.hint.text = HINT_DONE if round_setup.career.is_empty() else HINT_CAREER_DONE


## Keeps the finished round in user://replays/ (RoundRecord).
func _save_record() -> void:
	record.finished = true
	record.cards.clear()
	for c in scoring.cards:
		record.cards.append(c.strokes.duplicate())
	if record_rounds:
		record.save()


## Adds each person's finished card to their profile and says what it did to
## their handicap index. Rounds that stop early, or are shorter than nine
## holes, don't count.
func _record_rounds() -> String:
	if GameModes.shared_ball(round_setup.mode):
		return ""  # team scores, not the players' own
	var profiles := PlayerProfiles.load_saved()
	var date := Time.get_date_string_from_system()
	var lines: Array[String] = []
	for i in scoring.player_count():
		# Computer golfers keep no profile, nor do the other people online.
		if round_setup.is_computer(i) or (online != null and not online.owns(i)):
			continue
		var player := scoring.names[i]
		var before := profiles.index_of(player)
		if not profiles.record_round(player, scoring.cards[i], scoring.ranks, course.course_name, date, round_stats[i]):
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


## A Career round (RoundSetup.career): adds everyone's finished card to the
## event (Career.record_round) and says what it meant. The person is seat 0.
func _record_career() -> String:
	var c := Career.load_saved()
	if c == null:
		return ""
	var played := {}
	for i in scoring.player_count():
		var cd := scoring.cards[i]
		if cd.holes_played() == cd.pars.size():
			played[scoring.names[i]] = cd.to_par()
	var me := scoring.cards[0]
	var text := c.record_round(round_setup.career, played, me.pars.size(), me.total_par(), me.total_strokes())
	if text.is_empty():
		return ""
	c.save()
	Career.open_on_menu = true
	return text


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
	if caddie != null:
		caddie.quiet()
	var reference := _water_entry if reason == DropRules.Reason.WATER else ball_at
	var in_sand := reason == DropRules.Reason.UNPLAYABLE and lie == Surface.Type.SAND
	_drop_reason = reason
	_drop_from = ball_at
	_drop_note = ""
	_drop_zones = _drop_zones_for(reason, reference, in_sand)
	if reason == DropRules.Reason.FREE_RELIEF and not _drop_zones[0].found:
		_drop_reason = -1
		hud.show_message("There's no relief from the path near here.", 2.0)
		return
	_drop_choice = DropRules.best(_drop_zones, hole.pin)
	_drop_spot = _drop_zones[_drop_choice].spot
	if _is_remote():
		# Their game picks the spot; it arrives as an event.
		state = State.REMOTE
		hud.hint.text = HINT_REMOTE % scoring.names[shooter]
		return
	if opponents[shooter] != null:
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


func _drop_zones_for(reason: int, reference: Vector3, in_sand: bool) -> Array[DropRules.Zone]:
	var zones: Array[DropRules.Zone] = []
	for option in DropRules.options(reason, LATERAL_WATER):
		zones.append(DropRules.zone(option, reference, shot_from, hole.pin, in_sand, hole.terrain))
	return zones


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
		lines.append(scoring.names[shooter])
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
	record.drops.append({"ball": current, "hole": hole_index, "reason": reason,
		"penalty": 0 if reason == DropRules.Reason.WATER else DropRules.penalty(reason),
		"spot": [ball_at.x, ball_at.y, ball_at.z]})
	if online != null and not _is_remote():
		online.send_drop(shooter, reason, _drop_choice, ball_at)
	var what := DropRules.OPTION_NAMES[z.option]
	if reason == DropRules.Reason.UNPLAYABLE:
		what = "Unplayable: " + what.to_lower()
	shot_log.append("%s: %s, %.0f m left" % [scoring.names[shooter], what, _flat_distance(ball_at, hole.pin)])
	if strokes >= _pickup_at():
		_hole_out(true)
		return
	var msg := what + "."
	if players.size() > 1:
		msg = scoring.names[shooter] + ": " + msg
	if reason == DropRules.Reason.WATER:
		_pass_turn()
	else:
		_store_turn()  # so the saved round has the dropped ball
		_prepare_shot(false)
	hud.show_message(msg, 2.0)


# --- Online ------------------------------------------------------------------

## True when another game in the online round plays the current shooter.
func _is_remote() -> bool:
	return online != null and not online.owns(shooter)


func _wait_remote() -> void:
	state = State.REMOTE
	aim_marker.visible = false
	hud.hint.text = HINT_REMOTE % scoring.names[shooter]
	_apply_remote()


func _poll_online() -> void:
	online.poll()
	if not online.notices.is_empty():
		hud.show_message("\n".join(online.notices), 3.0)
		online.notices.clear()
	# Someone left and their seats came to this game: play them from here.
	if state == State.REMOTE and not _is_remote() and _drop_reason < 0:
		_prepare_shot(false)


## Plays the next event of the online round if it has arrived: another
## player's shot (their inputs, through this game's physics) or drop.
func _apply_remote() -> void:
	if state != State.REMOTE:
		return
	var ev := online.next_event()
	if ev.is_empty():
		return
	if int(ev.get("player", -1)) != shooter:
		hud.show_message("This game is out of step with the round.", 3.0)
		return
	online.done_event()
	if str(ev.get("kind", "")) == "drop":
		var reason := int(ev.get("reason", -1))
		if _drop_reason != reason:
			_begin_drop(reason)
		if _drop_zones.is_empty():
			return
		_drop_choice = clampi(int(ev.get("choice", 0)), 0, _drop_zones.size() - 1)
		var sp: Array = ev.get("spot", [])
		if sp.size() == 3:
			_drop_spot = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
		_finish_drop()
		return
	var rec := ShotRecord.from_dict(ev.get("shot", {}))
	club_index = clampi(rec.club, 0, clubs.size() - 1)
	aim_deg = rec.aim_deg
	_mouse_stroke = rec.stroke
	_mouse_help = rec.help
	_incoming = rec
	play_shot(rec.power, rec.accuracy)
	_incoming = null


# --- Computer golfers --------------------------------------------------------

func _start_computer_turn() -> void:
	state = State.COMPUTER
	_computer_timer = 0.0
	_computer_ready = false
	_computer_backswing = false
	opponents[shooter].plan(shot_model, clubs, hole, ball_at, lie, wind.velocity())
	hud.hint.text = HINT_COMPUTER % scoring.names[shooter]


## Plans over a few frames, lines up, then swings.
func _process_computer(delta: float) -> void:
	if pause_menu.visible or settings_panel.visible:
		return
	_computer_timer += delta
	var cpu := opponents[shooter]
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
	var cpu := opponents[shooter]
	_computer_ready = true
	_computer_timer = 0.0
	club_index = cpu.club_index
	aim_deg = cpu.aim_deg
	_place_golfer()
	_update_aim_marker()
	_update_hud()
	_aim_camera(false)


func _computer_swing() -> void:
	var cpu := opponents[shooter]
	var made := cpu.swing()
	if shot_model is LinksShotModel:
		# The Links physics adds the game's own computer misses (play_shot).
		made = PackedFloat64Array([cpu.power, 0.0, cpu.aim_deg])
	aim_deg = made[2]
	hud.meter.reset()
	play_shot(made[0], made[1])


# --- Clubs and aim -----------------------------------------------------------

func _auto_club() -> void:
	var to_pin := _flat_distance(ball_at, hole.pin)
	_chip = false
	if lie == Surface.Type.GREEN or (lie == Surface.Type.FRINGE and to_pin < 15.0):
		club_index = clubs.size() - 1
		return
	# The game's own rule: a Chip within 100 ft (straight line, to a foot
	# above the hole) unless the ball is in sand.
	_chip = lie != Surface.Type.SAND and ball_at.distance_to(hole.pin + Vector3(0, 0.3048, 0)) < CHIP_RANGE_M
	var power := Surface.lie_power(lie)
	var target := hole.aim_point(ball_at, clubs[0].total_m * shot_model.reach_scale(clubs[0]) * power)
	club_index = 0
	# Off the tee with the green out of reach, take the driver: picking the
	# shortest club that reaches a route point leaves a hybrid off a par 4.
	if lie == Surface.Type.TEE and target != hole.pin:
		return
	var d := _flat_distance(ball_at, target)
	for i in clubs.size():
		if not clubs[i].is_putter and clubs[i].total_m * shot_model.reach_scale(clubs[i]) * power >= d:
			club_index = i


## Which of the game's meters the next swing uses.
func _meter_mode() -> int:
	if clubs[club_index].is_putter:
		return LinksPowerStroke.Mode.PUTT
	return LinksPowerStroke.Mode.CHIP if _chip else LinksPowerStroke.Mode.FULL


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
	return club.total_m * shot_model.reach_scale(club) * Surface.lie_power(lie)


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
	_build_ball_details()
	add_child(CourseLife.new())  # birds now and then

	trail = MeshInstance3D.new()
	trail.mesh = _trail_mesh
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.albedo_color = Color(1, 1, 0.6)
	trail.material_override = trail_mat
	add_child(trail)
	tracer = BallTracer.new()
	add_child(tracer)
	driving_zone = DrivingZone.new()
	driving_zone.visible = false
	add_child(driving_zone)
	putt_read = PuttRead.new()
	putt_read.visible = false
	add_child(putt_read)
	green_grid = GreenGrid.new()
	add_child(green_grid)
	breakline = BreaklineIndicator.new()
	add_child(breakline)
	assistant = PuttRead.new()
	assistant.visible = false
	add_child(assistant)

	aim_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.8
	ring.outer_radius = 1.0
	aim_marker.mesh = ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.9, 0.2, 0.75)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	putting_panel = PuttingPanel.new()
	hud.add_child(putting_panel)
	# Down the right, under the wind (and the original's windows), clear of
	# the ball and the line to the hole.
	putting_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	putting_panel.offset_left = -PuttingPanel.WIDTH - 16.0
	putting_panel.offset_right = -16.0
	putting_panel.offset_top = 136.0 if hud.windows == null else 20.0 + ShotWindows.wanted_size().y
	putting_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	putting_panel.action.connect(_on_putting_action)
	settings_panel = SettingsPanel.new()
	canvas.add_child(settings_panel)
	settings_panel.changed.connect(_apply_graphics)
	settings_panel.back_pressed.connect(_on_settings_back)
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


func _on_settings_back() -> void:
	settings_panel.close()
	pause_menu.open()


func _on_pause_restart() -> void:
	pause_menu.close()
	start_round()


func _apply_graphics() -> void:
	graphics.apply_display(get_viewport())
	LinksGround.set_greens(graphics.green_firmness, graphics.green_speed)
	scenery.apply(graphics)
	post.apply(graphics)
	dynamic_resolution.setup(get_viewport(), graphics)
	camera.fov = graphics.fov
	camera.attributes = _camera_attributes()
	RenderingServer.global_shader_parameter_set("foliage_sway", 1.0 if graphics.foliage_wind else 0.0)
	RenderingServer.global_shader_parameter_set("cloud_shadow", CLOUD_SHADOW if graphics.cloud_shadows else 0.0)
	TreeFactory.set_level(graphics.trees)
	CrzTerrain.photo_ground = graphics.lighting == GraphicsSettings.Lighting.PHOTOREAL
	RenderingServer.global_shader_parameter_set("billboard_photo", 1.0 if CrzTerrain.photo_ground else 0.0)
	GroundShade.set_near(TreeFactory.impostor_distance() if TreeFactory.enabled() else 0.0)
	if grass.level != graphics.grass and hole != null:
		grass.setup(hole.terrain, graphics.grass)
	broadcast = graphics.broadcast()
	tour = broadcast and graphics.tour()
	camera.broadcast = broadcast
	hud.set_broadcast(broadcast, tour)
	trail.visible = not broadcast
	tracer.visible = broadcast
	tracer.set_style(tour)
	if tour and hole != null and _tour_map == null:
		_tour_map = HoleMap.build(hole)
	if not tour:
		driving_zone.clear()
		putt_read.clear()
	if not broadcast:
		hud.overlay.show_pip(false)
		camera.end_flyover()
	if hole != null and state == State.AIM:
		_update_green_grid()
		_update_green_aids()
	_set_caddie(graphics.caddie)
	_set_buggy(graphics.buggy)
	_set_monitor(graphics.launch_monitor)
	# A round on set conditions (online, or a friend's result code) keeps them.
	if wind != null and online == null and round_setup.wind_level < 0 and round_setup.challenge == null:
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


## Moves the cloud shadows on: the clouds ride a wind aloft that runs
## with the one on the course but stronger, and never quite stops.
func _drift_clouds(delta: float) -> void:
	if graphics == null or wind == null or not graphics.cloud_shadows:
		return
	var v := wind.velocity()
	var aloft := Vector2(v.x, v.z) * 2.5
	if aloft.length() < 3.0:
		aloft = (aloft.normalized() if aloft.length() > 0.01 else Vector2(0.6, 0.8)) * 3.0
	_cloud_offset += aloft * delta
	RenderingServer.global_shader_parameter_set("cloud_offset", _cloud_offset)


## Tells the grass, trees and water which way the wind blows.
## The steady wind is the hole's own; WindGust adds the gusts and lulls
## the eye sees each frame (visual only: the ball flies in `wind`).
func _update_wind_shaders() -> void:
	if wind == null:
		return
	var v := wind.velocity()
	var t := Time.get_ticks_msec() * 0.001
	var seen := WindGust.visual_wind(Vector2(v.x, v.z), t, float(hole_index) if hole != null else 0.0)
	RenderingServer.global_shader_parameter_set("wind_vector", seen)


## Flagstick height: the Rules ask for at least 7 ft (2.13 m).
const FLAGSTICK_M := 2.13


func _add_flag() -> void:
	var pin := hole.pin
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	# True to scale: tour flagsticks are about 3/4 in (19 mm) thick.
	pole_mesh.top_radius = 0.0095
	pole_mesh.bottom_radius = 0.0095
	pole_mesh.height = FLAGSTICK_M
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position = pin + Vector3(0, FLAGSTICK_M * 0.5, 0)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.92)
	pole.material_override = white
	hole_root.add_child(pole)

	# The flag flies with the wind (shaders/flag.gdshader).
	var flag := MeshInstance3D.new()
	var cloth := PlaneMesh.new()
	cloth.orientation = PlaneMesh.FACE_Z
	cloth.size = Vector2(0.51, 0.36)
	cloth.subdivide_width = 16
	cloth.subdivide_depth = 6
	flag.mesh = cloth
	flag.position = pin + Vector3(0, FLAGSTICK_M - 0.02, 0)
	flag.extra_cull_margin = 1.0  # the shader moves it well off the plane
	var cloth_mat := ShaderMaterial.new()
	cloth_mat.shader = load("res://shaders/flag.gdshader")
	flag.material_override = cloth_mat
	flag.name = "Flag"
	hole_root.add_child(flag)

	# The hole at its real size (4.25 in across), liner and all
	# (shaders/cup.gdshader).
	var cup := MeshInstance3D.new()
	var cup_mesh := PlaneMesh.new()
	cup_mesh.size = Vector2.ONE * BallPhysics.CUP_RADIUS * 2.0
	cup.mesh = cup_mesh
	cup.position = pin + Vector3(0, 0.004, 0)
	var cup_mat := ShaderMaterial.new()
	cup_mat.shader = load("res://shaders/cup.gdshader")
	cup.material_override = cup_mat
	cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hole_root.add_child(cup)


## The tee markers: a pair of squat domes about 15 cm across, set square
## to the line of the hole either side of the tee, as on a real tee box
## (Rule 6.2b: the teeing area runs back two club-lengths from them).
const TEE_MARKER_GAP := 5.5  ## metres between the two markers
const TEE_MARKER_AHEAD := 0.6  ## how far in front of the ball they stand


func _add_tee_markers() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.12, 0.1)
	mat.roughness = 0.45
	var s := SphereMesh.new()
	s.radius = 0.075
	s.height = 0.11
	s.is_hemisphere = true
	# Square to the first leg of the hole, so doglegs face down the fairway.
	var toward := hole.pin
	for r in hole.route:
		if Vector2(hole.tee.x, hole.tee.z).distance_to(r) > 1.0:
			toward = Vector3(r.x, hole.tee.y, r.y)
			break
	for p in tee_marker_spots(hole.tee, toward):
		var m := MeshInstance3D.new()
		m.mesh = s
		m.material_override = mat
		p.y = hole.terrain.height_at(p.x, p.z) - 0.005
		m.position = p
		hole_root.add_child(m)


## Where the two tee markers go: across the line from `tee` toward `toward`.
static func tee_marker_spots(tee: Vector3, toward: Vector3) -> Array[Vector3]:
	var dir := Vector3(toward.x - tee.x, 0.0, toward.z - tee.z)
	dir = Vector3(0, 0, 1) if dir.length() < 0.01 else dir.normalized()
	var side := Vector3.UP.cross(dir)
	var spots: Array[Vector3] = []
	for k: float in [-0.5, 0.5]:
		spots.append(tee + dir * TEE_MARKER_AHEAD + side * (k * TEE_MARKER_GAP))
	return spots


func _place_ball(p: Vector3) -> void:
	_ball_base = p
	_update_ball_size()


## Links 2003 draws the ball this much bigger per metre away (Settings >
## Ball size > Bigger far away): about 1% of the screen's height across.
const LINKS_BALL_GROWTH := 0.0045
## At true size the ball is never drawn smaller than this share of the
## view's height across (about 3 pixels on a 1080p screen), so it doesn't
## flicker out of sight in the air.
const BALL_MIN_SCREEN := 0.003


## The radius the ball is drawn at `distance` metres from a camera with this
## vertical field of view: its real 42.67 mm, kept from shrinking below
## BALL_MIN_SCREEN of the view; or Links 2003's bigger-far-away ball.
static func ball_radius(distance: float, fov_deg: float, true_size: bool) -> float:
	if not true_size:
		return maxf(BallPhysics.RADIUS, distance * LINKS_BALL_GROWTH)
	var half_view := distance * tan(deg_to_rad(fov_deg) * 0.5)
	return maxf(BallPhysics.RADIUS, half_view * BALL_MIN_SCREEN)


## Draws the balls at their size for the camera (ball_radius).
func _update_ball_size() -> void:
	if ball.visible:
		_size_ball(ball, _ball_base)
	for p in players:
		if p.marker.visible:
			_size_ball(p.marker, p.at)


func _size_ball(m: MeshInstance3D, base: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = camera
	var r := ball_radius(cam.global_position.distance_to(base), cam.fov, graphics == null or graphics.true_size_ball)
	m.scale = Vector3.ONE * r
	var gap := _tee_gap() if m == ball else 0.0
	m.position = base + Vector3.UP * (r + gap)
	if m == ball:
		_update_ball_details(base, r, gap)


## Driver tee height: about half the ball above the club's crown.
const TEE_GAP_DRIVER := 0.025
const TEE_GAP_WOOD := 0.012  ## fairway woods and hybrids, teed low
const TEE_GAP_IRON := 0.005  ## irons, the ball just off the grass
var _tee_peg: MeshInstance3D
var _ball_shadow: MeshInstance3D
var _footprints_at := Vector3.INF  ## the bunker lie that last got footprints


## How far the ball sits above the ground on a tee peg while aiming from
## the teeing ground; 0 anywhere else, and once the ball is struck.
func _tee_gap() -> float:
	if lie != Surface.Type.TEE or not (state == State.AIM or state == State.COMPUTER) \
			or _ball_base.distance_to(ball_at) > 0.01 or clubs.is_empty():
		return 0.0
	var club := clubs[club_index]
	if club.is_putter:
		return 0.0
	match SoundBank.club_kind(club):
		&"driver":
			return TEE_GAP_DRIVER
		&"wood":
			return TEE_GAP_WOOD
	return TEE_GAP_IRON


func _build_ball_details() -> void:
	# A white wooden tee: a thin shank with a cup on top.
	_tee_peg = MeshInstance3D.new()
	var shank := CylinderMesh.new()
	shank.top_radius = 0.0055
	shank.bottom_radius = 0.0022
	shank.height = 0.012
	shank.radial_segments = 8
	shank.rings = 1
	_tee_peg.mesh = shank
	var peg_mat := StandardMaterial3D.new()
	peg_mat.albedo_color = Color(0.92, 0.9, 0.84)
	peg_mat.roughness = 0.8
	_tee_peg.material_override = peg_mat
	_tee_peg.visible = false
	add_child(_tee_peg)
	_ball_shadow = MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_ball_shadow.mesh = quad
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = load("res://shaders/ball_shadow.gdshader")
	_ball_shadow.material_override = shadow_mat
	_ball_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ball_shadow)


## The tee peg under a teed-up ball (it stays in the ground after the
## shot, as they mostly do), and the soft shadow that sits the ball in the
## grass and follows it along the ground in flight, fading as it climbs.
func _update_ball_details(base: Vector3, r: float, gap: float) -> void:
	if _tee_peg == null or hole == null:
		return
	if gap > 0.0:
		var ground := hole.terrain.height_at(base.x, base.z)
		var shank := _tee_peg.mesh as CylinderMesh
		shank.height = gap + 0.004  # its cup holds the ball; the rest is in the ground
		_tee_peg.position = Vector3(base.x, ground + shank.height * 0.5, base.z)
		_tee_peg.visible = ball.visible
	elif state == State.AIM or state == State.COMPUTER:
		_tee_peg.visible = false
	var ground_y := hole.terrain.height_at(base.x, base.z)
	var height := maxf(base.y - ground_y, 0.0)
	var fade := 1.0 - clampf(height / 2.0, 0.0, 1.0)
	_ball_shadow.visible = ball.visible and fade > 0.0
	if _ball_shadow.visible:
		_ball_shadow.position = Vector3(base.x, ground_y + 0.006, base.z)
		_ball_shadow.scale = Vector3.ONE * r * 2.6 * (1.0 + height)
		(_ball_shadow.material_override as ShaderMaterial).set_shader_parameter("strength", 0.6 * fade)


## Each player's look: the golfer they made in the player creator, or the
## standard golfer. Computer golfers get a look of their own (from their
## name) unless the game's own golfers are loaded.
func _choose_looks() -> void:
	_looks.clear()
	var profiles := PlayerProfiles.load_saved()
	var free := AssetProviders.golfer_assets is PlaceholderGolferAssets
	for i in scoring.player_count():
		var player_name: String = round_setup.names[i] if i < round_setup.names.size() else ""
		var look := profiles.look_of(player_name) if not player_name.is_empty() else null
		if look == null and free:
			look = PlayerLook.random(player_name.hash()) if round_setup.is_computer(i) else PlayerLook.new()
		_looks.append(look)


## This hole's golfers, one per look, hidden until their turn.
func _make_golfers() -> void:
	_golfers.clear()
	golfer = null
	var made := {}
	for i in scoring.player_count():
		var look: PlayerLook = _looks[i] if i < _looks.size() else null
		var key := look.key() if look != null else ""
		if not made.has(key):
			var g: GolferRig = null
			if look != null:
				g = FreeGolfer.create(look)
			if g == null:
				g = AssetProviders.golfer_assets.create_golfer_for(look)
			g.visible = false
			hole_root.add_child(g)
			made[key] = g
		_golfers.append(made[key])
	if not _golfers.is_empty():
		golfer = _golfers[0]


## Makes player `i`'s golfer the one on the tee.
func _use_golfer(i: int) -> void:
	if _golfers.is_empty():
		return
	var g := _golfers[clampi(i, 0, _golfers.size() - 1)]
	if g != golfer and golfer != null:
		golfer.visible = false
	golfer = g


## Colours a ball as player `i` chose (white unless they picked another).
func _tint_ball(m: MeshInstance3D, i: int) -> void:
	if m == null:
		return
	var look: PlayerLook = _looks[i] if i < _looks.size() else null
	var mat := m.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = look.ball if look != null else Color.WHITE


func _place_golfer() -> void:
	if golfer == null:
		return
	var dir := _aim_dir()
	var left := Vector3.UP.cross(dir)
	golfer.basis = Basis.looking_at(-left, Vector3.UP)
	golfer.position = ball_at + left * 0.75
	golfer.visible = true
	# Players wriggle their feet into the sand to take a bunker stance.
	var in_sand := hole.terrain.surface_at(ball_at.x, ball_at.z) == Surface.Type.SAND
	golfer.set_ground(hole.terrain.height_at, FEET_IN_SAND if in_sand else 0.0)
	golfer.set_shot(clubs[club_index], _flat_distance(ball_at, hole.pin))
	golfer.play(&"address")


## The aim ring is a flat painted band, like a TV graphic laid on the
## grass, not a 20 cm tyre: the torus is squashed to AIM_FLAT of its width,
## so a putt's ring no longer stands over the cup like a yellow can.
static func _aim_marker_scale(size: float) -> Vector3:
	return Vector3(size, AIM_FLAT * size, size)


func _update_aim_marker() -> void:
	var club := clubs[club_index]
	var dir := _aim_dir()
	var reach := 0.0
	var size := 1.0
	if club.is_putter:
		reach = minf(_flat_distance(ball_at, hole.pin), club.total_m)
		size = 0.25
	else:
		reach = club.carry_m * shot_model.reach_scale(club) * Surface.lie_power(lie)
		size = clampf(reach * 0.02, 1.0, 4.0)
	var p := ball_at + dir * reach
	p.y = hole.terrain.height_at(p.x, p.z) + AIM_LIFT
	aim_marker.position = p
	aim_marker.scale = _aim_marker_scale(size)
	aim_marker.visible = true
	_update_breakline()


func _update_hud() -> void:
	var club := clubs[club_index]
	var to_pin := _flat_distance(ball_at, hole.pin)
	var pin_text := "%d yd" % roundi(to_pin * YARDS_PER_METRE)
	if lie == Surface.Type.GREEN or to_pin < 20.0:
		pin_text = "%d ft" % roundi(to_pin * FEET_PER_METRE)
	var club_text := club.full_name
	if _chip and not club.is_putter:
		club_text += " chip"
	elif not club.is_putter:
		club_text += " (%d yd)" % roundi(_club_reach() * YARDS_PER_METRE)
	if not club.is_putter and not shape.is_square():
		club_text += "  " + shape.describe()
	var thru := card.holes_played()
	var total := "E" if thru == 0 else Scorecard.format_to_par(card.to_par())
	var text := "%s    Hole %d    Par %d    %d yd\n" % [course.course_name, hole.number, hole.par, roundi(hole.length_m() * YARDS_PER_METRE)]
	if players.size() > 1 or opponents[shooter] != null:
		text += "%s    " % _player_label(shooter)
	text += "Stroke %d    To pin %s    Lie: %s\nClub: %s    Wind: %s\nRound: %s thru %d" % [
		strokes + 1, pin_text, Surface.name_of(lie), club_text, wind.describe(aim_deg), total, thru]
	var status := scoring.status_text()
	if not status.is_empty():
		text += "\n" + status
	hud.info.text = text
	hud.show_wind(wind, aim_deg)
	# The aim marker sits on the ground where the shot is aimed.
	var rise := aim_marker.position.y - 0.08 - ball_at.y if aim_marker.visible else 0.0
	var reach_text := "%d yd" % roundi(_club_reach() * YARDS_PER_METRE)
	if club.is_putter:
		reach_text = pin_text
	hud.show_shot(club, reach_text, rise, Surface.name_of(lie), 1.0 if club.is_putter else Surface.lie_power(lie))
	if broadcast:
		hud.overlay.set_status(_status(state == State.AIM or state == State.SWING))
	_update_tour()
	_update_putting_panel()


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
		# A TV tracer follows the flight and stops where the ball first
		# lands: the bounces and roll are never traced.
		var land := tracer_end(shot)
		if upto >= land:
			tracer.draw(shot.points, land - 1, shot.first_landing, camera.global_position)
		else:
			tracer.draw(shot.points, upto, head, camera.global_position)


## The index of the shot's first landing among its points (the last point
## for a shot that never leaves the ground, such as a putt).
static func tracer_end(s: ShotResult) -> int:
	var n := s.points.size()
	if s.carry_m < 1.0 or n < 2:
		return n - 1
	var best := n - 1
	var best_d := INF
	for i in range(1, n):
		var d := s.points[i].distance_squared_to(s.first_landing)
		if d < best_d:
			best_d = d
			best = i
	return best


# --- Camera ------------------------------------------------------------------

## Behind the ball, looking down the aim line. Links cuts straight to the
## new view rather than gliding, so this always snaps.
func _aim_camera(_snap: bool) -> void:
	if golfer:
		# Reading the putt, the golfer is the one looking, not standing over it.
		golfer.visible = read_view == GreenRead.View.PLAY
	if read_view != GreenRead.View.PLAY and hole != null:
		var pose := GreenRead.view_pose(read_view, hole.terrain, ball_at, hole.pin)
		camera.look_from(pose[0], pose[1])
		return
	camera.aim(ball_at, _aim_dir(), clubs[club_index].is_putter, _flat_distance(ball_at, _aim_target()))


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
		if not shape.is_square():
			club_text += "  " + shape.describe()
	var rise := (hole.pin.y - ball_at.y) * FEET_PER_METRE
	var elev := "Level" if absf(rise) < 1.0 else "%s%d ft" % ["+" if rise > 0.0 else "", roundi(rise)]
	return {
		"hole": hole.number, "par": hole.par, "yards": roundi(hole.length_m() * YARDS_PER_METRE),
		"player": scoring.names[shooter], "to_par": "E" if thru == 0 else Scorecard.format_to_par(card.to_par()),
		"thru": thru, "stroke": strokes + 1, "club": club_text, "to_pin": _pin_text(),
		"lie": Surface.name_of(lie), "wind": wind.describe(aim_deg), "elevation": elev,
		"ticker": _ticker_text(), "aiming": aiming,
	}


## The scrolling line along the bottom: the leaderboard with more than one
## player, otherwise the round so far.
func _ticker_text() -> String:
	var parts: Array[String] = []
	if round_setup.mode == GameModes.Mode.MATCH:
		# standings() is the final result ("Ann wins"); mid-match say who leads.
		parts.append(scoring.status_text().to_upper())
	elif not _career_title.is_empty():
		parts.append(_career_title.to_upper())
		parts.append_array(_career_board)
		parts.append("HOLE %d OF %d" % [hole_index + 1, holes.size()])
		var thru_c := card.holes_played()
		if thru_c > 0:
			parts.append("TODAY %s THRU %d" % [Scorecard.format_to_par(card.to_par()), thru_c])
	elif scoring.player_count() > 1:
		parts.append("LEADERBOARD")
		parts.append_array(leaderboard_lines(scoring.standings()))
	else:
		parts.append(course.course_name.to_upper())
		parts.append(GameModes.MODE_NAMES[round_setup.mode].to_upper())
		parts.append("HOLE %d OF %d" % [hole_index + 1, holes.size()])
		var thru := card.holes_played()
		if thru > 0:
			parts.append("ROUND %d (%s) THRU %d" % [card.total_strokes(), Scorecard.format_to_par(card.to_par()), thru])
		parts.append("WIND %s" % wind.describe(aim_deg).to_upper())
	return "      \u00b7      ".join(parts)


## "1. ANN  72 (E)" per standings row; level scores share a place ("T2.").
static func leaderboard_lines(rows: Array) -> Array[String]:
	var out: Array[String] = []
	for i in rows.size():
		var pos := i
		while pos > 0 and str(rows[pos - 1][1]) == str(rows[i][1]):
			pos -= 1
		var tied := (i > 0 and str(rows[i - 1][1]) == str(rows[i][1])) \
			or (i + 1 < rows.size() and str(rows[i + 1][1]) == str(rows[i][1]))
		out.append("%s%d. %s  %s" % ["T" if tied else "", pos + 1, str(rows[i][0]).to_upper(), rows[i][1]])
	return out


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
	_caption_crowd(line[1])
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
		golfer.watch(ball, 0.7 if putting else 0.3)
	sounds.play_detail(&"hit", _strike_sound)
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


## Where the green-side inset camera points: at the ball, but like a TV
## camera holding the green it tilts up at most PIP_MAX_TILT, so a high
## ball crosses the frame rather than the shot filling with sky.
const PIP_MAX_TILT := 12.0


static func pip_target(cam: Vector3, ball: Vector3) -> Vector3:
	var flat := Vector2(ball.x - cam.x, ball.z - cam.z).length()
	var t := ball
	t.y = minf(ball.y, cam.y + flat * tan(deg_to_rad(PIP_MAX_TILT)))
	return t


func _place_pip_camera() -> void:
	var start := shot.points[0]
	var back := Vector3(hole.pin.x - start.x, 0.0, hole.pin.z - start.z).normalized()
	var p := hole.pin + back * 9.0 + Vector3.UP * 2.0
	p.y = maxf(p.y, hole.terrain.height_at(p.x, p.z) + 1.5)
	var cam := hud.overlay.pip_camera
	cam.position = p
	cam.look_at(hole.pin + Vector3.UP * 0.5)


## The putting grid: the Broadcast TV graphic, or Links 2003's grid at the
## skill levels that have it (Settings > Putting grid sets the look).
func _update_green_grid() -> void:
	var on := _grid_allowed() and grid_on and graphics.putting_grid > 0 and state == State.AIM \
		and clubs[club_index].is_putter and (lie == Surface.Type.GREEN or lie == Surface.Type.FRINGE)
	green_grid.visible = on
	if on:
		green_grid.style = (graphics.putting_grid - 1) as GreenGrid.Style
		green_grid.build(hole.terrain, ball_at, hole.pin)


# --- Golfer voice -------------------------------------------------------------

## Picks the golfer's lines for the shot just struck: one at impact now, one
## during the flight or roll, one at the landing (GolferVoice). Timings are
## best guesses: a third of the way through a putt, a second into a flight.
func _plan_voice(power: float, accuracy: float) -> void:
	_voice_flight_at = INF
	_voice_landing = ""
	if voice == null:
		return
	var putting := clubs[club_index].is_putter
	var from_tee := strokes == 0 and hole.par > 3
	voice.say(GolferVoice.swing_event(power, accuracy, putting))
	var dir := _aim_dir()
	var land := shot.first_landing if shot.bounces > 0 else shot.rest
	var left_m := (land - shot_from).dot(Vector3.UP.cross(dir))
	var to_pin := 0.0 if shot.outcome == ShotResult.Outcome.HOLED else _flat_distance(shot.rest, hole.pin)
	var to_hole := Vector2(hole.pin.x - shot_from.x, hole.pin.z - shot_from.z)
	var past := Vector2(shot.rest.x - hole.pin.x, shot.rest.z - hole.pin.z).dot(to_hole) > 0.0
	_voice_flight = GolferVoice.flight_event(shot, putting, from_tee, to_pin, past, left_m)
	_voice_flight_at = shot.time_s * 0.35 if putting else minf(1.0, shot.time_s * 0.4)
	if not putting and shot.bounces > 0:
		var land_past := Vector2(land.x - hole.pin.x, land.z - hole.pin.z).dot(to_hole) > 0.0
		_voice_landing = GolferVoice.landing_event(shot, from_tee, _flat_distance(land, hole.pin), land_past)


# --- Tour graphics ------------------------------------------------------------

## Feeds TourGraphics and draws the driving zone or the putt read while a
## shot is being set up; hides them once it's struck.
func _update_tour() -> void:
	if not tour or hole == null:
		return
	var aiming := state == State.AIM or state == State.SWING
	var putting := clubs[club_index].is_putter
	var to_pin := _flat_distance(ball_at, hole.pin)
	var zone := {}
	if aiming and not putting and strokes == 0 and hole.par > 3:
		var spread: float = DrivingZone.SPREAD_DEG[clampi(graphics.skill, 0, DrivingZone.SPREAD_DEG.size() - 1)]
		zone = DrivingZone.compute(hole, ball_at, aim_deg, _club_reach(), strokes, spread)
		driving_zone.show_zone(zone, hole, ball_at, aim_deg)
	else:
		driving_zone.clear()
	hud.tour.zone = zone
	var read := {}
	if aiming and putting and (lie == Surface.Type.GREEN or (lie == Surface.Type.FRINGE and to_pin < 15.0)):
		if not _putt_from.is_equal_approx(ball_at):
			_putt = PuttRead.read(shot_model, clubs, hole, ball_at, lie)
			_putt_from = ball_at
		read = _putt
		putt_read.show_read(read, ball_at)
	else:
		putt_read.clear()
	hud.tour.putt = read
	if _tour_map == null:
		_tour_map = HoleMap.build(hole)
	if aiming and not putting:
		hud.overlay.hide_shot_card()  # the map has that corner while aiming
	hud.tour.set_map(_tour_map, _tour_dots, ball_at, aiming and not putting)
	hud.tour.set_state(_tour_state(aiming, putting, to_pin))


func _tour_state(aiming: bool, putting: bool, to_pin: float) -> Dictionary:
	var club := clubs[club_index]
	var rows: Array = []
	for i in scoring.names.size():
		var c := scoring.cards[i]
		rows.append({"name": scoring.names[i], "player": i, "current": i == shooter,
			"score": c.to_par(), "to_par": "E" if c.holes_played() == 0 or c.to_par() == 0 else Scorecard.format_to_par(c.to_par())})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score or (a.score == b.score and a.player < b.player))
	for i in rows.size():
		var score: int = rows[i].score
		var first := i
		while first > 0 and int(rows[first - 1].score) == score:
			first -= 1
		var tied: bool = first < i or (i + 1 < rows.size() and int(rows[i + 1].score) == score)
		rows[i].pos = ("T%d" if tied else "%d") % (first + 1)
	return {
		"to_play": holes.size() - hole_index, "round": "%s  \u00b7  %s" % [course.course_name, GameModes.MODE_NAMES[round_setup.mode]] if round_setup != null else course.course_name,
		"rows": rows, "hole": hole.number, "par": hole.par, "yards": roundi(hole.length_m() * YARDS_PER_METRE),
		"stroke": strokes + 1, "aiming": aiming, "putting": putting, "club": club.full_name,
		"carry_yd": roundi(club.carry_m * Surface.lie_power(lie) * YARDS_PER_METRE),
		"total_yd": roundi(_club_reach() * YARDS_PER_METRE), "to_pin_yd": roundi(to_pin * YARDS_PER_METRE),
		"wind_mph": 0.0 if wind.is_calm() else wind.speed_mph(), "wind_rel_deg": wind.relative_deg(aim_deg),
		"expected": strokes + OpponentSkill.expected_strokes(to_pin, lie),
	}


# --- Putting: green reading and the practice green -----------------------------

## The person at the keyboard is setting up a putt on (or by) the green.
func _putting_on_green() -> bool:
	return state == State.AIM and clubs[club_index].is_putter \
		and (lie == Surface.Type.GREEN or lie == Surface.Type.FRINGE) and _human_turn()


func _human_turn() -> bool:
	return shooter < opponents.size() and opponents[shooter] == null


## The grid shows as the Broadcast TV graphic, otherwise where Links 2003
## allows it (not at Elite skill).
func _grid_allowed() -> bool:
	return broadcast or GreenRead.grid_allowed(graphics.skill)


## The greens roll by Links 2003's own model (the game's executable found).
func _links_greens() -> bool:
	return shot_model is LinksShotModel and (shot_model as LinksShotModel).aero != null


## Ctrl+G: the next look for the grid, as the game's Ctrl+G swaps its yellow
## and coloured grids.
func _cycle_grid_style() -> void:
	graphics.putting_grid = graphics.putting_grid % (GraphicsSettings.PUTTING_GRID_NAMES.size() - 1) + 1
	graphics.save()
	grid_on = true
	_update_green_grid()
	hud.show_message("Grid: " + GraphicsSettings.PUTTING_GRID_NAMES[graphics.putting_grid], 1.5)


func _update_green_aids() -> void:
	if hole == null:
		return
	_update_breakline()
	_update_assistant()
	_update_putting_panel()


func _hide_green_aids() -> void:
	read_view = GreenRead.View.PLAY
	if golfer:
		golfer.visible = true
	breakline.clear()
	assistant.clear()
	hud.meter.target = -1.0
	putting_panel.visible = false


## Links 2003's Breakline Indicator, at the aiming marker when it is on the
## green.
func _update_breakline() -> void:
	if breakline == null or hole == null:
		return
	var p := aim_marker.position
	if graphics.breakline and state == State.AIM and aim_marker.visible and _human_turn() \
			and hole.terrain.surface_at(p.x, p.z) == Surface.Type.GREEN:
		breakline.show_at(hole.terrain, p)
	else:
		breakline.clear()


## Links 2003's Putting Assistant: the read line and the power dot on the
## meter at Amateur, a band round the line at Professional.
func _update_assistant() -> void:
	var level := GreenRead.assistant_level(graphics.skill) if graphics.putting_assistant else 0
	if level == 0 or not _putting_on_green():
		assistant.clear()
		hud.meter.target = -1.0
		return
	if not _assist_from.is_equal_approx(ball_at):
		_assist = PuttRead.read(shot_model, clubs, hole, ball_at, lie)
		_assist_from = ball_at
	if level == 2:
		assistant.show_read(_assist, ball_at)
		hud.meter.target = float(_assist.power) if not _assist.is_empty() else -1.0
	else:
		assistant.show_band(_assist)
		hud.meter.target = -1.0


## The putting panel: the practice drill and tally, the speed of the
## greens and the slope at the ball, and the read view.
func _update_putting_panel() -> void:
	if putting_panel == null or hole == null:
		return
	if not (state == State.AIM or state == State.SWING or state == State.SHOT_RESULT):
		putting_panel.visible = false
		return
	var lines: Array[String] = []
	if practice != null:
		lines.append(practice.status_text())
	var can_read := _putting_on_green()
	if can_read:
		var to_hole := Vector2(hole.pin.x - ball_at.x, hole.pin.z - ball_at.z)
		lines.append("Greens: %s\nSlope at the ball: %s" % [
			GreenRead.speed_text(graphics.green_firmness, graphics.green_speed, _links_greens()),
			GreenRead.lie_text(hole.terrain, ball_at, to_hole)])
		if read_view != GreenRead.View.PLAY:
			lines.append("View: %s" % GreenRead.VIEW_NAMES[read_view])
	putting_panel.show_panel("\n".join(lines), practice != null and state == State.AIM, can_read)


## V: the next way of looking at the putt (GreenRead.View).
func _next_read_view() -> void:
	if not _putting_on_green():
		return
	var views := GreenRead.views_for(graphics.skill)
	var i := views.find(read_view)
	read_view = views[(i + 1) % views.size()]
	_aim_camera(false)
	_update_putting_panel()


## The putting keys; true if `code` was one.
func _putting_key(code: int) -> bool:
	if state != State.AIM:
		return false
	var id := &""
	match code:
		KEY_V:
			id = &"read"
		KEY_N:
			id = &"new_spot"
		KEY_BRACKETLEFT:
			id = &"closer"
		KEY_BRACKETRIGHT:
			id = &"further"
		KEY_L:
			id = &"slope"
		KEY_P:
			id = &"drill"
		KEY_T:
			id = &"next_cup"
		KEY_H:
			id = &"next_green"
	if id == &"" or (practice == null and id != &"read"):
		return false
	_on_putting_action(id)
	return true


func _on_putting_action(id: StringName) -> void:
	if state != State.AIM or hud.hand_over.visible:
		return
	if id == &"read":
		_next_read_view()
		return
	if practice == null:
		return
	match id:
		&"new_spot":
			practice.new_spot()
		&"closer":
			practice.change_distance(-1)
		&"further":
			practice.change_distance(1)
		&"slope":
			practice.next_slope()
		&"drill":
			practice.next_drill()
			hud.show_message("%s: %s" % [PuttingPractice.DRILL_NAMES[practice.drill], PuttingPractice.DRILL_HELP[practice.drill]], 4.0)
		&"next_cup":
			practice.next_cup()
			hole.pin = practice.cup_position()
			practice_cups.build(practice.cups, practice.cup)
		&"next_green":
			start_hole((hole_index + 1) % holes.size())
			return
		_:
			return
	_practice_drop()


## Drops the practice ball at the practice's spot, ready to putt.
func _practice_drop() -> void:
	_assist_from = Vector3.INF
	_putt_from = Vector3.INF
	ball.visible = true
	ball_at = practice.spot
	players[current].at = ball_at
	strokes = 0
	_clear_trail()
	_prepare_shot(true)


## A practice putt has finished: score it, say how it went, and drop the
## next ball once the pause is over (_after_result).
func _practice_result() -> void:
	var holed := shot.outcome == ShotResult.Outcome.HOLED
	if holed:
		sounds.play(&"cup")
		ball.visible = false
	var msg := practice.record(shot.rest, holed)
	hud.show_message(msg, RESULT_PAUSE + 1.0)
	hud.hint.text = "Space or click: next putt    R: replay"
	state = State.SHOT_RESULT
	result_timer = RESULT_PAUSE
	_update_putting_panel()
