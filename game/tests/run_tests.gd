extends SceneTree
## Headless checks for the GDScript side of the game. Run after importing:
##   godot --headless --path game --import
##   godot --headless --path game -s res://tests/run_tests.gd
## Prints "GODOT TESTS PASSED" and exits 0 when everything passes.
##
## The expected numbers in the physics tests come from the C++ core
## (libs/olcore/tests/test_main.cpp prints them), so a drift between the two
## implementations fails here.

var _failures := 0
var _current := ""
var _game: GolfRound
var _frames := 0
var _done := false


func _initialize() -> void:
	# Rounds the tests finish go here, not into the player's own profiles.
	PlayerProfiles.path = "user://test_profiles.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfiles.path))
	SavedRound.path = "user://test_saved_round.cfg"
	SavedRound.clear()
	_run("physics_matches_olcore", _test_physics_matches_olcore)
	_run("club_table_matches_physics", _test_club_table_matches_physics)
	_run("putting", _test_putting)
	_run("hazards", _test_hazards)
	_run("wind_matches_olcore", _test_wind_matches_olcore)
	_run("wind_conditions", _test_wind_conditions)
	_run("links_flight_matches_olcore", _test_links_flight_matches_olcore)
	_run("links_ground_matches_olcore", _test_links_ground_matches_olcore)
	_run("links_cup_matches_olcore", _test_links_cup_matches_olcore)
	_run("links_objects_match_olcore", _test_links_objects_match_olcore)
	_run("links_models_match_olcore", _test_links_models_match_olcore)
	_run("links_launch_matches_olcore", _test_links_launch_matches_olcore)
	_run("links_lie_matches_olcore", _test_links_lie_matches_olcore)
	_run("links_swing_matches_olcore", _test_links_swing_matches_olcore)
	_run("obstacles_match_olcore", _test_obstacles_match_olcore)
	_run("swing_accuracy", _test_swing_accuracy)
	_run("shot_shape", _test_shot_shape)
	_run("swing_meter", _test_swing_meter)
	_run("analog_swing", _test_analog_swing)
	_run("scorecard", _test_scorecard)
	_run("game_modes_match_olcore", _test_game_modes)
	_run("handicaps_match_olcore", _test_handicaps)
	_run("player_profiles", _test_player_profiles)
	_run("round_setup", _test_round_setup)
	_run("round_scoring", _test_round_scoring)
	_run("drop_rules_match_olcore", _test_drop_rules_match_olcore)
	_run("drop_rules_hazards_and_bounds", _test_drop_rules_hazards_and_bounds)
	_run("rest_out_of_bounds", _test_rest_out_of_bounds)
	_run("opponent_skill_matches_olcore", _test_opponent_skill_matches_olcore)
	_run("computer_golfer_plans", _test_computer_golfer_plans)
	_run("caddie", _test_caddie)
	_run("buggy_drive", _test_buggy_drive)
	_run("real_scale", _test_real_scale)
	_run("handicap_scoring", _test_handicap_scoring)
	_run("placeholder_course", _test_placeholder_course)
	_run("graphics_settings", _test_graphics_settings)
	_run("grass", _test_grass)
	_run("wind_gusts", _test_wind_gusts)
	_run("course_marks", _test_course_marks)
	_run("sound_over_distance", _test_sound_over_distance)
	_run("trees", _test_trees)
	_run("ground shade", _test_ground_shade)
	_run("broadcast_pieces", _test_broadcast_pieces)
	_run("hd_pack", _test_hd_pack)
	_run("object_library_chain", _test_object_library_chain)
	_run("free_assets", _test_free_assets)
	_run("web_game_files", _test_web_game_files)
	_run("golfer_file_readers", _test_golfer_file_readers)
	_run("free_golfer", _test_free_golfer)
	_run("free_sounds", _test_free_sounds)
	_run("format_readers", _test_format_readers)
	_run("course_reader", _test_course_reader)
	_run("course_designer", _test_course_designer)
	_run("real_courses", _test_real_courses)
	# Nodes added here only get _ready() once the main loop runs, so the
	# full round is played from _process().
	# Fixed wind, so the shots (and what the camera sees) are the same every run.
	GolfRound.wind_seed = 20031
	RoundRecord.folder = "user://test_replays"
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as GolfRound
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _done or (not _game.is_node_ready() and _frames < 30):
		return false
	_done = true
	_run("full_round", _test_full_round)
	_run("round_replay", _test_round_replay)
	_run("drops_in_round", _test_drops_in_round)
	_run("multiplayer_rounds", _test_multiplayer_rounds)
	_run("practice_range", _test_practice_range)
	_run("gimmes", _test_gimmes)
	_run("launch_monitor_input", _test_launch_monitor_input)
	_run("computer_opponents", _test_computer_opponents)
	_run("team_ball_modes", _test_team_ball_modes)
	_run("team_drops", _test_team_drops)
	_run("pause_stops_play", _test_pause_stops_play)
	_run("touch_and_stick_swings", _test_touch_and_stick_swings)
	_run("tee_view", _test_tee_view)
	_run("rounds_recorded", _test_rounds_recorded)
	_run("saved_round", _test_saved_round)
	_run("viewer_return", _test_viewer_return)
	_run("retee_after_ob", _test_retee_after_ob)
	_run("players_panel", _test_players_panel)
	SavedRound.clear()
	_run("menu_resume", _test_menu_resume)
	SavedRound.clear()
	_run("broadcast_round", _test_broadcast_round)
	_run("designer_scene", _test_designer_scene)
	_run("designed_round", _test_designed_round)
	_run("caddie_and_buggy_in_round", _test_caddie_and_buggy_in_round)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfiles.path))
	if _failures > 0:
		print("%d check(s) failed" % _failures)
		quit(1)
	else:
		print("GODOT TESTS PASSED")
		quit(0)
	return true


## OL_TEST_ONLY=name1,name2 runs just those tests (handy when iterating).
func _run(test_name: String, fn: Callable) -> void:
	var only := OS.get_environment("OL_TEST_ONLY")
	if not only.is_empty() and not test_name in only.split(","):
		return
	_current = test_name
	print(test_name)
	fn.call()


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		print("  FAIL %s: %s" % [_current, what])


func _check_near(actual: float, expected: float, tol: float, what: String) -> void:
	_check(absf(actual - expected) <= tol, "%s = %f, expected %f +/- %f" % [what, actual, expected, tol])


func _club(short_name: String) -> Club:
	for c in Club.standard_set():
		if c.short_name == short_name:
			return c
	_check(false, "no club " + short_name)
	return null


func _test_course_reader() -> void:
	var tests: RefCounted = load("res://tests/course_tests.gd").new()
	for failure: String in tests.call("run_all"):
		_check(false, failure)


func _test_real_courses() -> void:
	var tests: RefCounted = load("res://tests/realcourse_tests.gd").new()
	for failure: String in tests.call("run_all"):
		_check(false, failure)


func _test_course_designer() -> void:
	var tests: RefCounted = load("res://tests/designer_tests.gd").new()
	for failure: String in tests.call("run_all"):
		_check(false, failure)


## Opens the designer on a fresh starter course, adds a hole and undoes it.
func _test_designer_scene() -> void:
	CourseDesigner.last_path = ""
	var scene: PackedScene = load("res://scenes/course_designer.tscn")
	var d := scene.instantiate() as CourseDesigner
	root.add_child(d)
	_check(d.is_node_ready() and d.course != null and d.course.holes.size() == 1, "the designer opens on a starter course")
	if d.course == null:
		d.queue_free()
		return
	d._process(0.016)
	var built := 0
	for c: Vector2i in d._chunks:
		if (d._chunks[c] as MeshInstance3D).mesh != null:
			built += 1
	_check(built > 0 and built == d._chunks.size(), "every ground chunk has a mesh (%d of %d)" % [built, d._chunks.size()])
	var shapes := d.course.shapes.size()
	d._add_hole()
	d._process(0.016)
	_check(d.course.holes.size() == 2 and d.hole_index == 1, "a hole is added")
	_check(d.course.shapes.size() > shapes, "with its tee box and green")
	d._undo_step(d._undo, d._redo, "undo")
	_check(d.course.holes.size() == 1 and d.course.shapes.size() == shapes, "undo takes it away again")
	d._undo_step(d._redo, d._undo, "redo")
	_check(d.course.holes.size() == 2, "redo puts it back")
	_check(d._pick(Vector2(640, 360)) != null, "the middle of the view is on the ground")
	var objects := d.course.objects.size()
	d._place_or_remove_object(Vector2(0, 0), false)
	_check(d.course.objects.size() == objects + 1 and d._tree_nodes.size() == objects + 1, "an object is placed")
	d._place_or_remove_object(Vector2(0, 0), true)
	_check(d.course.objects.size() == objects, "and removed again")
	d._start_flyover()
	_check(d._preview.current and d._preview.flying(), "the hole flyover starts")
	for i in 3:
		d._process(0.5)
	d._stop_flyover()
	_check(not d._preview.current and d.camera.current, "and hands back to the designer camera")
	d.queue_free()


## The caddie reads the player's shots and the buggy drives to the ball
## (skipped here) through a real round, then both go away when turned off.
func _test_caddie_and_buggy_in_round() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	GolfRound.setup = null
	game.course_path = ""
	game.graphics.caddie = true
	game.graphics.buggy = true
	game._apply_graphics()
	game.start_round()
	_check(game.caddie != null and game.buggy != null, "caddie and buggy are on")
	var read := false
	var drove := false
	var steps := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 600:
		if game.state == GolfRound.State.AIM and game.caddie.advice != null and not read:
			game.caddie.advice.finish()
			read = game.caddie.advice.is_ready() and not game.caddie.advice.text.is_empty()
			print("  caddie: " + game.caddie.advice.text)
		if game.state == GolfRound.State.DRIVE and not drove:
			drove = true
			var from := game.buggy.drive.position
			for i in 60:
				game.buggy.step(1.0 / 30.0, 1.0, 0.0, game.hole.terrain)
			_check(game.buggy.drive.position.distance_to(from) > 1.0 or game.buggy.drive.blocked, "the buggy drives")
			game._process_drive(1.0 / 30.0)
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.ROUND_DONE, "the round finishes with the caddie and buggy")
	_check(read, "the caddie read a shot")
	_check(drove, "the buggy drove to a ball")
	game.graphics.caddie = false
	game.graphics.buggy = false
	game._apply_graphics()
	_check(game.caddie == null and game.buggy == null, "both off again")


## A whole round on the designer's starter course.
func _test_designed_round() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var path := "user://designed_round_test.olc"
	var c := DesignedCourse.starter()
	c.course_name = "Designed test"
	_check(c.save_file(path) == OK, "the course saves")
	GolfRound.setup = RoundSetup.single(path)
	game.course_path = ""
	game.start_round()
	_check(game.course.course_name == "Designed test", "the round plays the designed course")
	var steps := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 400:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.ROUND_DONE, "the designed round finishes")
	print("  designed course: %d strokes on a par %d" % [game.card.total_strokes(), game.holes[0].par])
	GolfRound.setup = null
	DirAccess.remove_absolute(path)

	# Saving never writes over a different course with the same name.
	var a := DesignedCourse.starter()
	a.course_name = "Save path test"
	var own := a.save_path()
	_check(own == a.default_path(), "a new course saves under its name")
	_check(a.save_file(own) == OK, "save path test course saves")
	_check(a.save_path(own) == own, "a course saves over its own file")
	var b := DesignedCourse.starter()
	b.course_name = "Save path test"
	_check(b.save_path().get_file() == "Save path test 2.olc", "a second course with the name gets its own file: %s" % b.save_path())
	DirAccess.remove_absolute(own)


func _test_format_readers() -> void:
	var tests: RefCounted = load("res://tests/format_tests.gd").new()
	for failure: String in tests.call("run_all"):
		_check(false, failure)


func _test_physics_matches_olcore() -> void:
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY)
	var drive := BallPhysics.simulate_shot(Swing.launch_from_swing(_club("Dr"), 1.0, 0.0, 0.0, Surface.Type.TEE), fairway)
	print("  drive: carry %.2f m, total %.2f m, %d bounces" % [drive.carry_m, drive.total_m, drive.bounces])
	_check_near(drive.carry_m, 223.61, 1.0, "drive carry")
	_check_near(drive.total_m, 264.33, 1.5, "drive total")
	_check(drive.outcome == ShotResult.Outcome.REST, "drive comes to rest")

	var green := FlatTerrain.new(Surface.Type.GREEN)
	var wedge := BallPhysics.simulate_shot(Swing.launch_from_swing(_club("PW"), 1.0, 0.0, 0.0, Surface.Type.FAIRWAY), green)
	print("  wedge: carry %.2f m, total %.2f m" % [wedge.carry_m, wedge.total_m])
	_check_near(wedge.carry_m, 126.30, 1.0, "wedge carry")
	_check_near(wedge.total_m, 126.28, 1.0, "wedge total")


func _test_club_table_matches_physics() -> void:
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY)
	for c in Club.standard_set():
		if c.is_putter:
			continue
		var r := BallPhysics.simulate_shot(Swing.launch_from_swing(c, 1.0, 0.0, 0.0, Surface.Type.FAIRWAY), fairway)
		_check_near(r.carry_m, c.carry_m, c.carry_m * 0.015, c.short_name + " carry")
		_check_near(r.total_m, c.total_m, c.total_m * 0.015, c.short_name + " total")


func _test_putting() -> void:
	var green := FlatTerrain.new(Surface.Type.GREEN)
	var cup := Vector3(0, 0, 3)
	var made := BallPhysics.simulate_shot(BallPhysics.make_launch(2.0, 0, 0, 0, 0), green, true, cup)
	_check(made.outcome == ShotResult.Outcome.HOLED, "2 m/s putt drops")
	var fast := BallPhysics.simulate_shot(BallPhysics.make_launch(5.0, 0, 0, 0, 0), green, true, cup)
	_check(fast.outcome == ShotResult.Outcome.REST and fast.rest.z > 3.0, "5 m/s putt runs past")
	var roll := BallPhysics.simulate_shot(BallPhysics.make_launch(3.0, 0, 0, 0, 0), green)
	_check_near(roll.total_m, 9.0 / (2.0 * Surface.rolling_resistance(Surface.Type.GREEN) * BallPhysics.GRAVITY), 0.05, "putt length")
	var putter := _club("Pt")
	var full := BallPhysics.simulate_shot(Swing.launch_from_swing(putter, 1.0, 0.0, 0.0, Surface.Type.GREEN), green)
	_check_near(full.total_m, putter.total_m, 0.5, "full putt")


func _test_hazards() -> void:
	var water := BallPhysics.simulate_shot(Swing.launch_from_swing(_club("7i"), 1.0, 0.0, 0.0, Surface.Type.FAIRWAY), FlatTerrain.new(Surface.Type.WATER))
	_check(water.outcome == ShotResult.Outcome.WATER, "lands in water")
	var ob := BallPhysics.simulate_shot(Swing.launch_from_swing(_club("7i"), 1.0, 0.0, 0.0, Surface.Type.FAIRWAY), FlatTerrain.new(Surface.Type.OUT_OF_BOUNDS))
	_check(ob.outcome == ShotResult.Outcome.OUT_OF_BOUNDS, "lands out of bounds")


func _test_obstacles_match_olcore() -> void:
	var f := ObstacleField.new()
	f.add_cylinder(0, 10, 0.5, 0, 5, ObstacleField.Kind.SOLID)
	f.add_box(Vector3(20, 1, 0), Basis.IDENTITY, Vector3(1, 1, 2), ObstacleField.Kind.SOLID)
	f.add_cylinder(-30, 0, 4, 2, 10, ObstacleField.Kind.CANOPY)
	f.finalize()
	_check(f.size() == 3, "three obstacles")
	var h := f.segment_hit(Vector3(0, 1, 0), Vector3(0, 1, 20))
	_check(not h.is_empty(), "hits the trunk")
	if not h.is_empty():
		_check_near(h.fraction, 9.5 / 20.0, 1e-5, "trunk entry")
		_check_near((h.normal as Vector3).z, -1.0, 1e-5, "trunk normal")
	_check(f.segment_hit(Vector3(0, 6, 0), Vector3(0, 6, 20)).is_empty(), "passes over the trunk")
	_check(f.segment_hit(Vector3(0, 1, 10), Vector3(0, 1, 20)).is_empty(), "starting inside misses")
	h = f.segment_hit(Vector3(15, 1, 0), Vector3(25, 1, 0))
	_check(not h.is_empty() and absf(float(h.fraction) - 0.4) < 1e-5 and (h.normal as Vector3).x < -0.99, "box side")
	h = f.segment_hit(Vector3(20, 4, 0.5), Vector3(20, 1, 0.5))
	_check(not h.is_empty() and absf(float(h.fraction) - 2.0 / 3.0) < 1e-5 and (h.normal as Vector3).y > 0.99, "box top")
	h = f.segment_hit(Vector3(-30, 12, 1), Vector3(-30, 8, 1))
	_check(not h.is_empty() and int(h.kind) == ObstacleField.Kind.CANOPY, "canopy top")
	_check(f.segment_hit(Vector3(-40, 1, 0), Vector3(-20, 1, 0)).is_empty(), "under the canopy")

	# The same shots as test_trees_stop_the_ball in test_main.cpp.
	var ground := FlatTerrain.new(Surface.Type.FAIRWAY)
	var trunk := ObstacleField.new()
	trunk.add_cylinder(0, 40, 0.5, -1, 30, ObstacleField.Kind.SOLID)
	trunk.finalize()
	ground.obstacles = trunk
	var r := BallPhysics.simulate_shot(Swing.launch_from_swing(_club("Dr"), 1.0, 0.0, 0.0, Surface.Type.TEE), ground)
	print("  trunk: rest z %.2f m, total %.2f m, %d hits" % [r.rest.z, r.total_m, r.obstacle_hits])
	_check_near(r.rest.z, -27.06, 1.0, "trunk rest z")
	_check(r.obstacle_hits >= 1, "trunk hit")
	var canopy := ObstacleField.new()
	canopy.add_cylinder(0, 150, 6, 3, 40, ObstacleField.Kind.CANOPY)
	canopy.finalize()
	ground.obstacles = canopy
	r = BallPhysics.simulate_shot(Swing.launch_from_swing(_club("Dr"), 1.0, 0.0, 0.0, Surface.Type.TEE), ground)
	print("  canopy: carry %.2f m, total %.2f m, %d hits" % [r.carry_m, r.total_m, r.obstacle_hits])
	_check_near(r.carry_m, 140.95, 1.0, "canopy carry")
	_check_near(r.total_m, 155.83, 1.5, "canopy total")
	var wall := ObstacleField.new()
	wall.add_box(Vector3(0, 0.5, 4), Basis.IDENTITY, Vector3(2, 1, 0.1), ObstacleField.Kind.SOLID)
	wall.finalize()
	var green := FlatTerrain.new(Surface.Type.GREEN)
	green.obstacles = wall
	r = BallPhysics.simulate_shot(BallPhysics.make_launch(3.0, 0, 0, 0, 0), green)
	print("  wall: rest z %.3f m, %d hits" % [r.rest.z, r.obstacle_hits])
	_check_near(r.rest.z, 3.348, 0.02, "wall rest z")
	_check(r.obstacle_hits == 1, "wall hit once")
	var deck := ObstacleField.new()
	deck.add_box(Vector3(0, 1, 0), Basis.IDENTITY, Vector3(5, 0.5, 5), ObstacleField.Kind.SOLID)
	deck.finalize()
	ground.obstacles = deck
	r = BallPhysics.simulate_shot(BallState.new(Vector3(0, 3, 0), Vector3(0, 1, 0.5)), ground)
	_check(r.outcome == ShotResult.Outcome.REST, "settles on the deck")
	_check_near(r.rest.y, 1.510, 0.01, "deck rest y")
	_check(r.obstacle_hits == 3, "deck hits")


func _test_swing_accuracy() -> void:
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY)
	var hook := BallPhysics.simulate_shot(Swing.launch_from_swing(_club("7i"), 1.0, -0.5, 0.0, Surface.Type.FAIRWAY), fairway)
	var slice := BallPhysics.simulate_shot(Swing.launch_from_swing(_club("7i"), 1.0, 0.5, 0.0, Surface.Type.FAIRWAY), fairway)
	_check(hook.rest.x > 5.0, "early swing goes left")
	_check(slice.rest.x < -5.0, "late swing goes right")
	var rough := BallPhysics.simulate_shot(Swing.launch_from_swing(_club("7i"), 1.0, 0.0, 0.0, Surface.Type.ROUGH), fairway)
	var clean := BallPhysics.simulate_shot(Swing.launch_from_swing(_club("7i"), 1.0, 0.0, 0.0, Surface.Type.FAIRWAY), fairway)
	_check(rough.carry_m < clean.carry_m, "rough costs distance")


func _test_shot_shape() -> void:
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY)
	var model := StandardShotModel.new()
	var shape := ShotShape.new()
	var results := {}
	for name: String in ["square", "fade", "draw", "high", "low"]:
		shape.reset()
		match name:
			"fade": shape.nudge_curve(5)
			"draw": shape.nudge_curve(-5)
			"high": shape.nudge_height(2)
			"low": shape.nudge_height(-2)
		model.setup = shape.to_setup("7i")
		results[name] = model.simulate(model.launch(_club("7i"), 1.0, 0.0, 0.0, Surface.Type.FAIRWAY, Vector3.ZERO), fairway, Vector3(0, 0, 999))
	var square: ShotResult = results["square"]
	_check(absf(square.rest.x) < 0.5, "a square shot goes straight")
	_check((results["fade"] as ShotResult).rest.x < -5.0, "a fade finishes right")
	_check((results["draw"] as ShotResult).rest.x > 5.0, "a draw finishes left")
	_check((results["high"] as ShotResult).apex_m > square.apex_m + 1.0, "ball forward flies higher")
	_check((results["low"] as ShotResult).apex_m < square.apex_m - 1.0, "ball back flies lower")
	# Through the game's own launch: square is the game's default setup, and
	# a fade spins the other way from a draw.
	shape.reset()
	var setup := shape.to_setup("Dr")
	_check(setup.ball_position == -1 and setup.face == 30 and setup.stance == 30, "square is the game's default setup")
	shape.nudge_curve(2)
	setup = shape.to_setup("Dr")
	_check(setup.stance == 28 and setup.face == 32, "a fade turns the path left and the face back square")
	shape.nudge_height(1)
	_check(shape.to_setup("7i").ball_position == 3, "higher moves the ball one step forward")
	_check(shape.describe() == "Fade 2, high 1", "shape text")
	# A shaped shot's setup survives a result code.
	var rec := ShotRecord.new()
	rec.face = 32
	rec.stance = 28
	rec.ball_position = 3
	var back := ShotRecord.from_dict(rec.to_dict())
	_check(back.face == 32 and back.stance == 28 and back.ball_position == 3, "setup round-trips")
	_check(not ShotRecord.new().to_dict().has("setup"), "square shots add nothing to the record")


func _test_club_ratings() -> void:
	# The game's full-swing power ratings, from its default club records.
	var want := {"Dr": 112.0, "PW": 80.0}
	var bag := Club.standard_set()
	var last := 999.0
	for c in bag:
		var r := LinksShotModel.club_rating(c)
		if c.is_putter:
			_check(r == 100.0, "the putter keeps its own scale")
			continue
		if want.has(c.short_name):
			_check_near(r, want[c.short_name], 1e-9, "%s power rating" % c.short_name)
		_check(r <= last, "ratings fall through the bag (%s)" % c.short_name)
		last = r
	var plain := StandardShotModel.new()
	_check(plain.reach_scale(bag[0]) == 1.0, "the stand-in model keeps club distances")


func _test_swing_meter() -> void:
	var meter := SwingMeter.new()
	var results := []
	meter.swing_finished.connect(func(p: float, a: float) -> void: results.append([p, a]))
	meter.click()
	_check(meter.phase == SwingMeter.Phase.BACKSWING, "first click starts the backswing")
	_check(meter.run.pos == LinksPowerStroke.SNAP, "a full swing starts at the snap line")
	# Half a frame at a time, so the marker never moves more than a position.
	var t := 0.0
	while meter.run.pos < LinksPowerStroke.FULL_POWER:
		meter._process(0.004)
		t += 0.004
	_check_near(t, 1.048, 0.01, "the game's meter takes about a second to full power")
	meter.click()
	_check_near(meter.power, 1.0, 1e-6, "second click at position 54 is full power")
	while meter.run.pos > LinksPowerStroke.SNAP:
		meter._process(0.004)
	meter.click()
	_check(results.size() == 1, "third click finishes the swing")
	if results.size() == 1:
		_check_near(results[0][1], 0.0, 1e-6, "on the line is perfect")
	meter.click()
	while meter.run.pos < 40:
		meter._process(0.004)
	meter.click()
	while meter.run.rising or meter.run.pos > 7:
		meter._process(0.004)
	meter.click()
	_check(results.size() == 2 and results[1][1] > 0.4, "late click slices")
	_check_near(LinksPowerStroke.full_power(67), 1.08, 1e-6, "overswing tops out 8 percent over")
	_check_near(LinksPowerStroke.chip_power(15), 7.0, 1e-6, "chip power at the snap line")
	_check_near(LinksPowerStroke.chip_power(68), 34.95, 1e-4, "chip power at the top")
	_check_near(LinksPowerStroke.chip_power(32), 14.25, 1e-4, "chip power midway")
	# A chip waits for its earliest power, then turns six positions on.
	var chip := LinksPowerStroke.Run.new(LinksPowerStroke.Mode.CHIP)
	chip.click_power()
	while chip.rising:
		chip.advance(0.004)
	_check(chip.power_pos == 16 and chip.pos == 22, "chip power waits for 16 and turns at 22 (%d, %d)" % [chip.power_pos, chip.pos])
	meter.free()


func _test_scorecard() -> void:
	_check(Scorecard.score_name(1, 3) == "Hole in one", "ace")
	_check(Scorecard.score_name(3, 4) == "Birdie", "birdie")
	_check(Scorecard.score_name(2, 5) == "Albatross", "albatross")
	_check(Scorecard.score_name(9, 4) == "+5", "+5")
	var pars: Array[int] = [4, 3, 5]
	var card := Scorecard.new(pars)
	card.record(0, 5)
	card.record(1, 2)
	_check(card.total_strokes() == 7, "total")
	_check(Scorecard.format_to_par(card.to_par()) == "E", "even")
	card.record(2, 7)
	_check(Scorecard.format_to_par(card.to_par()) == "+2", "+2")
	var board := GolfRound.leaderboard_lines([["Ann", "70 (-2)"], ["Bob", "72 (E)"], ["Cy", "72 (E)"], ["Di", "75 (+3)"]])
	_check(board == _strs(["1. ANN  70 (-2)", "T2. BOB  72 (E)", "T2. CY  72 (E)", "4. DI  75 (+3)"]), "leaderboard ties: %s" % [board])
	# An 18-hole card gets an Out column after the ninth.
	var s18 := RoundSetup.new()
	s18.mode = GameModes.Mode.STABLEFORD
	var pars18: Array[int] = []
	var numbers: Array[int] = []
	for i in 18:
		pars18.append(4)
		numbers.append(i + 1)
	var scoring := RoundScoring.new(s18, pars18, numbers)
	for i in 10:
		scoring.cards[0].record(i, 5)
	var panel := ScorecardPanel.new()
	panel._ready()  # not in the tree yet: nodes added now only get _ready() once the main loop runs
	panel.show_round(scoring, "Test")
	var grid: GridContainer = panel._grid
	_check(grid.columns == 21, "scorecard: 18 holes, Out and Tot")
	# Rows: hole, par, score, points.
	_check(grid.get_child_count() == 21 * 4, "scorecard: every row has the Out column (%d cells)" % grid.get_child_count())
	_check((grid.get_child(21 + 10) as Label).text == "36", "scorecard: par out")
	_check((grid.get_child(42 + 10) as Label).text == "45", "scorecard: strokes out")
	_check((grid.get_child(63 + 10) as Label).text == "9", "scorecard: points out")
	panel.free()


## The same cases as test_game_modes in libs/olcore/tests/test_main.cpp.
func _test_game_modes() -> void:
	_check(GameModes.stableford_points(4, 4) == 2, "stableford par")
	_check(GameModes.stableford_points(3, 4) == 3, "stableford birdie")
	_check(GameModes.stableford_points(2, 5) == 5, "stableford albatross")
	_check(GameModes.stableford_points(6, 4) == 0, "stableford double bogey")
	_check(GameModes.stableford_points(9, 4) == 0, "stableford never negative")
	_check(GameModes.stableford_points(0, 4) == 0, "stableford unplayed")
	var pars: Array[int] = [4, 3, 5]
	var card := Scorecard.new(pars)
	card.record(0, 5)
	card.record(1, 2)
	_check(GameModes.stableford_total(card) == 4, "stableford total")

	var bb := GameModes.best_ball([_ints([5, 3, 0]), _ints([4, 4, 0])])
	_check(bb == _ints([4, 3, 0]), "best ball %s" % [bb])

	var sk := GameModes.skins([_ints([4, 3, 4, 5, 0]), _ints([5, 3, 5, 5, 0]), _ints([5, 4, 6, 5, 0])])
	_check(sk.skins == _ints([3, 0, 0]), "skins %s" % [sk.skins])
	_check(sk.hole_winner == _ints([0, -1, 0, -1, -2]), "skin winners %s" % [sk.hole_winner])
	_check(sk.carried == 1, "skin carried")
	var part := GameModes.skins([_ints([4, 3]), _ints([3, 0])])
	_check(part.skins[1] == 1 and part.hole_winner[1] == -2, "incomplete hole doesn't count")

	var a := _ints([4, 3, 5, 4, 0, 0, 0, 0, 0])
	var b := _ints([5, 4, 5, 5, 0, 0, 0, 0, 0])
	var m := GameModes.match_status(a, b)
	_check(m.up == 3 and m.played == 4 and m.remaining == 5 and not m.finished and not m.dormie, "match after 4: %s" % m)
	_check(GameModes.match_text(m) == "3 up", "3 up")
	a[4] = 4
	b[4] = 5
	m = GameModes.match_status(a, b)
	_check(m.up == 4 and m.remaining == 4 and m.dormie and GameModes.match_text(m) == "4 up (dormie)", "dormie: %s" % m)
	a[5] = 3
	b[5] = 4
	m = GameModes.match_status(a, b)
	_check(m.finished and m.played == 6 and m.remaining == 3 and GameModes.match_text(m) == "5 & 3", "won early: %s" % m)
	m = GameModes.match_status(_ints([4, 4, 4]), _ints([4, 3, 5]))
	_check(m.up == 0 and m.finished and GameModes.match_text(m) == "Halved", "halved")
	m = GameModes.match_status(_ints([4, 4, 3]), _ints([4, 4, 4]))
	_check(m.up == 1 and m.finished and m.remaining == 0 and GameModes.match_text(m) == "1 up", "won on the last")
	m = GameModes.match_status(_ints([5, 0]), _ints([4, 0]))
	_check(m.up == -1 and m.played == 1 and m.dormie and GameModes.match_text(m) == "1 up (dormie)", "B dormie")
	_check(GameModes.match_text(GameModes.match_status(_ints([0, 0]), _ints([0, 0]))) == "All square", "all square")


## The same cases as test_handicaps in libs/olcore/tests/test_main.cpp.
func _test_handicaps() -> void:
	_check(Handicap.div_round(95, 10) == 10 and Handicap.div_round(94, 10) == 9, "div_round")
	_check(Handicap.div_round(-95, 10) == -10 and Handicap.div_round(-94, 10) == -9, "div_round negative")
	var r := Handicap.stroke_ranks(_ints([8, 2, 16, 4, 12, 18, 6, 14, 10]))
	_check(r == _ints([4, 1, 8, 2, 6, 9, 3, 7, 5]), "back nine ranks: %s" % [r])
	r = Handicap.stroke_ranks(_ints([0, 3, 0, 1]))
	_check(r == _ints([3, 2, 4, 1]), "missing index ranks last: %s" % [r])
	var ranks := _ints([3, 1, 2])
	_check(Handicap.strokes(4, ranks) == _ints([1, 2, 1]), "4 over 3 holes")
	_check(Handicap.strokes(6, ranks) == _ints([2, 2, 2]), "6 over 3 holes")
	_check(Handicap.strokes(0, ranks) == _ints([0, 0, 0]), "scratch")
	_check(Handicap.strokes(-1, ranks) == _ints([-1, 0, 0]), "plus 1 gives back on the easiest")
	_check(Handicap.strokes(-4, ranks) == _ints([-2, -1, -1]), "plus 4")
	_check(Handicap.net_scores(_ints([5, 3, 0, 2]), _ints([1, 2, 1, 3])) == _ints([4, 1, 0, 1]), "net scores")
	_check(Handicap.net_scores(_ints([4, 4]), _ints([-1, 0])) == _ints([5, 4]), "net with a plus handicap")
	_check(Handicap.playing_handicap(100, 18, 95) == 10, "9.5 rounds up")
	_check(Handicap.playing_handicap(184, 18, 100) == 18, "18.4")
	_check(Handicap.playing_handicap(184, 9, 100) == 9, "9.2 over nine")
	_check(Handicap.playing_handicap(-14, 18, 100) == -1, "plus 1.4")
	_check(Handicap.playing_handicap(Handicap.NONE, 18, 100) == 0, "no index plays scratch")
	var card := Scorecard.new(_ints([4, 3, 5]))
	card.record(0, 9)
	card.record(1, 4)
	card.record(2, 5)
	_check(Handicap.adjusted_gross(card, _ints([1, 0, 0]), true) == 16, "net double bogey cap")
	_check(Handicap.adjusted_gross(card, _ints([0, 0, 0]), false) == 18, "par + 5 cap")
	_check(Handicap.score_differential(85, 72, 18) == 130, "differential")
	_check(Handicap.score_differential(42, 36, 9) == 120, "nine-hole differential")
	_check(Handicap.score_differential(70, 72, 18) == -20, "under par")
	_check(Handicap.score_differential(41, 35, 7) == 154, "seven holes")
	_check(Handicap.rounds_used(2) == 0 and Handicap.rounds_used(6) == 2 and Handicap.rounds_used(19) == 7, "rounds used")
	_check(Handicap.rounds_used(20) == 8 and Handicap.rounds_used(40) == 8, "rounds used tops out at 8")
	_check(Handicap.index(_ints([130, 120])) == Handicap.NONE, "two rounds: no index")
	_check(Handicap.index(_ints([130, 120, 150])) == 100, "three rounds")
	_check(Handicap.index(_ints([130, 120, 150, 140])) == 110, "four rounds")
	_check(Handicap.index(_ints([130, 125, 150, 140, 160, 170])) == 118, "six rounds")
	var many: Array[int] = []
	for i in 25:
		many.append(100 + i * 10)
	_check(Handicap.index(many) == 185, "most recent 20: %d" % Handicap.index(many))
	_check(Handicap.index(_ints([700, 650, 800])) == Handicap.MAX_TENTHS, "capped at 54")
	_check(Handicap.index(_ints([-300, -250, -200])) == Handicap.MIN_TENTHS, "capped at +10")
	_check(Handicap.format(123) == "12.3" and Handicap.format(-14) == "+1.4", "format")
	_check(Handicap.format(0) == "0.0" and Handicap.format(Handicap.NONE) == "-", "format scratch and none")
	_check(Handicap.parse("12.3") == 123 and Handicap.parse("+1.4") == -14 and Handicap.parse("8") == 80, "parse")
	_check(Handicap.parse("") == Handicap.NONE and Handicap.parse("abc") == Handicap.NONE, "parse rejects")


func _test_player_profiles() -> void:
	var p := PlayerProfiles.load_saved()
	_check(not p.has_player("Ann"), "no profile yet")
	_check(p.index_of("Ann") == Handicap.NONE, "no index yet")
	p.set_start_index("Ann", 200)
	_check(p.index_of("ann ") == 200, "names match without case or spaces")
	var pars := _ints([4, 4, 3, 5, 4, 4, 3, 5, 4])
	var ranks := Handicap.stroke_ranks(_ints([1, 3, 5, 7, 9, 11, 13, 15, 17]))
	var short := Scorecard.new(_ints([4, 4, 3]))
	for h in 3:
		short.record(h, 5)
	_check(not p.record_round("Ann", short, _ints([1, 2, 3]), "Test", "2026-10-31"), "three holes don't count")
	var card := Scorecard.new(pars)
	_check(not p.record_round("Ann", card, ranks, "Test", "2026-10-31"), "an unfinished round doesn't count")
	# 45 on a par 36: 9 over, so 18.0 scaled to 18 holes.
	for h in 9:
		card.record(h, pars[h] + 1)
	for _n in 3:
		_check(p.record_round("Ann", card, ranks, "Test", "2026-10-31"), "a full nine counts")
	_check(p.rounds("Ann").size() == 3 and p.rounds("Ann")[0].differential == 180, "rounds kept: %s" % [p.rounds("Ann")])
	_check(p.has_record("Ann") and p.index_of("Ann") == 160, "index from three rounds: %d" % p.index_of("Ann"))
	var c := p.career("Ann")
	_check(c.rounds == 3 and c.holes == 27 and c.strokes == 135 and c.par == 108 and c.stat_holes == 0, "career totals: %s" % c)
	var stats := {"holes": 9, "fairways": 4, "fairway_holes": 7, "gir": 3, "putts": 16}
	_check(p.record_round("Ann", card, ranks, "Test", "2026-10-31", stats), "a round with stats")
	_check(p.rounds("Ann").back().putts == 16 and p.rounds("Ann").back().gir == 3, "stats on the round")
	c = p.career("Ann")
	_check(c.rounds == 4 and c.stat_holes == 9 and c.fairways == 4 and c.fairway_holes == 7 and c.putts == 16, "career stats: %s" % c)
	var text := PlayerProfiles.career_text(c)
	_check(text == "Average 90.0 per 18   Fairways 57%   Greens 33%   Putts 32.0 per 18", "career text: %s" % text)
	_check(PlayerProfiles.career_text(p.career("Nobody")).is_empty(), "no career yet")
	# Personal records: a birdie and an eagle on a better round, and a drive.
	var good := Scorecard.new(pars)
	for h in 9:
		good.record(h, pars[h])
	good.record(0, 3)
	good.record(3, 3)
	var drive := {"holes": 9, "fairways": 4, "fairway_holes": 7, "gir": 3, "putts": 16, "longest_drive_yd": 281}
	_check(p.record_round("Bea", good, ranks, "Test", "2026-11-01", drive), "a good round")
	var rec := p.records("Bea")
	_check(rec.birdies == 1 and rec.eagles == 1 and rec.aces == 0 and rec.longest_drive_yd == 281, "records: %s" % rec)
	var rtext := PlayerProfiles.records_text(rec)
	_check(rtext == "Best 33 (-3) at Test   Longest drive 281 yd   1 birdie, 1 eagle", "records text: %s" % rtext)
	_check(PlayerProfiles.records_text(p.records("Nobody")).is_empty(), "no records yet")
	p.remove("Bea")
	# A profile saved before career stats starts from its rounds.
	p._cfg.set_value(PlayerProfiles._section("Old"), "rounds", [{"holes": 18, "gross": 90, "par": 72, "differential": 180}])
	_check(p.career("Old").rounds == 1 and p.career("Old").strokes == 90, "career from old rounds")
	p.remove("Old")
	p.save()
	var again := PlayerProfiles.load_saved()
	_check(again.names() == _strs(["Ann"]) and again.index_of("Ann") == 170, "profiles saved: %d" % again.index_of("Ann"))
	_check(again.career("Ann").putts == 16, "career saved")
	again.remove("Ann")
	_check(not again.has_player("Ann"), "profile removed")
	again.save()


func _test_handicap_scoring() -> void:
	var s := RoundSetup.new()
	s.names = _strs(["Ann", "Bob"])
	s.teams = _ints([0, 1])
	s.mode = GameModes.Mode.MATCH
	s.handicaps = true
	s.indexes = _ints([20, 80])  # 2.0 and 8.0: 1 and 4 strokes over nine at 100%
	var pars := _ints([4, 3, 5, 4, 4, 3, 5, 4, 4])
	var numbers := _ints([1, 2, 3, 4, 5, 6, 7, 8, 9])
	var si := _ints([5, 15, 3, 7, 1, 17, 11, 9, 13])
	var r := RoundScoring.new(s, pars, numbers, si)
	_check(r.playing == _ints([0, 3]), "match plays off the low: %s" % [r.playing])
	# Bob gets his strokes on the three hardest holes: 5, 3 and 1.
	_check(r.received[1] == _ints([1, 0, 1, 0, 1, 0, 0, 0, 0]), "strokes on the hardest: %s" % [r.received[1]])
	_check(r.label(1) == "Bob (3)", "label: %s" % r.label(1))
	r.cards[0].record(0, 4)
	r.cards[1].record(0, 5)
	_check(r.hole_result(0) == "Hole halved.", "a stroke halves the hole: %s" % r.hole_result(0))
	r.cards[0].record(1, 3)
	r.cards[1].record(1, 4)
	_check(r.hole_result(1) == "Ann wins the hole.", "no stroke on hole 2")
	_check(r.status_text() == "Match: Ann 1 up", "net match: %s" % r.status_text())

	s.mode = GameModes.Mode.STROKE
	r = RoundScoring.new(s, pars, numbers, si)
	_check(r.playing == _ints([1, 4]), "stroke play at 95%%: %s" % [r.playing])
	for h in 9:
		r.cards[0].record(h, pars[h] + 1)
		r.cards[1].record(h, pars[h] + 1)
	_check(r.scored_card(1).total_strokes() == 41 and r.scored_card(0).total_strokes() == 44, "net totals")
	_check(r.standings()[0] == ["Bob", "net 41 (+5)"], "net standings: %s" % [r.standings()])

	s.mode = GameModes.Mode.STABLEFORD
	r = RoundScoring.new(s, pars, numbers, si)
	r.cards[1].record(4, 5)  # bogey with a stroke on the hardest hole: net par
	_check(GameModes.stableford_total(r.scored_card(1)) == 2, "net Stableford")
	s.handicaps = false
	r = RoundScoring.new(s, pars, numbers, si)
	_check(r.playing == _ints([0, 0]) and r.label(0) == "Ann", "handicaps off")

	# Computer golfers play off their level's index.
	_check(RoundSetup.computer_index(OpponentSkill.Level.BEGINNER) == 240 and RoundSetup.computer_index(OpponentSkill.Level.TOUR) == -40, "computer indexes")
	s.handicaps = true
	s.mode = GameModes.Mode.STABLEFORD
	s.computer = _ints([RoundSetup.HUMAN, OpponentSkill.Level.BEGINNER])
	_check(s.index_of(1) == 240 and s.index_of(0) == 20, "the computer seat's index")
	r = RoundScoring.new(s, pars, numbers, si)
	_check(r.playing == _ints([1, 11]), "a weekend golfer gets strokes: %s" % [r.playing])


func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for v: int in values:
		out.append(v)
	return out


func _strs(values: Array) -> Array[String]:
	var out: Array[String] = []
	for v: String in values:
		out.append(v)
	return out


func _test_round_setup() -> void:
	var s := RoundSetup.new()
	_check(s.problem().is_empty(), "one player stroke play is fine")
	s.mode = GameModes.Mode.MATCH
	_check(not s.problem().is_empty(), "match play needs two")
	s.names = _strs(["A", "B"])
	s.teams = _ints([0, 1])
	_check(s.problem().is_empty(), "two-player match")
	s.mode = GameModes.Mode.BEST_BALL
	_check(not s.problem().is_empty(), "best ball needs three or four")
	s.names = _strs(["A", "B", "C"])
	s.teams = _ints([0, 0, 0])
	_check(not s.problem().is_empty(), "best ball needs both teams")
	s.teams = _ints([0, 1, 0])
	_check(s.problem().is_empty(), "best ball, three players")
	s.mode = GameModes.Mode.SCRAMBLE
	_check(s.problem().is_empty(), "scramble, three players")
	s.names = _strs(["A", "B", "a "])
	_check(not s.problem().is_empty(), "two players can't share a name")
	s.names = _strs(["A", "B", "C"])
	s.teams = _ints([1, 1, 1])
	_check(not s.problem().is_empty(), "scramble needs both teams")
	s.teams = _ints([0, 1, 0])
	s.mode = GameModes.Mode.BEST_BALL
	_check(s.hole_indices(18).size() == 18, "all 18")
	s.holes = RoundSetup.Holes.BACK_NINE
	_check(s.hole_indices(18) == _ints([9, 10, 11, 12, 13, 14, 15, 16, 17]), "back nine")
	_check(s.hole_indices(9).size() == 9, "a nine-hole course has no back nine")
	s.holes = RoundSetup.Holes.FRONT_NINE
	_check(s.hole_indices(18).back() == 8, "front nine")
	_check(s.tee_index(5) == 0, "back tees")
	s.tees = RoundSetup.Tees.FORWARD
	_check(s.tee_index(5) == 4 and s.tee_index(1) == 0, "forward tees")
	s.tees = RoundSetup.Tees.MIDDLE
	_check(s.tee_index(3) == 1, "middle tees")

	var path := "user://test_round.cfg"
	s.save(path)
	var loaded := RoundSetup.load_saved(path)
	_check(loaded.mode == GameModes.Mode.BEST_BALL and loaded.holes == RoundSetup.Holes.FRONT_NINE and loaded.tees == RoundSetup.Tees.MIDDLE, "setup saved")
	_check(loaded.names == s.names and loaded.teams == s.teams, "players saved")
	_check(loaded.computer == _ints([RoundSetup.HUMAN, RoundSetup.HUMAN, RoundSetup.HUMAN]), "everyone human by default")
	s.computer = _ints([RoundSetup.HUMAN, OpponentSkill.Level.TOUR, OpponentSkill.Level.BEGINNER])
	s.save(path)
	loaded = RoundSetup.load_saved(path)
	_check(loaded.computer == s.computer, "computer players saved: %s" % [loaded.computer])
	_check(not loaded.is_computer(0) and loaded.computer_level(1) == OpponentSkill.Level.TOUR and not loaded.all_computer(), "who is a computer")
	_check(not loaded.handicaps, "handicaps off by default")
	s.handicaps = true
	s.save(path)
	_check(RoundSetup.load_saved(path).handicaps, "handicaps saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_round_scoring() -> void:
	var s := RoundSetup.new()
	s.names = _strs(["Ann", "Bob"])
	s.teams = _ints([0, 1])
	s.mode = GameModes.Mode.MATCH
	var pars := _ints([4, 3, 5])
	var numbers := _ints([10, 11, 12])
	var r := RoundScoring.new(s, pars, numbers)
	_check(r.status_text() == "Match: All square", "match starts square: %s" % r.status_text())
	r.cards[0].record(0, 4)
	r.cards[1].record(0, 5)
	_check(r.hole_result(0) == "Ann wins the hole.", "hole result: %s" % r.hole_result(0))
	r.cards[0].record(1, 3)
	r.cards[1].record(1, 4)
	_check(r.decided(), "2 up with 1 to play is decided")
	_check(r.winner_text() == "Ann wins 2 & 1", "winner: %s" % r.winner_text())

	s.mode = GameModes.Mode.SKINS
	r = RoundScoring.new(s, pars, numbers)
	r.cards[0].record(0, 4)
	r.cards[1].record(0, 4)
	_check(r.hole_result(0) == "Tied: the skin carries over.", "skin tie: %s" % r.hole_result(0))
	r.cards[0].record(1, 4)
	r.cards[1].record(1, 3)
	_check(r.hole_result(1) == "Bob wins 2 skins.", "carried skins: %s" % r.hole_result(1))
	_check(r.status_text() == "Skins: Ann 0, Bob 2", "skins status: %s" % r.status_text())

	s.mode = GameModes.Mode.BEST_BALL
	s.names = _strs(["Ann", "Bob", "Cy"])
	s.teams = _ints([0, 1, 0])
	r = RoundScoring.new(s, pars, numbers)
	r.cards[0].record(0, 5)
	r.cards[1].record(0, 4)
	r.cards[2].record(0, 3)
	_check(r.team_name(0) == "Ann & Cy", "team name")
	_check(r.team_scores(0)[0] == 3, "team best ball")
	_check(r.hole_result(0) == "Ann & Cy win the hole, 3 to 4.", "best ball hole: %s" % r.hole_result(0))
	_check(r.winner_text() == "Ann & Cy win: 3 (-1)", "best ball winner: %s" % r.winner_text())

	# Shared-ball teams get one handicap from their players' indexes.
	var team_setup := RoundSetup.new()
	team_setup.names = _strs(["Ann", "Bob", "Cy", "Di"])
	team_setup.teams = _ints([0, 1, 0, 1])
	team_setup.computer = _ints([RoundSetup.HUMAN, RoundSetup.HUMAN, RoundSetup.HUMAN, RoundSetup.HUMAN])
	team_setup.indexes = _ints([300, 0, 100, 0])
	team_setup.handicaps = true
	var pars18: Array[int] = []
	for i in 18:
		pars18.append(4)
	team_setup.mode = GameModes.Mode.SCRAMBLE
	var ts := RoundScoring.new(team_setup, pars18, pars18)
	_check(ts.playing == _ints([8, 0, 8, 0]), "scramble team handicap 35/15%%: %s" % [ts.playing])
	team_setup.mode = GameModes.Mode.ALTERNATE_SHOT
	ts = RoundScoring.new(team_setup, pars18, pars18)
	_check(ts.playing == _ints([20, 0, 20, 0]), "alternate shot team handicap 50%%: %s" % [ts.playing])

	s.mode = GameModes.Mode.STABLEFORD
	r = RoundScoring.new(s, pars, numbers)
	r.cards[0].record(0, 3)
	r.cards[1].record(0, 4)
	r.cards[2].record(0, 6)
	_check(r.standings()[0] == ["Ann", "3 points"], "stableford leader: %s" % [r.standings()])
	_check(r.winner_text() == "Ann wins: 3 points", "stableford winner: %s" % r.winner_text())
	r.cards[1].record(0, 3)
	r.cards[2].record(0, 3)
	var tie := r.winner_text()
	_check(tie.begins_with("Tied at the top: ") and tie.ends_with(", 3 points") and "Ann" in tie and "Bob" in tie and "Cy" in tie and " and " in tie, "three-way tie: %s" % tie)


## The hole of test_drop_rules in libs/olcore/tests/test_main.cpp: a stream
## from z = 40 to 60, out of bounds beyond x = 30, a bunker round (10, 80),
## a cart path from x = -12 to -10 and the green within 5 m of the pin.
class RulesTerrain extends CourseTerrain:
	func height_at(x: float, z: float) -> float:
		return 0.01 * x + 0.02 * z

	func surface_at(x: float, z: float) -> int:
		if x > 30:
			return Surface.Type.OUT_OF_BOUNDS
		if Vector2(x, z - 100).length() < 5:
			return Surface.Type.GREEN
		if z >= 40 and z <= 60:
			return Surface.Type.WATER
		if Vector2(x - 10, z - 80).length() < 4:
			return Surface.Type.SAND
		return Surface.Type.FAIRWAY

	func free_drop_at(x: float, _z: float) -> bool:
		return x > -12 and x < -10


## RulesTerrain with a course hazard round (-5, 70) and the hole's bounds at
## x = 20, as in test_drop_rules_hazards_and_bounds (libs/olcore).
class BoundedRulesTerrain extends RulesTerrain:
	func hazard_at(x: float, z: float) -> bool:
		return Vector2(x + 5, z - 70).length() < 3

	func in_bounds(x: float, _z: float) -> bool:
		return x < 20


func _test_drop_rules_hazards_and_bounds() -> void:
	var t := BoundedRulesTerrain.new()
	var pin := Vector3(0, 2, 100)
	var side := DropRules.zone(DropRules.Option.LATERAL, Vector3(-5, 0, 75), Vector3.ZERO, pin, false, t)
	_check(DropRules.check(side, Vector3(-5, 0, 71), pin, t) == DropRules.Check.HAZARD, "no drop in a course hazard")
	_check(DropRules.check(side, Vector3(25, 0, 80), pin, t) == DropRules.Check.OUT_OF_BOUNDS, "no drop outside the hole")
	var free := DropRules.zone(DropRules.Option.FREE_DROP, Vector3(-11, 0, 70), Vector3.ZERO, pin, false, t)
	_check(free.found, "free relief beside the hazard")
	_check_spot(free.spot, -12.0840, 69.3776, "free relief beside the hazard")


## A hole whose ground ends at z = limit: judged where the ball stops.
class BoundedTerrain extends FlatTerrain:
	var limit := 0.0

	func in_bounds(_x: float, z: float) -> bool:
		return z < limit


func _test_rest_out_of_bounds() -> void:
	var start := Swing.launch_from_swing(_club("7i"), 1.0, 0.0, 0.0, Surface.Type.FAIRWAY)
	var t := BoundedTerrain.new(Surface.Type.FAIRWAY)
	t.limit = 1e9
	var free := BallPhysics.simulate_shot(start, t)
	_check(free.outcome == ShotResult.Outcome.REST, "rests in bounds")
	t.limit = free.rest.z - 1.0
	_check(BallPhysics.simulate_shot(start, t).outcome == ShotResult.Outcome.OUT_OF_BOUNDS, "rests out of bounds")
	t.limit = free.rest.z + 1.0
	_check(BallPhysics.simulate_shot(start, t).outcome == ShotResult.Outcome.REST, "rests just in bounds")


func _check_spot(actual: Vector3, x: float, z: float, what: String) -> void:
	_check_near(actual.x, x, 2e-3, what + " x")
	_check_near(actual.z, z, 2e-3, what + " z")


## Expected spots printed by test_drop_rules.
func _test_drop_rules_match_olcore() -> void:
	var t := RulesTerrain.new()
	var pin := Vector3(0, 2, 100)
	var tee := Vector3.ZERO
	_check(DropRules.penalty(DropRules.Reason.WATER) == 1 and DropRules.penalty(DropRules.Reason.FREE_RELIEF) == 0, "penalties")
	_check(DropRules.options(DropRules.Reason.WATER, false).size() == 2, "water options")
	_check(DropRules.options(DropRules.Reason.WATER, true).size() == 3, "lateral water options")
	var path := PackedVector3Array()
	for i in 14:
		path.append(Vector3(6.0 * i / 13, 3.0, 52.0 * i / 13))
	var entry := DropRules.water_entry(path, t)
	_check_spot(entry, 4.6154, 40.0, "entry")
	_check_near(entry.y, 0.8462, 2e-3, "entry height")
	var back := DropRules.zone(DropRules.Option.BACK_ON_LINE, entry, tee, pin, false, t)
	var side := DropRules.zone(DropRules.Option.LATERAL, entry, tee, pin, false, t)
	var again := DropRules.zone(DropRules.Option.STROKE_AND_DISTANCE, entry, tee, pin, false, t)
	_check(back.found and side.found and again.found, "water drops found")
	_check_spot(back.spot, 4.7113, 38.7537, "back on the line")
	_check_near(back.spot.y, 0.8222, 2e-3, "back on the line height")
	_check_spot(side.spot, 4.6346, 39.7507, "lateral")
	var zones: Array[DropRules.Zone] = [back, side, again]
	_check(DropRules.best(zones, pin) == 1, "lateral is nearer the pin")
	_check(DropRules.check(back, Vector3(entry.x, 0, 45), pin, t) == DropRules.Check.HAZARD, "in the water")
	_check(DropRules.check(side, Vector3(entry.x - 0.5, 0, entry.z - 0.01), pin, t) == DropRules.Check.NEARER_PIN, "nearer the pin")
	var sand := Vector3(10, 0, 80)
	var sand_back := DropRules.zone(DropRules.Option.BACK_ON_LINE, sand, tee, pin, true, t)
	var sand_side := DropRules.zone(DropRules.Option.LATERAL, sand, tee, pin, true, t)
	_check_spot(sand_back.spot, 10.4472, 79.1056, "sand back on the line")
	_check_spot(sand_side.spot, 10.1118, 79.7764, "sand lateral")
	_check(DropRules.check(sand_back, Vector3(10, 0, 75.5), pin, t) == DropRules.Check.NOT_SAND, "stays in the bunker")
	var free := DropRules.zone(DropRules.Option.FREE_DROP, Vector3(-11, 0, 20), tee, pin, false, t)
	_check(free.found, "free relief found")
	_check_spot(free.reference, -12.0581, 19.3344, "nearest point of relief")
	_check(DropRules.check(free, Vector3(-11, 0, 20), pin, t) == DropRules.Check.STILL_ON_PATH, "still on the path")


## Same seeds and inputs as test_opponent_rng_and_swings and
## test_expected_strokes in libs/olcore/tests/test_main.cpp.
func _test_opponent_skill_matches_olcore() -> void:
	var r := OpponentSkill.Rng.new(2003)
	_check(r.next() == 532058734 and r.next() == 1922934515, "xorshift32 sequence")
	var q := OpponentSkill.Rng.new(7)
	_check_near(q.uniform(), 0.000440598, 1e-9, "uniform")
	_check_near(q.normal(), 0.396480682, 1e-8, "normal")
	var expected := [
		[0.897376, 0.170120, 7.908560, 0.387823, -5.478538],
		[0.863215, 0.203403, 10.076681, 0.332468, -6.730970],
		[0.839794, -0.049017, 9.693239, 0.380458, -6.656684],
		[0.890076, -0.374709, 10.435747, 0.406676, -5.654990],
	]
	var s := OpponentSkill.Rng.new(42)
	for level in OpponentSkill.LEVEL_NAMES.size():
		var skill := OpponentSkill.new(level)
		var full := skill.execute(0.9, 0.0, 10.0, false, s)
		var putt := skill.execute(0.4, 0.0, -5.0, true, s)
		var e: Array = expected[level]
		_check_near(full[0], e[0], 2e-6, "%s full power" % skill.level_name())
		_check_near(full[1], e[1], 2e-6, "%s full accuracy" % skill.level_name())
		_check_near(full[2], e[2], 2e-6, "%s full aim" % skill.level_name())
		_check_near(putt[0], e[3], 2e-6, "%s putt pace" % skill.level_name())
		_check_near(putt[2], e[4], 2e-6, "%s putt aim" % skill.level_name())
	_check_near(OpponentSkill.expected_strokes(0.5, Surface.Type.GREEN), 1.008202, 2e-6, "0.5 m putt")
	_check_near(OpponentSkill.expected_strokes(6.0, Surface.Type.FRINGE), 1.964331, 2e-6, "6 m from the fringe")
	_check_near(OpponentSkill.expected_strokes(30.0, Surface.Type.SAND), 2.878084, 2e-6, "30 m bunker shot")
	_check_near(OpponentSkill.expected_strokes(140.0, Surface.Type.GREEN), 3.877270, 2e-6, "140 m on a green")
	_check_near(OpponentSkill.expected_strokes(600.0, Surface.Type.SAND), 5.552756, 2e-6, "600 m from sand")


## The planner on flat ground: it holes a straight putt and puts an approach
## close, without any of its level's mistakes.
func _test_computer_golfer_plans() -> void:
	var model := StandardShotModel.new()
	var clubs := Club.standard_set()
	var hole := HoleData.new()
	hole.terrain = FlatTerrain.new(Surface.Type.GREEN)
	hole.pin = Vector3(0.0, 0.0, 4.0)
	var cpu := ComputerGolfer.new(OpponentSkill.Level.TOUR, 5)
	cpu.plan(model, clubs, hole, Vector3.ZERO, Surface.Type.GREEN, Vector3.ZERO)
	cpu.finish()
	_check(cpu.is_putt(), "putts on the green")
	_check(cpu.expected == 0.0, "plans to hole a flat 4 m putt (expects %f)" % cpu.expected)

	hole.terrain = FlatTerrain.new(Surface.Type.FAIRWAY)
	hole.pin = Vector3(10.0, 0.0, 140.0)
	cpu.plan(model, clubs, hole, Vector3.ZERO, Surface.Type.FAIRWAY, Vector3(3.0, 0.0, 0.0))
	cpu.finish()
	var start := model.launch(clubs[cpu.club_index], cpu.power, 0.0, cpu.aim_deg, Surface.Type.FAIRWAY, Vector3.ZERO)
	var r := model.simulate(start, hole.terrain, hole.pin, Vector3(3.0, 0.0, 0.0))
	var miss := Vector2(r.rest.x - hole.pin.x, r.rest.z - hole.pin.z).length()
	print("  approach: %s at %.2f power, aim %.2f deg, %.1f m from the pin" % [clubs[cpu.club_index].short_name, cpu.power, cpu.aim_deg, miss])
	_check(not clubs[cpu.club_index].is_putter, "a full club from the fairway")
	_check(miss < 6.0, "approach plan ends within 6 m in a crosswind (%.1f m)" % miss)

	var weak := ComputerGolfer.new(OpponentSkill.Level.BEGINNER, 5)
	weak.plan(model, clubs, hole, Vector3.ZERO, Surface.Type.FAIRWAY, Vector3.ZERO)
	weak.finish()
	_check(weak.power <= weak.skill.strength + 1e-6, "never swings harder than its strength")


func _test_caddie() -> void:
	# Rules of thumb: a yard per yard of rise, 1% per mph into the wind, half that helping.
	_check_near(CaddieAdvice.plays_like_m(100.0, 0.0, 0.0), 100.0, 1e-6, "flat and calm plays its length")
	_check_near(CaddieAdvice.plays_like_m(100.0, 10.0, 0.0), 110.0, 1e-6, "10 m uphill")
	_check_near(CaddieAdvice.plays_like_m(100.0, 0.0, -10.0 * CaddieAdvice.MPS_PER_MPH), 110.0, 1e-4, "10 mph into the wind")
	_check_near(CaddieAdvice.plays_like_m(100.0, 0.0, 10.0 * CaddieAdvice.MPS_PER_MPH), 95.0, 1e-4, "10 mph helping")
	_check(CaddieAdvice.detail_for_skill(0) == CaddieAdvice.Detail.FULL, "easiest skill hears everything")
	_check(CaddieAdvice.detail_for_skill(3) == CaddieAdvice.Detail.SPARSE, "hardest skill hears the numbers only")

	var info := {"to_pin_m": 140.0, "rise_m": 6.0, "wind_along_mps": 0.0, "wind_cross_mps": 3.0,
		"club": "7 Iron", "power": 1.0, "aim_off_m": 5.0, "in_range": true, "lie": Surface.Type.FAIRWAY}
	var full := CaddieAdvice.shot_text(CaddieAdvice.Detail.FULL, info)
	var sparse := CaddieAdvice.shot_text(CaddieAdvice.Detail.SPARSE, info)
	print("  full: " + full)
	print("  sparse: " + sparse)
	_check(full.begins_with("153 to the pin, playing 160 uphill."), "yardage and plays-like (%s)" % full)
	_check(full.contains("Start it 5 yards left for the wind"), "full read gives the line (%s)" % full)
	_check(sparse.contains("7 Iron") and not sparse.contains("left"), "sparse read gives the club, not the line (%s)" % sparse)
	_check(CaddieAdvice.shot_text(CaddieAdvice.Detail.STANDARD, info).contains("Favour the left side"), "standard read names the side")
	var putt := CaddieAdvice.putt_text(CaddieAdvice.Detail.FULL, 4.0, 0.1, 0.15)
	print("  putt: " + putt)
	_check(putt.contains("13 feet") and putt.contains("left to right") and putt.contains("6\" left"), "full putt read (%s)" % putt)
	var hard_putt := CaddieAdvice.putt_text(CaddieAdvice.Detail.SPARSE, 4.0, 0.1, 0.15)
	_check(hard_putt.contains("left to right") and not hard_putt.contains("\""), "sparse putt read has no inches (%s)" % hard_putt)
	_check(CaddieAdvice.putt_text(CaddieAdvice.Detail.FULL, 0.5, 0.0, 0.0).contains("tap-in"), "tap-in")

	# A real read, planned through the physics.
	var model := StandardShotModel.new()
	var clubs := Club.standard_set()
	var hole := HoleData.new()
	hole.terrain = FlatTerrain.new(Surface.Type.FAIRWAY)
	hole.pin = Vector3(10.0, 0.0, 140.0)
	var advice := CaddieAdvice.new()
	advice.start(model, clubs, hole, Vector3.ZERO, Surface.Type.FAIRWAY, Vector3(3.0, 0.0, 0.0), 0)
	advice.finish()
	print("  approach: " + advice.text)
	_check(advice.is_ready() and not clubs[advice.club_index].is_putter, "a full club for an approach")
	_check(advice.text.to_lower().contains(clubs[advice.club_index].full_name.to_lower()), "names the club it planned")
	_check(clubs[advice.club_index].short_name in ["8i", "9i"], "a full 8 or 9 iron for 140 m, as a caddie would (%s)" % clubs[advice.club_index].short_name)
	_check(CaddieAdvice.club_for(clubs, 150.0, Surface.Type.FAIRWAY) == 8, "8 iron reaches 150 m")
	hole.terrain = FlatTerrain.new(Surface.Type.GREEN)
	hole.pin = Vector3(0.0, 0.0, 6.0)
	advice.start(model, clubs, hole, Vector3.ZERO, Surface.Type.GREEN, Vector3.ZERO, 3)
	advice.finish()
	print("  green: " + advice.text)
	_check(advice.text.begins_with("20 feet"), "putt read gives the length (%s)" % advice.text)

	_check(GolfBag.shared_mesh().get_surface_count() == 3, "bag is one mesh of three materials")
	var figure := Caddie.make_figure()
	_check(figure != null, "caddie figure from the free golfer")
	if figure != null:
		_check(not figure.find_children("*", "Skeleton3D", true, false).is_empty(), "caddie figure has a skeleton")
		figure.free()
	var path := "user://test_caddie_settings.cfg"
	var gs := GraphicsSettings.new()
	_check(not gs.caddie, "caddie is off by default")
	gs.caddie = true
	gs.save(path)
	_check(GraphicsSettings.load_saved(path).caddie, "caddie setting is saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_buggy_drive() -> void:
	# The handling, against what an electric cart does: speeds and grip by
	# ground, hills, braking, reverse, the park brake and the course rules.
	var dt := 1.0 / 30.0
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY)
	var d := BuggyDrive.new()
	d.place(Vector3.ZERO, 0.0, fairway)
	for i in 300:
		d.step(dt, 1.0, 0.0, fairway)
	print("  fairway top speed %.2f m/s" % d.speed)
	_check(d.speed > 6.0 and d.speed <= BuggyDrive.GOVERNED, "governed at about 15 mph on grass (%.2f)" % d.speed)
	_check(d.position.z > 40.0 and absf(d.position.x) < 1e-3, "drives straight down +z (%s)" % d.position)
	var rough := FlatTerrain.new(Surface.Type.ROUGH)
	var r := BuggyDrive.new()
	r.place(Vector3.ZERO, 0.0, rough)
	for i in 300:
		r.step(dt, 1.0, 0.0, rough)
	_check(r.speed < d.speed - 1.0, "slower in the rough (%.2f)" % r.speed)
	for i in 60:
		d.step(dt, 1.0, 1.0, fairway)
	print("  full lock at speed: %.0f deg, sliding %.2f m/s, %.2f g" % [d.heading_deg, d.lateral, d.accel_lat / BuggyDrive.GRAVITY])
	_check(d.heading_deg > 30.0, "steering left turns towards +x (%.1f deg)" % d.heading_deg)
	_check(absf(d.accel_lat) <= 0.7 * BuggyDrive.GRAVITY, "cornering limited by the tyres (%.2f g)" % (d.accel_lat / BuggyDrive.GRAVITY))
	d.place(Vector3.ZERO, 0.0, fairway)
	for i in 300:
		d.step(dt, 1.0, 0.0, fairway)
	var from := d.position.z
	var t := 0
	while d.speed > 0.0 and t < 300:
		d.step(dt, -1.0, 0.0, fairway)
		t += 1
	print("  stops from top speed in %.1f s, %.1f m" % [t * dt, d.position.z - from])
	_check(t * dt < 2.5 and d.position.z - from < 8.0, "brakes hard")
	for i in 150:
		d.step(dt, -1.0, 0.0, fairway)
	_check(d.speed < 0.0 and d.speed >= -BuggyDrive.GOVERNED_REVERSE - 0.1, "backs up slowly (%.2f)" % d.speed)
	for i in 150:
		d.step(dt, 0.0, 0.0, fairway)
	_check(d.speed == 0.0, "the park brake holds once stopped")
	var hill := TiltedTerrain.new()
	var up := BuggyDrive.new()
	up.place(Vector3.ZERO, 0.0, hill)
	for i in 450:
		up.step(dt, 1.0, 0.0, hill)
	_check(up.speed < BuggyDrive.TOP_GRASS - 1.5, "slower up a 15%% hill (%.2f)" % up.speed)
	var down := BuggyDrive.new()
	down.place(Vector3.ZERO, 180.0, hill)
	for i in 450:
		down.step(dt, 1.0, 0.0, hill)
	_check(absf(down.speed - BuggyDrive.GOVERNED) < 0.6, "the governor holds it downhill (%.2f)" % down.speed)
	var parked := BuggyDrive.new()
	parked.place(Vector3.ZERO, 0.0, hill)
	for i in 90:
		parked.step(dt, 0.0, 0.0, hill)
	_check(parked.position.distance_to(Vector3.ZERO) < 1e-3, "parked on a hill, it stays put")
	var green := FlatTerrain.new(Surface.Type.GREEN)
	d.place(Vector3.ZERO, 0.0, green)
	for i in 30:
		d.step(dt, 1.0, 0.0, green)
	_check(d.blocked and d.position == Vector3.ZERO, "stays off the green")
	_check(BuggyDrive.keeps_off(Surface.Type.SAND) and BuggyDrive.keeps_off(Surface.Type.WATER), "and bunkers and water")
	var spot := BuggyDrive.parking_spot(fairway, Vector3.ZERO, Vector3(0.0, 0.0, 100.0))
	_check(spot.z < 0.0 and spot.length() > 5.0, "parks back from the ball, off the line (%s)" % spot)
	var b := GolfBuggy.new()
	_check(b.get_child_count() == 5, "body (with the bag) and four wheels")
	b.park(Vector3(5.0, 0.0, 5.0), 90.0, fairway)
	for i in 30:
		b.step(dt, 1.0, 0.0, fairway)
	_check(b.position.x > 5.0, "the model moves with the drive (%s)" % b.position)
	var view: Array = b.chase(0.1, fairway)
	_check((view[0] as Vector3).x < b.position.x, "the chase camera sits behind")
	b.free()


## Everything at its real size: the cart against a Club Car Precedent's
## published dimensions, the golfer and caddie against an average man, the
## bag, the ball and the hole against the Rules of Golf.
func _test_real_scale() -> void:
	var cart := (load(GolfBuggy.MODEL_PATH) as PackedScene).instantiate() as Node3D
	var body := cart.find_child("Body", true, false) as MeshInstance3D
	var box := body.get_aabb()
	var wheel := cart.find_child("Wheel_RR", true, false) as MeshInstance3D
	var outer := wheel.position.x + wheel.get_aabb().end.x
	print("  cart: %.2f m long, %.2f m wide, %.2f m high, wheels %.3f m radius" % [box.size.z, maxf(box.size.x, 2.0 * outer), box.end.y, wheel.get_aabb().end.y])
	_check_near(box.size.z, 2.39, 0.03, "cart length (Precedent 2.39 m)")
	_check_near(maxf(box.size.x, 2.0 * outer), 1.19, 0.03, "cart width (1.19 m)")
	_check_near(box.end.y, 1.76, 0.03, "cart height to the canopy (1.76 m)")
	_check_near(wheel.get_aabb().end.y, 0.2286, 0.003, "18 in tyres")
	_check_near(absf((cart.find_child("Wheel_FR", true, false) as Node3D).position.z - wheel.position.z), BuggyDrive.WHEELBASE, 0.01, "wheelbase matches the physics")
	cart.free()
	var golfer := (load(FreeGolfer.SCENE_PATH) as PackedScene).instantiate() as Node3D
	var top := -INF
	var bottom := INF
	for n in golfer.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.name.begins_with("Driver") or m.name.begins_with("Putter"):
			continue
		top = maxf(top, m.get_aabb().end.y)
		bottom = minf(bottom, m.get_aabb().position.y)
	print("  golfer and caddie: %.2f m tall" % (top - bottom))
	_check(top - bottom > 1.7 and top - bottom < 1.85, "golfer about 1.75 m tall (%.2f)" % (top - bottom))
	golfer.free()
	var bag := GolfBag.shared_mesh().get_aabb()
	_check(bag.size.y > 0.95 and bag.size.y < 1.15, "stand bag with clubs about a metre high (%.2f)" % bag.size.y)
	_check_near(BallPhysics.RADIUS * 2.0, 0.04267, 0.0001, "ball 42.67 mm across")
	_check_near(BallPhysics.CUP_RADIUS * 2.0, 0.108, 0.001, "hole 108 mm across")


func _test_placeholder_course() -> void:
	var course := AssetProviders.load_course("")
	_check(course.holes.size() == 9, "nine holes")
	var par := 0
	for h in course.holes:
		par += h.par
		_check(h.terrain.surface_at(h.tee.x, h.tee.z) == Surface.Type.TEE, "hole %d tee is on the tee box" % h.number)
		_check(h.terrain.surface_at(h.pin.x, h.pin.z) == Surface.Type.GREEN, "hole %d pin is on the green" % h.number)
		var tee_ground := h.terrain.height_at(h.tee.x, h.tee.z)
		_check_near(h.tee.y, tee_ground, 1e-3, "hole %d tee height" % h.number)
		_check(h.length_m() > 100.0 and h.length_m() < 560.0, "hole %d length" % h.number)
	_check(par == 36, "par 36")


func _test_hd_pack() -> void:
	_check(HdPack.key("terrain/cabo", "Sand 1A.tga") == "terrain/cabo__sand 1a", "course texture key")
	_check(HdPack.key("billboards", "Tall Trees100A.btc") == "billboards/tall trees100a", "billboard key")
	_check(HdPack.key("models/cabo", "Cabo 3D005_20") == "models/cabo__cabo 3d005_20", "model key")
	_check(HdPack.key_for_file("Links 2003 HD/terrain/cabo__Sand 1A_upscayl_4x_remacri.png") == "terrain/cabo__sand 1a", "upscayl file name")
	_check(HdPack.key_for_file("pack/golfers/eric/L_M03_FACE_01.png") == "golfers/eric__l_m03_face_01", "nested folders")
	_check(HdPack.key_for_file("pack/hdpack.json").is_empty(), "not a texture")
	# A 32 x 32 ground texture exported with its 16-pixel border, upscaled 4x.
	var up := Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
	_check(HdPack.trim_border(up, Vector2i(32, 32), 16, true).get_size() == Vector2i(128, 128), "border trimmed")
	var plain := Image.create_empty(1024, 1024, false, Image.FORMAT_RGB8)
	_check(HdPack.trim_border(plain, Vector2i(256, 256), 16, true).get_size() == Vector2i(1024, 1024), "no border kept")
	var sky := Image.create_empty(2 * (4800 + 128) / 8, 2 * 320 / 8, false, Image.FORMAT_RGB8)
	_check(HdPack.trim_border(sky, Vector2i(600, 40), 8, false).get_size() == Vector2i(1200, 80), "sky border trimmed")
	# A pack folder: the upscaled file is used, other textures stay as they were.
	var dir := "user://test_hd_pack/terrain"
	DirAccess.make_dir_recursive_absolute(dir)
	var big := Image.create_empty(80, 80, false, Image.FORMAT_RGB8)
	big.fill(Color.RED)
	big.save_png(dir.path_join("standard__Rough01_upscayl_2x_remacri.png"))
	HdPack.override_path = ProjectSettings.globalize_path("user://test_hd_pack")
	var original := Image.create_empty(8, 8, false, Image.FORMAT_RGB8)
	var got := HdPack.replace("terrain/standard", "Rough01.tga", original)
	_check(got.get_size() == Vector2i(16, 16), "upscaled texture loaded and trimmed: %s" % got.get_size())
	_check(HdPack.replace("terrain/standard", "Fairway01.tga", original) == original, "missing texture keeps the original")
	_check(HdPack.is_active(), "pack is active")
	HdPack.override_path = ""
	_check(not HdPack.is_active() or not HdPack.saved_enabled(), "pack off again")


func _test_graphics_settings() -> void:
	var path := "user://test_settings.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("game", "folder", "/somewhere")
	cfg.save(path)
	var s := GraphicsSettings.new()
	s.quality = GraphicsSettings.Quality.ULTRA
	s.msaa = 4
	s.render_scale = 0.75
	s.fov = 70.0
	s.wind = Wind.Level.STRONG
	s.presentation = GraphicsSettings.Presentation.CLASSIC
	s.skill = 1
	s.green_firmness = 2
	s.green_speed = 0
	s.swing_method = 0
	s.save(path)
	var loaded := GraphicsSettings.load_saved(path)
	_check(loaded.quality == GraphicsSettings.Quality.ULTRA, "quality saved")
	_check(loaded.msaa == 4, "msaa saved")
	_check_near(loaded.render_scale, 0.75, 1e-6, "render scale saved")
	_check_near(loaded.fov, 70.0, 1e-6, "fov saved")
	_check(loaded.wind == Wind.Level.STRONG, "wind saved")
	_check(loaded.presentation == GraphicsSettings.Presentation.CLASSIC, "presentation saved")
	_check(loaded.skill == 1, "swing skill saved")
	_check(loaded.green_firmness == 2 and loaded.green_speed == 0, "green options saved")
	_check(loaded.swing_method == 0 and GraphicsSettings.new().swing_method == 1, "swing method saved, mouse by default")
	_check(GraphicsSettings.new().broadcast(), "broadcast presentation by default")
	cfg = ConfigFile.new()
	cfg.load(path)
	_check(cfg.get_value("game", "folder", "") == "/somewhere", "other sections kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(Materials.terrain().shader != null, "terrain shader loads")
	_check(Materials.water().shader != null, "water shader loads")
	_check(Materials.water_surface().get_shader_parameter("disc") == false, "course water isn't cut to a disc")

	# Looks: a preset sets everything, a saved look comes back, and settings
	# saved before looks existed get one picked for the device.
	s = GraphicsSettings.new()
	s.apply_look(GraphicsSettings.Look.PHOTOREAL)
	_check(s.lighting == GraphicsSettings.Lighting.PHOTOREAL and s.grass > 0 and s.foliage_wind and s.cloud_shadows, "photoreal look")
	s.apply_look(GraphicsSettings.Look.CLASSIC)
	_check(s.lighting == GraphicsSettings.Lighting.CLASSIC and s.grass == 0 and s.sharpen == 0 and not s.dof, "classic look is plain")
	_check(s.trees == 0, "classic look keeps the course's own trees")
	s.apply_look(GraphicsSettings.Look.PERFORMANCE)
	_check(s.quality == GraphicsSettings.Quality.LOW and s.render_scale < 1.0 and s.target_fps() > 0, "performance look")
	s.apply_look(GraphicsSettings.Look.CINEMATIC)
	s.grain = 1
	s.trees = 1
	s.look = GraphicsSettings.Look.CUSTOM
	s.save(path)
	loaded = GraphicsSettings.load_saved(path)
	_check(loaded.look == GraphicsSettings.Look.CUSTOM and loaded.grain == 1 and loaded.grade == GraphicsSettings.Grade.FILM, "custom look saved")
	_check(loaded.dof and loaded.ssao and loaded.bloom == 3, "effects saved")
	_check(loaded.trees == 1, "tree setting saved")
	cfg = ConfigFile.new()
	cfg.set_value("graphics", "quality", 1)
	cfg.save(path)
	loaded = GraphicsSettings.load_saved(path)
	_check(loaded.look == GraphicsSettings.detect_look(), "old settings get a look for the device")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	loaded = GraphicsSettings.load_saved(path)
	_check(loaded.look == GraphicsSettings.detect_look(), "first run gets a look for the device")
	GraphicsSettings.force_look = GraphicsSettings.Look.CLASSIC
	loaded = GraphicsSettings.load_saved(path)
	GraphicsSettings.force_look = -1
	_check(loaded.look == GraphicsSettings.Look.CLASSIC, "forced look")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for g in GraphicsSettings.Grade.values():
		_check(g < PostProcess.GRADES.size(), "grade %d has values" % g)


func _test_trees() -> void:
	for v in TreeFactory.VARIANTS.size():
		var spec: Array = TreeFactory.VARIANTS[v]
		var m := TreeFactory.build_mesh(spec[0], spec[1])
		_check(m.get_surface_count() == 2, "tree %d has bark and leaves" % v)
		var tris := 0
		for i in m.get_surface_count():
			tris += (m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		_check(tris > 200 and tris < 6000, "tree %d stays light (%d triangles)" % [v, tris])
		var box := m.get_aabb()
		_check(box.end.y > 8.0 and box.end.y < 19.0 and box.position.y > -0.5, "tree %d is tree-sized (%.1f m)" % [v, box.end.y])
		var again := TreeFactory.build_mesh(spec[0], spec[1])
		_check(again.surface_get_array_len(1) == m.surface_get_array_len(1), "tree %d grows the same each time" % v)
		_check(TreeFactory.frame_size(v) >= box.end.y, "tree %d fits its impostor frame" % v)
	var lib := PlaceholderObjectLibrary.new()
	TreeFactory.level = 0
	var classic := lib.instantiate("tree_pine")
	_check(classic != null and not classic.has_meta("tree_variant"), "classic trees when 3D trees are off")
	TreeFactory.level = 2
	var tree := lib.instantiate("tree_broadleaf")
	_check(tree != null and tree.has_meta("tree_variant") and tree.get_node_or_null("Full") != null, "3D tree when on")
	_check(lib.instantiate("rock") == null, "other ids still unknown")
	TreeFactory.level = 0
	classic.free()
	tree.free()
	for which in ["bark", "leaves", "needles", "bake_leaves"]:
		_check(TreeFactory.material(which).shader != null, "%s shader loads" % which)


func _test_ground_shade() -> void:
	# A 10 m tree at the origin with its crown from 4 to 10 m, radius 3 m,
	# and a sun 45 degrees up shining towards +z.
	var casters := PackedFloat32Array([0, 0, 0, 4, 10, 3, 5])
	var sun := Vector3(0, -1, 1).normalized()
	var st := GroundShade.stamps(casters, sun)
	_check(st.size() == 16, "a shadow and an occlusion stamp per caster")
	_check(is_equal_approx(st[0], 0.0) and is_equal_approx(st[1], 7.0), "shadow falls away from the sun, under the crown's middle")
	_check(is_equal_approx(st[2], 6.0) and is_equal_approx(st[3], 3.0), "shadow stretched along the sun")
	_check(st[5] > 0.0 and is_zero_approx(st[6]), "shadow stamp darkens R only")
	_check(is_equal_approx(st[7], 5.0) and is_equal_approx(st[15], -1.0), "the crown's shadow takes the tree type's shape, the occlusion an ellipse")
	_check(is_zero_approx(st[8]) and is_zero_approx(st[9]) and is_zero_approx(st[13]) and st[14] > 0.0, "occlusion at the foot, in G")
	var shape := Image.create(128, 128, false, Image.FORMAT_L8)
	shape.fill(Color.WHITE)
	var atlas := GroundShade.shape_atlas([null, shape])
	_check(atlas != null and atlas.get_width() == GroundShade.SHAPE_COLUMNS * GroundShade.SHAPE_CELL, "shadow shapes packed into an atlas")
	if atlas != null:
		var img := atlas.get_image()
		_check(img.get_pixel(GroundShade.SHAPE_CELL + 5, 5).r > 0.9 and img.get_pixel(5, 5).r < 0.1, "a type's shape sits in its own cell")
	_check(GroundShade.shape_atlas([]) == null, "no atlas without shapes")
	# A 3D object's footprint: its top rows (least y) are set; in the atlas,
	# after the billboard shapes, it is flipped so v runs along Godot +z.
	var footprint := Image.create(16, 16, false, Image.FORMAT_L8)
	footprint.fill_rect(Rect2i(0, 0, 16, 4), Color.WHITE)
	var both := GroundShade.shape_atlas([null, shape], [footprint])
	if both != null:
		var img := both.get_image()
		var cell := 2 * GroundShade.SHAPE_CELL
		_check(img.get_pixel(cell + 5, GroundShade.SHAPE_CELL - 3).r > 0.9 and img.get_pixel(cell + 5, 3).r < 0.1, "footprints go in flipped after the shapes")
	# A 10 m tall object 4 x 6 m, turned a quarter, under the same sun.
	var fs := GroundShade.footprint_stamps(PackedFloat32Array([1, 2, 2, 3, 0.5, 10, 7]), sun)
	_check(fs.size() == 16, "a shadow and an occlusion stamp per footprint")
	_check(is_equal_approx(fs[0], 1.0) and is_equal_approx(fs[1], 7.0), "footprint shadow moved along the sun by half the height")
	_check(is_equal_approx(fs[2], 3.0) and is_equal_approx(fs[3], 2.0) and is_equal_approx(fs[4], 0.5), "footprint keeps its size and turn")
	_check(is_equal_approx(fs[7], 7.0) and is_equal_approx(fs[15], 7.0), "both stamps take the footprint's shape")
	_check(is_equal_approx(fs[8], 1.0) and is_equal_approx(fs[9], 2.0) and fs[14] > 0.0, "footprint occlusion at the object")
	var low := GroundShade.stamps(casters, Vector3(0, -0.01, 1).normalized())
	_check(Vector2(low[0], low[1]).length() <= GroundShade.MAX_SLANT * 7.0 + 1e-3, "low sun shadows stay bounded")
	var course := AssetProviders.load_course("")
	var hole: HoleData = course.holes[0]
	var rect := GroundShade.hole_rect(hole)
	_check(rect.has_point(Vector2(hole.tee.x, hole.tee.z)) and rect.has_point(Vector2(hole.pin.x, hole.pin.z)), "bake covers the hole")
	var placed := GroundShade.placed_casters(hole)
	_check(placed.size() % GroundShade.CASTER_SIZE == 0, "placed objects give whole casters")
	GroundShade.bake(hole, null, sun)  # headless: nothing to draw, no error
	# Photo ground: the pale 2003 colours become deeper, darker turf.
	var pale := Color(0.62, 0.78, 0.55)
	var turf := CrzTerrain.realistic(pale, Surface.Type.FAIRWAY)
	_check(turf.v < pale.v and turf.s >= pale.s and absf(turf.h - CrzTerrain.MOWN_HUE) < absf(pale.h - CrzTerrain.MOWN_HUE) + 0.001, "photo ground turns deeper, darker and greener")
	var rough := CrzTerrain.realistic(Color(0.78, 0.76, 0.66), Surface.Type.ROUGH)
	_check(rough.s >= 0.3 and rough.v < 0.6, "pale rough becomes straw")
	var sand := Color(0.85, 0.8, 0.65)
	_check(absf(CrzTerrain.realistic(sand, Surface.Type.SAND).h - sand.h) < 0.01, "sand keeps its hue")


func _test_wind_gusts() -> void:
	var low := 9.0
	var high := 0.0
	for i in 2000:
		var f := WindGust.factor(i * 0.1, 3.0)
		low = minf(low, f)
		high = maxf(high, f)
	_check(low >= WindGust.LULL - 1e-4 and high <= WindGust.PEAK + 1e-4, "gusts stay between lull and peak")
	_check(high - low > 0.4, "gusts really vary (%.2f to %.2f)" % [low, high])
	_check(WindGust.visual_wind(Vector2.ZERO, 5.0) == Vector2.ZERO, "no gusts in a calm")
	var seen := WindGust.visual_wind(Vector2(4, 0), 7.0)
	_check(absf(rad_to_deg(seen.angle())) <= 8.01, "gusts swing the direction only a few degrees")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/flag.gdshader")
	_check(mat.shader != null and mat.shader.get_code().contains("wind_vector"), "flag shader reads the wind")


func _test_course_marks() -> void:
	var clubs := Club.standard_set()
	var by_name := {}
	for c in clubs:
		by_name[c.short_name] = c
	_check(CourseMarks.divot_size(by_name["Dr"], Surface.Type.TEE) == Vector2.ZERO, "no divot off the tee with a driver")
	_check(CourseMarks.divot_size(by_name["3W"], Surface.Type.FAIRWAY) == Vector2.ZERO, "fairway woods sweep the ball")
	_check(CourseMarks.divot_size(by_name["Pt"], Surface.Type.GREEN) == Vector2.ZERO, "putts take no turf")
	var seven := CourseMarks.divot_size(by_name["7i"], Surface.Type.FAIRWAY)
	var wedge := CourseMarks.divot_size(by_name["SW"], Surface.Type.FAIRWAY)
	_check(seven.x > 0.09 and seven.x < 0.18, "a 7 iron takes a hand-sized divot (%.2f m)" % seven.x)
	_check(wedge.x > seven.x, "wedges take longer divots than irons")
	_check(CourseMarks.divot_size(by_name["7i"], Surface.Type.TEE).x < seven.x, "an iron off a peg only nicks the tee")
	_check(CourseMarks.divot_size(by_name["SW"], Surface.Type.FAIRWAY, true).x < wedge.x, "chips take small divots")
	var centre := CourseMarks.divot_centre(Vector3.ZERO, Vector3(0, 0, 1), seven)
	_check(centre.z > 0.0 and absf(centre.x) < 1e-6, "divots start ahead of the ball")
	_check(CourseMarks.landing_mark(Surface.Type.GREEN, 25.0)[0] == CourseMarks.Kind.PITCH_MARK, "approach shots mark the green")
	_check(CourseMarks.landing_mark(Surface.Type.GREEN, 3.0).is_empty(), "a rolling ball leaves no pitch mark")
	_check(CourseMarks.landing_mark(Surface.Type.SAND, 20.0)[0] == CourseMarks.Kind.SAND_CRATER, "balls plug craters in sand")
	_check(CourseMarks.landing_mark(Surface.Type.FAIRWAY, 30.0).is_empty(), "fairway landings leave no mark")
	var course := AssetProviders.load_course("")
	var t := course.holes[0].terrain
	var marks := CourseMarks.new()
	for i in CourseMarks.MAX_MARKS + 5:
		marks.add_divot(t, course.holes[0].tee + Vector3(0, 0, 60 + i), Vector3(0, 0, 1), by_name["8i"], Surface.Type.FAIRWAY)
	_check(marks.mark_count() == CourseMarks.MAX_MARKS, "marks are capped per hole")
	marks.free()
	# Footprints: find a bunker on the first hole and stand in it.
	var sand := Vector3.INF
	var h0 := course.holes[0]
	for z in range(0, 400, 2):
		for x in range(-60, 61, 2):
			if t.surface_at(h0.tee.x + x, h0.tee.z + z) == Surface.Type.SAND \
					and t.surface_at(h0.tee.x + x, h0.tee.z + z - 3) == Surface.Type.SAND:
				sand = Vector3(h0.tee.x + x, 0.0, h0.tee.z + z)
				break
		if sand != Vector3.INF:
			break
	_check(sand != Vector3.INF, "the placeholder course has a bunker")
	if sand != Vector3.INF:
		var spots := CourseMarks.footprint_spots(t, sand, Vector3(0, 0, 1), Vector3(1, 0, 0))
		_check(spots.size() >= 2, "footprints in the bunker (%d)" % spots.size())
		var on_sand := true
		for spot in spots:
			var at: Vector3 = spot[0]
			on_sand = on_sand and t.surface_at(at.x, at.z) == Surface.Type.SAND
		_check(on_sand, "footprints only on sand")
		_check(spots.size() <= 2 + CourseMarks.MAX_STEPS, "the walk in is bounded")


func _test_sound_over_distance() -> void:
	var near := SoundBank.heard_from(5.0)
	_check(near.gain_db == 0.0 and near.delay_s < 0.02, "close sounds play at once, at full level")
	var drive := SoundBank.heard_from(250.0)
	_check_near(drive.delay_s, 250.0 / 343.0, 1e-6, "sound takes 0.73 s to cover 250 m")
	_check_near(SoundBank.heard_from(40.0).gain_db, -6.0206, 1e-3, "6 dB quieter each time the distance doubles")
	_check(SoundBank.heard_from(5000.0).gain_db == SoundBank.FAINTEST_DB, "far sounds stay faintly audible")


func _test_grass() -> void:
	var course := AssetProviders.load_course("")
	var t := course.holes[0].terrain
	var tufts := 0
	var outside := 0
	# A strip across the first hole, which crosses rough on both sides.
	var tee := course.holes[0].tee
	for i in range(-6, 7):
		var key := Vector2i(floori(tee.x / GrassField.CHUNK) + i, floori((tee.z + 60.0) / GrassField.CHUNK))
		var mm := GrassField.build_chunk(t, key, 4.0)
		if mm == null:
			continue
		tufts += mm.instance_count
		var buffer: PackedFloat32Array = mm.get_meta("buffer")
		for k in mini(mm.instance_count, 50):
			var at := Vector3(buffer[16 * k + 3], buffer[16 * k + 7], buffer[16 * k + 11])
			if not GrassField.HEIGHTS.has(t.surface_at(at.x, at.z)):
				outside += 1
		var again := GrassField.build_chunk(t, key, 4.0)
		_check(again.instance_count == mm.instance_count, "chunk grows the same grass each time")
	_check(tufts > 100, "grass grows in the rough (%d tufts)" % tufts)
	_check(outside == 0, "no grass on fairways, greens or sand")
	_check(GrassField.tuft_mesh().get_surface_count() == 1, "tuft mesh")
	var field := GrassField.new()
	field.setup(t, 1)
	field.update_around(tee + Vector3(0, 2, 60))
	_check(field.chunk_count() == GrassField.BUILDS_PER_FRAME, "builds a few chunks per frame")
	field.free()


## Numbers from the C++ wind_moves_the_ball test.
func _test_wind_matches_olcore() -> void:
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY)
	var launch := Swing.launch_from_swing(_club("7i"), 1.0, 0.0, 0.0, Surface.Type.FAIRWAY)
	var head := BallPhysics.simulate_shot(launch, fairway, false, Vector3.ZERO, Vector3(0, 0, -8))
	var tail := BallPhysics.simulate_shot(launch, fairway, false, Vector3.ZERO, Vector3(0, 0, 8))
	var cross := BallPhysics.simulate_shot(launch, fairway, false, Vector3.ZERO, Vector3(8, 0, 0))
	print("  7i wind: head carry %.2f, tail carry %.2f, cross carry %.2f drift %.2f m" % [head.carry_m, tail.carry_m, cross.carry_m, cross.first_landing.x])
	_check_near(head.carry_m, 133.17, 1.0, "headwind carry")
	_check_near(tail.carry_m, 179.50, 1.0, "tailwind carry")
	_check_near(cross.carry_m, 164.77, 1.0, "crosswind carry")
	_check_near(cross.first_landing.x, 22.69, 0.5, "crosswind drift")


## Same made-up tables as synthetic_aero_exe() in the C++ tests.
static func _synthetic_aero_exe() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(64)
	out.fill(0xCD)
	for table in 2:
		var b := PackedByteArray()
		b.resize(LinksAero.TABLE_BYTES)
		b.encode_u32(0, 11)
		b.encode_u32(4, 14)
		var q := 8
		for i in 11:
			b.encode_float(q, 30.0 * i)
			q += 4
		for i in 14:
			b.encode_float(q, 10.0 * i)
			q += 4
		b.encode_u32(q, 0x00401000)
		b.encode_u32(q + 4, 0x0040102c)
		b.encode_u32(q + 8, 0)
		q += 12
		for row in 11:
			for col in 14:
				b.encode_float(q, 0.2 + 0.01 * row + 0.001 * col if table == 0 else 0.01 * col)
				q += 4
		out.append_array(b)
		var pad := PackedByteArray()
		pad.resize(40)
		pad.fill(0xCD)
		out.append_array(pad)
	return out


## The game's frame for the Links ground tests: a plane, or a flat shelf
## ending in a 3 ft drop at y = 5. Mirrors TestGround in the C++ tests.
class TestLinksGround extends LinksGround.Ground:
	var cls: int
	var gx: float
	var gy: float
	var cliff: bool

	func _init(p_cls: int, p_gx := 0.0, p_gy := 0.0, p_cliff := false) -> void:
		cls = p_cls
		gx = p_gx
		gy = p_gy
		cliff = p_cliff

	func height(x: float, y: float) -> float:
		if cliff:
			return 0.0 if y < 5.0 else -3.0
		return gx * x + gy * y

	func normal(_x: float, _y: float) -> Vector3:
		return Vector3(-gx, -gy, 1.0).normalized()

	func surface(_x: float, _y: float) -> LinksGround.Params:
		return LinksGround.surface_for_class(cls)


static func _still_air() -> LinksAero:
	var a := LinksAero.new()
	var t := {"speeds": PackedFloat64Array([0, 1]), "spins": PackedFloat64Array([0, 1]), "values": PackedFloat64Array([0, 0, 0, 0])}
	a.drag = t
	a.lift = t
	return a


static func _links_ball(pos: Vector3, vel: Vector3, spin: Vector3, mode: int) -> LinksGround.Ball:
	var b := LinksGround.Ball.new()
	b.position = pos
	b.velocity = vel
	b.spin = spin
	b.mode = mode
	if mode != LinksGround.Mode.FLIGHT:
		b.on_ground_started = true
		b.checkpoint_x = pos.x
		b.checkpoint_y = pos.y
	return b


## Steps until the ball stops; returns the step it stopped on, or -1.
static func _run_links_ball(b: LinksGround.Ball, g: LinksGround.Ground, rng: LinksGround.Rng) -> int:
	var air := _still_air()
	for k in 2000:
		LinksGround.step(b, g, air, Vector3.ZERO, rng)
		if b.mode == LinksGround.Mode.REST:
			return k
	return -1


## Steps a ball near a hole at the origin until it is holed or stops;
## returns the step, or -1. `seen` gets the state after step `at`.
static func _run_cup_ball(b: LinksGround.Ball, seen: LinksGround.Ball = null, at := -1) -> int:
	var green := TestLinksGround.new(LinksGround.GREEN)
	var air := _still_air()
	var rng := LinksGround.Rng.new()
	var cup := LinksGround.Cup.new()
	for k in 600:
		LinksGround.step(b, green, air, Vector3.ZERO, rng, LinksGround.FRAME_DT, cup)
		if k == at and seen != null:
			seen.assign(b)
		if b.mode == LinksGround.Mode.REST or b.mode == LinksGround.Mode.HOLED:
			return k
	return -1


## A 20 x 20 billboard type; `opaque` takes (x, y from the bottom).
static func _object_type(collision: int, shape: Array, opaque: Callable) -> LinksObjects.ObjType:
	var t := LinksObjects.ObjType.new()
	t.collision = collision
	t.shape = PackedFloat32Array(shape)
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	for y in 20:
		for x in 20:
			img.set_pixel(x, 19 - y, Color(1, 1, 1, 1) if opaque.call(x, y) else Color(0, 0, 0, 0))
	t.mask = img
	return t


## Flies a ball at a 10 ft billboard 20 ft away until it hits something.
static func _fly_at_billboard(type: LinksObjects.ObjType) -> LinksGround.Ball:
	var objects := LinksObjects.new()
	objects.types.append(type)
	objects.add(Vector3(0, 20, 0), 10.0, 0)
	var ball := _links_ball(Vector3(0, 0, 3), Vector3(0, 60, 0), Vector3.ZERO, LinksGround.Mode.FLIGHT)
	var ground := TestLinksGround.new(LinksGround.FAIRWAY)
	var air := _still_air()
	var rng := LinksGround.Rng.new()
	for k in 30:
		if ball.last_object >= 0 or ball.mode != LinksGround.Mode.FLIGHT:
			break
		LinksGround.step(ball, ground, air, Vector3.ZERO, rng, LinksGround.FRAME_DT, null, objects, Vector3(0, -1, 0))
	return ball


## As test_links_objects in the C++ core.
func _test_links_objects_match_olcore() -> void:
	_check_near(LinksObjects.anchor_x(-1), 0.5, 1e-12, "default anchor")
	_check_near(LinksObjects.anchor_x(0xf6), 0.5 - 10 / 128.0, 1e-12, "anchor from the extra byte")
	_check_near(LinksObjects.anchor_z(58), 58 / 256.0, 1e-12, "anchor from the extra word")
	var all := func(_x: int, _y: int) -> bool: return true
	var none := func(_x: int, _y: int) -> bool: return false
	var b := _fly_at_billboard(_object_type(1, [0.8, 1, 0, 0, 1, 1], all))
	_check(b.last_object == 0, "rock hit")
	_check_near(b.velocity.y, -0.8 * 60, 1e-4, "rock restitution")
	_check(b.position.y < 20 - 0.09 and b.position.y > 20 - 0.11, "put back 0.1 ft")
	b = _fly_at_billboard(_object_type(2, [0.5, 1, 0, 0, 1, 1], all))
	_check(b.last_object == 0, "canopy met")
	_check_near(b.velocity.y, 0.9 * 60, 1e-4, "canopy keeps 0.9")
	b = _fly_at_billboard(_object_type(1, [0.8, 1, 0, 0, 1, 1], none))
	_check(b.last_object < 0, "transparent parts let the ball by")
	var trunk := func(x: int, y: int) -> bool: return y >= 12 or (x >= 8 and x <= 11)
	b = _fly_at_billboard(_object_type(0, [0.7, 1, 0.35, 0, 0.65, 0.6], trunk))
	_check(b.last_object == 0, "trunk hit")
	var turn := (3.0 / 5.0 - 0.5) * 2.09440565
	_check_near(b.velocity.x, 0.5 * 60 * sin(2 * turn), 1e-3, "trunk turns the ball")
	_check_near(b.velocity.y, -0.5 * 60 * cos(2 * turn), 1e-3, "trunk sends it back")


## 3D objects for the tests: each quad is four corners, fanned from the
## first; a face is met from the side its corners turn anticlockwise to.
static func _test_models(quads: Array, holes := false) -> LinksObjects:
	var objects := LinksObjects.new()
	var mesh := LinksObjects.Mesh3D.new()
	for q: Array in quads:
		mesh.faces.append_array(PackedInt32Array([mesh.corners.size(), 4, 0]))
		for v: Vector3 in q:
			mesh.corners.append(mesh.positions.size())
			mesh.positions.append(v)
			mesh.uvs.append(Vector2(0.5, 0.5))
	var picture: Image = null
	if holes:
		picture = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		picture.fill(Color(0, 0, 0, 0))
	mesh.holes.append(picture)
	objects.meshes.append(mesh)
	objects.add_model(0, mesh.positions)
	return objects


## Runs a ball for up to `steps` frames; `each` sees it after every step.
static func _run_with_objects(b: LinksGround.Ball, objects: LinksObjects, steps: int, each: Callable) -> LinksGround.Ball:
	var ground := TestLinksGround.new(LinksGround.FAIRWAY)
	var air := _still_air()
	var rng := LinksGround.Rng.new()
	for k in steps:
		if b.mode == LinksGround.Mode.REST:
			break
		LinksGround.step(b, ground, air, Vector3.ZERO, rng, LinksGround.FRAME_DT, null, objects, Vector3(0, -1, 0))
		each.call(b)
	return b


## As test_links_models in the C++ core.
func _test_links_models_match_olcore() -> void:
	var wall := [Vector3(-5, 20, 0), Vector3(-5, 20, 10), Vector3(5, 20, 10), Vector3(5, 20, 0)]
	var seen := {"hit": false}
	var fly := _links_ball(Vector3(0, 0, 3), Vector3(0, 60, 0), Vector3.ZERO, LinksGround.Mode.FLIGHT)
	var on_wall := func(b: LinksGround.Ball) -> void:
		if not seen.hit and b.velocity.y < 0.0:
			seen.hit = true
			seen.vy = b.velocity.y
			seen.y = b.position.y
			seen.last = b.last_object
	_run_with_objects(fly, _test_models([wall]), 30, on_wall)
	_check(seen.hit, "wall hit")
	_check_near(seen.get("vy", 0.0), -0.7 * 60, 1e-3, "wall keeps 70%")
	_check_near(seen.get("y", 0.0), 20, 1e-4, "met at the wall")
	_check(seen.get("last", 0) < 0, "a 3D object is not skipped")
	var noop := func(_b: LinksGround.Ball) -> void:
		pass
	var back := [wall[3], wall[2], wall[1], wall[0]]
	fly = _links_ball(Vector3(0, 0, 3), Vector3(0, 60, 0), Vector3.ZERO, LinksGround.Mode.FLIGHT)
	_check(_run_with_objects(fly, _test_models([back]), 30, noop).position.y > 25, "a face's back lets it through")
	fly = _links_ball(Vector3(0, 0, 3), Vector3(0, 60, 0), Vector3.ZERO, LinksGround.Mode.FLIGHT)
	_check(_run_with_objects(fly, _test_models([wall], true), 30, noop).position.y > 25, "clear texels let it through")

	var deck := [Vector3(-5, 10, 2), Vector3(-5, 30, 2), Vector3(5, 30, 2), Vector3(5, 10, 2)]
	var roll := {"rolled": false, "off": false, "z": 0.0}
	var b := _links_ball(Vector3(0, 15, 2.05), Vector3(0, 30, 0), Vector3.ZERO, LinksGround.Mode.FLIGHT)
	var on_deck := func(x: LinksGround.Ball) -> void:
		if x.mode == LinksGround.Mode.ON_OBJECT and x.position.y > 20 and not roll.rolled:
			roll.rolled = true
			roll.z = x.position.z
		if roll.rolled and x.mode == LinksGround.Mode.FLIGHT:
			roll.off = true
	b = _run_with_objects(b, _test_models([deck]), 400, on_deck)
	_check(roll.rolled, "rolls on the deck")
	_check_near(roll.z, 2.07, 1e-4, "on the deck by its radius")
	_check(roll.off, "rolls off the deck's end")
	_check(b.mode == LinksGround.Mode.REST, "comes to rest")
	_check_near(b.position.z, 0.07, 1e-4, "on the ground")
	_check_near(b.position.y, 36.943, 2e-2, "where the C++ core stops it")

	var low := [Vector3(-5, 10, 2), Vector3(-5, 20, 2), Vector3(5, 20, 2), Vector3(5, 10, 2)]
	var high := [Vector3(-5, 20, 3), Vector3(-5, 30, 3), Vector3(5, 30, 3), Vector3(5, 20, 3)]
	b = _links_ball(Vector3(0, 15, 2.07), Vector3(0, 10, 0), Vector3.ZERO, LinksGround.Mode.ON_OBJECT)
	b.on_object = 0
	b = _run_with_objects(b, _test_models([low, high]), 400, noop)
	_check(b.mode == LinksGround.Mode.REST, "a step up stops it")
	_check(b.position.y > 19 and b.position.y < 20, "stopped before the step")
	_check_near(LinksGround.object_surface().roll_resistance, 0.2, 1e-9, "object ground")


## As test_links_cup in the C++ core; every case matches the game's own code.
func _test_links_cup_matches_olcore() -> void:
	_check_near(LinksGround.cup_radius(1), 0.17708, 1e-9, "regulation hole")
	_check_near(LinksGround.cup_radius(2), 0.29167, 1e-9, "big hole")
	var seen := LinksGround.Ball.new()
	var b := _links_ball(Vector3(0.02, -1.5, 0.07), Vector3(0, 6, 0), Vector3.ZERO, LinksGround.Mode.SKID)
	_check(_run_cup_ball(b, seen, 18) == 35, "putt off the flagstick is holed on step 35")
	_check(b.mode == LinksGround.Mode.HOLED, "putt holed")
	_check(seen.mode == LinksGround.Mode.CUP_RIM, "on the rim at step 18")
	b = _links_ball(Vector3(0.02, -1.5, 0.07), Vector3(0, 6, 0), Vector3.ZERO, LinksGround.Mode.SKID)
	_run_cup_ball(b, seen, 21)
	_check(seen.mode == LinksGround.Mode.CUP_AIR and seen.flagstick_out, "off the flagstick at step 21")
	_check_near(seen.velocity.x, 0.9429, 2e-4, "flagstick vx")
	_check_near(seen.velocity.y, -0.6037, 2e-4, "flagstick vy")
	_check_near(seen.velocity.z, -0.7611, 2e-4, "flagstick vz")
	b = _links_ball(Vector3(0.02, -1.5, 0.07), Vector3(0, 6, 0), Vector3.ZERO, LinksGround.Mode.SKID)
	b.flagstick_out = true
	_check(_run_cup_ball(b) == 34 and b.mode == LinksGround.Mode.HOLED, "flagstick out: holed on step 34")
	b = _links_ball(Vector3(0.12, -1, 0.07), Vector3(0, 5, 0), Vector3.ZERO, LinksGround.Mode.SKID)
	_check(_run_cup_ball(b) == 31 and b.mode == LinksGround.Mode.HOLED, "firm putt holed on step 31")
	b = _links_ball(Vector3(0.16, -1, 0.07), Vector3(0, 4, 0), Vector3.ZERO, LinksGround.Mode.SKID)
	var lip := _run_cup_ball(b)
	_check(lip == 63 and b.mode == LinksGround.Mode.REST, "lip-out stops on step 63, got %d" % lip)
	_check_near(b.position.x, -0.08464, 2e-3, "lip-out x")
	_check_near(b.position.y, 0.64145, 2e-3, "lip-out y")
	b = _links_ball(Vector3(0.19, -1, 0.07), Vector3(0, 3.5, 0), Vector3.ZERO, LinksGround.Mode.SKID)
	_check(_run_cup_ball(b) == 47 and b.mode == LinksGround.Mode.REST, "misses the hole")
	b = _links_ball(Vector3(0.05, -0.05, 0.06), Vector3(0, 1, -3), Vector3.ZERO, LinksGround.Mode.CUP_AIR)
	_check(_run_cup_ball(b) == 10 and b.mode == LinksGround.Mode.HOLED, "dropped in on step 10")


## Same cases and numbers as the links_* tests in the C++ core, which come
## from the game's own code.
func _test_links_lie_matches_olcore() -> void:
	var s := LinksLaunch.Strike.new()
	s.face_error = 0.05
	LinksLaunch.apply_lie(s, LinksGround.surface_for_class(LinksGround.ROUGH))
	_check_near(s.spin_scale, 0.406505, 1e-6, "rough spin")
	_check_near(s.speed_scale, 0.927315, 1e-6, "rough speed")
	_check_near(s.face_error, 0.05, 1e-9, "rough keeps the face")
	# contact, speed, spin, loft: as test_links_lie in libs/olcore/tests.
	for c in [[0, 0.4, 1.5, 1.0], [3, 0.38, 1.25, 1.0], [10, 0.333333, 0.666667, 1.0], [-3, 0.7, 1.2, 1.0], [-5, 0.9, 1.0, 1.0], [-8, 0.705, 0.7, 0.73]]:
		var t := LinksLaunch.Strike.new()
		t.face_error = 0.05
		LinksLaunch.apply_lie(t, LinksGround.surface_for_class(LinksGround.SAND), c[0])
		_check_near(t.face_error, 0.0, 1e-9, "sand drops the face error")
		_check_near(t.speed_scale, c[1], 1e-5, "sand speed %d" % c[0])
		_check_near(t.spin_scale, c[2], 1e-5, "sand spin %d" % c[0])
		_check_near(t.loft_scale, c[3], 1e-6, "sand loft %d" % c[0])


func _test_links_swing_matches_olcore() -> void:
	var r := LinksLaunch.Rand.new(1)
	_check(r.next() == 41 and r.next() == 18467 and r.next() == 6334, "C runtime rand")
	# snap units, skill, contact: as test_links_swing in libs/olcore/tests.
	for c in [[16.0, 0, 0], [16.0, 1, 1], [16.0, 3, 0], [17.0, 3, 1], [-30.0, 3, -1], [10.0, 2, 0]]:
		_check(LinksLaunch.meter_contact(c[0], c[1]) == c[2], "meter contact %s" % [c])
	# class, club, skill, mouse, contact, power, seed, left-handed, teed up,
	# then aim, power, face, path, spin, speed, loft.
	var cases := [
		[LinksGround.ROUGH, 13, 3, false, -1, 100.0, 12345, false, false, 0.073820061, 98.9875, 0.011343904, 0.006179939, 0.306505, 0.897315, 1.0],
		[LinksGround.FAIRWAY, 0, 2, false, 1, 100.0, 777, false, false, 0.117637011, 98.105, 0.010139626, -0.037637011, 0.9, 0.902034979, 1.0],
		[LinksGround.DIRT, 7, 1, false, 2, 90.0, 99, false, false, 0.148869219, 90.0, 0.01, -0.068869219, 0.92, 0.9728, 1.0],
		[LinksGround.ROUGH, 11, 3, true, -2, 100.0, 5, false, false, 0.1, 100.0, 0.043633231, -0.06981317, 0.25, 0.927315, 0.95],
		[LinksGround.SAND, 17, 3, false, -1, 100.0, 42, true, false, 0.1, 94.8025, 0.0, 0.0, 1.416666667, 0.393333333, 1.0],
		[LinksGround.FAIRWAY, 0, 3, false, 1, 100.0, 2003, false, true, 0.116496095, 97.3625, 0.011466077, -0.036406095, 1.0, 1.0, 1.0],
	]
	for c in cases:
		var s := LinksLaunch.Strike.new()
		s.club = c[1]
		s.power = c[5]
		s.aim = 0.1
		s.face_error = 0.01
		s.path_error = -0.02
		var w := LinksLaunch.SwingInput.new()
		w.method = LinksLaunch.Method.MOUSE if c[3] else LinksLaunch.Method.POWERSTROKE
		w.skill = c[2]
		w.contact = c[4]
		w.mouse_face_deg = 2.5
		w.mouse_path_deg = -4.0
		w.mouse_loft = 0.95
		w.left_handed = c[7]
		w.teed_up = c[8]
		LinksLaunch.apply_swing(s, w, LinksGround.surface_for_class(c[0]), LinksLaunch.Rand.new(c[6]))
		var got := [s.aim, s.power, s.face_error, s.path_error, s.spin_scale, s.speed_scale, s.loft_scale]
		for i in got.size():
			_check_near(got[i], c[9 + i], 1e-6, "swing case %d value %d" % [cases.find(c), i])
	# Computer misses, as test_links_computer_miss: rating, max power, steady,
	# teed up, club, chip, class, power, feet, seed, then power, face, path.
	var cpu := [
		[80, 100, false, false, 12, false, LinksGround.FAIRWAY, 100.0, 300.0, 12345, 101.21875, 0.3125, 0.0],
		[70, 100, false, true, 0, false, LinksGround.FAIRWAY, 100.0, 1200.0, 777, 98.5175018, 0.0, 0.375],
		[60, 100, false, false, 3, false, LinksGround.ROUGH, 100.0, 600.0, 99, 103.9375, 0.0, 1.875],
		[95, 90, false, false, 8, false, LinksGround.SAND, 100.0, 450.0, 2003, 100.474998, 0.474999994, 0.0],
		[40, 100, true, false, 17, false, LinksGround.DEEP_GRASS, 60.0, 120.0, 5, 56.360939, 0.0, 3.9312501],
		[65, 100, false, false, 14, true, LinksGround.PATH, 30.0, 90.0, 42, 23.4375, 0.0, -1.125],
	]
	for c in cpu:
		var g := LinksLaunch.GolferRatings.even(c[0])
		g.max_power = c[1]
		g.steady = c[2]
		if c[3]:
			g.tee = 85
		var w := LinksLaunch.ComputerSwing.new()
		w.power = c[7]
		LinksLaunch.computer_miss(w, g, c[4], c[3], c[5], c[6], c[8], LinksLaunch.Rand.new(c[9]))
		var got := [w.power, w.face_deg, w.path_deg]
		for i in got.size():
			_check_near(got[i], c[10 + i], 1e-4, "computer miss case %d value %d" % [cpu.find(c), i])
	# Computer putts, as test_links_computer_putt: long, short, steady, feet,
	# lie, seed, power, then power and path (radians).
	var cputts := [
		[80, 90, false, 20.0, LinksGround.GREEN, 12345, 8.0, 7.75, 0.266666681],
		[95, 95, false, 40.0, LinksGround.FAIRWAY, 777, 15.0, 15.0375004, 0.0],
		[60, 85, false, 5.0, LinksGround.GREEN, 99, 3.0, 3.03686643, -0.0166666675],
		[40, 70, true, 10.0, LinksGround.ROUGH, 2003, 6.0, 5.66666651, 0.76666671],
		[85, 100, false, 4.5, LinksGround.GREEN, 42, 2.5, 2.5, 0.0],
		[70, 60, false, 2.6, LinksGround.GREEN, 5, 1.5, 1.5625, -0.0250000022],
	]
	for c in cputts:
		var cg := LinksLaunch.GolferRatings.new()
		cg.long_putts = c[0]
		cg.short_putts = c[1]
		cg.steady = c[2]
		var cw := LinksLaunch.ComputerSwing.new()
		cw.power = c[6]
		LinksLaunch.computer_putt_miss(cw, cg, c[4], c[3], LinksLaunch.Rand.new(c[5]))
		_check_near(cw.power, c[7], 1e-4, "computer putt %d power" % cputts.find(c))
		_check_near(deg_to_rad(cw.path_deg), c[8], 1e-5, "computer putt %d path" % cputts.find(c))
	# The mouse swing, as test_links_mouse_swing: skill, shot, club, screen
	# width, seed, frames back, pixels back and up and across a frame, then
	# speed, drift, drift two frames before, down, backswing, power, face,
	# path, loft, quality.
	var strokes := [
		[3, LinksMouse.Shot.FULL, 0, 1920, 11, 20, 12, 90, 0, -4.772966, 0.0, 0.0, 90, 0.297828, 31.626182, 0.0, 0.0, 0.157841, 0],
		[1, LinksMouse.Shot.FULL, 9, 1100, 5, 15, 10, 70, 3, -3.412456, -0.45, -0.27, 70, 0.152596, 11.886348, 0.004837,
				-0.117355, 0.071311, 0],
		[2, LinksMouse.Shot.PUTT, 19, 1920, 7, 12, 6, 40, -2, -0.592555, 0.24, 0.0, 40, 0.034813, 1.0, -0.360105,
				0.398950, 0.033288, 0],
		[0, LinksMouse.Shot.CHIP, 16, 800, 3, 10, 8, 50, 1, -0.884124, -0.04, 0.0, 50, 0.064996, 1.522239, 0.000077,
				-0.021463, 0.064996, 0],
		[3, LinksMouse.Shot.FULL, 4, 1920, 9, 30, 15, 110, -6, -8.128368, 1.8, 1.2, 127, 0.626433, 77.270356, -1.1742,
				-0.825252, 0.517093, 1],
		[2, LinksMouse.Shot.FULL, 12, 1920, 21, 25, 14, 100, 12, -7.405264, -2.16, -1.44, 127, 0.428111, 46.535126,
				0.244594, -0.477122, 0.355657, 0],
	]
	for c in strokes:
		var i := strokes.find(c)
		var mc := LinksMouse.MouseClub.new(c[0], c[1], c[2], LinksMouse.meter_for(c[3]))
		var mr := LinksLaunch.Rand.new(c[4])
		for k in c[5]:
			mc.step(0, c[6], mr)
		for k in 40:
			if mc.done():
				break
			mc.step(c[8], -c[7], mr)
		_check(mc.phase == LinksMouse.Phase.IMPACT, "mouse swing %d strikes" % i)
		var st := mc.stroke
		_check_near(st.speed, c[9], 1e-5, "mouse swing %d speed" % i)
		_check_near(st.drift, c[10], 1e-5, "mouse swing %d drift" % i)
		_check_near(st.drift_before, c[11], 1e-5, "mouse swing %d drift before" % i)
		_check(st.down == c[12], "mouse swing %d down" % i)
		_check_near(st.backswing, c[13], 1e-5, "mouse swing %d backswing" % i)
		var mw := LinksMouse.swing(st, mr)
		_check_near(mw.power, c[14], 1e-5, "mouse swing %d power" % i)
		_check_near(mw.face_deg, c[15], 1e-5, "mouse swing %d face" % i)
		_check_near(mw.path_deg, c[16], 1e-5, "mouse swing %d path" % i)
		_check_near(mw.loft, c[17], 1e-5, "mouse swing %d loft" % i)
		_check(not mw.whiff and mw.quality == c[18], "mouse swing %d quality" % i)
	var wild := LinksMouse.Stroke.new()
	wild.drift = -19.0
	wild.down = 80
	wild.speed = 8.0
	var miss := LinksMouse.swing(wild, LinksLaunch.Rand.new(1))
	_check(miss.whiff and miss.power == 0.0, "mouse swing misses past 18")
	_check(LinksMouse.meter_for(800).height == 278 and LinksMouse.meter_for(1024).ball_line == 96, "mouse meter sizes")
	var iron := LinksMouse.Stroke.new()
	iron.club = 13
	iron.speed = -6.0
	iron.down = 90
	iron.backswing = 0.8
	iron.drift = -12.0
	iron.drift_before = -12.0
	var hooked := LinksMouse.swing(iron, LinksLaunch.Rand.new(5))
	_check_near(hooked.power, 44.295517, 1e-5, "iron drift power")
	_check_near(hooked.face_deg, 35.1, 1e-5, "iron drift turns the face")
	var still := LinksMouse.Stroke.new()
	still.speed = -6.0
	still.down = 90
	still.backswing = 0.8
	var help := LinksMouse.Help.new()
	help.enabled = true
	help.strokes = 3
	help.still_strokes = 3
	var nudged := LinksMouse.swing(still, LinksLaunch.Rand.new(42), help)
	_check_near(nudged.help_deg, 3.9, 1e-6, "swing help nudge")
	_check_near(nudged.path_deg, 2.600013, 1e-5, "swing help path")
	_check_near(nudged.power, 65.042229, 1e-5, "swing help power")
	_check(help.strokes == 4 and help.still_strokes == 4, "swing help counts")
	# The control: frames of movement shared out; pushing first does nothing.
	var ctl := MouseSwingControl.new()
	var got: Array = []
	ctl.stroke_finished.connect(func(m: LinksMouse.Stroke) -> void: got.append(m))
	ctl.begin(0, 3)
	ctl.motion(Vector2(0, -300))
	ctl.advance(0.1)
	_check(ctl.is_swinging() and ctl.club.club_height() == 119.0, "mouse swing waits for the backswing")
	for k in 40:
		ctl.motion(Vector2(0, 14))
		ctl.advance(1.0 / 60.0)
	for k in 30:
		if not ctl.is_swinging():
			break
		ctl.motion(Vector2(0, -100))
		ctl.advance(1.0 / 60.0)
	_check(got.size() == 1, "mouse stroke finished")
	if got.size() == 1:
		var fin: LinksMouse.Stroke = got[0]
		_check(fin.backswing > 0.3 and absf(fin.speed) > 4.0, "mouse stroke backswing and speed")
	ctl.free()
	# Putts, as test_links_putt: skill, contact, then the face error.
	var putts := [[0, 1, 0.0], [1, 1, -0.0111701], [2, 1, -0.017637], [2, -2, 0.0440925],
			[2, 3, -0.070548], [3, 1, -0.0251327], [3, -2, 0.0502655], [3, 3, -0.0753982]]
	for c in putts:
		var ps := LinksLaunch.Strike.new()
		ps.club = LinksLaunch.PUTTER
		ps.power = 10.0
		var pw := LinksLaunch.SwingInput.new()
		pw.skill = c[0]
		pw.contact = c[1]
		LinksLaunch.apply_swing(ps, pw, LinksGround.surface_for_class(LinksGround.GREEN), LinksLaunch.Rand.new(777))
		_check_near(ps.face_error, c[2], 1e-6, "putt miss skill %d contact %d" % [c[0], c[1]])
		_check_near(ps.power, 10.0, 1e-9, "putt keeps its power")
	var pt := LinksLaunch.Strike.new()
	pt.club = LinksLaunch.PUTTER
	pt.face_error = 0.02
	pt.path_error = -0.01
	pt.power = 6.0
	pt.aim = 0.3
	var pl := LinksLaunch.putt(pt)
	var pn := Vector3(0.1, -0.2, 0.97).normalized()
	var pv := LinksLaunch.putt_slope(pl[0], pn)
	var pspin := LinksLaunch.putt_slope(pl[1], pn)
	for i in 3:
		_check_near(pv[i], [-3.584047, 13.229612, -3.111701][i], 1e-5, "putt velocity %d" % i)
		_check_near(pspin[i], [30.563985, 9.249282, 1.233750][i], 1e-5, "putt spin %d" % i)


func _test_links_launch_matches_olcore() -> void:
	# The made-up club table of test_links_launch in libs/olcore/tests.
	var exe := PackedByteArray()
	exe.resize(36)
	exe.fill(0x11)
	var rows: Array[Callable] = [
		func(i: int) -> float: return 1.5 + 0.2 * i,
		func(i: int) -> float: return 2.0 + 0.01 * i,
		func(i: int) -> float: return 10.0 + 2.0 * i if i < 7 else 14.0 + 4.0 * (i - 7),
		func(i: int) -> float: return 0.05 + 0.01 * i,
		func(i: int) -> float: return 10.0 + 0.5 * i,
	]
	for row in rows:
		for i in 20:
			var at := exe.size()
			exe.resize(at + 4)
			exe.encode_float(at, row.call(i) if i < 19 else 0.0)
	var t := LinksLaunch.from_exe(exe)
	_check(t != null, "club table found")
	var empty := PackedByteArray()
	empty.resize(600)
	_check(LinksLaunch.from_exe(empty) == null, "no club table in zeros")
	if t == null:
		return
	var s := LinksLaunch.Strike.new()
	_check_launch(t, s, [0, 195.679363, 24.503551, 73.860581, 0, 0], "square driver")
	s = LinksLaunch.Strike.new()
	s.club = 12
	s.aim = 0.4
	s.power = 85
	s.face_error = 0.03
	s.path_error = -0.02
	s.setup.ball_position = 6
	s.setup.face = 33
	s.setup.stance = 27
	_check_launch(t, s, [-60.178063, 130.934603, 58.414966, 135.705451, 62.62540, -0.570758], "set-up iron")
	s = LinksLaunch.Strike.new()
	s.club = 5
	s.aim = -1.2
	s.power = 70
	s.face_error = -0.05
	s.path_error = 0.04
	s.spin_scale = 0.9
	s.speed_scale = 1.05
	s.loft_scale = 1.1
	s.setup.face = 26
	s.setup.stance = 32
	s.ground_normal = Vector3(0.2, -0.1, sqrt(1 - 0.05))
	_check_launch(t, s, [130.663751, 47.660517, 18.457195, 27.686730, -73.138883, -7.141661], "on a slope")
	s = LinksLaunch.Strike.new()
	s.club = 18
	s.aim = 2.5
	s.power = 60
	s.setup.ball_position = 1
	s.ground_normal = Vector3(-0.3, 0.25, sqrt(1 - 0.09 - 0.0625))
	_check_launch(t, s, [-24.752554, -31.449690, 48.410392, -62.535463, 46.668793, -1.656532], "steep slope")
	var b := t.launch_state(LinksLaunch.Strike.new())
	_check_near(b.velocity.z, 195.679363 * 0.3048, 1e-3, "SI speed")
	_check_near(b.spin.x, -73.860581 * TAU, 1e-2, "SI backspin")


func _check_launch(t: LinksLaunch, s: LinksLaunch.Strike, want: Array, what: String) -> void:
	var l := t.launch(s)
	var got := [l[0].x, l[0].y, l[0].z, l[1].x, l[1].y, l[1].z]
	for i in 6:
		_check_near(got[i], want[i], 2e-3, "%s [%d]" % [what, i])


func _test_links_ground_matches_olcore() -> void:
	# The game's green options, as test_links_green.
	var greens := [
		[1, 1, 0.10538], [1, 2, 0.09], [1, 0, 0.12076], [2, 2, 0.07462], [0, 0, 0.13614], [2, 0, 0.10538],
	]
	for c in greens:
		_check_near(LinksGround.green_for(c[0], c[1]).roll_resistance, c[2], 1e-6, "green %s" % [c])
	_check_near(LinksGround.green_for(2, 1).spin_grip, 1.3, 1e-6, "firm greens grip")
	_check_near(LinksGround.green_for(0, 1).restitution, 0.21, 1e-6, "soft greens bounce less")
	var rng := LinksGround.Rng.new()
	_check(rng.next_u32() == 0x79a8b120, "first random number")
	_check(rng.state == 0x65b8545c, "random state")
	_check(rng.next_u32() == 0xe8a8769a, "second random number")
	_check(LinksGround.Rng.seed_for(12.7, -3.2) == 0xffffffdc, "seed")
	_check(LinksGround.Rng.seed_for(0.5, 100) == 0x12345678, "zero seed")

	var b := _links_ball(Vector3(0, 0, 0.07), Vector3(0, 40, -40), Vector3(100, 0, 0), LinksGround.Mode.FLIGHT)
	LinksGround.impact(b, Vector3(0, 0, 1), LinksGround.surface_for_class(LinksGround.FAIRWAY))
	_check_near(b.velocity.y, 16.3559, 2e-3, "fairway bounce along")
	_check_near(b.velocity.z, 10.6632, 2e-3, "fairway bounce up")
	_check_near(b.spin.x, 62.2534, 2e-3, "fairway bounce spin")
	b = _links_ball(Vector3(0, 0, 0.07), Vector3(0, 30, -45), Vector3(150, 0, 0), LinksGround.Mode.FLIGHT)
	LinksGround.impact(b, Vector3(0, 0, 1), LinksGround.surface_for_class(LinksGround.GREEN))
	_check_near(b.velocity.y, 9.5844, 2e-3, "green bounce along")
	_check_near(b.spin.x, 119.3187, 2e-3, "green bounce spin")
	b = _links_ball(Vector3(12.3, 40.7, 0.07), Vector3(5, 40, -30), Vector3(60, 0, 0), LinksGround.Mode.FLIGHT)
	LinksGround.impact(b, Vector3(0, 0, 1), LinksGround.surface_for_class(LinksGround.ROUGH))
	_check_near(b.velocity.x, 1.3239, 2e-3, "rough bounce turns")
	_check_near(b.spin.y, -2.7779, 2e-3, "rough bounce spin")
	_check_near(LinksGround.contact_time(Vector3(0, 2, -3), Vector3(0, 1.5, -3.5), 0.7), 0.72827, 1e-4, "contact time")

	# Float vectors here, so allow a step either way.
	b = _links_ball(Vector3(0, 0, 0.07), Vector3(0, 45, 0), Vector3(-102.3, 0, 0), LinksGround.Mode.ROLL)
	_check(absi(_run_links_ball(b, TestLinksGround.new(LinksGround.FAIRWAY), rng) - 382) <= 1, "fast roll stops")
	_check_near(b.position.y, 119.867, 0.02, "fast roll distance")
	b = _links_ball(Vector3(0, 0, 0.07), Vector3(2, 25, 0), Vector3(30, 0, 10), LinksGround.Mode.SKID)
	_check(absi(_run_links_ball(b, TestLinksGround.new(LinksGround.GREEN, 0.03, -0.02), rng) - 334) <= 1, "sloping green stops")
	_check_near(b.position.y, 47.457, 0.02, "sloping green distance")
	b = _links_ball(Vector3(0, 0, 0.07), Vector3(0, 15, 0), Vector3(-34.1, 0, 0), LinksGround.Mode.ROLL)
	_check(absi(_run_links_ball(b, TestLinksGround.new(LinksGround.FAIRWAY, 0.0, 0.0, true), rng) - 155) <= 1, "off the drop")
	_check_near(b.position.y, 19.705, 0.02, "off the drop distance")
	b = _links_ball(Vector3(0, 0, 0.3), Vector3(0, 40, -40), Vector3(100, 0, 0), LinksGround.Mode.FLIGHT)
	_check(absi(_run_links_ball(b, TestLinksGround.new(LinksGround.FAIRWAY), rng) - 114) <= 1, "landing stops")
	_check_near(b.position.y, 18.366, 0.02, "landing distance")
	b = _links_ball(Vector3(0, 0, 0.07), Vector3(0, 20, 0), Vector3(-45.47, 0, 0), LinksGround.Mode.ROLL)
	_check(absi(_run_links_ball(b, TestLinksGround.new(LinksGround.ROUGH), rng) - 138) <= 1, "rough hops stop")
	# Each hop flies on from a slightly different float, so the spread grows.
	_check_near(b.position.x, -2.594, 0.3, "rough hops across")
	_check_near(b.position.y, 19.371, 0.5, "rough hops distance")
	var rocks := LinksGround.Rng.new(0x65b8545c)
	b = _links_ball(Vector3(0, 0, 0.07), Vector3(0, 14, 0), Vector3(-31.8, 0, 0), LinksGround.Mode.ROLL)
	_check(absi(_run_links_ball(b, TestLinksGround.new(LinksGround.ROCKS), rocks) - 74) <= 1, "rocks stop")
	_check_near(b.position.y, 2.761, 0.02, "rocks distance")

	var aero := LinksAero.from_exe(_synthetic_aero_exe())
	var putt := BallPhysics.simulate_shot(BallState.new(Vector3.ZERO, Vector3(0, 0, 3.55)), FlatTerrain.new(Surface.Type.GREEN), true, Vector3(0, 0, 3), Vector3.ZERO, aero)
	_check(putt.outcome == ShotResult.Outcome.HOLED, "links putt drops")
	# Links 2003's own putt (power 10) starts on the ground with backspin as
	# fast as rolling: it skids, then rolls about 28 ft on a flat green.
	var v_fps := 10.0 * LinksLaunch.PUTT_SPEED
	var lp := BallState.new(Vector3.ZERO, Vector3(0, 0, v_fps / LinksLaunch.FEET_PER_METRE), Vector3(-v_fps * 2.273642507507853 * TAU, 0, 0))
	lp.on_ground = true
	var lr := BallPhysics.simulate_shot(lp, FlatTerrain.new(Surface.Type.GREEN), false, Vector3.ZERO, Vector3.ZERO, aero)
	_check(lr.outcome == ShotResult.Outcome.REST and lr.bounces == 0, "links putt rolls without bouncing")
	_check_near(lr.total_m, 27.84 / LinksLaunch.FEET_PER_METRE, 0.03, "links putt length")
	var pw := BallPhysics.simulate_shot(BallPhysics.make_launch(40.0, 25.0, 0.0, 8000.0, 0.0), FlatTerrain.new(Surface.Type.FAIRWAY), false, Vector3.ZERO, Vector3.ZERO, aero)
	_check(pw.outcome == ShotResult.Outcome.REST and pw.bounces >= 1 and pw.total_m > pw.carry_m, "links wedge lands and rolls")


func _test_links_flight_matches_olcore() -> void:
	var aero := LinksAero.from_exe(_synthetic_aero_exe())
	_check(aero != null, "finds the coefficient tables")
	if aero == null:
		return
	_check_near(LinksAero.coefficient(aero.drag, 45, 15), 0.2165, 1e-6, "drag lookup")
	_check_near(LinksAero.coefficient(aero.lift, 45, 15), 0.015, 1e-6, "lift lookup")
	_check_near(LinksAero.coefficient(aero.drag, -5, 500), 0.213, 1e-6, "clamped lookup")
	var zeros := PackedByteArray()
	zeros.resize(400)
	_check(LinksAero.from_exe(zeros) == null, "no tables in zeros")
	var still := aero.step_flight(BallState.new(Vector3(0, 10, 0), Vector3.ZERO, Vector3.ZERO), 0.5, Vector3.ZERO)
	_check_near(still.velocity.y, -32.152 * 0.3048 * 0.5, 1e-6, "gravity")
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY)
	var launch := Swing.launch_from_swing(_club("7i"), 1.0, 0.0, 0.0, Surface.Type.FAIRWAY)
	var calm := BallPhysics.simulate_shot(launch, fairway, false, Vector3.ZERO, Vector3.ZERO, aero)
	var head := BallPhysics.simulate_shot(launch, fairway, false, Vector3.ZERO, Vector3(0, 0, -8), aero)
	print("  links 7i: carry %.2f m, apex %.2f m, headwind carry %.2f m" % [calm.carry_m, calm.apex_m, head.carry_m])
	_check_near(calm.carry_m, 151.23, 1.0, "links carry")
	_check_near(calm.apex_m, 15.57, 0.3, "links apex")
	_check_near(head.carry_m, 146.87, 1.0, "links headwind carry")


func _test_wind_conditions() -> void:
	var off := Wind.new(Wind.Level.OFF, 7)
	_check(off.velocity() == Vector3.ZERO and off.describe(0.0) == "calm", "no wind when off")
	var a := Wind.new(Wind.Level.STRONG, 7)
	var b := Wind.new(Wind.Level.STRONG, 7)
	_check(a.velocity() == b.velocity(), "same seed, same wind")
	for i in 20:
		a.start_hole()
		a.next_shot()
		var mph := a.speed_mph()
		_check(mph >= 25.0 * Wind.MIN_FRACTION * 0.85 - 1e-6 and mph <= 25.0 * 1.15 + 1e-6, "strong wind in range: %.1f mph" % mph)
		_check_near(a.velocity().length(), a.speed_mps, 1e-5, "velocity matches speed")
	var light := a.speed_mph()
	a.set_level(Wind.Level.LIGHT)
	_check_near(a.speed_mph(), light * 8.0 / 25.0, 1e-4, "level change rescales the wind")
	a.towards_deg = 0.0
	_check(a.describe(0.0).ends_with("helping"), "tailwind described as helping")
	_check(a.describe(180.0).ends_with("against"), "headwind described as against")
	_check(a.describe(-90.0).ends_with("right to left"), "blowing to the left of the aim")
	_check(a.describe(90.0).ends_with("left to right"), "blowing to the right of the aim")


func _test_object_library_chain() -> void:
	var chain := ObjectLibraryChain.new(PlaceholderObjectLibrary.new(), PlaceholderObjectLibrary.new(), {"alias": "tree_pine"})
	var aliased := chain.instantiate("alias")
	_check(aliased != null and aliased.name == "tree_pine", "alias reaches the primary")
	var direct := chain.instantiate("tree_broadleaf")
	_check(direct != null, "plain id")
	_check(chain.instantiate("no_such_object") == null, "unknown id gives null")
	for n in [aliased, direct]:
		if n:
			n.free()


func _test_free_assets() -> void:
	_check(Materials.terrain_weights(Surface.Type.SAND) == Vector2(0, 1), "sand uses the sand texture")
	_check(Materials.terrain_weights(Surface.Type.DEEP_ROUGH) == Vector2(1, 0), "deep rough uses the rough texture")
	_check(Materials.terrain_weights(Surface.Type.GREEN) == Vector2.ZERO, "greens use the grass texture")
	var textured: bool = Materials.terrain().get_shader_parameter("textured") == true
	_check(textured == FreeAssets.has_grounds(), "terrain textured exactly when the free textures are there")
	print("free assets: ground textures %s, sky %s" % [FreeAssets.has_grounds(), FreeAssets.sky() != null])


func _test_web_game_files() -> void:
	var files := {
		"OBJECT.LIB": 143877, "PREDEF_1.SSF": 741000, "LinksMMIII.exe": 5000000, "StdTerrain.lib": 26651491,
		"TOURNA_1.SSF": 83703038, "Courses/Cabo.crz": 103656595, "Sounds/Ambient/Birds.wav": 10000,
		"POLYANI/CLUBS.L3": 583012, "POLYANI/ERIC.L3": 10959576, "POLYANI/ANNIKA_1.L3": 8994096,
		"Object/Tall Trees/Tall Trees100.btx": 50000,
	}
	var startup := WebGameFiles.startup_files(files, "")
	startup.sort()
	_check(", ".join(startup) == "LinksMMIII.exe, OBJECT.LIB, POLYANI/ANNIKA_1.L3, POLYANI/CLUBS.L3, PREDEF_1.SSF, StdTerrain.lib",
		"startup set: catalog, sounds, course key, ground textures, first golfer and clubs; got %s" % [startup])
	_check(WebGameFiles.startup_files(files, "eric.l3").has("POLYANI/ERIC.L3"), "the chosen golfer is copied")
	_check(not startup.has("TOURNA_1.SSF"), "no disc sounds by default")
	files["SOUNDS.LS"] = 9000000
	files["POLYANI/MALE1_1.SSF"] = 4000000
	files["POLYANI/ERIC_1.SSF"] = 4000000
	var full := WebGameFiles.startup_files(files, "eric.l3", true)
	_check(full.has("TOURNA_1.SSF") and full.has("SOUNDS.LS"), "disc sounds: crowd and menu sounds copied")
	_check(full.has("POLYANI/ERIC_1.SSF") and full.has("POLYANI/MALE1_1.SSF"), "disc sounds: the golfer's and the default voice; got %s" % [full])
	_check(GraphicsSettings.disc_sounds(), "desktop always uses the disc sounds")
	_check(not WebGameFiles.is_supported(), "not the web build")
	_check(FileAccess.file_exists(WebGameFiles.SCRIPT_PATH), "browser bridge script is in the project")


func _test_full_round() -> void:
	var game := _game
	_check(game.is_node_ready(), "game scene is ready")
	if not game.is_node_ready():
		return
	var steps := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 600:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.ROUND_DONE, "round finishes")
	var line := "  card:"
	for i in game.card.strokes.size():
		var s := game.card.strokes[i]
		line += " %d" % s
		_check(s >= 1 and s <= GolfRound.MAX_STROKES, "hole %d strokes %d" % [i + 1, s])
	print(line + "  total %d (%s)" % [game.card.total_strokes(), Scorecard.format_to_par(game.card.to_par())])
	# Without game files the round plays the free recordings.
	_check(game.sounds is FreeSoundBank, "free sound bank without game files")
	_check(game.free_ambience != null and game.free_ambience.get_child_count() == 3, "free ambience beds")
	var before := game.sounds.get_child_count()
	game.sounds.play_detail(&"hit", {"club": _club("Dr"), "lie": Surface.Type.ROUGH, "power": 1.0})
	game.sounds.play_detail(&"land", {"surface": Surface.Type.SAND, "speed": 15.0})
	_check(game.sounds.get_child_count() == before + 3, "driver from the rough plays strike and grass, sand landing plays")


## The full round was recorded and plays again to the same card; a changed
## shot, card or seed is caught.
func _test_round_replay() -> void:
	var game := _game
	if not game.is_node_ready() or game.record == null:
		_check(false, "the full round has a record")
		return
	var rec := game.record
	_check(rec.finished and rec.round_seed == 20031 and rec.shots.size() >= 9, "record of the full round: %d shots" % rec.shots.size())
	_check(rec.cards.size() == 1 and str(rec.cards[0]) == str(game.card.strokes), "record keeps the card")
	var ok := RoundReplay.verify(rec, game.shot_model, game.clubs, game.holes)
	_check(ok.ok and ok.cards_checked and ok.checked == rec.shots.size(), "the round replays: %s" % [ok.errors])
	var files := DirAccess.get_files_at(ProjectSettings.globalize_path(RoundRecord.folder))
	_check(files.size() >= 1, "the round is saved in the replays folder")
	var path := RoundRecord.folder + "/" + files[files.size() - 1]
	var loaded := RoundRecord.load_file(path)
	_check(loaded != null and loaded.shots.size() == rec.shots.size(), "the saved round loads")
	if loaded != null:
		var again := RoundReplay.verify(loaded, game.shot_model, game.clubs, game.holes)
		_check(again.ok, "the saved round replays: %s" % [again.errors])
	print("  %d shots, %d bytes as JSON" % [rec.shots.size(), rec.to_json().length()])
	# A longer drive than the swing gave.
	var tampered := RoundRecord.from_json(rec.to_json())
	tampered.shots[0].power = minf(tampered.shots[0].power + 0.15, 1.0) if tampered.shots[0].power < 0.9 else tampered.shots[0].power - 0.15
	_check(not RoundReplay.verify(tampered, game.shot_model, game.clubs, game.holes).ok, "a changed swing is caught")
	# A better score than the shots make.
	tampered = RoundRecord.from_json(rec.to_json())
	tampered.cards[0][0] = int(tampered.cards[0][0]) - 1
	_check(not RoundReplay.verify(tampered, game.shot_model, game.clubs, game.holes).ok, "a changed card is caught")
	# Kinder wind from another seed.
	if rec.wind_level != Wind.Level.OFF:
		tampered = RoundRecord.from_json(rec.to_json())
		tampered.round_seed = 777
		_check(not RoundReplay.verify(tampered, game.shot_model, game.clubs, game.holes).ok, "a different wind seed is caught")
	tampered = RoundRecord.from_json(rec.to_json())
	tampered.resumed = true
	_check(not RoundReplay.verify(tampered, game.shot_model, game.clubs, game.holes).ok, "a resumed round can't be checked")
	_check(RoundRecord.shot_seed(5, 3, 1) == RoundRecord.shot_seed(5, 3, 1), "shot seeds repeat")
	_check(RoundRecord.shot_seed(5, 3, 1) != RoundRecord.shot_seed(5, 3, 2) and RoundRecord.shot_seed(5, 3, 1) != RoundRecord.shot_seed(5, 4, 1), "shot seeds differ by shot and source")
	for f in files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RoundRecord.folder + "/" + f))
	_test_result_codes(game, rec)


## A result code carries the round to a friend, whose game checks it and plays
## the same course and wind.
func _test_result_codes(game: GolfRound, rec: RoundRecord) -> void:
	var code := rec.to_code()
	print("  result code: %d characters" % code.length())
	_check(code.begins_with(RoundRecord.CODE_PREFIX) and code.length() < 12000, "a result code is short enough to paste")
	var back := RoundRecord.from_code(" " + code.substr(0, 40) + "\n" + code.substr(40) + " ")
	_check(back != null and back.shots.size() == rec.shots.size() and back.round_seed == rec.round_seed, "the code survives spaces and line breaks")
	_check(RoundRecord.from_code("hello") == null and RoundRecord.from_code(RoundRecord.CODE_PREFIX + "!!!") == null, "junk isn't a code")
	_check(rec.summary().begins_with("Player 1 "), "summary names the player: %s" % rec.summary())
	if back != null:
		var answer := RoundReplay.check(back, game.course_path)
		_check(answer.ok and answer.course_ok, "a friend's game checks the code: %s" % [answer.errors])
	# The setup page reads the code and plays against it.
	var panel := RoundSetupPanel.new()
	root.add_child(panel)
	panel.open(PackedStringArray(["Placeholder Nine (built in)"]), 0, RoundSetup.new())
	panel._code.text = code
	panel._open_code()
	_check(panel.current_setup().challenge != null, "the setup page takes the code")
	_check(panel._challenge_info.text.contains("Checked"), "the setup page checks it: %s" % panel._challenge_info.text)
	panel._code.text = "not a code"
	panel._open_code()
	_check(panel.current_setup().challenge == null and panel._challenge_info.visible, "the setup page refuses junk")
	panel.queue_free()
	# Playing against it: their seed and wind level, whatever the settings say.
	var versus := RoundRecord.from_json(rec.to_json())
	versus.round_seed = 4243
	versus.wind_level = Wind.Level.STRONG
	var setup := RoundSetup.single("")
	setup.challenge = versus
	GolfRound.setup = setup
	game.start_round()
	_check(game.round_seed == 4243 and game.wind.level == Wind.Level.STRONG and game.record.wind_level == Wind.Level.STRONG,
		"a challenge round plays the friend's seed and wind")
	GolfRound.setup = null


## The free recordings: every event has takes, the ambience loops, and clubs
## and course names map as intended.
func _test_free_sounds() -> void:
	var bank := FreeSoundBank.new()
	for event: StringName in FreeSoundBank.STEMS:
		var takes := bank.takes(FreeSoundBank.STEMS[event])
		_check(not takes.is_empty(), "takes for %s" % event)
		for t: AudioStream in takes:
			_check(t is AudioStreamOggVorbis and t.get_length() > 0.1 and t.get_length() < 12.0,
				"%s take is a short OGG" % event)
	for kind in ["driver", "wood", "iron", "wedge"]:
		_check(not bank.takes("hit_" + kind).is_empty(), "strike for " + kind)
	bank.free()
	var kinds := {"Dr": &"driver", "3W": &"wood", "5W": &"wood", "3H": &"wood", "4i": &"iron", "9i": &"iron",
		"PW": &"wedge", "SW": &"wedge", "LW": &"wedge", "Pt": &"putter"}
	for c in Club.standard_set():
		_check(SoundBank.club_kind(c) == kinds.get(c.short_name, &"iron"), "%s strikes as %s" % [c.short_name, kinds.get(c.short_name, &"iron")])
	for stem: String in FreeAmbience.BEDS.values() + ["amb_breeze", "amb_water"]:
		var s := load("res://assets/sounds/%s.ogg" % stem) as AudioStreamOggVorbis
		_check(s != null and s.get_length() > 20.0, "%s is a long loop" % stem)
	_check(load(MenuSounds.FREE_CLICK) is AudioStream, "free menu click")
	_check(FreeAmbience.setting_for("Placeholder Nine") == FreeAmbience.Setting.PARKLAND, "parkland by default")
	_check(FreeAmbience.setting_for("Kiawah Island Ocean Course") == FreeAmbience.Setting.SEASIDE, "seaside")
	_check(FreeAmbience.setting_for("Desert Mountain") == FreeAmbience.Setting.DESERT, "desert before mountain")
	_check(FreeAmbience.setting_for("Pine Valley") == FreeAmbience.Setting.WOODLAND, "woodland")


## An unplayable lie and a water drop through the real round.
func _test_drops_in_round() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	GolfRound.setup = null
	game.start_round()
	var steps := 0
	while not (game.state == GolfRound.State.AIM and game.lie != Surface.Type.TEE and game.lie != Surface.Type.GREEN) and steps < 50:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.AIM, "off the tee and aiming")
	var before := game.strokes
	game._start_drop(DropRules.Reason.UNPLAYABLE)
	_check(game.state == GolfRound.State.DROP, "unplayable opens the drop menu")
	_check(game._drop_zones.size() == 3, "three unplayable options")
	game._move_drop(1.0, 0.0)
	game.auto_play_step()
	_check(game.state == GolfRound.State.AIM, "back to aiming after the drop")
	_check(game.strokes == before + 1, "an unplayable lie costs a stroke")
	game._water_entry = game.ball_at
	game._begin_drop(DropRules.Reason.WATER)
	_check(game.state == GolfRound.State.DROP, "water opens the drop menu")
	game._cancel_drop()
	_check(game.state == GolfRound.State.DROP, "a water drop can't be cancelled")
	game._finish_drop()
	_check(game.state == GolfRound.State.AIM, "playing on after the water drop")
	_check(game.strokes == before + 1, "the water penalty is counted at the splash, not the drop")
	var drops := game.record.drops
	_check(drops.size() == 2 and int(drops[0].penalty) == 1 and int(drops[1].penalty) == 0, "drops recorded with their penalties: %s" % [drops])
	var replay := RoundReplay.verify(game.record, game.shot_model, game.clubs, game.holes)
	_check(replay.ok and replay.checked == game.record.shots.size(), "the shots before the drops replay: %s" % [replay.errors])


## The MakeHuman golfer used without the original files.
func _test_free_golfer() -> void:
	var golfer := FreeGolfer.create()
	_check(golfer != null, "free_golfer.glb loads with an AnimationPlayer")
	if golfer == null:
		return
	for anim_name in [&"address", &"address_putt", &"backswing", &"swing", &"putt", &"celebrate", &"upset", &"walk", &"idle", &"read"]:
		_check(golfer.has_animation(anim_name), "free golfer has %s" % anim_name)
	var made := PlaceholderGolferAssets.new().create_golfer()
	_check(made is FreeGolfer, "the placeholder assets use the free golfer")
	made.free()
	golfer.play(&"putt")
	golfer.play(&"address")
	golfer.free()


## Hot-seat rounds through the real round: skins over the front nine for three
## players, and a match that can end early.
## The practice range: the ball comes back to the tee, nothing is scored,
## and the launch monitor reads every shot.
func _test_practice_range() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var s := RoundSetup.new()
	s.practice = true
	_check(s.problem().is_empty(), "one person can practise")
	s.names = _strs(["Ann", "Bob"])
	s.teams = _ints([0, 1])
	s.computer = _ints([RoundSetup.HUMAN, RoundSetup.HUMAN])
	_check(not s.problem().is_empty(), "the range is for one person")
	s = RoundSetup.new()
	s.practice = true
	GolfRound.setup = s
	game.start_round()
	_check(game.monitor_panel != null, "the launch monitor is up")
	var tee: Vector3 = game.hole.tee
	for i in 6:
		var steps := 0
		while game.state != GolfRound.State.AIM or steps == 0:
			game.auto_play_step()
			steps += 1
			if steps > 10:
				break
		_check(game.state == GolfRound.State.AIM and game.ball_at.distance_to(tee) < 0.01, "shot %d: the ball is back on the tee" % i)
	_check(game.practice_session.readings.size() == 6, "six readings (%d)" % game.practice_session.readings.size())
	_check(game.card.holes_played() == 0, "nothing is scored")
	var r: LaunchMonitor.Reading = game.practice_session.readings[0]
	_check(r.ball_mph > 60.0 and r.ball_mph < 200.0, "ball speed %.0f mph" % r.ball_mph)
	_check(r.launch_deg > 2.0 and r.launch_deg < 40.0, "launch %.1f deg" % r.launch_deg)
	_check(r.back_rpm > 500.0, "back spin %.0f rpm" % r.back_rpm)
	_check(r.carry_yd > 50.0 and r.total_yd >= r.carry_yd - 1.0, "carry %.0f, total %.0f yd" % [r.carry_yd, r.total_yd])
	_check(r.descent_deg > 5.0 and r.descent_deg < 80.0, "descent %.0f deg" % r.descent_deg)
	_check(not game.practice_session.summary(r.club).is_empty(), "session summary")
	print("  range: %s" % game.practice_session.summary(r.club))
	GolfRound.setup = null


## Gimmes: short putts are conceded for a stroke, and the round still
## replays to the same card.
func _test_gimmes() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	game.graphics.gimme = 3
	GolfRound.setup = RoundSetup.new()
	game.start_round()
	var steps := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 600:
		game.auto_play_step()
		steps += 1
	game.graphics.gimme = 0
	_check(game.state == GolfRound.State.ROUND_DONE, "round with gimmes finishes")
	var gimmes := 0
	for d in game.record.drops:
		if d.get("gimme", false):
			gimmes += 1
	_check(gimmes >= 1, "some putts were conceded (%d)" % gimmes)
	var ok := RoundReplay.verify(game.record, game.shot_model, game.clubs, game.holes)
	_check(ok.ok and ok.cards_checked, "a round with gimmes replays: %s" % [ok.errors])
	print("  gimmes: %d, card %s" % [gimmes, str(game.card.strokes)])
	GolfRound.setup = null


## OpenConnect: messages split from a stream, read into a launch, flown the
## right way, sent over a real socket, and played and replayed in a round.
func _test_launch_monitor_input() -> void:
	var shot_msg := {"DeviceID": "Test LM", "Units": "Yards", "ShotNumber": 1, "APIversion": "1",
		"BallData": {"Speed": 120.0, "SpinAxis": 4.0, "TotalSpin": 6500.0, "HLA": 2.0, "VLA": 17.0},
		"ShotDataOptions": {"ContainsBallData": true, "IsHeartBeat": false}}
	var beat := {"DeviceID": "Test LM", "ShotDataOptions": {"ContainsBallData": false, "IsHeartBeat": true}}
	var text := JSON.stringify(beat) + JSON.stringify(shot_msg)
	var split := OpenConnect.split_messages(text.substr(0, text.length() - 5))
	_check((split[0] as Array).size() == 1 and (split[1] as String).length() > 0, "a part message waits for the rest")
	split = OpenConnect.split_messages(split[1] + text.substr(text.length() - 5))
	_check((split[0] as Array).size() == 1 and (split[1] as String).is_empty(), "then it completes")
	_check(OpenConnect.launch_of(beat) == null, "heartbeats are not shots")
	var l := OpenConnect.launch_of(split[0][0])
	_check(l != null and l.speed_mph == 120.0 and l.vla_deg == 17.0 and l.total_rpm == 6500.0, "ball data read")
	var bs := {"BallData": {"Speed": 100.0, "BackSpin": 3000.0, "SideSpin": -400.0, "HLA": 0.0, "VLA": 20.0}}
	var l2 := OpenConnect.launch_of(bs)
	_check(l2 != null and absf(l2.total_rpm - Vector2(3000, 400).length()) < 0.01 and l2.axis_deg < 0.0, "back and side spin read")
	# HLA right starts it right (-x); a positive spin axis curves it further right.
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY)
	var right := BallPhysics.simulate_shot(OpenConnect.ball_state(l, 0.0), fairway)
	var start := OpenConnect.ball_state(l, 0.0)
	_check(start.velocity.x < 0.0, "HLA right starts right")
	_check(right.rest.x < start.velocity.x / start.velocity.z * right.rest.z, "a positive spin axis curves right")
	_check_near(start.velocity.length(), 120.0 * OpenConnect.MPS_PER_MPH, 1e-4, "ball speed")
	var straight := OpenConnect.Launch.from_array([120.0, 17.0, 0.0, 6500.0, 0.0])
	var carry := BallPhysics.simulate_shot(OpenConnect.ball_state(straight, 0.0), fairway).carry_m * 1.0936
	_check(carry > 140.0 and carry < 185.0, "a 120 mph 7-iron-like launch carries %.0f yd" % carry)
	# Over a socket.
	var server := OpenConnectServer.new()
	root.add_child(server)
	_check(server.start(19210), "server listens")
	var got: Array = []
	server.shot_received.connect(func(x: OpenConnect.Launch) -> void: got.append(x))
	var client := StreamPeerTCP.new()
	client.connect_to_host("127.0.0.1", 19210)
	var reply := ""
	for _i in 200:
		client.poll()
		server._process(0.0)
		if client.get_status() == StreamPeerTCP.STATUS_CONNECTED and got.is_empty() and reply.is_empty():
			client.put_data(JSON.stringify(shot_msg).to_utf8_buffer())
		if client.get_available_bytes() > 0:
			reply += (client.get_partial_data(client.get_available_bytes())[1] as PackedByteArray).get_string_from_utf8()
		if not got.is_empty() and reply.contains("200"):
			break
		OS.delay_msec(5)
	_check(got.size() == 1, "the shot came over the socket")
	_check(reply.contains("\"Code\":200"), "and was answered: %s" % reply)
	client.disconnect_from_host()
	server.stop()
	server.queue_free()
	# In a round: played as measured, recorded, and replayed.
	var game := _game
	if not game.is_node_ready():
		return
	GolfRound.setup = RoundSetup.new()
	game.start_round()
	game.camera.end_flyover()
	game._on_monitor_shot(OpenConnect.Launch.from_array([150.0, 11.0, 0.0, 2800.0, 0.0]))
	_check(game.state == GolfRound.State.FLIGHT, "the monitor's shot is in the air")
	var rec: ShotRecord = game.record.shots.back()
	_check(rec.monitor.size() == 5 and ShotRecord.from_dict(rec.to_dict()).monitor == rec.monitor, "recorded as measured")
	var ok := RoundReplay.verify(game.record, game.shot_model, game.clubs, game.holes)
	_check(ok.ok and ok.checked == 1, "the monitor's shot replays: %s" % [ok.errors])
	GolfRound.setup = null


func _test_multiplayer_rounds() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var s := RoundSetup.new()
	s.names = _strs(["Ann", "Bob", "Cy"])
	s.teams = _ints([0, 1, 0])
	s.mode = GameModes.Mode.SKINS
	GolfRound.setup = s
	game.start_round()
	_check(game.players.size() == 3, "three players")
	_check(game.honour == _ints([0, 1, 2]), "first hole in player order")
	_check(not game.hud.hand_over.visible, "no hand-over before the first shot")
	var steps := 0
	var hand_overs := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 2000:
		game.auto_play_step()
		steps += 1
		if game.hud.hand_over.visible:
			hand_overs += 1
			_check(game.state == GolfRound.State.AIM, "the hand-over waits on a person's shot")
	_check(game.state == GolfRound.State.ROUND_DONE, "skins round finishes")
	_check(hand_overs >= game.holes.size() * 2, "the controls are handed over between people (%d)" % hand_overs)
	var won := 0
	var sk := GameModes.skins(game.scoring.strokes_table())
	for i in 3:
		_check(game.scoring.cards[i].holes_played() == game.holes.size(), "player %d played every hole" % i)
		won += sk.skins[i]
	_check(won + sk.carried == game.holes.size(), "every skin is won or carried")
	print("  skins: %s" % game.scoring.status_text())

	s = RoundSetup.new()
	s.names = _strs(["Ann", "Bob"])
	s.teams = _ints([0, 1])
	s.mode = GameModes.Mode.MATCH
	s.holes = RoundSetup.Holes.FRONT_NINE
	GolfRound.setup = s
	game.start_round()
	steps = 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 2000:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.ROUND_DONE, "match finishes")
	var m := game.scoring.match_status()
	_check(m.finished, "match is decided at the end: %s" % m)
	print("  match: %s after %d holes" % [game.scoring.winner_text(), m.played])
	GolfRound.setup = null


## Computer golfers through the real round: a tour pro and a weekend golfer
## play nine holes on their own, then a person (the test's auto-play) plays a
## match against a club golfer.
func _test_computer_opponents() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var s := RoundSetup.new()
	s.names = _strs(["Pro", "Hacker"])
	s.teams = _ints([0, 1])
	s.computer = _ints([OpponentSkill.Level.TOUR, OpponentSkill.Level.BEGINNER])
	GolfRound.setup = s
	game.start_round()
	_check(game.state == GolfRound.State.COMPUTER, "a computer golfer is on the tee")
	var started := Time.get_ticks_msec()
	var steps := 0
	var worst := 0
	var worst_log := PackedStringArray()
	while game.state != GolfRound.State.ROUND_DONE and steps < 2000:
		game.auto_play_step()
		steps += 1
		if game.state == GolfRound.State.HOLE_DONE and game.players[0].strokes > worst:
			worst = game.players[0].strokes
			worst_log = game.shot_log.duplicate()
	_check(game.state == GolfRound.State.ROUND_DONE, "computer round finishes")
	print("  the tour pro's worst hole:\n    " + "\n    ".join(worst_log))
	var pro := game.scoring.cards[0]
	var hacker := game.scoring.cards[1]
	_check(pro.holes_played() == game.holes.size() and hacker.holes_played() == game.holes.size(), "both played every hole")
	print("  tour pro %s: %d (%s)   weekend golfer %s: %d (%s)   %.1f s" % [
		pro.strokes, pro.total_strokes(), Scorecard.format_to_par(pro.to_par()),
		hacker.strokes, hacker.total_strokes(), Scorecard.format_to_par(hacker.to_par()),
		(Time.get_ticks_msec() - started) / 1000.0])
	_check(pro.total_strokes() < hacker.total_strokes(), "the tour pro beats the weekend golfer")
	_check(pro.to_par() <= 6, "the tour pro plays near par (%s)" % Scorecard.format_to_par(pro.to_par()))

	s = RoundSetup.new()
	s.names = _strs(["Ann", "Club"])
	s.teams = _ints([0, 1])
	s.computer = _ints([RoundSetup.HUMAN, OpponentSkill.Level.CLUB])
	s.mode = GameModes.Mode.MATCH
	GolfRound.setup = s
	game.start_round()
	_check(game.state == GolfRound.State.AIM, "the person tees off first")
	steps = 0
	var computer_turns := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 2000:
		if game.state == GolfRound.State.COMPUTER:
			computer_turns += 1
			_check(game.current == 1, "only the computer seat plays itself")
		_check(not game.hud.hand_over.visible, "one person against the computer needs no hand-over")
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.ROUND_DONE and computer_turns > 0, "match against the computer finishes")
	print("  match: %s" % game.scoring.winner_text())
	GolfRound.setup = null


## Scramble and alternate shot through the real round, with people (the
## test's auto-play) and computer golfers on both teams.
func _test_team_ball_modes() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	for mode: int in [GameModes.Mode.SCRAMBLE, GameModes.Mode.ALTERNATE_SHOT]:
		var mode_name: String = GameModes.MODE_NAMES[mode]
		var s := RoundSetup.new()
		s.names = _strs(["Ann", "Bob", "Cy", "Di"])
		s.teams = _ints([0, 1, 0, 1])
		s.computer = _ints([RoundSetup.HUMAN, RoundSetup.HUMAN, OpponentSkill.Level.TOUR, OpponentSkill.Level.CLUB])
		s.holes = RoundSetup.Holes.FRONT_NINE
		s.mode = mode as GameModes.Mode
		GolfRound.setup = s
		game.start_round()
		_check(game.ball_of == _ints([0, 1, 0, 1]), "%s: one ball per team" % mode_name)
		_check(game.honour == _ints([0, 1]), "%s: teams tee off in order" % mode_name)
		var hitters := {}
		var steps := 0
		while game.state != GolfRound.State.ROUND_DONE and steps < 3000:
			if game.state == GolfRound.State.AIM or game.state == GolfRound.State.COMPUTER:
				_check(game.current == 0 or game.current == 1, "%s: only the team balls are played" % mode_name)
				_check(game.ball_of[game.shooter] == game.current, "%s: the shooter is on the ball's team" % mode_name)
				hitters[game.shooter] = true
			game.auto_play_step()
			steps += 1
		_check(game.state == GolfRound.State.ROUND_DONE, "%s round finishes" % mode_name)
		_check(hitters.size() == 4, "%s: everyone hit: %s" % [mode_name, hitters.keys()])
		for t in 2:
			var members := game.scoring.team_members(t)
			_check(game.scoring.cards[members[0]].strokes == game.scoring.cards[members[1]].strokes, "%s: partners share the team score" % mode_name)
			_check(game.scoring.cards[members[0]].holes_played() == game.holes.size(), "%s: team %d played every hole" % [mode_name, t])
		print("  %s: %s" % [mode_name.to_lower(), game.scoring.winner_text()])
	GolfRound.setup = null


## Drops in the team modes: a partner's water ball in a scramble doesn't move
## the team's ball, and a person choosing the drop is asked even when the
## team's ball belongs to a computer partner.
func _test_team_drops() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var s := RoundSetup.new()
	s.names = _strs(["Ann", "Bob", "Cy", "Di"])
	s.teams = _ints([0, 1, 0, 1])
	s.computer = _ints([RoundSetup.HUMAN, RoundSetup.HUMAN, OpponentSkill.Level.TOUR, OpponentSkill.Level.CLUB])
	s.mode = GameModes.Mode.SCRAMBLE
	GolfRound.setup = s
	game.start_round()
	var tee := game.ball_at
	_check(game.state == GolfRound.State.AIM and game.current == 0 and game.shooter == 0, "scramble: Ann tees off first")
	var wet := ShotResult.new()
	wet.outcome = ShotResult.Outcome.WATER
	wet.rest = tee + Vector3(0.0, -1.0, 150.0)
	wet.first_landing = wet.rest
	wet.time_s = 5.0
	wet.add_sample(0.0, tee)
	wet.add_sample(5.0, wet.rest)
	game.shot = wet
	game.shot_from = tee
	game.players[0].shots += 1
	game._complete_flight()
	_check(not game._drop_pending, "scramble: no drop left pending for a partner's water ball")
	_check(game.ball_at.distance_to(tee) < 0.01, "scramble: the partner plays from the tee")
	var best: Dictionary = game.players[0].round_best
	_check(int(best.get("add", 0)) == 2, "scramble: the water ball counts its penalty")
	_check((best.get("at", wet.rest) as Vector3).distance_to(wet.rest) > 1.0, "scramble: the water ball is kept where it was dropped")
	game._after_result()
	_check(game.state == GolfRound.State.COMPUTER and game.shooter == 2 and game.ball_at.distance_to(tee) < 0.01, "scramble: Cy hits from the tee next")

	# A computer owns the team ball; its human partner chooses their own drop.
	s.computer = _ints([OpponentSkill.Level.TOUR, RoundSetup.HUMAN, RoundSetup.HUMAN, OpponentSkill.Level.CLUB])
	GolfRound.setup = s
	game.start_round()
	var steps := 0
	while not (game.state == GolfRound.State.AIM and game.shooter == 2) and steps < 20:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.AIM and game.current == 0 and game.shooter == 2, "scramble: Cy aims the computer-owned team ball")
	game._water_entry = game.ball_at
	game._begin_drop(DropRules.Reason.WATER)
	_check(game.state == GolfRound.State.DROP, "a person picks their drop on a computer partner's ball")
	game._process(0.0)
	_check(not game.hud.meter.visible, "drop: the meter is hidden under the drop options")
	_check(BroadcastOverlay.caption_height(4) > BroadcastOverlay.caption_height(1) + 60.0, "drop: broadcast caption stacks the options")
	game._finish_drop()
	game._process(0.0)
	_check(game.hud.meter.visible, "drop: the meter is back after the drop")
	GolfRound.setup = null


## The first tee of the placeholder course: the driver comes out, and the
## camera can see where the shot is aimed.
func _test_tee_view() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	GolfRound.setup = null
	game.start_round()
	if game.camera.flying():
		game.camera.end_flyover()
	_check(game.lie == Surface.Type.TEE and game.hole.par >= 4, "tee view: a par 4 or 5 tee")
	_check(game.club_index == 0, "tee view: the driver off the tee, not %s" % game.clubs[game.club_index].full_name)
	var reach := game._flat_distance(game.ball_at, game._aim_target())
	var far := game.ball_at + game._aim_dir() * reach
	var target := Vector3(far.x, game.hole.terrain.height_at(far.x, far.z) + 1.0, far.z)
	_check(RoundCamera.sight_clear(game.hole.terrain, game.camera._aim_pos, target), "tee view: the camera sees the target %.0f m away" % reach)


## The pause menu holds the round: the meter, the ball in flight and the
## pause after a shot all wait until it closes.
func _test_pause_stops_play() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	GolfRound.setup = null
	game.start_round()
	if game.camera.flying():
		game.camera.end_flyover()  # the broadcast hole flyover takes the first click
	game._on_swing_pressed()
	_check(game.state == GolfRound.State.SWING and game.hud.meter.is_swinging(), "pause: swinging")
	var method := game.graphics.swing_method
	game.graphics.swing_method = 1
	_check("mouse swing" in game._aim_hint(), "aim hint names the mouse swing: %s" % game._aim_hint())
	game.graphics.swing_method = 0
	_check("Space or click: swing" in game._aim_hint(), "aim hint names the meter")
	var desktop := not OS.has_feature("web")
	_check(("O: objects" in game._aim_hint()) == desktop, "aim hint offers the object viewer only off the web")
	game.graphics.swing_method = method
	game.open_pause_menu()
	game._process(0.1)
	_check(not game.hud.meter.is_processing(), "pause: the swing meter stops")
	game.pause_menu.close()
	game._process(0.01)
	_check(game.hud.meter.is_processing(), "pause: the swing meter runs again")
	game.hud.meter.reset()
	game.state = GolfRound.State.AIM
	game.play_shot(0.8, 0.0)
	_check(game.state == GolfRound.State.FLIGHT, "pause: ball in the air")
	game.open_pause_menu()
	game._process(60.0)
	_check(game.state == GolfRound.State.FLIGHT and game.shot_time == 0.0, "pause: the ball waits in the air")
	game.pause_menu.close()
	game._process(60.0)
	_check(game.state == GolfRound.State.SHOT_RESULT, "pause: the shot finishes after closing")
	game.open_pause_menu()
	game._process(60.0)
	_check(game.state == GolfRound.State.SHOT_RESULT, "pause: the turn doesn't pass while paused")
	game.pause_menu.close()


## The main menu resumes a saved round on a real course before the setup
## page has ever been opened.
func _test_menu_resume() -> void:
	var boot: Control = (load("res://scripts/boot.gd") as GDScript).new()
	var key := "Courses/TEST.crz"
	boot._course_paths = PackedStringArray(["Courses/OTHER.crz", key])
	var s := RoundSetup.new()
	s.course_key = key
	SavedRound.save(s, {"hole": 0})
	_check(boot._resume_slot() == 2, "menu: the saved course's slot")
	_check(boot._setup_paths.size() >= 2 and boot._setup_paths[1] == key, "menu: the setup list is filled for resuming")
	s.course_key = "Courses/GONE.crz"
	SavedRound.save(s, {"hole": 0})
	_check(not boot._can_resume(), "menu: no resume when the course is gone")
	s.course_key = ""
	SavedRound.save(s, {"hole": 0})
	_check(boot._resume_slot() == 0, "menu: the placeholder course resumes")
	boot.free()


## Leaving for the object or course viewer and coming back carries on with
## the round; one saved on the end-of-hole screen counts the hole once.
func _test_viewer_return() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	GolfRound.setup = null
	game.start_round()
	var steps := 0
	while game.state != GolfRound.State.HOLE_DONE and steps < 200:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.HOLE_DONE and game.hole_index == 0, "viewer: hole 1 finished")
	var stats: Dictionary = game.round_stats[0].duplicate()
	var strokes: Array = Array(game.scoring.cards[0].strokes)
	game.prepare_return()
	_check(not GolfRound.resume.is_empty(), "viewer: the round is kept to come back to")
	game.start_round()
	_check(GolfRound.resume.is_empty(), "viewer: used once")
	_check(game.state == GolfRound.State.HOLE_DONE and game.hole_index == 0, "viewer: back on the end-of-hole screen")
	_check(Array(game.scoring.cards[0].strokes) == strokes, "viewer: the card is the same")
	for key: String in stats:
		_check(int(game.round_stats[0][key]) == int(stats[key]), "viewer: %s counted once" % key)
	game.auto_play_step()
	_check(game.hole_index == 1 and game.state == GolfRound.State.AIM, "viewer: on to hole 2")
	SavedRound.clear()


## A tee shot out of bounds is played again from the tee, teed up.
func _test_retee_after_ob() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	GolfRound.setup = null
	game.start_round()
	var tee := game.ball_at
	_check(game.lie == Surface.Type.TEE, "re-tee: first shot teed up")
	var ob := ShotResult.new()
	ob.outcome = ShotResult.Outcome.OUT_OF_BOUNDS
	ob.rest = tee + Vector3(80.0, 0.0, 200.0)
	ob.first_landing = ob.rest
	ob.time_s = 5.0
	ob.add_sample(0.0, tee)
	ob.add_sample(5.0, ob.rest)
	game.shot = ob
	game.shot_from = tee
	game._complete_flight()
	game._after_result()
	_check(game.state == GolfRound.State.AIM and game.strokes == 2, "re-tee: stroke and distance")
	_check(game.lie == Surface.Type.TEE, "re-tee: the third shot is teed up too")
	SavedRound.clear()


## The full and multiplayer rounds above went into the test profiles.
func _test_rounds_recorded() -> void:
	var p := PlayerProfiles.load_saved()
	_check(p.rounds("Player 1").size() >= 1, "the full round is on Player 1's record")
	_check(p.rounds("Ann").size() >= 1, "the skins round is on Ann's record")
	for r: Dictionary in p.rounds("Player 1"):
		_check(r.holes == 9 and r.par == 36 and r.adjusted <= r.gross, "round record: %s" % r)
		# The placeholder nine has seven par 4s and 5s.
		_check(r.fairway_holes == 7 and r.fairways <= 7 and r.gir <= 9 and r.putts >= 1 and r.putts <= r.gross, "round stats: %s" % r)
	_check(not PlayerProfiles.career_text(p.career("Player 1")).is_empty(), "Player 1 has a career line")
	print("  Player 1: %s" % PlayerProfiles.career_text(p.career("Player 1")))


## A round saved part way through carries on where it stopped.
func _test_saved_round() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var s := RoundSetup.new()
	s.names = _strs(["Ann", "Bob"])
	s.teams = _ints([0, 1])
	s.handicaps = true
	s.indexes = _ints([50, 120])
	GolfRound.setup = s
	game.start_round()
	var steps := 0
	while steps < 2000 and not (game.hole_index == 1 and game.state == GolfRound.State.AIM and game.players[game.current].strokes > 0):
		game.auto_play_step()
		steps += 1
	_check(game.hole_index == 1 and game.state == GolfRound.State.AIM, "part way through hole 2")
	_check(SavedRound.exists(), "the round is saved as it goes")
	var cards: Array = []
	for c in game.scoring.cards:
		cards.append(c.strokes.duplicate())
	var balls: Array = []
	for p in game.players:
		balls.append([p.at, p.strokes, p.done()])
	var current := game.current

	var saved := SavedRound.load_setup()
	_check(saved != null and saved.names == s.names and saved.handicaps and saved.indexes == s.indexes and saved.computer == _ints([RoundSetup.HUMAN, RoundSetup.HUMAN]), "setup saved")
	_check(SavedRound.describe().contains("hole 2"), "describe: %s" % SavedRound.describe())
	GolfRound.setup = saved
	GolfRound.resume = SavedRound.load_state()
	game.start_round()
	_check(GolfRound.resume.is_empty(), "the saved state is used once")
	_check(game.hole_index == 1, "resumed on hole 2")
	_check(game.current == current, "same player to play")
	for i in 2:
		_check(game.scoring.cards[i].strokes == cards[i], "card %d restored: %s" % [i, game.scoring.cards[i].strokes])
		var p := game.players[i]
		_check(p.strokes == balls[i][1] and p.done() == balls[i][2], "ball %d strokes restored" % i)
		_check(p.at.distance_to(balls[i][0]) < 0.01, "ball %d lies where it did" % i)
	_check(game.scoring.playing == _ints([2, 6]), "handicaps restored: %s" % [game.scoring.playing])
	steps = 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 2000:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.ROUND_DONE, "resumed round finishes")
	_check(not SavedRound.exists(), "a finished round is no longer saved")
	GolfRound.setup = null


func _test_players_panel() -> void:
	var p := PlayerProfiles.load_saved()
	var panel := PlayersPanel.new()
	root.add_child(panel)
	panel.open()
	_check(panel.visible, "players page opens")
	var played := p.rounds("Ann")
	_check(played.size() >= 2, "Ann has rounds by now")
	var used := panel._used_rounds(played)
	_check(used.size() == Handicap.rounds_used(mini(played.size(), Handicap.ROUNDS)), "rounds used: %s" % [used])
	if played.size() >= 3:
		var diffs: Array[int] = []
		for i in used:
			diffs.append(int(played[i].differential))
		var lowest := p.differentials("Ann").slice(maxi(0, played.size() - Handicap.ROUNDS))
		lowest.sort()
		_check(diffs.max() <= lowest[used.size() - 1], "the starred rounds are the lowest")
	panel._on_delete("Ann")
	_check(PlayerProfiles.load_saved().has_player("Ann"), "the first press only asks")
	panel._on_delete("Ann")
	_check(not PlayerProfiles.load_saved().has_player("Ann"), "the second press deletes")
	panel.queue_free()


## The readers behind LinksGolfer, on synthetic data (no original files).
func _test_golfer_file_readers() -> void:
	_check(GolferAnimData.name_hash("123456789") == 0xcbf43926, "name_hash is CRC-32")
	_check(GolferAnimData.name_hash("Root") == 0xb6c65665, "name_hash of Root")
	# Same strip as the C++ skinned_mesh test: the degenerate (3, 2, 2) goes
	# and the second triangle is flipped to keep the winding.
	var tris := GolferAnimData.strip_to_triangles(PackedInt32Array([0, 1, 3, 2, 2]), 10)
	_check(tris == PackedInt32Array([10, 11, 13, 13, 11, 12]), "strip_to_triangles: %s" % tris)
	_check(GolferAnimData.influence_joint(18) == 18 and GolferAnimData.influence_joint(21) == 20,
			"influence numbers skip 19")
	_check(LinksGolfer.shot_section("Dr", false, 250.0) == "Driver", "driver uses [Driver]")
	_check(LinksGolfer.shot_section("3W", false, 200.0) == "Driver", "fairway wood uses [Driver]")
	_check(LinksGolfer.shot_section("7i", false, 150.0) == "Iron", "iron uses [Iron]")
	_check(LinksGolfer.shot_section("SW", false, 90.0) == "Iron", "full wedge uses [Iron]")
	_check(LinksGolfer.shot_section("PW", false, 25.0) == "Chip", "short shot uses [Chip]")
	_check(LinksGolfer.shot_section("Pt", true, 3.0) == "Putter", "putter uses [Putter]")
	var putts := LinksGolfer.parse_clip_list("PutterLong( 2@35),PutterMedium( 2@41),PutterShort( 2@36)")
	_check(LinksGolfer.pick_swing(putts, "Putter", 15.0, 1.0)["clip"] == "PutterLong", "long putt clip")
	_check(LinksGolfer.pick_swing(putts, "Putter", 6.0, 1.0)["clip"] == "PutterMedium", "medium putt clip")
	_check(LinksGolfer.pick_swing(putts, "Putter", 1.0, 1.0)["clip"] == "PutterShort", "short putt clip")
	var irons := LinksGolfer.parse_clip_list("IronSwing( 2@47),IronHalfSwing( 2@43)")
	_check(LinksGolfer.pick_swing(irons, "Iron", 150.0, 1.0)["clip"] == "IronSwing", "full iron swing")
	_check(LinksGolfer.pick_swing(irons, "Iron", 150.0, 0.4)["clip"] == "IronHalfSwing", "half swing when weak")
	var outfit := LinksGolfer.parse_script("[customizable part 1]\nTitle=Shirts\nVarieties=3\nTextures=2\n"
			+ "Texture1=L_A01_Shirt01_%%.TGA\nTexture2=L_A01_Shirt01_CLR_%%.TGA\n")
	var swaps := LinksGolfer.outfit_swaps(outfit, func(key: String) -> String: return "2" if key == "shirts" else "")
	_check(swaps.get("L_A01_SHIRT01_01.TGA", "") == "L_A01_SHIRT01_02.TGA", "shirt variety swap: %s" % swaps)
	_check(swaps.get("L_A01_SHIRT01_CLR_01.TGA", "") == "L_A01_SHIRT01_CLR_02.TGA", "shirt colour swap")
	_check(LinksGolfer.outfit_swaps(outfit, func(_key: String) -> String: return "").is_empty(), "default outfit")
	var m := GolferAnimData.read_matrix(PackedFloat32Array([1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 2, 3, 4, 1]).to_byte_array(), 0)
	# Row-vector matrix: the x axis stays, y maps onto +z, and it translates by (2, 3, 4).
	_check(m * Vector3(0, 1, 0) == Vector3(2, 3, 5), "read_matrix: %s" % (m * Vector3(0, 1, 0)))
	# Clear, 'R', 'I', code 258 ("RI"), end: 9-bit codes, LSB first.
	var acc := 0
	var bits := 0
	for code in [256, 82, 73, 258, 257]:
		acc |= code << bits
		bits += 9
	var packed := PackedByteArray()
	for i in (bits + 7) / 8:
		packed.append((acc >> (8 * i)) & 0xff)
	_check(LsArchiveFile.lzw_decompress(packed, 100).get_string_from_ascii() == "RIRI", "LZW known stream")
	var clips := LinksGolfer.parse_clip_list("DriverSwing( 0@29 1@32 2@46),IronHalfSwing")
	_check(clips.size() == 2, "clip list length")
	_check(clips[0]["clip"] == "DriverSwing" and clips[0]["events"].get(2, -1) == 46, "clip events")
	_check(clips[1]["clip"] == "IronHalfSwing" and clips[1]["events"].is_empty(), "clip without events")
	var parsed := LinksGolfer.parse_script("[Driver]\nAddress=DriverAddress ; comment\n[file_locations]\ngolfer.skl=a_bound.skl")
	_check(parsed.get("Driver", {}).get("Address", "") == "DriverAddress", "script value")
	_check(parsed.get("file_locations", {}).get("golfer.skl", "") == "a_bound.skl", "script file location")


## The broadcast cameras, green grid, hole map and commentary on their own.
func _test_broadcast_pieces() -> void:
	# A straight 200 m drive down +z on flat ground, landing 40 m from the pin.
	var shot := ShotResult.new()
	for i in 121:
		var t := i * 0.05
		var u := t / 6.0
		shot.add_sample(t, Vector3(0.0, 30.0 * 4.0 * u * (1.0 - u), 200.0 * u))
	shot.first_landing = Vector3(0, 0, 200)
	shot.rest = Vector3(0, 0, 215)
	shot.carry_m = 200.0
	shot.total_m = 215.0
	shot.time_s = 6.0
	shot.bounces = 2
	var terrain := FlatTerrain.new()
	var behind := Vector3(0, 1.75, -4.2)
	var pin := Vector3(0, 0, 240)
	var d := ShotDirector.plan(shot, pin, terrain, behind, false, 0)
	_check(d.cut_cams.size() == 3, "drive gets three cameras (got %d)" % d.cut_cams.size())
	_check(d.cut_cams[0] == ShotDirector.Cam.BEHIND, "starts behind the ball")
	_check(d.cut_cams[1] == ShotDirector.Cam.CHASE, "variant 0 chases the ball")
	_check(d.cut_cams[2] == ShotDirector.Cam.PIN, "landing near the pin cuts to the pin camera")
	var first: Array = d.step(0.0, shot.points[0], behind, 0.016)
	_check((first[0] as Vector3).is_equal_approx(behind), "behind camera stays put")
	var late: Array = d.step(5.5, shot.position_at(5.5), behind, 0.016)
	_check(late[2], "the pin camera starts with a cut")
	_check((late[0] as Vector3).z > 240.0, "pin camera stands beyond the pin")
	var side := ShotDirector.plan(shot, Vector3(0, 0, 400), terrain, behind, false, 2)
	_check(side.cut_cams[1] == ShotDirector.Cam.SIDE, "variant 2 cuts side-on")
	_check(side.cut_cams[2] == ShotDirector.Cam.LANDING, "far from the pin: landing camera")
	var putt := ShotDirector.plan(shot, pin, terrain, behind, true, 0)
	_check(putt.cut_cams.size() == 1 and putt.cut_cams[0] == ShotDirector.Cam.PUTT, "putts track the ball")

	_check_near(GreenGrid.slope_percent(Vector3.UP), 0.0, 1e-6, "flat green has no slope")
	_check_near(GreenGrid.slope_percent(Vector3(0.03, 1.0, 0.04).normalized()), 5.0, 1e-3, "slope in percent")
	var grid := GreenGrid.new()
	grid.build(terrain, Vector3(0, 0, 0), Vector3(0, 0, 8))
	_check(grid.mesh.get_surface_count() == 1, "green grid builds")
	grid.free()

	var course := PlaceholderCourseLoader.new().load_course("")
	var map := HoleMap.make(course.holes[0])
	_check(map.get_width() == HoleMap.WIDTH and map.get_height() == HoleMap.HEIGHT, "hole map size")
	var h0 := course.holes[0]
	var built := HoleMap.build(h0)
	var tee_px := built.to_px(h0.tee)
	var pin_px := built.to_px(h0.pin)
	_check(pin_px.y < tee_px.y and Rect2(Vector2.ZERO, Vector2(HoleMap.WIDTH, HoleMap.HEIGHT)).has_point(pin_px), "map: pin above the tee, on the map")

	# Tour graphics: the driving zone splits the lines three ways.
	if h0.par > 3:
		var aim := rad_to_deg(atan2(h0.pin.x - h0.tee.x, h0.pin.z - h0.tee.z))
		var zone := DrivingZone.compute(h0, h0.tee, aim, 230.0, 0, 4.0)
		if not zone.is_empty():
			_check_near(zone.left + zone.hit + zone.right, 1.0, 1e-4, "driving zone chances add up")
			_check(zone.lo < zone.hi and zone.anchors.size() == 3, "driving zone has a fairway window and three labels")
			_check(zone.score_hit <= zone.score_left + 0.5 and zone.score_hit > 1.0, "fairway scores no worse than a miss")
	_check_near(DrivingZone._cdf(0.0), 0.5, 1e-6, "normal cdf at 0")
	_check_near(DrivingZone._cdf(1.0), 0.8413447, 1e-5, "normal cdf at 1")
	_check(PuttRead.aim_text(0.0) == "Straight", "putt read: straight")
	_check(PuttRead.aim_text(1.45) == "4' 9\" left", "putt read: feet and inches left; got %s" % PuttRead.aim_text(1.45))
	_check(PuttRead.aim_text(-0.1) == "4\" right", "putt read: inches right")
	_check(PuttRead.slope_text(0.2, 10.0) == "2.0% uphill", "putt read: slope")
	_check(TourGraphics._short("JORDAN SMITH") == "J. SMITH", "rail names")

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var holed := ShotResult.new()
	holed.outcome = ShotResult.Outcome.HOLED
	var line: Array = Commentary.pick(holed, Surface.Type.GREEN, false, 0.0, 140.0, rng)
	_check(line[1] == Commentary.Crowd.ROAR and Commentary.HOLED_LONG.has(line[0]), "holed approach roars")
	var wet := ShotResult.new()
	wet.outcome = ShotResult.Outcome.WATER
	_check(Commentary.pick(wet, Surface.Type.WATER, false, 50.0, 150.0, rng)[1] == Commentary.Crowd.GROAN, "water groans")

	# Golfer voice lines, by what the shot did.
	_check(GolferVoice.event_for(wet, Surface.Type.WATER, false, false, 4, 2, 50.0, 150.0, false) == "In Water", "voice: water")
	var rolled := ShotResult.new()
	_check(GolferVoice.event_for(rolled, Surface.Type.GREEN, true, false, 4, 3, 3.0, 8.0, true) == "Putt Too Hard", "voice: putt past")
	_check(GolferVoice.event_for(rolled, Surface.Type.GREEN, true, false, 4, 3, 3.0, 8.0, false) == "Putt Too Soft", "voice: putt short")
	_check(GolferVoice.event_for(holed, Surface.Type.GREEN, true, false, 4, 3, 0.0, 12.0, false) == "Birdie", "voice: birdie")
	_check(GolferVoice.event_for(holed, Surface.Type.GREEN, false, true, 3, 1, 0.0, 150.0, false) == "Hole In One!", "voice: ace")
	var drive := ShotResult.new()
	drive.total_m = 250.0
	_check(GolferVoice.event_for(drive, Surface.Type.FAIRWAY, false, true, 4, 1, 150.0, 400.0, false) == "Great Tee Shot", "voice: big drive")

	# Timed lines: at impact, in flight and on landing.
	_check(GolferVoice.swing_event(1.0, 0.0, false) == "Perfect Swing", "voice: perfect swing")
	_check(GolferVoice.swing_event(0.8, 0.7, false) == "Bad Swing", "voice: bad swing")
	_check(GolferVoice.swing_event(1.0, 0.0, true) == "", "voice: no swing line on putts")
	var flown := ShotResult.new()
	flown.carry_m = 250.0
	flown.total_m = 290.0
	_check(GolferVoice.flight_event(flown, false, true, 150.0, false, 0.0) == "Crush Tee Shot", "voice: crushed drive")
	_check(GolferVoice.flight_event(flown, false, true, 150.0, false, 30.0) == "Hook", "voice: hook")
	_check(GolferVoice.flight_event(flown, false, true, 150.0, false, -30.0) == "Slice", "voice: slice")
	_check(GolferVoice.flight_event(flown, false, false, 4.0, false, 0.0) == "Straight at  pin", "voice: at the pin")
	_check(GolferVoice.flight_event(wet, false, false, 50.0, false, 0.0) == "Water", "voice: heading for water")
	_check(GolferVoice.flight_event(rolled, true, false, 3.0, true, 0.0) == "Putt Too Hard", "voice: putt racing past")
	_check(GolferVoice.flight_event(rolled, true, false, 1.0, false, -0.3) == "Putt Push (right hand)", "voice: pushed putt")
	_check(GolferVoice.landing_event(flown, true, 150.0, false) == "Tee Shot Roll", "voice: drive rolls out")
	_check(GolferVoice.landing_event(flown, false, 5.0, false) == "Approach Near-Pin", "voice: lands near the pin")
	_check(GolferVoice.landing_event(flown, false, 20.0, true) == "Approach Long", "voice: lands long")
	_check(GolferVoice.bank_for(PackedStringArray(["P/NONE.SSF", "P/MALE1_1.SSF", "P/ERIC_1.SSF"]), "ERIC.L3") == "P/ERIC_1.SSF", "voice bank by golfer")
	_check(GolferVoice.bank_for(PackedStringArray(["P/NONE.SSF", "P/MALE1_1.SSF"]), "ERIC.L3") == "P/MALE1_1.SSF", "default voice bank")

	# SOUNDS.LS entries keep their block header before the RIFF data.
	var wav := PackedByteArray()
	wav.resize(LsArchiveFile.BLOCK_HEADER_SIZE)
	wav.append_array("RIFF".to_ascii_buffer())
	wav.append_array(PackedByteArray([36, 0, 0, 0]))
	wav.append_array("WAVEfmt ".to_ascii_buffer())
	wav.append_array(PackedByteArray([16, 0, 0, 0, 1, 0, 1, 0, 0x22, 0x56, 0, 0, 0x44, 0xac, 0, 0, 2, 0, 16, 0]))
	wav.append_array("data".to_ascii_buffer())
	wav.append_array(PackedByteArray([4, 0, 0, 0, 0, 0, 0, 0]))
	_check(MenuSounds._stream(wav) != null, "menu sound past the block header")


## A round in each presentation, with a replay, a flyover and the green grid.
func _test_broadcast_round() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var panel := Control.new()
	root.add_child(panel)
	SceneFade.pop_in(panel)
	_check(panel.modulate.a == 0.0, "panels fade in from transparent")
	panel.free()
	game.graphics.presentation = GraphicsSettings.Presentation.BROADCAST
	game._apply_graphics()
	game.start_round()
	_check(game.camera.flying(), "broadcast holes open with a flyover")
	for i in 60:
		game._process(0.2)
	_check(not game.camera.flying(), "the flyover ends by itself")
	game.auto_play_step()
	_check(game.state == GolfRound.State.FLIGHT, "shot in flight")
	_check(game.camera.director != null, "broadcast cameras direct the shot")
	for i in 3:
		game._process(0.5)
	game.auto_play_step()
	_check(game.state == GolfRound.State.SHOT_RESULT, "shot result")
	_check(game.start_replay(), "replay starts")
	var frames := 0
	while game._replaying and frames < 400:
		game._process(0.1)
		frames += 1
	_check(not game._replaying, "replay ends")
	_check(game.state == GolfRound.State.SHOT_RESULT, "replay leaves the result up")
	var steps := 0
	while not (game.state == GolfRound.State.AIM and game.clubs[game.club_index].is_putter) and steps < 40 \
			and game.state != GolfRound.State.ROUND_DONE:
		game.auto_play_step()
		steps += 1
	if game.state == GolfRound.State.AIM and game.lie == Surface.Type.GREEN:
		_check(game.green_grid.visible, "green grid on the green")
	game.graphics.presentation = GraphicsSettings.Presentation.CLASSIC
	game._apply_graphics()
	_check(not game.hud.overlay.visible and not game.green_grid.visible, "classic hides the broadcast pieces")
	game.start_round()
	_check(not game.camera.flying(), "classic has no flyover")
	steps = 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 600:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.ROUND_DONE, "classic round finishes")
	game.graphics.presentation = GraphicsSettings.Presentation.BROADCAST
	game._apply_graphics()
	# Tour: the tour graphics on top of Broadcast.
	game.graphics.presentation = GraphicsSettings.Presentation.TOUR
	game._apply_graphics()
	_check(game.tour and game.hud.tour.visible and game.hud.overlay.tour, "tour graphics on")
	game.start_round()
	game.camera.end_flyover()
	game._update_hud()
	_check(not game.hud.tour.state.is_empty() and game.hud.tour.state.rows.size() == game.scoring.names.size(), "tour rail has every player")
	if game.hole.par > 3:
		_check(game.driving_zone.visible == not game.hud.tour.zone.is_empty(), "driving zone drawn when there is one")
	steps = 0
	while not (game.state == GolfRound.State.AIM and game.clubs[game.club_index].is_putter) and steps < 40 \
			and game.state != GolfRound.State.ROUND_DONE:
		game.auto_play_step()
		steps += 1
	if game.state == GolfRound.State.AIM and game.lie == Surface.Type.GREEN:
		_check(not game.hud.tour.putt.is_empty() and game.putt_read.visible, "putt read on the green")
		_check(not game.driving_zone.visible, "no driving zone on the green")
	_check(game._tour_dots.size() > 0, "shots marked on the tour map")
	game.graphics.presentation = GraphicsSettings.Presentation.BROADCAST
	game._apply_graphics()
	_check(not game.hud.tour.visible and not game.putt_read.visible, "broadcast hides the tour graphics")


## A stick (or finger) swing through AnalogSwing into Links 2003's mouse
## swing: pulled `back` of the way over 40 frames, held 10 (with a little
## jitter if asked), then pushed all the way forward over `flick` frames.
func _analog_club(shot: int, club: int, back: float, flick: int, jitter := false) -> LinksMouse.MouseClub:
	var mc := LinksMouse.MouseClub.new(3, shot, club, LinksMouse.meter_for(1920))
	var rng := LinksLaunch.Rand.new(7)
	var tracker := AnalogSwing.Tracker.new(AnalogSwing.reach_px(shot, club))
	var pending := 0.0
	for f in 300:
		if mc.done():
			break
		var s := 0.0
		if f < 40:
			s = back * (f + 1) / 40.0
		elif f < 50:
			s = back - (0.02 if jitter and f % 2 == 0 else 0.0)
		else:
			var u := minf(1.0, (f - 49) / float(flick))
			s = back - (back + 1.0) * u * u * (3.0 - 2.0 * u)
		pending += tracker.feed(Vector2(0.0, s)).y
		var dy := int(pending)
		pending -= dy
		mc.step(0, dy, rng)
		if f == 49 and jitter:
			_check(mc.phase == LinksMouse.Phase.BACKSWING, "stick jitter at the top doesn't start the downswing")
	return mc


func _analog_power(mc: LinksMouse.MouseClub) -> float:
	if mc.phase != LinksMouse.Phase.IMPACT:
		return -1.0
	return LinksMouse.swing(mc.stroke, LinksLaunch.Rand.new(3)).power


func _test_analog_swing() -> void:
	_check(AnalogSwing.dead_zone(0.1) == 0.0 and AnalogSwing.dead_zone(1.0) == 1.0, "stick dead zone")
	_check_near(AnalogSwing.dead_zone(-0.56), -0.5, 1e-6, "stick dead zone rescales")
	_check(AnalogSwing.touch(Vector2(0, 100), Vector2(0, 500), 1000.0) == Vector2(0, 1), "a finger 40% of the screen back is a full deflection")
	var t := AnalogSwing.Tracker.new(100.0)
	_check(t.feed(Vector2(0, 0.5)) == Vector2(0, 50), "tracker moves the mouse back")
	_check(t.feed(Vector2(0.1, 0.48)).is_equal_approx(Vector2(10, 0)), "tracker waits at the top")
	var down := t.feed(Vector2(0.1, 0.4))
	_check(t.coming_down() and down.y < 0.0, "tracker comes down")
	_check_near(AnalogSwing.reach_px(LinksMouse.Shot.PUTT, LinksMouse.PUTTER), 1000.0 / 0.75, 1e-6, "putt reach")
	# A full swing: all the way back gives about the mouse's usual backswing,
	# and a brisk flick hits the driver near its best; a slow push less.
	var full := _analog_club(LinksMouse.Shot.FULL, 0, 1.0, 10, true)
	_check(full.phase == LinksMouse.Phase.IMPACT, "stick driver strikes")
	_check(full.stroke.backswing > 0.75 and full.stroke.backswing < 0.95, "stick driver backswing %f" % full.stroke.backswing)
	var flick := _analog_power(full)
	_check(flick > 75.0, "stick driver flick power %f" % flick)
	var slow := _analog_power(_analog_club(LinksMouse.Shot.FULL, 0, 1.0, 40))
	_check(slow > 0.0 and slow < flick, "a slow push hits softer: %f" % slow)
	var half := _analog_club(LinksMouse.Shot.FULL, 0, 0.5, 10)
	_check(half.phase == LinksMouse.Phase.IMPACT and half.stroke.backswing > 0.35 and half.stroke.backswing < 0.6,
			"half the stick is about half a backswing")
	# Putts follow the stick: all the way back fills the meter, half is half.
	var putt := _analog_club(LinksMouse.Shot.PUTT, LinksMouse.PUTTER, 1.0, 10)
	var short := _analog_club(LinksMouse.Shot.PUTT, LinksMouse.PUTTER, 0.5, 10)
	_check(putt.phase == LinksMouse.Phase.IMPACT and putt.stroke.backswing > 0.95, "stick putt fills the meter")
	_check(short.phase == LinksMouse.Phase.IMPACT and short.stroke.backswing > 0.3 and short.stroke.backswing < 0.6,
			"half a stick putt")
	_check(_analog_power(short) < _analog_power(putt), "a shorter putt stroke is softer")
	var chip := _analog_club(LinksMouse.Shot.CHIP, 16, 1.0, 10)
	_check(chip.phase == LinksMouse.Phase.IMPACT and chip.stroke.backswing > 0.7, "stick chip")


func _touch(game: GolfRound, pressed: bool, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = at
	game._unhandled_input(e)


func _drag(game: GolfRound, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = at
	game._unhandled_input(e)
	game.hud.mouse_swing.advance(1.0 / 60.0)


func _stick(game: GolfRound, y: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = JOY_AXIS_RIGHT_Y
	e.axis_value = y
	game._unhandled_input(e)
	game.hud.mouse_swing.advance(1.0 / 60.0)


func _ready_to_aim(game: GolfRound) -> void:
	GolfRound.setup = null
	game.graphics.presentation = GraphicsSettings.Presentation.CLASSIC
	game._apply_graphics()
	game.start_round()
	if game.camera.flying():
		game.camera.end_flyover()
	if game.hud.hand_over.visible:
		game.hud.hand_over.close()


func _test_touch_and_stick_swings() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var presentation := game.graphics.presentation
	_ready_to_aim(game)
	_check(game.state == GolfRound.State.AIM, "touch: aiming")
	var h := game.get_viewport().get_visible_rect().size.y
	var from := Vector2(640, h * 0.3)
	# The mouse events a touch screen makes up don't start the mouse swing.
	var fake := InputEventMouseButton.new()
	fake.device = InputEvent.DEVICE_ID_EMULATION
	fake.button_index = MOUSE_BUTTON_LEFT
	fake.pressed = true
	game._unhandled_input(fake)
	_check(game.state == GolfRound.State.AIM and not game.hud.mouse_swing.is_swinging(), "touch: made-up mouse ignored")
	# A tap starts the PowerStroke meter.
	_touch(game, true, from)
	_touch(game, false, from)
	_check(game.state == GolfRound.State.SWING and game.hud.meter.is_swinging(), "touch: a tap starts the meter")
	# A swipe: drag back 40% of the screen, then flick up.
	_ready_to_aim(game)
	_touch(game, true, from)
	for f in 40:
		_drag(game, from + Vector2(0, h * 0.4 * (f + 1) / 40.0))
	_check(game.state == GolfRound.State.SWING and game.hud.mouse_swing.is_swinging(), "touch: swiping back swings")
	_check(game.hud.mouse_swing.club.backswing_percent() > 60.0, "touch: backswing %f" % game.hud.mouse_swing.club.backswing_percent())
	for f in 30:
		if game.state != GolfRound.State.SWING:
			break
		_drag(game, from + Vector2(0, h * 0.4 - h * 0.8 * minf(1.0, (f + 1) / 8.0)))
	_check(game.state == GolfRound.State.FLIGHT, "touch: the flick hits the ball")
	_touch(game, false, from)
	# A swipe called off: lifting the finger before the downswing.
	_ready_to_aim(game)
	_touch(game, true, from)
	for f in 10:
		_drag(game, from + Vector2(0, h * 0.02 * (f + 1)))
	_touch(game, false, from + Vector2(0, h * 0.2))
	_check(game.state == GolfRound.State.AIM and not game.hud.mouse_swing.is_swinging(), "touch: lifting early calls it off")
	# The right stick: back over 40 frames, then a flick forward.
	_ready_to_aim(game)
	_stick(game, 0.0)
	for f in 40:
		_stick(game, (f + 1) / 40.0)
	_check(game.state == GolfRound.State.SWING and game._swing_input == GolfRound.SwingInput.STICK, "stick: pulling back swings")
	for f in 30:
		if game.state != GolfRound.State.SWING:
			break
		_stick(game, 1.0 - 2.0 * minf(1.0, (f + 1) / 6.0))
	_check(game.state == GolfRound.State.FLIGHT, "stick: the flick hits the ball")
	_stick(game, 0.0)
	# B calls a stick swing off, and the stick must rest before the next.
	_ready_to_aim(game)
	for f in 20:
		_stick(game, (f + 1) / 40.0)
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	game._unhandled_input(b)
	_check(game.state == GolfRound.State.AIM, "stick: B calls it off")
	_stick(game, 0.6)
	_check(game.state == GolfRound.State.AIM, "stick: waits for the stick to rest")
	_stick(game, 0.0)
	_stick(game, 0.5)
	_check(game.state == GolfRound.State.SWING, "stick: swings again from rest")
	game.hud.mouse_swing.reset()
	game._on_mouse_stroke_cancelled()
	_stick(game, 0.0)
	game.graphics.presentation = presentation
	game._apply_graphics()


## A 15% slope rising towards +z, for the buggy tests.
class TiltedTerrain:
	extends FlatTerrain

	func height_at(_x: float, z: float) -> float:
		return 0.15 * z

	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3(0.0, 1.0, -0.15).normalized()
