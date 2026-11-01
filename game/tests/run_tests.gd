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
	_run("pin_positions", _test_pin_positions)
	_run("swing_meter", _test_swing_meter)
	_run("analog_swing", _test_analog_swing)
	_run("scorecard", _test_scorecard)
	_run("game_modes_match_olcore", _test_game_modes)
	_run("handicaps_match_olcore", _test_handicaps)
	_run("player_profiles", _test_player_profiles)
	_run("round_setup", _test_round_setup)
	_run("round_scoring", _test_round_scoring)
	_run("career", _test_career)
	_run("tour_pros", _test_tour_pros)
	_run("tournament_hole_odds", _test_tournament_hole_odds)
	_run("tournament_stroke_play", _test_tournament_stroke_play)
	_run("tournament_match_play", _test_tournament_match_play)
	_run("tournament_skins", _test_tournament_skins)
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
	_run("course_life", _test_course_life)
	_run("gallery", _test_gallery)
	_run("trees", _test_trees)
	_run("ground shade", _test_ground_shade)
	_run("broadcast_pieces", _test_broadcast_pieces)
	_run("green_reading", _test_green_reading)
	_run("putting_practice", _test_putting_practice)
	_run("hd_pack", _test_hd_pack)
	_run("object_library_chain", _test_object_library_chain)
	_run("free_assets", _test_free_assets)
	_run("web_game_files", _test_web_game_files)
	_run("golfer_file_readers", _test_golfer_file_readers)
	_run("free_golfer", _test_free_golfer)
	_run("player_looks", _test_player_looks)
	_run("golfer_roster", _test_golfer_roster)
	_run("face_from_photo", _test_face_from_photo)
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
	_run("online_round", _test_online_round)
	_run("drops_in_round", _test_drops_in_round)
	_run("multiplayer_rounds", _test_multiplayer_rounds)
	_run("putting_practice_round", _test_putting_practice_round)
	_run("practice_range", _test_practice_range)
	_run("gimmes", _test_gimmes)
	_run("launch_monitor_input", _test_launch_monitor_input)
	_run("practice_ground", _test_practice_ground)
	_run("range_game", _test_range_game)
	_run("practice_ground_round", _test_practice_ground_round)
	_run("mulligans", _test_mulligans)
	_run("click_aim", _test_click_aim)
	_run("glass_ui", _test_glass_ui)
	_run("pick_up", _test_pick_up)
	_run("round_conditions", _test_round_conditions)
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
	_run("career_round", _test_career_round)
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
			_check(not game.hud.meter.visible and not game.hud.info.visible, "the swing meter and shot info hide while driving")
			var rider := game.buggy.rider
			if rider != null:  # only with the free golfer model
				var sk := rider.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
				var thigh := sk.find_bone("thigh_l")
				var bent := sk.get_bone_global_pose(thigh).basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)
				_check(rider.is_visible_in_tree() and bent > 1.0, "the golfer sits at the wheel, thighs along the seat")
			var from := game.buggy.drive.position
			for i in 60:
				game.buggy.step(1.0 / 30.0, 1.0, 0.0, game.hole.terrain)
			_check(game.buggy.drive.position.distance_to(from) > 1.0 or game.buggy.drive.blocked, "the buggy drives")
			game._process_drive(1.0 / 30.0)
			# By touch: a drag up drives, sideways steers, a tap skips.
			var down := InputEventScreenTouch.new()
			down.index = 0
			down.pressed = true
			down.position = Vector2(400, 500)
			_check(game._drive_touch_input(down), "a finger takes the wheel")
			var drag := InputEventScreenDrag.new()
			drag.index = 0
			drag.position = Vector2(445, 410)
			game._drive_touch_input(drag)
			_check(game._drive_stick.y < -0.9 and game._drive_stick.x > 0.4, "dragging up and right is pedal down and steering right")
			var speed := game.buggy.drive.speed
			for i in 30:
				game._process_drive(1.0 / 30.0)
			_check(game.buggy.drive.speed > speed or game.buggy.drive.blocked, "the touch pedal drives")
			var up := InputEventScreenTouch.new()
			up.index = 0
			game._drive_touch_input(up)
			_check(game._drive_stick == Vector2.ZERO and game.state == GolfRound.State.DRIVE, "letting go after a drag doesn't skip")
			game._drive_touch_input(down)
			game._drive_touch_input(up)
			_check(game.state != GolfRound.State.DRIVE, "a tap skips to the ball")
			_check(game._drive_hidden.is_empty() and (rider == null or not rider.visible), "after the drive the HUD is back and the seat is empty")
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


func _test_pin_positions() -> void:
	var h := HoleData.new()
	h.number = 3
	h.pin = Vector3(1, 0, 1)
	_check(RoundSetup.pick_pin(h, 1, 1234) == h.pin, "a hole with one position keeps it")
	for i in 18:
		h.pins.append(Vector3(i, 0, 100))
	_check(RoundSetup.pick_pin(h, 0, 1234) == h.pins[0], "usual positions play the first")
	var seen := {}
	for round_seed in range(1, 200):
		var p := RoundSetup.pick_pin(h, 1, round_seed)
		_check(p == RoundSetup.pick_pin(h, 1, round_seed), "the same seed, the same position")
		seen[p] = true
	_check(seen.size() >= 12, "random positions use most of the course's (%d of 18)" % seen.size())
	var rec := RoundRecord.new()
	rec.pins = 1
	_check(RoundRecord.from_dict(rec.to_dict()).pins == 1, "the record keeps the pin setting")


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
## A green tilted by `grad` (rise per metre along x and z), green within
## `radius` of the origin and fringe beyond.
class TiltTerrain extends CourseTerrain:
	var grad := Vector2.ZERO
	var radius := 15.0

	func _init(g: Vector2, r := 15.0) -> void:
		grad = g
		radius = r

	func height_at(x: float, z: float) -> float:
		return grad.x * x + grad.y * z

	func surface_at(x: float, z: float) -> int:
		return Surface.Type.GREEN if Vector2(x, z).length() <= radius else Surface.Type.FRINGE

	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3(-grad.x, 1.0, -grad.y).normalized()


func _test_green_reading() -> void:
	# A stimpmeter on the game's greens: the roll at 6 ft/s, frame by frame.
	var stimp := GreenRead.stimp(1, 1, true)
	_check_near(stimp, 5.263, 0.01, "stimp of medium, normal-speed greens")
	_check_near(GreenRead.stimp(2, 2, true), 7.453, 0.01, "stimp of firm, fast greens")
	_check(GreenRead.stimp(1, 2, true) > stimp and GreenRead.stimp(1, 0, true) < stimp, "faster greens roll further")
	_check(GreenRead.stimp(0, 1, true) < stimp, "soft greens roll less")
	_check(GreenRead.stimp(1, 1, false) > 1.0, "the standard model's greens have a stimp")
	_check(GreenRead.speed_text(1, 1, true) == "Medium, normal speed (stimp 5.3)", "speed text: %s" % GreenRead.speed_text(1, 1, true))

	# Rises to the golfer's left (+x) facing +z, so it falls right.
	var side_hill := TiltTerrain.new(Vector2(0.02, 0.0))
	var r := GreenRead.line(side_hill, Vector3.ZERO, Vector3(0, 0, 5))
	_check_near(r.side_percent, -2.0, 0.01, "falls right across the line")
	_check_near(r.rise_m, 0.0, 1e-6, "level along the line")
	_check(GreenRead.break_text(r.side_percent) == "Breaks left to right (moderate)", "break: %s" % GreenRead.break_text(r.side_percent))
	_check(GreenRead.break_text(0.1) == "Straight", "a flat line is straight")
	_check(GreenRead.break_text(0.6) == "Breaks right to left (gentle)", "gentle right to left")
	var up := GreenRead.line(TiltTerrain.new(Vector2(0, 0.01)), Vector3.ZERO, Vector3(0, 0.05, 5))
	_check_near(up.rise_m, 0.05, 1e-5, "uphill putt rises 5 cm")
	_check(GreenRead.lie_text(side_hill, Vector3.ZERO, Vector2(0, 1)) == "2.0%, falls right", "lie: %s" % GreenRead.lie_text(side_hill, Vector3.ZERO, Vector2(0, 1)))
	_check(GreenRead.length_text(0.7112) == "2' 4\"", "feet and inches")
	_check(GreenRead.length_text(0.1) == "4\"", "inches")

	# Links 2003's aids by skill: Amateur, Professional, Championship, Elite.
	_check(GreenRead.assistant_level(0) == 2 and GreenRead.assistant_level(1) == 1, "assistant at Amateur and Professional")
	_check(GreenRead.assistant_level(2) == 0 and GreenRead.assistant_level(3) == 0, "no assistant at Championship and Elite")
	_check(GreenRead.grid_allowed(2) and not GreenRead.grid_allowed(3), "no grid at Elite")
	_check(GreenRead.views_for(0).size() == 5 and not GreenRead.views_for(3).has(GreenRead.View.OVERHEAD), "no Green Analyzer at Elite")
	var flat := FlatTerrain.new(Surface.Type.GREEN)
	var crouch: Array = GreenRead.view_pose(GreenRead.View.CROUCH, flat, Vector3.ZERO, Vector3(0, 0, 6))
	_check((crouch[0] as Vector3).z < 0.0 and (crouch[0] as Vector3).y < 1.0, "crouched low behind the ball")
	var behind: Array = GreenRead.view_pose(GreenRead.View.BEHIND_HOLE, flat, Vector3.ZERO, Vector3(0, 0, 6))
	_check((behind[0] as Vector3).z > 6.0, "behind the hole")
	var low: Array = GreenRead.view_pose(GreenRead.View.LOW_SIDE, side_hill, Vector3.ZERO, Vector3(0, 0, 6))
	_check((low[0] as Vector3).x < 0.0, "the low side is the side it falls to")

	# The breakline indicator stands taller on steeper ground.
	_check(BreaklineIndicator.height_for(3.0) > BreaklineIndicator.height_for(1.0), "steeper, taller breakline")
	var bl := BreaklineIndicator.new()
	bl.show_at(side_hill, Vector3(0, 0, 3))
	_check(bl.visible and bl.mesh.get_surface_count() == 1, "breakline builds")
	bl.free()
	# The grid's three looks build.
	var grid := GreenGrid.new()
	for style in [GreenGrid.Style.YELLOW, GreenGrid.Style.HEIGHT, GreenGrid.Style.SLOPE]:
		grid.style = style
		grid.build(side_hill, Vector3.ZERO, Vector3(0, 0, 6))
		_check(grid.mesh.get_surface_count() == 1, "grid style %d builds" % style)
	_check(GreenGrid.height_color(0.0).b > GreenGrid.height_color(0.0).r and GreenGrid.height_color(1.0).r > GreenGrid.height_color(1.0).b, "low blue, high red")
	grid.free()


func _test_putting_practice() -> void:
	# Rises toward +z: putts from -z are uphill.
	var green := TiltTerrain.new(Vector2(0.0, 0.015))
	var hole := HoleData.new()
	hole.terrain = green
	hole.pin = Vector3.ZERO
	var pr := PuttingPractice.new(7)
	var spot := pr.setup(hole)
	_check(pr.cups.size() == PuttingPractice.MAX_CUPS, "six cups on a big green (%d)" % pr.cups.size())
	_check(pr.cups[0].is_equal_approx(Vector3.ZERO), "the hole's own pin is the first cup")
	for i in pr.cups.size():
		_check(green.surface_at(pr.cups[i].x, pr.cups[i].z) == Surface.Type.GREEN, "cup %d on the green" % i)
		for j in i:
			_check(Vector2(pr.cups[i].x - pr.cups[j].x, pr.cups[i].z - pr.cups[j].z).length() >= PuttingPractice.CUP_SPACING - 1e-4, "cups %d and %d apart" % [j, i])
	_check_near(Vector2(spot.x, spot.z).length(), 10.0 * 0.3048, 1e-3, "first ball 10 ft from the cup")
	var same := PuttingPractice.new(7)
	same.setup(hole)
	_check(same.cups == pr.cups and same.spot.is_equal_approx(pr.spot), "a seed gives the same green")

	pr.slope = PuttingPractice.Slope.UPHILL
	pr.new_spot()
	_check(pr.slope_found and float(GreenRead.line(green, pr.spot, pr.cup_position()).rise_m) > 0.03, "uphill putt")
	pr.slope = PuttingPractice.Slope.DOWNHILL
	pr.new_spot()
	_check(pr.slope_found and float(GreenRead.line(green, pr.spot, pr.cup_position()).rise_m) < -0.03, "downhill putt")
	pr.slope = PuttingPractice.Slope.LEFT_TO_RIGHT
	pr.new_spot()
	_check(pr.slope_found and float(GreenRead.line(green, pr.spot, pr.cup_position()).side_percent) < -0.5, "left-to-right putt")
	pr.slope = PuttingPractice.Slope.RIGHT_TO_LEFT
	pr.new_spot()
	_check(pr.slope_found and float(GreenRead.line(green, pr.spot, pr.cup_position()).side_percent) > 0.5, "right-to-left putt")
	pr.change_distance(3)
	_check_near(Vector2(pr.spot.x - pr.cup_position().x, pr.spot.z - pr.cup_position().z).length(), 20.0 * 0.3048, 1e-3, "20 ft putt")

	# Free putting keeps the spot and the tally.
	var at := pr.spot
	pr.record(pr.cup_position(), true)
	var miss := pr.record(pr.cup_position() + Vector3(0.3, 0, 0), false)
	_check(pr.spot.is_equal_approx(at), "free putting comes back to the same spot")
	_check(pr.putts == 2 and pr.holed == 1 and miss.contains("Holed 1 of 2 (50%)"), "tally: %s" % miss)
	_check(PuttingPractice.miss_text(Vector3(0, 0, -3), Vector3.ZERO, Vector3(0.1, 0, 0.3)) == "1' 0\" long, 4\" left", "miss text: %s" % PuttingPractice.miss_text(Vector3(0, 0, -3), Vector3.ZERO, Vector3(0.1, 0, 0.3)))

	# Around the clock: six in a row from 3 ft; a miss starts again.
	pr.next_drill()
	_check(pr.drill == PuttingPractice.Drill.CLOCK, "clock drill")
	_check_near(Vector2(pr.spot.x - pr.cup_position().x, pr.spot.z - pr.cup_position().z).length(), 3.0 * 0.3048, 1e-3, "clock ball 3 ft out")
	pr.record(pr.cup_position(), true)
	pr.record(pr.cup_position() + Vector3(0.2, 0, 0), false)
	_check(pr.status_text().contains("Ball 1 of 6"), "a miss starts the clock again")
	var last := ""
	for i in PuttingPractice.CLOCK_BALLS:
		last = pr.record(pr.cup_position(), true)
	_check(last.contains("all 6 in a row") and pr.clock_best == 6, "round the clock: %s" % last)

	# The lag ladder scores the putts that finish within 3 ft.
	pr.next_drill()
	_check(pr.drill == PuttingPractice.Drill.LADDER, "ladder drill")
	_check_near(Vector2(pr.spot.x - pr.cup_position().x, pr.spot.z - pr.cup_position().z).length(), 20.0 * 0.3048, 1e-3, "first rung 20 ft")
	pr.record(pr.cup_position() + Vector3(0.5, 0, 0), false)
	pr.record(pr.cup_position() + Vector3(2.0, 0, 0), false)
	pr.record(pr.cup_position(), true)
	var ladder := pr.record(pr.cup_position() + Vector3(0, 0, 0.8), false)
	_check(ladder.contains("Ladder: 3 of 4") and pr.ladder_best == 3, "ladder: %s" % ladder)

	pr.next_cup()
	_check(pr.cup == 1, "next cup")
	_check(PuttingPractice.find_cups(FlatTerrain.new(Surface.Type.FAIRWAY), Vector3.ZERO, RandomNumberGenerator.new()).size() == 1, "no green, just the pin")


func _test_putting_practice_round() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var s := RoundSetup.new()
	s.names = _strs(["Ann", "Bob"])
	s.teams = _ints([0, 1])
	s.computer = _ints([RoundSetup.HUMAN, 1])
	s.putting = true
	GolfRound.setup = s
	game.start_round()
	_check(game.practice != null and game.players.size() == 1, "practice is for one player")
	_check(game.practice.cups.size() >= 3, "a practice green with several cups (%d)" % game.practice.cups.size())
	_check(game.lie == Surface.Type.GREEN and game.clubs[game.club_index].is_putter, "practice ball on the green, putter out")
	_check(game.hole.pin.is_equal_approx(game.practice.cup_position()), "the chosen cup is the hole")
	_check(game.putting_panel.visible and game.putting_panel.label.text.contains("Free putting"), "the practice panel shows")
	var from := game.ball_at
	game.auto_play_step()
	game.auto_play_step()
	_check(game.state == GolfRound.State.SHOT_RESULT and game.practice.putts == 1, "a practice putt is counted")
	game.auto_play_step()
	_check(game.state == GolfRound.State.AIM and game.ball_at.is_equal_approx(from), "the ball comes back to its spot")
	_check(game.strokes == 0 and game.card.holes_played() == 0, "practice keeps no score")
	game._on_putting_action(&"further")
	_check(game.practice.distance_index == PuttingPractice.DEFAULT_DISTANCE + 1, "] moves the ball further")
	game._on_putting_action(&"next_cup")
	_check(game.practice.cup == 1 and game.hole.pin.is_equal_approx(game.practice.cups[1]), "next cup is the hole")
	game._on_putting_action(&"read")
	_check(game.read_view == GreenRead.View.CROUCH, "read: crouched behind the ball")
	_check(game.camera.position.y - game.ball_at.y < 1.0, "the camera crouches")
	game._on_putting_action(&"drill")
	_check(game.practice.drill == PuttingPractice.Drill.CLOCK and game.read_view == GreenRead.View.PLAY, "clock drill, back behind the ball")
	_check_near(game._flat_distance(game.ball_at, game.hole.pin), 3.0 * 0.3048, 0.01, "clock ball 3 ft out")
	for i in 3:
		game.auto_play_step()
		game.auto_play_step()
		game.auto_play_step()
	_check(game.practice.putts == 4 and game.state == GolfRound.State.AIM, "clock putts counted")
	var before := game.hole_index
	game._on_putting_action(&"next_green")
	_check(game.hole_index == (before + 1) % game.holes.size() and game.lie == Surface.Type.GREEN, "next green")
	# The original's aids, on at Amateur skill.
	var keep := [game.graphics.skill, game.graphics.putting_assistant, game.graphics.breakline, game.graphics.putting_grid]
	game.graphics.skill = 0
	game.graphics.putting_assistant = true
	game.graphics.breakline = true
	game.graphics.putting_grid = 2
	game._apply_graphics()
	_check(game.green_grid.visible and game.green_grid.style == GreenGrid.Style.HEIGHT, "grid coloured by height")
	_check(game.assistant.visible and game.hud.meter.target > 0.0, "assistant line and power dot")
	_check(game.breakline.visible, "breakline at the aiming marker")
	game.graphics.skill = 3
	game._apply_graphics()
	_check(not game.green_grid.visible or game.broadcast, "no grid at Elite outside Broadcast")
	_check(not game.assistant.visible and game.hud.meter.target < 0.0, "no assistant at Elite")
	game.graphics.skill = keep[0]
	game.graphics.putting_assistant = keep[1]
	game.graphics.breakline = keep[2]
	game.graphics.putting_grid = keep[3]
	game._apply_graphics()
	GolfRound.setup = null


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
	# strength, links strength, mishit, drive/approach/chip errors, putt
	# pace and line, then the Links ratings: tee, irons, chips, putts, power.
	var profiles := [
		[0.677574, 0.687500, 0.060000, 0.082238, 0.483752, 1.693133, 0.125143, 0.625714, 3.754286, 0.149692, 0.534615, 4.704615, 0.066379, 2.655172, 68, 0, 28, 0, 68],
		[0.777876, 0.765625, 0.025000, 0.063434, 0.373144, 1.306004, 0.095348, 0.476739, 2.860435, 0.106615, 0.380769, 3.350769, 0.054762, 2.190476, 70, 0, 45, 0, 78],
		[0.894444, 0.843750, 0.008000, 0.047762, 0.280955, 0.983343, 0.073532, 0.367660, 2.205957, 0.082923, 0.296154, 2.606154, 0.049020, 1.960784, 72, 27, 63, 8, 89],
		[1.000000, 0.937500, 0.002000, 0.039027, 0.229570, 0.803495, 0.060750, 0.303750, 1.822500, 0.068923, 0.246154, 2.166154, 0.044237, 1.769492, 73, 39, 70, 15, 100],
	]
	var swings := [
		[[0.896404, 0.221450, 7.786821], [0.873212, -0.146992, 8.072734], [0.896988, 0.396496, 2.723202], [0.810088, 0.050000, 5.798891]],
		[[0.821298, 0.266047, 11.291252], [0.809778, 0.233342, 5.946137], [0.650314, 0.309248, 11.873928], [0.859648, 0.050000, 9.958976]],
		[[0.896325, 0.333600, 10.618287], [0.964201, 0.525815, 11.520573], [1.000000, -0.009076, 13.528700], [0.889837, 0.050000, 10.657724]],
		[[0.867148, -0.290413, 8.616788], [1.000000, 0.172952, 6.588064], [0.910087, 0.136453, 6.190413], [0.936964, 0.050000, 9.099603]],
	]
	var s := OpponentSkill.Rng.new(42)
	for level in OpponentSkill.LEVEL_NAMES.size():
		var skill := OpponentSkill.new(level)
		var p: Array = profiles[level]
		var got := [skill.strength, skill.links_strength, skill.mishit_chance,
			skill.shots[0][0], skill.shots[0][1], skill.shots[0][2], skill.shots[1][0], skill.shots[1][1], skill.shots[1][2],
			skill.shots[2][0], skill.shots[2][1], skill.shots[2][2], skill.shots[3][0], skill.shots[3][2]]
		for k in got.size():
			_check_near(got[k], p[k], 2e-6, "%s profile value %d" % [skill.level_name(), k])
		_check([skill.links_tee, skill.links_irons, skill.links_chips, skill.links_putts, skill.links_max_power] == p.slice(14),
			"%s Links ratings" % skill.level_name())
		for kind in 4:
			var made := skill.execute(0.9, 0.05, 10.0, kind, 1.25, s)
			var e: Array = swings[level][kind]
			for k in 3:
				_check_near(made[k], e[k], 2e-6, "%s kind %d value %d" % [skill.level_name(), kind, k])
	_check(OpponentSkill.kind_of(true, false, false, 300.0) == OpponentSkill.Kind.PUTT, "putt kind")
	_check(OpponentSkill.kind_of(false, true, true, 300.0) == OpponentSkill.Kind.DRIVE, "drive kind")
	_check(OpponentSkill.kind_of(false, true, false, 150.0) == OpponentSkill.Kind.APPROACH, "par 3 tee shot kind")
	_check(OpponentSkill.kind_of(false, false, false, 30.0) == OpponentSkill.Kind.CHIP, "chip kind")
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
	var cpu := ComputerGolfer.new(OpponentSkill.Level.TOUR, 5, TourPro.find("Callum Reid"))
	cpu.plan(model, clubs, hole, Vector3.ZERO, Surface.Type.GREEN, Vector3.ZERO)
	cpu.finish()
	_check(cpu.is_putt(), "putts on the green")
	_check(cpu.expected == 0.0, "plans to hole a flat 4 m putt (expects %f)" % cpu.expected)

	hole.terrain = FlatTerrain.new(Surface.Type.FAIRWAY)
	hole.pin = Vector3(10.0, 0.0, 140.0)
	cpu.plan(model, clubs, hole, Vector3.ZERO, Surface.Type.FAIRWAY, Vector3(3.0, 0.0, 0.0))
	cpu.finish()
	_check(cpu.accuracy > 0.0, "a fader plans a fade (%f)" % cpu.accuracy)
	var start := model.launch(clubs[cpu.club_index], cpu.power, cpu.accuracy, cpu.aim_deg, Surface.Type.FAIRWAY, Vector3.ZERO)
	var r := model.simulate(start, hole.terrain, hole.pin, Vector3(3.0, 0.0, 0.0))
	var miss := Vector2(r.rest.x - hole.pin.x, r.rest.z - hole.pin.z).length()
	print("  approach: %s at %.2f power, aim %.2f deg, %.1f m from the pin" % [clubs[cpu.club_index].short_name, cpu.power, cpu.aim_deg, miss])
	_check(not clubs[cpu.club_index].is_putter, "a full club from the fairway")
	_check(miss < 6.0, "approach plan ends within 6 m in a crosswind (%.1f m)" % miss)

	# After stroke and distance it doesn't play the same club out of bounds
	# again: the plan can't see a real swing catch a bunker lip.
	var first := cpu.club_index
	var ob := ShotResult.new()
	ob.outcome = ShotResult.Outcome.OUT_OF_BOUNDS
	ob.rest = Vector3(60.0, 0.0, 120.0)
	cpu.learn(Vector3(30.0, 0.0, 0.0), first, ob)  # from somewhere else: ignored
	cpu.plan(model, clubs, hole, Vector3.ZERO, Surface.Type.FAIRWAY, Vector3(3.0, 0.0, 0.0))
	cpu.finish()
	_check(cpu.club_index == first, "a result from another spot changes nothing")
	cpu.learn(Vector3.ZERO, first, ob)
	cpu.plan(model, clubs, hole, Vector3.ZERO, Surface.Type.FAIRWAY, Vector3(3.0, 0.0, 0.0))
	cpu.finish()
	print("  after %s went out of bounds: %s" % [clubs[first].short_name, clubs[cpu.club_index].short_name])
	_check(cpu.club_index != first, "doesn't repeat a club that just went out of bounds from here")
	cpu.end_hole(0)
	cpu.plan(model, clubs, hole, Vector3.ZERO, Surface.Type.FAIRWAY, Vector3(3.0, 0.0, 0.0))
	cpu.finish()
	_check(cpu.club_index == first, "forgets it on the next hole")

	var weak := ComputerGolfer.new(OpponentSkill.Level.BEGINNER, 5)
	weak.plan(model, clubs, hole, Vector3.ZERO, Surface.Type.FAIRWAY, Vector3.ZERO)
	weak.finish()
	_check(weak.power <= weak.skill.strength + 1e-6, "never swings harder than its strength")

	# Form and pressure: a clutch golfer tightens up less than a nervy one.
	var clutch := ComputerGolfer.new(OpponentSkill.Level.TOUR, 7, TourPro.find("Henrik Lindqvist"))
	var nervy := ComputerGolfer.new(OpponentSkill.Level.TOUR, 7, TourPro.find("Mateo Ibarra"))
	clutch.form = 1.0
	nervy.form = 1.0
	clutch.pressure = 1.0
	nervy.pressure = 1.0
	_check(clutch.error_scale() < 1.0 and nervy.error_scale() > 1.0, "pressure: clutch %.2f, nervy %.2f" % [clutch.error_scale(), nervy.error_scale()])
	var hot := ComputerGolfer.new(OpponentSkill.Level.TOUR, 7, TourPro.find("Ryan Cole"))
	hot.form = 1.0
	hot.end_hole(-1)
	hot.end_hole(-1)
	_check(hot.error_scale() < 1.0, "a streaky golfer on a run of birdies gets hot (%.3f)" % hot.error_scale())
	_check(TourPro.find("Ryan Cole").routine_s < TourPro.find("Kenji Morita").routine_s, "a fast and a slow player")
	var quick := ComputerGolfer.new(OpponentSkill.Level.TOUR, 7, TourPro.find("Ryan Cole"))
	var slow := ComputerGolfer.new(OpponentSkill.Level.TOUR, 7, TourPro.find("Kenji Morita"))
	_check(quick.address_time() + quick.think_time() < slow.address_time() + slow.think_time(), "routine pace")


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

	_check(GolfBag.shared_mesh().get_surface_count() == 5, "bag is one mesh of five materials")
	_check(GolfBag.simple_mesh().get_surface_count() == 3, "simple bag is one mesh of three materials")
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
	# Rear drum brakes only, as on real fleet carts: about 0.3 g on grass,
	# held back by the grip of the rear tyres.
	_check(t * dt < 2.6 and d.position.z - from < 9.0 and d.position.z - from > 4.0, "rear brakes stop it in a few metres")
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
	var noise := BuggySound.whine_clip()
	_check(noise.loop_mode == AudioStreamWAV.LOOP_FORWARD and noise.data.size() == BuggySound.RATE * 2, "a second of motor whine, looping")
	b.sound.update(BuggyDrive.GOVERNED, 1.0, 1.0)
	var loud: float = (b.sound.get_child(0) as AudioStreamPlayer3D).volume_db
	b.sound.update(0.0, 0.0, 0.0)
	_check(loud > -20.0 and (b.sound.get_child(0) as AudioStreamPlayer3D).volume_db < -60.0, "the motor whines at speed and is silent stopped")
	b.park(Vector3(5.0, 0.0, 5.0), 90.0, fairway)
	for i in 30:
		b.step(dt, 1.0, 0.0, fairway)
	_check(b.position.x > 5.0, "the model moves with the drive (%s)" % b.position)
	var view: Array = b.chase(0.1, fairway)
	_check((view[0] as Vector3).x < b.position.x, "the chase camera sits behind")
	b.free()


## Everything at its real size: the cart against the published dimensions
## of a current two-seat fleet cart, the golfer and caddie against an average man, the
## bag, the ball and the hole against the Rules of Golf.
func _test_real_scale() -> void:
	var cart := (load(GolfBuggy.MODEL_PATH) as PackedScene).instantiate() as Node3D
	var body := cart.find_child("Body", true, false) as MeshInstance3D
	var box := body.get_aabb()
	var wheel := cart.find_child("Wheel_RR", true, false) as MeshInstance3D
	var outer := wheel.position.x + wheel.get_aabb().end.x
	print("  cart: %.2f m long, %.2f m wide, %.2f m high, wheels %.3f m radius" % [box.size.z, maxf(box.size.x, 2.0 * outer), box.end.y, wheel.get_aabb().end.y])
	_check_near(box.size.z, 2.38, 0.02, "cart length (2.38 m)")
	_check_near(maxf(box.size.x, 2.0 * outer), 1.20, 0.02, "cart width (1.20 m)")
	_check_near(box.end.y, 1.765, 0.02, "cart height to the sun top (1.765 m)")
	_check_near(wheel.get_aabb().end.y, 0.2286, 0.003, "18 in tyres")
	_check_near(absf((cart.find_child("Wheel_FR", true, false) as Node3D).position.z - wheel.position.z), BuggyDrive.WHEELBASE, 0.01, "wheelbase matches the physics")
	cart.free()
	var golfer := FreeGolfer.create()
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
	_check(bag.size.y > 1.2 and bag.size.y < 1.4, "staff bag with the driver's cover about 1.3 m up (%.2f)" % bag.size.y)
	_test_props_real_size()
	_check_near(BallPhysics.RADIUS * 2.0, 0.04267, 0.0001, "ball 42.67 mm across")
	_check_near(BallPhysics.CUP_RADIUS * 2.0, 0.108, 0.001, "hole 108 mm across")


## The course props are their real size (docs/props.md), and the tee
## furniture and rakes go where they should.
func _test_props_real_size() -> void:
	var sizes := {
		"tee_marker": [Vector3(0.127, 0.115, 0.127), 0.01],
		"ball_washer": [Vector3(0.5, 1.28, 0.5), 0.03],
		"tee_sign": [Vector3(0.71, 1.74, 0.08), 0.03],
		"tee_bench": [Vector3(1.54, 0.97, 0.63), 0.04],
		"bunker_rake": [Vector3(0.64, 0.06, 1.42), 0.02],
		"yardage_plate": [Vector3(0.304, 0.034, 0.204), 0.01],
		"yardage_pole": [Vector3(0.09, 2.04, 0.09), 0.02],
		"sponsor_sign": [Vector3(0.61, 0.985, 0.075), 0.02],
		"water_station": [Vector3(0.76, 1.38, 0.745), 0.03],
		"practice_flag": [Vector3(0.228, 0.718, 0.043), 0.01],
		"course_sign": [Vector3(0.3, 0.195, 0.012), 0.01],
		"tee_peg": [Vector3(0.011, 0.0705, 0.011), 0.002],
		"flagstick": [Vector3(0.0196, 2.2375, 0.0196), 0.005],
	}
	for prop: String in sizes:
		var m := CourseProps.mesh(prop)
		_check(m != null, "%s model loads" % prop)
		if m == null:
			continue
		var want: Vector3 = sizes[prop][0]
		var got := m.get_aabb().size
		var tol: float = sizes[prop][1]
		_check(absf(got.x - want.x) < tol and absf(got.y - want.y) < tol and absf(got.z - want.z) < tol,
				"%s is %.2f x %.2f x %.2f m (want %.2f x %.2f x %.2f)" % [prop, got.x, got.y, got.z, want.x, want.y, want.z])
	# A bunker 20 m right of the line, 100 m out: one rake, at its edge, the
	# handle pointing out of the sand.
	var t := _BunkerTerrain.new()
	var route := PackedVector2Array([Vector2(0, 150)])
	var rakes := CourseProps.rake_spots(t, Vector3.ZERO, Vector3(0, 0, 150), route, 8)
	_check(rakes.size() == 1, "one rake for one bunker (%d)" % rakes.size())
	if rakes.size() == 1:
		var head: Vector3 = rakes[0][0]
		var out: Vector3 = rakes[0][1]
		_check(t.surface_at(head.x, head.z) == Surface.Type.SAND, "rake head in the sand")
		var tip := head + out * CourseProps.RAKE_LENGTH
		_check(t.surface_at(tip.x, tip.z) != Surface.Type.SAND, "rake handle out over the grass")
		_check(head.x < -12.0, "rake on the side of the bunker facing the line (%.1f)" % head.x)
	# 150 yards back from the pin along a dogleg, and the fairway's edge.
	var dog := PackedVector2Array([Vector2(0, 200), Vector2(100, 200)])
	var at := CourseProps.point_back_from_pin(Vector3.ZERO, Vector3(200, 0, 200), dog, 150.0)
	_check((at[0] as Vector3).distance_to(Vector3(50, 0, 200)) < 0.01, "150 m back along the route (%s)" % at[0])
	_check((at[1] as Vector3).distance_to(Vector3(1, 0, 0)) < 0.01, "line runs towards the pin there")
	at = CourseProps.point_back_from_pin(Vector3.ZERO, Vector3(200, 0, 200), dog, 250.0)
	_check((at[0] as Vector3).distance_to(Vector3(0, 0, 150)) < 0.01, "250 m back is round the dogleg (%s)" % at[0])
	_check((at[1] as Vector3).distance_to(Vector3(0, 0, 1)) < 0.01, "and the line there runs up the first leg")
	var edge := CourseProps.fairway_edge(_FairwayTerrain.new(), Vector3(0, 0, 100), Vector3(0, 0, 1))
	_check(absf(edge.x + 16.0) < 0.01, "pole a metre into the rough on the right (%s)" % edge)
	# Tee furniture keeps out of water: the right is a pond, so it goes left.
	var spot := CourseProps.tee_spot(t, Vector3(0, 0, 0), Vector3(0, 0, 100), CourseProps.WASHER_SPOT)
	_check(spot != Vector3.INF and spot.x > 0.0, "tee furniture on the dry side (%s)" % spot)


## A 30 m fairway down the z axis, rough either side.
class _FairwayTerrain extends CourseTerrain:
	func surface_at(x: float, _z: float) -> int:
		return Surface.Type.FAIRWAY if absf(x) < 15.0 else Surface.Type.ROUGH


## Flat fairway with a pond right of the tee and a 10 m bunker 100 m out.
class _BunkerTerrain extends CourseTerrain:
	func surface_at(x: float, z: float) -> int:
		if x < -2.0 and x > -12.0 and z > -8.0 and z < 4.0:
			return Surface.Type.WATER
		if x < -15.0 and x > -25.0 and z > 95.0 and z < 105.0:
			return Surface.Type.SAND
		return Surface.Type.FAIRWAY


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
	_check(SettingsPanel.scroll_height(1100.0, 120.0, 720.0) == 584.0, "settings: the rows scroll in a 720p window")
	_check(SettingsPanel.scroll_height(400.0, 120.0, 720.0) == 400.0, "settings: no scrolling when they fit")
	# Heat shimmer: a level camera has the horizon mid-screen, one tipped
	# down sees it higher up, and the top edge is half the lens away.
	_check(is_equal_approx(PostProcess.horizon_screen_y(0.0, 0.7), 0.5), "shimmer: level camera, horizon mid-screen")
	_check(PostProcess.horizon_screen_y(-0.1, 0.7) < 0.5, "shimmer: camera tipped down, horizon higher")
	_check(is_equal_approx(PostProcess.horizon_screen_y(-0.35, 0.7), 0.0), "shimmer: horizon at the top edge")
	# The sun found in a sky photo: a bright spot a quarter of the way
	# across, a quarter of the way down (45 degrees up).
	var sky_img := Image.create(64, 32, false, Image.FORMAT_RGBF)
	sky_img.fill(Color(0.3, 0.4, 0.6))
	sky_img.set_pixel(16, 8, Color(500.0, 500.0, 480.0))
	var found := FreeAssets.sun_in_image(sky_img)
	_check(absf(found.x - 16.5 / 64.0) < 0.01 and absf(found.y - PI * (0.5 - 8.5 / 32.0)) < 0.01, "sky sun: found in the photo (%s)" % found)
	sky_img.set_pixel(16, 8, Color(0.5, 0.5, 0.6))
	_check(FreeAssets.sun_in_image(sky_img).x < 0.0, "sky sun: none in a grey sky")
	var mapped := Scenery.sky_sun_mapping(Vector3(0.0, 0.5, 0.866), deg_to_rad(48.0))
	_check(absf(mapped.y - deg_to_rad(30.0)) < 0.001, "sky sun: the photo's sun is moved down to a 30 degree sun")
	_check(absf(Scenery.sky_sun_mapping(Vector3(0.0, 0.156, 0.988), deg_to_rad(48.0)).y - deg_to_rad(28.8)) < 0.001, "sky sun: a low sun stretches the sky at most 40%")
	# The learned grade: a 32-cubed lookup per time of day and renderer.
	for t in [GraphicsSettings.TimeOfDay.AFTERNOON, GraphicsSettings.TimeOfDay.MORNING, GraphicsSettings.TimeOfDay.MIDDAY, GraphicsSettings.TimeOfDay.GOLDEN]:
		for fwd in [false, true]:
			var lut := PostProcess.lut_for(t, fwd)
			_check(lut != null and lut.get_width() == 1024 and lut.get_height() == 32, "grade: lookup for time %d (forward %s)" % [t, fwd])
	var lut_img := PostProcess.lut_for(GraphicsSettings.TimeOfDay.AFTERNOON, false).get_image()
	_check(lut_img.get_pixel(0, 0).get_luminance() < 0.1 and lut_img.get_pixel(1023, 31).get_luminance() > 0.9, "grade: black stays dark and white stays bright")
	# The TV cameraman's drift stays tiny, and grows while panning.
	var most := 0.0
	var most_pan := 0.0
	for i in 600:
		most = maxf(most, RoundCamera.operator_offset(i * 0.1, 0.0).length())
		most_pan = maxf(most_pan, RoundCamera.operator_offset(i * 0.1, 1.0).length())
	_check(most > 0.0 and most < deg_to_rad(0.1), "camera operator: resting drift under 0.1 degree")
	_check(most_pan > most and most_pan < deg_to_rad(0.3), "camera operator: more drift while panning, under 0.3 degree")
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
	s.ui_scale = 3
	s.gimme = 2
	s.mulligans = 1
	s.pickup = 2
	s.captions = true
	s.launch_monitor = true
	s.save(path)
	var loaded := GraphicsSettings.load_saved(path)
	_check(loaded.ui_scale == 3 and GraphicsSettings.new().ui_scale == 1, "interface size saved, normal by default")
	_check(loaded.gimme == 2 and loaded.mulligans == 1 and loaded.launch_monitor, "house rules and launch monitor saved")
	_check(loaded.pickup == 2 and GraphicsSettings.new().pickup == 0, "pick up saved, off by default")
	_check(loaded.captions and not GraphicsSettings.new().captions, "captions saved, off by default")
	_check(SoundCaptions.voice("Great Shot!") == "[Golfer: Great Shot]" and SoundCaptions.voice("Birdie", "Ann") == "[Ann: Birdie]"
			and SoundCaptions.voice("") == "", "voice captions")
	_check(SoundCaptions.crowd(&"crowd_roar") == "[The crowd roars]" and SoundCaptions.crowd(&"club") == "", "crowd captions")
	_check(GolfRound.pickup_limit(0, 4) == GolfRound.MAX_STROKES and GolfRound.pickup_limit(1, 3) == 6
			and GolfRound.pickup_limit(1, 5) == GolfRound.MAX_STROKES and GolfRound.pickup_limit(2, 4) == 7,
			"pick-up scores: off, double par, triple bogey, never past the limit")
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
	cfg = ConfigFile.new()
	cfg.set_value("graphics", "look", GraphicsSettings.Look.NATURAL)
	cfg.set_value("graphics", "grass", 0)
	cfg.set_value("graphics", "fov", 50.0)
	cfg.save(path)
	loaded = GraphicsSettings.load_saved(path)
	var natural := GraphicsSettings.new()
	natural.apply_look(GraphicsSettings.Look.NATURAL)
	_check(loaded.look == GraphicsSettings.Look.NATURAL and loaded.grass == natural.grass, "presets saved by an older version are redone")
	_check_near(loaded.fov, 40.0, 1e-6, "the old default lens moves to the long lens")
	_check(RoundCamera.lens_factor(50.0) == 1.0 and RoundCamera.lens_factor(40.0) > 1.2, "a longer lens stands the aim view further back")
	loaded.save(path)
	cfg.load(path)
	_check(int(cfg.get_value("graphics", "look_version", 0)) == GraphicsSettings.LOOK_VERSION, "look version saved")
	_check(not GraphicsSettings.web_capable(), "the higher web tier is for the browser only")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	loaded = GraphicsSettings.load_saved(path)
	_check(loaded.look == GraphicsSettings.detect_look(), "first run gets a look for the device")
	GraphicsSettings.force_look = GraphicsSettings.Look.CLASSIC
	loaded = GraphicsSettings.load_saved(path)
	GraphicsSettings.force_look = -1
	_check(loaded.look == GraphicsSettings.Look.CLASSIC, "forced look")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# The desktop launcher's requests: a look, then a quality, applied once.
	cfg = ConfigFile.new()
	cfg.set_value("graphics", "look", GraphicsSettings.Look.CLASSIC)
	cfg.set_value("graphics", "look_version", GraphicsSettings.LOOK_VERSION)
	cfg.set_value("graphics", "display_mode", GraphicsSettings.DisplayMode.EXCLUSIVE)
	cfg.set_value("graphics", "window_width", 1920)
	cfg.set_value("graphics", "window_height", 1080)
	cfg.set_value("launcher", "look", GraphicsSettings.Look.NATURAL)
	cfg.save(path)
	loaded = GraphicsSettings.load_saved(path)
	_check(loaded.look == GraphicsSettings.Look.NATURAL and loaded.grass == natural.grass, "the launcher's look is applied")
	_check(loaded.display_mode == GraphicsSettings.DisplayMode.EXCLUSIVE and loaded.window_size == Vector2i(1920, 1080), "display mode and window size load")
	cfg = ConfigFile.new()
	cfg.load(path)
	_check(not cfg.has_section("launcher") and int(cfg.get_value("graphics", "look", -1)) == GraphicsSettings.Look.NATURAL, "launcher requests are used up and saved")
	cfg.set_value("launcher", "quality", GraphicsSettings.Quality.LOW)
	cfg.save(path)
	loaded = GraphicsSettings.load_saved(path)
	_check(loaded.quality == GraphicsSettings.Quality.LOW and loaded.look == GraphicsSettings.Look.CUSTOM, "the launcher's quality makes the look custom")
	cfg = ConfigFile.new()
	cfg.set_value("audio", "master", 50)
	cfg.set_value("audio", "music", 0)
	cfg.save(path)
	_check_near(AudioSettings.level("master", path), 0.5, 1e-6, "master volume")
	_check(AudioSettings.music_db(path) <= -79.0 and AudioSettings.level("effects", path) == 1.0, "music off, unset volumes full")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for g in GraphicsSettings.Grade.values():
		_check(g < PostProcess.GRADES.size(), "grade %d has values" % g)
	_check(GraphicsSettings.TIME_NAMES.size() == GraphicsSettings.TimeOfDay.size(), "a name per time of day")
	var noon := Scenery.time_light(GraphicsSettings.TimeOfDay.MIDDAY, 0.0)
	var dawn := Scenery.time_light(GraphicsSettings.TimeOfDay.ROUND, 0.0)
	var half := Scenery.time_light(GraphicsSettings.TimeOfDay.ROUND, 0.5)
	var dusk := Scenery.time_light(GraphicsSettings.TimeOfDay.ROUND, 1.0)
	_check(noon.elevation > dawn.elevation and dawn.elevation > dusk.elevation, "the sun is highest at midday, lowest at golden hour")
	_check(half.elevation < noon.elevation and half.elevation > Scenery.TIMES["afternoon"].elevation, "through the round blends the light (%.1f)" % half.elevation)
	_check((dusk.sun as Color).b < (noon.sun as Color).b, "golden hour sun is warm")
	_check(Scenery.time_light(GraphicsSettings.TimeOfDay.AFTERNOON, 0.7).elevation == Scenery.TIMES["afternoon"].elevation, "afternoon is the afternoon sun at any point of the round")


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
		var low := 1.2 if spec[0] == TreeFactory.Species.BUSH else 8.0
		var high := 3.5 if spec[0] == TreeFactory.Species.BUSH else 19.0
		_check(box.end.y > low and box.end.y < high and box.position.y > -0.5, "tree %d is its species' size (%.1f m)" % [v, box.end.y])
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
	# The TV tracer stops at the first landing, not after the bounces.
	var sr := ShotResult.new()
	sr.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 20, 50), Vector3(0, 0.1, 99), Vector3(0, 2, 105), Vector3(0, 0, 110)])
	sr.first_landing = Vector3(0, 0, 100)
	sr.carry_m = 100.0
	_check(GolfRound.tracer_end(sr) == 2, "the tracer ends at the first landing")
	sr.carry_m = 0.0
	_check(GolfRound.tracer_end(sr) == 4, "a putt's trace runs to the end")
	# The green-side inset tilts up at most 12 degrees after a high ball.
	var pt := GolfRound.pip_target(Vector3(0, 2, 0), Vector3(0, 40, 100))
	_check_near(rad_to_deg(atan2(pt.y - 2.0, 100.0)), GolfRound.PIP_MAX_TILT, 1e-3, "the inset camera stays on the green")
	_check_near(GolfRound.pip_target(Vector3(0, 2, 0), Vector3(0, 1, 30)).y, 1.0, 1e-6, "the inset follows a low ball")
	# Tee markers stand square to the line of the hole, 5.5 m apart.
	var tm := GolfRound.tee_marker_spots(Vector3.ZERO, Vector3(100, 0, 0))
	_check_near(tm[0].distance_to(tm[1]), GolfRound.TEE_MARKER_GAP, 1e-4, "tee markers 5.5 m apart")
	_check_near(absf(tm[0].z - tm[1].z), GolfRound.TEE_MARKER_GAP, 1e-4, "tee markers square to an east-bound hole")
	_check(tm[0].x > 0.0 and tm[1].x > 0.0, "tee markers just in front of the ball")
	var all_clubs := Club.standard_set()
	_check_near(CourseMarks.stance_for(all_clubs[0]), CourseMarks.STANCE_WOOD, 1e-6, "the driver stands 0.93 m off the ball")
	_check_near(CourseMarks.stance_for(all_clubs[11]), CourseMarks.STANCE_IRON, 1e-6, "the sand wedge stands closer, 0.62 m")


func _test_gallery() -> void:
	_check_near(Gallery.rope_drop(0.0), 0.0, 1e-6, "the rope is at full height at a stake")
	_check_near(Gallery.rope_drop(0.5), Gallery.ROPE_SAG, 1e-6, "the rope sags most mid-span")
	var course := PlaceholderCourseLoader.new().load_course("")
	var hole: HoleData = course.holes[0]
	var t := hole.terrain
	var lines := Gallery.tee_lines(t, hole.tee, hole.pin)
	_check(lines.size() >= 2, "gallery ropes down both sides of the tee (%d)" % lines.size())
	var ok := true
	for line in lines:
		for k in line.size() - 1:
			ok = ok and absf(Vector2(line[k].x, line[k].z).distance_to(Vector2(line[k + 1].x, line[k + 1].z)) - Gallery.STAKE_GAP) < 0.01
	_check(ok, "gallery stakes 4 m apart")
	lines.append_array(Gallery.green_lines(t, hole.pin, hole.tee))
	var spots := Gallery.crowd_spots(hole, lines, 20, 7)
	_check(spots.size() > 0 and spots.size() <= 20, "a crowd behind the ropes (%d)" % spots.size())
	var placed := true
	for i in spots.size():
		var p: Vector3 = spots[i][0]
		var s := t.surface_at(p.x, p.z)
		placed = placed and s != Surface.Type.GREEN and s != Surface.Type.SAND and s != Surface.Type.WATER
		for j in i:
			placed = placed and p.distance_to(spots[j][0]) >= Gallery.CROWD_SPACING - 1e-3
	_check(placed, "spectators off the greens and bunkers, not on top of each other")
	var g := Gallery.build(hole, hole.pin, 3, 7, true)
	root.add_child(g)
	_check(g.crowd_count() <= 3, "the crowd keeps to its count")
	var spot := Gallery.grandstand_spot(hole)
	if not spot.is_empty():
		var capacity := Gallery.STAND_ROWS * (int(Gallery.STAND_WIDTH / Gallery.STAND_SEAT) - 1)
		_check(g.seated_count() > capacity / 2 and g.seated_count() <= capacity, "a grandstand full of people (%d)" % g.seated_count())
		var front: Vector3 = spot[0]
		_check(front.distance_to(hole.pin) > Gallery.GREEN_MARGIN + Gallery.STAND_BACK, "the grandstand stands back from the green")
	_check(g.card_count() > 0 and g.card_count() <= Gallery.CARDS_BY_QUALITY[3], "crowd cards fill in behind the 3D people (%d)" % g.card_count())
	var cards := Gallery.card_spots(hole, lines, spots, 120, 7)
	var spaced := cards.size() > 0
	for i in cards.size():
		var c := cards[i]
		var cs := t.surface_at(c.x, c.z)
		spaced = spaced and cs != Surface.Type.GREEN and cs != Surface.Type.SAND and cs != Surface.Type.WATER
		for spot_i: Array in spots:
			var q: Vector3 = spot_i[0]
			spaced = spaced and Vector2(q.x - c.x, q.z - c.z).length() >= Gallery.CARD_SPACING - 1e-3
		for j in i:
			spaced = spaced and Vector2(cards[j].x - c.x, cards[j].z - c.z).length() >= Gallery.CARD_SPACING - 1e-3
	_check(spaced, "crowd cards off greens, bunkers and water, clear of people and each other")
	var low := Gallery.build(hole, hole.pin, 0, 7, false, 0)
	root.add_child(low)
	_check(low.crowd_count() == 0 and low.card_count() <= Gallery.CARDS_BY_QUALITY[0], "Low quality: cards only, no 3D people")
	low.free()
	var yaw := Gallery.facing_yaw(Vector3.ZERO, Vector3(3, 0, 4))
	var facing := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	_check(facing.distance_to(Vector3(0.6, 0, 0.8)) < 1e-4, "spectators face what they watch")
	g.watch_point(hole.tee + Vector3.UP)
	_check(g.murmur_db() == Gallery.MURMUR_DB, "the gallery murmurs")
	g.react(Commentary.Crowd.ROAR)
	g.free()
	_check_near(Gallery.stand_depth(), 6.8, 1e-4, "eight bleacher rows of 0.85 m")


func _test_course_life() -> void:
	var life := CourseLife.new()
	root.add_child(life)
	life.set("_wait", 1e9)  # no flocks but the one this test starts
	life.spawn(Vector3.ZERO)
	_check(life.flock_count() == 1, "a flock of birds sets off")
	var node := life.get_child(0) as MultiMeshInstance3D
	var start := node.position
	_check(start.y >= CourseLife.MIN_HEIGHT and start.y <= CourseLife.MAX_HEIGHT, "birds fly high over the course")
	life.step(1.0, Vector3.ZERO)
	_check_near(node.position.distance_to(start), CourseLife.SPEED, 1e-3, "birds fly at their speed")
	var n := node.multimesh.instance_count
	_check(n >= 3 and n <= 9, "a small flock (%d)" % n)
	for i in ceili(CourseLife.CROSS_DIST / CourseLife.SPEED) + 1:
		life.step(1.0, Vector3.ZERO)
	_check(life.flock_count() == 0, "flocks leave once they've crossed")
	life.free()


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
	_check(game.free_ambience != null and game.free_ambience.get_child_count() == 7, "free ambience beds, road, mower, insects and birdcalls")
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
	# Faster greens than the round was played on.
	tampered = RoundRecord.from_json(rec.to_json())
	_check(tampered.green_firmness == rec.green_firmness and tampered.green_speed == rec.green_speed, "the record keeps the greens")
	tampered.green_speed = LinksGround.GreenSpeed.SLOW if rec.green_speed == LinksGround.GreenSpeed.FAST else LinksGround.GreenSpeed.FAST
	# Only Links 2003's own ground (LinksGround) has the green options.
	if rec.model == "links":
		_check(not RoundReplay.verify(tampered, game.shot_model, game.clubs, game.holes).ok, "other greens are caught")
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


## Two games in one online room play the same round in step: each plays its
## own player's shots and replays the other's, and they agree on every shot,
## drop and card. A computer golfer belongs to the host.
func _test_online_round() -> void:
	var setup := RoundSetup.single("")
	setup.names.assign(["Ann", "Bo", "Club pro"])
	setup.computer.assign([RoundSetup.HUMAN, RoundSetup.HUMAN, 1])
	setup.teams.assign([0, 1, 0])
	setup.holes = RoundSetup.Holes.FRONT_NINE
	setup.round_seed = 4321
	setup.wind_level = Wind.Level.STRONG
	var owners: Array[int] = [0, 1, 0]
	var msg := OnlineRound.setup_message(setup, 4321, Wind.Level.STRONG, owners, "")
	var copy := OnlineRound.setup_from(JSON.parse_string(JSON.stringify(msg)))
	_check(copy != null and copy.names == setup.names and copy.computer == setup.computer and copy.round_seed == 4321 and copy.wind_level == Wind.Level.STRONG,
		"the setup message carries the round")
	_check(OnlineRound.owners_from(msg) == owners, "and who plays each seat")
	setup.pins = 1
	var pins_copy := OnlineRound.setup_from(JSON.parse_string(JSON.stringify(OnlineRound.setup_message(setup, 4321, Wind.Level.STRONG, owners, ""))))
	_check(pins_copy != null and pins_copy.pins == 1, "the setup message carries the hole positions")
	setup.pins = 0
	var links := LoopbackLink.room(2)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var games: Array[GolfRound] = []
	for seat in 2:
		GolfRound.setup = OnlineRound.setup_from(JSON.parse_string(JSON.stringify(msg)))
		var g := scene.instantiate() as GolfRound
		g.online = OnlineRound.new(links[seat], seat, owners)
		root.add_child(g)
		games.append(g)
	GolfRound.setup = null
	var a := games[0]
	var b := games[1]
	_check(a.round_seed == 4321 and b.round_seed == 4321 and b.wind.level == Wind.Level.STRONG, "both games play the host's seed and wind")
	var own_pickup := a.graphics.pickup
	a.graphics.pickup = 1
	_check(not a._house_rules() and a._pickup_at() == GolfRound.MAX_STROKES, "online: no own pick-up, gimmes or mulligans")
	a.graphics.pickup = own_pickup
	var dropped := false
	var steps := 0
	while not (a.state == GolfRound.State.ROUND_DONE and b.state == GolfRound.State.ROUND_DONE) and steps < 6000:
		# Bo takes an unplayable lie once, on his own machine.
		if not dropped and b.state == GolfRound.State.AIM and b.shooter == 1 and b.lie != Surface.Type.TEE and b.lie != Surface.Type.GREEN:
			b._start_drop(DropRules.Reason.UNPLAYABLE)
			b._move_drop(1.0, 0.0)
			dropped = true
		a.auto_play_step()
		b.auto_play_step()
		steps += 1
	_check(a.state == GolfRound.State.ROUND_DONE and b.state == GolfRound.State.ROUND_DONE, "both games finish the round (%d steps, states %d %d)" % [steps, a.state, b.state])
	_check(dropped and a.record.drops.size() == b.record.drops.size() and b.record.drops.size() >= 1, "Bo's drop reached the host: %d %d" % [a.record.drops.size(), b.record.drops.size()])
	_check(a.record.shots.size() == b.record.shots.size() and a.record.shots.size() > 20, "the same shots: %d and %d" % [a.record.shots.size(), b.record.shots.size()])
	var same := true
	for i in mini(a.record.shots.size(), b.record.shots.size()):
		var x := a.record.shots[i]
		var y := b.record.shots[i]
		same = same and x.player == y.player and x.rest.distance_to(y.rest) < 1e-3 and x.wind.distance_to(y.wind) < 1e-4
	_check(same, "every shot stops in the same place on both machines")
	_check(a.online.mismatches == 0 and b.online.mismatches == 0, "no shot disagreed")
	for i in 3:
		_check(str(a.scoring.cards[i].strokes) == str(b.scoring.cards[i].strokes), "%s's card agrees: %s" % [setup.names[i], a.scoring.cards[i].strokes])
	var computer_shots := 0
	for r in b.record.shots:
		computer_shots += 1 if r.player == 2 else 0
	_check(computer_shots > 0, "the host's computer golfer played on the guest's machine too")
	print("  online: %d shots, %d events, cards %s / %s / %s" % [a.record.shots.size(), a.online.seq,
		a.scoring.cards[0].strokes, a.scoring.cards[1].strokes, a.scoring.cards[2].strokes])
	for g in games:
		g.queue_free()
	_test_online_lobby()


## The lobby: the host picks the course and starts; the guest's game gets the
## same setup, seed and seats, and refuses a course it doesn't have.
func _test_online_lobby() -> void:
	var links := LoopbackLink.room(2)
	var panels: Array[OnlinePanel] = []
	var started: Array = []
	for seat in 2:
		var p := OnlinePanel.new()
		root.add_child(p)
		p.open(PackedStringArray(["Placeholder Nine (built in)"]), ["Ann", "Bo"][seat])
		p.use_link(links[seat])
		p.handle({"type": "welcome", "you": seat + 1, "seat": seat, "host": 1, "code": "ABCD"})
		p.handle({"type": "members", "host": 1, "members": [{"id": 1, "name": "Ann", "seat": 0}, {"id": 2, "name": "Bo", "seat": 1}]})
		p.start_pressed.connect(func(s: RoundSetup, i: int, r: OnlineRound) -> void: started.append([s, i, r]))
		panels.append(p)
	_check(panels[0]._host_box.visible and not panels[1]._host_box.visible, "only the host picks the course")
	panels[0]._computers.select(1)
	panels[0]._on_start()
	panels[1]._process(0.0)
	_check(started.size() == 2, "both games start")
	if started.size() == 2:
		var host_setup: RoundSetup = started[0][0]
		var guest_setup: RoundSetup = started[1][0]
		var guest: OnlineRound = started[1][2]
		_check(guest_setup.names == host_setup.names and host_setup.names.size() == 3 and guest_setup.computer == host_setup.computer,
			"the guest plays the host's players: %s" % [guest_setup.names])
		_check(guest_setup.round_seed == host_setup.round_seed and guest_setup.round_seed != 0, "and the host's seed")
		_check(guest.my_seat == 1 and str(guest.owners) == "[0, 1, 0]" and started[1][1] == 0, "Bo plays seat 1; the host plays the computer golfer")
	panels[1].use_link(links[1])
	panels[1].handle({"type": "setup", "course_file": "Nowhere.crz", "course_name": "Nowhere", "names": ["Ann", "Bo"],
		"computer": [-1, -1], "teams": [0, 1], "owners": [0, 1], "seed": 5})
	_check(panels[1]._status.text.contains("isn't among your courses"), "a course the guest doesn't have: %s" % panels[1]._status.text)
	for p in panels:
		p.queue_free()


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
	for stem: String in ["amb_traffic", "amb_murmur", "amb_mower"]:
		var layer := load("res://assets/sounds/%s.ogg" % stem) as AudioStreamOggVorbis
		_check(layer != null and layer.get_length() > 15.0, "%s is there" % stem)
	var park := FreeAmbience.Setting.PARKLAND
	_check(FreeAmbience.bed_db(park, "morning") > FreeAmbience.bed_db(park, "afternoon") + 6.0, "the dawn chorus is louder than the afternoon")
	_check(FreeAmbience.bed_db(park, "midday") <= FreeAmbience.bed_db(park, "afternoon"), "birds are quietest at midday")
	_check(FreeAmbience.bed_db(park, "afternoon") <= -28.0, "birdsong stays in the background")
	_check(FreeAmbience.bed_db(FreeAmbience.Setting.DESERT, "midday") > FreeAmbience.bed_db(FreeAmbience.Setting.DESERT, "morning"), "cicadas loudest in the heat")
	_check(FreeAmbience.has_calls(park) and not FreeAmbience.has_calls(FreeAmbience.Setting.SEASIDE), "birdcalls in parkland, not over the waves")
	_check(FreeAmbience.breeze_db(0.0) == FreeAmbience.BREEZE_FLOOR_DB, "leaves stir on a still day")
	_check(FreeAmbience.breeze_db(12.0) > FreeAmbience.breeze_db(3.0), "louder trees in a stronger wind")
	_check(Scenery.time_name(GraphicsSettings.TimeOfDay.ROUND, 0.0) == "morning" and Scenery.time_name(GraphicsSettings.TimeOfDay.ROUND, 1.0) == "golden", "the round runs from morning to evening")
	_check(Scenery.time_name(GraphicsSettings.TimeOfDay.AFTERNOON, 0.0) == "afternoon", "afternoon by default")
	var open := FreeAmbience.spot_levels(park, "afternoon", 3.0, 0.0, 0.0)
	var wooded := FreeAmbience.spot_levels(park, "afternoon", 3.0, 1.0, 0.0)
	_check(wooded.bed > open.bed + 6.0 and wooded.breeze > open.breeze, "birds and leaves louder under the trees than on an open fairway")
	var links := FreeAmbience.Setting.SEASIDE
	_check(FreeAmbience.spot_levels(links, "afternoon", 8.0, 0.0, 0.0).breeze > FreeAmbience.spot_levels(links, "afternoon", 8.0, 1.0, 0.0).breeze, "more wind out on an open links")
	_check(open.water == FreeAmbience.SILENT_DB and FreeAmbience.spot_levels(park, "afternoon", 3.0, 0.5, 1.0).water == FreeAmbience.WATER_DB, "water heard only near it")
	_check(FreeAmbience.water_for(5.0) == 1.0 and FreeAmbience.water_for(200.0) == 0.0 and FreeAmbience.water_for(46.0) > 0.0, "water fades with distance")
	_check(FreeAmbience.woods_for(0) == 0.0 and FreeAmbience.woods_for(100) == 1.0, "woods from the trees around")
	_check(FreeAmbience.water_distance(null, Vector3.ZERO) == INF, "no terrain, no water")
	var nowhere := Vector2(NAN, NAN)
	_check(FreeAmbience.setting_for_place("Placeholder Nine", nowhere) == FreeAmbience.Setting.PARKLAND, "unknown place: from the name")
	_check(FreeAmbience.setting_for_place("TPC Scottsdale", Vector2(33.64, -111.91)) == FreeAmbience.Setting.DESERT, "Scottsdale is desert")
	_check(FreeAmbience.setting_for_place("Emirates Golf Club", Vector2(25.09, 55.16)) == FreeAmbience.Setting.DESERT, "Dubai is desert")
	_check(FreeAmbience.setting_for_place("Augusta National", Vector2(33.50, -82.02)) == FreeAmbience.Setting.PARKLAND, "Augusta is parkland")
	_check(FreeAmbience.setting_for_place("St Andrews Links", Vector2(56.34, -2.80)) == FreeAmbience.Setting.SEASIDE, "a links by name wins")
	_check(FreeAmbience.setting_for_place("Gleneagles", Vector2(56.28, -3.75)) == FreeAmbience.Setting.WOODLAND, "Scottish highlands are woodland")
	_check(FreeAmbience.is_warm(Vector2(33.5, -82.0)) and not FreeAmbience.is_warm(Vector2(51.4, -0.6)) and not FreeAmbience.is_warm(nowhere), "cicadas in Georgia, not Surrey")
	_check(FreeAmbience.insects_db(park, true, "midday", 1.0) > FreeAmbience.insects_db(park, true, "morning", 1.0), "cicadas loudest at midday")
	_check(FreeAmbience.insects_db(park, false, "midday", 1.0) == FreeAmbience.SILENT_DB, "no cicadas somewhere cool")
	var trees: Array[PlacedObject] = [PlacedObject.new("oak", Vector3(50, 0, 0))]
	var spot := FreeAmbience.call_spot(trees, Vector3.ZERO)
	_check(Vector2(spot.x, spot.z).distance_to(Vector2(50, 0)) < 0.01 and spot.y >= FreeAmbience.CALL_HEIGHT.x, "birds call from up in the trees")


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
	for anim_name in [&"address", &"address_putt", &"backswing", &"swing", &"putt", &"celebrate", &"fist_pump", &"slump", &"upset", &"walk", &"idle", &"read", &"address_iron", &"backswing_iron", &"swing_iron"]:
		_check(golfer.has_animation(anim_name), "free golfer has %s" % anim_name)
	var made := PlaceholderGolferAssets.new().create_golfer()
	_check(made is FreeGolfer, "the placeholder assets use the free golfer")
	made.free()
	golfer.play(&"putt")
	golfer.play(&"address")
	# GolferHands: a grip for the driver, iron and putter, the right hand a
	# hand's width or so from the left; on for swings, off for the walk.
	var hands: GolferHands = golfer._hands
	var fresh := GolferHands.new()
	_check(fresh.influence == 0.0 and not fresh.holding, "the hands start free (a walk before any swing keeps them apart)")
	fresh.free()
	for ref: StringName in [&"ref_address", &"ref_address_iron", &"ref_address_putt"]:
		var gap := hands.grips.get(ref, Transform3D.IDENTITY).origin.length() as float
		_check(gap > 0.03 and gap < 0.2, "the %s grip has the right hand %.3f m from the left" % [ref, gap])
	hands.follow(&"swing_iron", 0.0)
	_check(hands.holding and hands.influence == 1.0, "both hands hold the club in a swing")
	hands.follow(&"walk", 0.0)
	_check(not hands.holding and hands.influence == 0.0, "the hands swing free on the walk")
	_test_club_heads(golfer)
	golfer.free()


## The clubs are modelled to real sizes (tools/golfer/clubs.py): each head's
## widest span, hosel and ferrule included, and the driver's crown, face and
## sole as separate surfaces so only the crown takes the player's colour.
func _test_club_heads(golfer: Node) -> void:
	var spans := {"Driver_head": [0.15, 0.19], "Iron_head": [0.12, 0.16], "Putter_head": [0.13, 0.17]}
	for node in golfer.find_children("*_head", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not spans.has(String(mi.name)):
			continue
		var pts := PackedVector3Array()
		var names: Array[String] = []
		for i in mi.mesh.get_surface_count():
			pts.append_array(mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX])
			names.append(mi.mesh.surface_get_material(i).resource_name)
		var span := 0.0
		for i in range(0, pts.size(), 3):
			for j in range(i + 3, pts.size(), 3):
				span = maxf(span, pts[i].distance_to(pts[j]))
		var want: Array = spans[String(mi.name)]
		_check(span > want[0] and span < want[1], "%s spans %.3f m" % [mi.name, span])
		_check(names.has("Ferrule"), "%s has a ferrule" % mi.name)
		if mi.name == "Driver_head":
			_check(names.has("DriverHead") and names.has("DriverFace") and names.has("DriverSole"), "driver crown, face and sole: %s" % [names])
		spans.erase(String(mi.name))
	_check(spans.is_empty(), "every club head found: %s left" % [spans.keys()])


## The player creator's looks: saved and read back, mapped to blend shapes,
## kept with the player's profile, and dressing the free golfer.
## PlayerFaceFit: measurements ignore a photo's size, position and tilt; the
## fit finds known sliders again from the golfer's own landmarks; colours are
## read from the right patches.
func _test_face_from_photo() -> void:
	var parts := GolferParts.shared()
	_check(parts != null and parts.info.has("face_fit"), "the look pack has face points")
	if parts == null or not parts.info.has("face_fit"):
		return
	var face_fit: Dictionary = parts.info.face_fit
	_check(face_fit.points == PlayerFaceFit.POINTS, "face points match the pack's")
	_check(PlayerFaceFit.MEDIAPIPE.size() == PlayerFaceFit.POINTS.size() and PlayerFaceFit.POINT_LABELS.size() == PlayerFaceFit.POINTS.size(), "every point has a MediaPipe index and a label")
	var n := PlayerFaceFit.FEATURE_NAMES.size()
	_check(PlayerFaceFit.OFFSET.size() == n and PlayerFaceFit.GAIN.size() == n and PlayerFaceFit.WEIGHT.size() == n, "calibration for every measurement")
	var base := PlayerFaceFit.model_points(face_fit, PlayerLook.new().shape_weights())
	var f0 := PlayerFaceFit.features(base)
	_check(f0.size() == n, "measurements")
	# The same face scaled, moved and tilted measures the same.
	var moved := PackedVector2Array()
	for p in base:
		moved.append(p.rotated(0.2) * 37.0 + Vector2(120, -40))
	var f1 := PlayerFaceFit.features(moved)
	var worst := 0.0
	for i in n:
		worst = maxf(worst, absf(f1[i] - f0[i]))
	_check(worst < 1e-4, "measurements don't depend on size or tilt (%.6f)" % worst)
	# Image pixels (y down) flip to the face frame.
	_check(PlayerFaceFit.from_image(PackedVector2Array([Vector2(3, 4)]))[0] == Vector2(3, -4), "pixels to the face frame")
	var marks := PackedVector2Array()
	for i in 478:
		marks.append(Vector2(i, 0))
	var picked := PlayerFaceFit.from_mediapipe(marks)
	_check(picked.size() == PlayerFaceFit.POINTS.size() and picked[0] == Vector2(33, 0) and picked[4] == Vector2((105 + 52) / 2.0, 0), "MediaPipe indices picked and averaged")
	_check(PlayerFaceFit.from_mediapipe(PackedVector2Array([Vector2.ZERO])).is_empty(), "too few MediaPipe landmarks is no face")
	# A known face, measured straight from the golfer (no photo error), fits
	# back close to its sliders; its body is kept.
	var truth := PlayerLook.new()
	truth.sex = 1.0
	var want := {"face_width": 0.5, "face_full": -0.4, "nose_width": 0.6, "nose_length": -0.5, "eye_size": 0.3, "eye_spacing": -0.6, "brows": 0.7, "mouth_width": -0.5}
	for key: String in want:
		truth.face[key] = want[key]
	var exact := {"offset": [], "gain": [], "weight": [], "regularise": 1e-6}
	for i in n:
		exact.offset.append(0.0)
		exact.gain.append(1.0)
		exact.weight.append(1.0)
	var start := PlayerLook.new()
	start.sex = 1.0
	start.face["chin"] = 0.4
	var got := PlayerFaceFit.fit(face_fit, start, PlayerFaceFit.model_points(face_fit, truth.shape_weights()), exact)
	var err := 0.0
	for key: String in want:
		err = maxf(err, absf(float(got.get(key, 9.0)) - float(want[key])))
	_check(err < 0.1, "fit finds a known face again (worst slider off by %.2f)" % err)
	_check(not got.has("chin") and start.face_value("chin") == 0.4, "sliders a photo can't show are left alone")
	_check(PlayerFaceFit.fit(face_fit, start, PackedVector2Array()).is_empty(), "no points, no fit")
	# Colours: a photo with skin-coloured cheeks and forehead and dark hair above.
	var img := Image.create(200, 200, false, Image.FORMAT_RGB8)
	img.fill(Color(0.1, 0.08, 0.06))
	img.fill_rect(Rect2i(40, 60, 120, 140), Color(0.8, 0.6, 0.5))
	var pts := PackedVector2Array([
		Vector2(70, 110), Vector2(90, 110), Vector2(110, 110), Vector2(130, 110),
		Vector2(80, 98), Vector2(120, 98),
		Vector2(100, 135), Vector2(90, 138), Vector2(110, 138),
		Vector2(85, 155), Vector2(115, 155), Vector2(100, 150), Vector2(100, 160),
		Vector2(100, 185), Vector2(60, 155), Vector2(140, 155), Vector2(50, 125), Vector2(150, 125),
		Vector2(65, 170), Vector2(135, 170),
	])
	var skin := PlayerFaceFit.skin_colour(img, pts)
	_check(skin.is_equal_approx(Color(0.8, 0.6, 0.5)) or skin.r > 0.78, "skin colour from the cheeks and forehead")
	var hair := PlayerFaceFit.hair_colour(img, pts)
	_check(hair.r < 0.15, "hair colour from above the forehead")


func _test_golfer_roster() -> void:
	var pros := GolferRoster.golfers()
	_check(pros.size() == 16, "sixteen tour pros on the roster")
	var seen := {}
	var women := 0
	var tones := {}
	for g in pros:
		var look: PlayerLook = g["look"]
		seen[str(g["name"]).to_lower()] = true
		women += 1 if look.sex >= 0.5 else 0
		tones[look.skin.to_html()] = true
		_check(look.outfit == "polo", "%s wears a polo" % g["name"])
		_check(look.height_cm >= 150.0 and look.height_cm <= 200.0, "%s is a real height" % g["name"])
		_check(look.sex < 0.5 or look.stubble == 0.0, "%s has no stubble" % g["name"])
	_check(seen.size() == pros.size(), "every pro has their own name")
	_check(women >= 5 and women <= 8, "men and women on the roster (%d women)" % women)
	_check(tones.size() >= 6, "skin tones vary across the roster (%d)" % tones.size())
	var callum := GolferRoster.find(" callum REID ")
	_check(not callum.is_empty() and callum["country"] == "SCO", "pros are found by name in any case")
	_check(GolferRoster.look_for("Callum Reid").key() == (callum["look"] as PlayerLook).key(), "a pro's own look")
	var a := GolferRoster.look_for("Somebody Else")
	_check(a.key() == GolferRoster.look_for("somebody else").key(), "an unknown name always gets the same look")
	_check(a.key() != GolferRoster.look_for("Another Golfer").key(), "unknown names look different")
	_check(is_equal_approx(GolferRoster.age_slider(25.0), 0.0) and GolferRoster.age_slider(54.0) > 0.4,
		"ages in years map to the age slider")
	# Random golfers follow real odds: red hair is rare, women don't wear
	# the short shorts, men have some stubble.
	var red := 0
	var shorts_women := 0
	var stubbled := 0
	for k in 400:
		var l := PlayerLook.random(k)
		if l.hair_colour == PlayerLook.HAIR_COLOURS[4][1]:
			red += 1
		if l.sex >= 0.5 and l.outfit == "shorts":
			shorts_women += 1
		if l.sex < 0.5 and l.stubble > 0.1:
			stubbled += 1
	_check(red < 20, "red hair is rare (%d of 400)" % red)
	_check(shorts_women == 0, "women golfers wear trousers")
	_check(stubbled > 60, "some men have stubble (%d)" % stubbled)
	var l2 := PlayerLook.new()
	l2.stubble = 0.6
	_check(is_equal_approx(PlayerLook.from_dict(l2.to_dict()).stubble, 0.6), "stubble is saved with the look")
	var parts := GolferParts.shared()
	if parts == null:
		return
	var shown := FreeGolfer.parts_for(PlayerLook.new(), parts.info)
	_check(shown.has("Collar_polo") and shown.has("Placket_polo") and shown.has("Buttons_polo"),
		"a polo has its collar, placket and buttons")
	var sleeves := PlayerLook.new()
	sleeves.outfit = "sleeves"
	_check(not FreeGolfer.parts_for(sleeves, parts.info).has("Collar_polo"), "collars only on polos")
	_check(int(parts.info.materials.Cap.texture) >= 0 and parts.texture(int(parts.info.materials.Cap.texture)) != null,
		"the cap has its stitched texture")
	_check(int(parts.info.materials.Skin.get("regions", -1)) >= 0, "the skin has its region map")
	var golfer := FreeGolfer.create(GolferRoster.look_for("Luis Navarro"))
	if golfer == null:
		return
	var body := golfer.find_child("Body", true, false) as MeshInstance3D
	var mat: Material = body.get_surface_override_material(0) if body.mesh.get_surface_count() > 1 else body.material_override
	_check(mat is ShaderMaterial and is_equal_approx(float((mat as ShaderMaterial).get_shader_parameter("stubble")), 0.7),
		"the skin shader shows the pro's stubble")
	var hair := golfer.find_child("Hair_side_part", true, false) as MeshInstance3D
	_check(hair != null and hair.material_override is ShaderMaterial, "hair uses the hair shader")
	golfer.free()


func _test_player_looks() -> void:
	var look := PlayerLook.new()
	look.sex = 1.0
	look.height_cm = 168.0
	look.weight = -0.5
	look.age = 0.25
	look.face["nose_width"] = 0.4
	look.face["jaw"] = -0.3
	look.hair = "ponytail"
	look.outfit = "shorts"
	look.cap = true
	look.ball = Color(1.0, 0.55, 0.15)
	var back := PlayerLook.from_dict(look.to_dict())
	_check(back.key() == look.key(), "a look reads back as saved")
	_check(back.wears_cap(), "a cap goes with a ponytail")
	_check(back.glove and not PlayerLook.from_dict({"glove": false}).glove, "the glove is on unless taken off")
	var pack := GolferParts.shared()
	if pack != null:
		var names := pack.bone_names()
		var left_hand := PackedInt32Array()
		for i in names.size():
			if names[i] == "hand_l" or (names[i].ends_with("_l") and names[i].split("_")[0] in FreeGolfer.GLOVE_FINGERS):
				left_hand.append(i)
		var gloved := 0
		for part_name: String in pack.info.parts:
			if not part_name.begins_with("Body"):
				continue
			var whole := pack.bake(part_name, {})
			var split := pack.bake(part_name, {}, left_hand)
			var tris := 0
			for s in split.get_surface_count():
				tris += split.surface_get_array_index_len(s)
			_check(tris == whole.surface_get_array_index_len(0), "%s keeps every triangle when the glove is split off" % part_name)
			if split.get_surface_count() > 1:
				gloved += split.surface_get_array_index_len(1) / 3
		_check(gloved > 200, "the glove covers the left hand (%d triangles)" % gloved)
	var w := look.shape_weights()
	_check(w.get("female") == 1.0 and w.get("thin") == 0.5 and w.get("old") == 0.25, "body shape weights: %s" % w)
	_check(w.get("nose_width_plus") == 0.4 and w.get("jaw_minus") == 0.3 and not w.has("jaw_plus"), "face shape weights: %s" % w)
	var odd := PlayerLook.from_dict({"hair": "mohawk", "height_cm": 400, "skin": "not a colour", "weight": -9})
	_check(odd.hair == "short" and odd.height_cm == PlayerLook.HEIGHT_MAX and odd.weight == -1.0, "bad values fall back")
	_check(PlayerLook.random(42).key() == PlayerLook.random(42).key(), "a computer golfer's look is the same every time")
	_check(PlayerLook.random(42).key() != PlayerLook.random(43).key(), "computer golfers look different")
	var hat := PlayerLook.new()
	hat.cap = true
	hat.hair = "afro"
	_check(not hat.wears_cap(), "no cap over an afro")

	var profiles := PlayerProfiles.new()
	_check(profiles.look_of("Zoe") == null, "no look before the creator")
	profiles.set_look("Zoe", look)
	_check(profiles.has_player("Zoe") and profiles.look_of("zoe ").key() == look.key(), "look kept with the profile")
	_check(profiles.rename("Zoe", "Zoë") and profiles.look_of("Zoë").key() == look.key() and not profiles.has_player("Zoe"),
		"renaming keeps the look")
	profiles.set_look("Ann", PlayerLook.new())
	_check(not profiles.rename("Zoë", "ann"), "can't rename onto another player")

	var parts := GolferParts.shared()
	_check(parts != null, "the look pack loads")
	if parts == null:
		return
	for style: String in PlayerLook.HAIR_STYLES:
		_check(style == "bald" or parts.has_part("Hair_" + style), "hair style %s in the pack" % style)
	for o: String in PlayerLook.OUTFITS:
		_check(parts.has_part("Top_" + o) and parts.has_part("Bottom_" + o), "outfit %s in the pack" % o)
	for entry: Array in PlayerLook.FACE:
		_check((parts.info.shapes as Dictionary).has(entry[0] + "_plus"), "face shape %s in the pack" % entry[0])
	var plain := parts.bake("Body", {})
	var shaped := parts.bake("Body", w)
	_check(plain != null and shaped != null and plain != shaped, "body baked plain and shaped")
	_check(parts.bake("Body", w) == shaped, "baked meshes are reused")
	var a: PackedVector3Array = plain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = shaped.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var moved := 0
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.001:
			moved += 1
	_check(a.size() == b.size() and moved > a.size() / 2, "the shape moves the body (%d of %d)" % [moved, a.size()])
	_check(parts.standing_height(w) < parts.standing_height({}) - 0.05, "a woman's body is shorter before scaling")
	var shown := FreeGolfer.parts_for(look, parts.info)
	_check(shown.has("Top_shorts") and shown.has("Hair_ponytail") and shown.has("Cap") and not shown.has("Top_polo"),
		"the look's parts: %s" % shown)
	var legs := ""
	for part_name in shown:
		if part_name.begins_with("Body_") and not FreeGolfer.parts_for(PlayerLook.new(), parts.info).has(part_name):
			legs = part_name
	_check(not legs.is_empty(), "shorts show skin that trousers cover: %s" % parts.info.body_chunks)

	var golfer := FreeGolfer.create(look)
	_check(golfer != null, "the free golfer dresses for a look")
	if golfer == null:
		return
	root.add_child(golfer)
	var skeleton := golfer.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head := skeleton.find_bone("head")
	var head_y := skeleton.get_bone_global_rest(head).origin.y
	_check(golfer.find_child("Hair_ponytail", true, false) != null, "the golfer has the look's hair")
	var model := golfer.get_child(0) as Node3D
	_check_near(model.scale.x * parts.standing_height(w), 1.68, 0.005, "scaled to the look's height")
	_check_near(model.position.z, FreeGolfer.BALL.z * (1.0 - model.scale.x), 1e-5, "scaled about the ball")
	golfer.apply_look(PlayerLook.new())
	_check(skeleton.get_bone_global_rest(head).origin.y > head_y + 0.05, "the skeleton fits the new shape")
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


## The built-in practice ground: the range's targets are greens at their
## yardages, the tee line is wide and flat, and the putting green is big.
func _test_practice_ground() -> void:
	var course := PracticeGround.new().load_course(PracticeGround.PATH)
	_check(course.holes.size() == 2, "a range and a putting green")
	var range_hole := course.holes[PracticeGround.RANGE]
	var t := range_hole.terrain
	var last := 0.0
	for i in PracticeGround.TARGETS.size():
		var p := PracticeGround.target_position(t, i)
		var yards := Vector2(p.x, p.z).distance_to(Vector2.ZERO) / PracticeGround.YARD
		_check(t.surface_at(p.x, p.z) == Surface.Type.GREEN, "target %d is a green" % i)
		_check(absf(Vector2(0, p.z).length() / PracticeGround.YARD - PracticeGround.TARGETS[i][0]) < 0.5 and yards > last, "target %d at %d yd down the range" % [i, PracticeGround.TARGETS[i][0]])
		var edge := p + Vector3(PracticeGround.target_radius(i) + 0.7, 0, 0)
		# The furthest is the terrain's own green, a blob shape: no exact edge.
		if i < PracticeGround.TARGETS.size() - 1:
			_check(t.surface_at(edge.x, edge.z) == Surface.Type.FRINGE, "target %d has a collar" % i)
		last = yards
	for x in [-30.0, -3.0, 0.0, 3.0, 30.0]:
		_check(t.surface_at(x, 0.0) == Surface.Type.TEE, "tee line at x %.0f" % x)
		_check(absf(t.height_at(x, 0.0) - t.height_at(0.0, 0.0)) < 0.25, "tee line level at x %.0f" % x)
	_check(t.surface_at(40.0, 120.0) == Surface.Type.FAIRWAY, "the field is mown")
	_check(range_hole.aim_point(range_hole.tee, 125.0).distance_to(PracticeGround.target_position(t, 3)) < 0.1, "a 125 m club aims at the 125 yd target")
	var green := course.holes[PracticeGround.PUTTING_GREEN]
	var pr := PuttingPractice.new(3)
	pr.setup(green)
	_check(pr.cups.size() == PuttingPractice.MAX_CUPS, "six cups on the practice green (%d)" % pr.cups.size())
	var dressing := RangeDressing.build(range_hole, GraphicsSettings.Quality.MEDIUM, range_hole.tee)
	var balls := dressing.find_child("RangeBalls", true, false) as MultiMeshInstance3D
	_check(balls != null and balls.multimesh.instance_count > 400, "ball pyramids and range balls in one draw")
	_check(dressing.find_child("Yardage150", true, false) != null, "a 150 yard board")
	dressing.free()


## The target game: points by target and bullseye, the last balls double,
## and a bucket ends after its balls.
func _test_range_game() -> void:
	var targets: Array[Vector3] = [Vector3(0, 50, 5), Vector3(10, 100, 8)]
	var g := RangeGame.new(targets)
	_check(g.points_at(Vector2(0, 50))[0] == RangeGame.POINTS[0] * 2, "bullseye doubles")
	_check(g.points_at(Vector2(4, 50))[0] == RangeGame.POINTS[0], "on the green")
	_check(g.points_at(Vector2(30, 30))[0] == 0, "a miss")
	_check(g.add_shot(Vector3(20, 0, 20), Vector3(10, 0, 96)) == RangeGame.POINTS[1], "rolled onto a target")
	_check(g.add_shot(Vector3(4, 0, 50), Vector3(30, 0, 70)) == RangeGame.POINTS[0], "pitched on and ran off")
	for _i in RangeGame.BALLS - 3:
		g.add_shot(Vector3(40, 0, 10), Vector3(40, 0, 10))
	_check(not g.finished(), "one ball left")
	_check(g.add_shot(Vector3(0, 0, 50), Vector3(0, 0, 50)) == RangeGame.POINTS[0] * 4, "a bullseye with the last ball")
	_check(g.finished() and g.best == g.score and g.status().contains("Bucket done"), "bucket done")
	g.add_shot(Vector3(40, 0, 10), Vector3(40, 0, 10))
	_check(g.ball == 1 and g.score == 0 and g.best > 0, "the next ball starts a new bucket")


func _test_practice_ground_round() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	var s := RoundSetup.new()
	s.practice = true
	s.facility = true
	s.target_game = true
	GolfRound.setup = s
	game.start_round()
	_check(game.course.course_name == "Practice Ground" and game.holes.size() == 1, "the range")
	_check(game.range_game != null and game.monitor_panel != null, "target game and launch monitor")
	_check(game.hole_root.find_child("RangeDressing", true, false) != null, "the range is dressed")
	_check(game.gallery == null, "no gallery on the range")
	var tee: Vector3 = game.hole.tee
	for i in 3:
		var steps := 0
		while game.state != GolfRound.State.AIM or steps == 0:
			game.auto_play_step()
			steps += 1
			if steps > 10:
				break
		_check(game.state == GolfRound.State.AIM and game.ball_at.distance_to(tee) < 0.01, "range ball %d back on the tee" % i)
	_check(game.range_game.ball == 3, "three balls of the bucket (%d)" % game.range_game.ball)
	print("  target game: %s" % game.range_game.status())
	s = RoundSetup.new()
	s.putting = true
	s.facility = true
	GolfRound.setup = s
	game.start_round()
	_check(game.holes.size() == 1 and game.hole.number == 2 and game.practice != null, "the practice putting green")
	_check(game.lie == Surface.Type.GREEN, "ball on the practice green")
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


## Mulligans: the shot is taken again from the same spot, the card doesn't
## count it, and the round still replays to the same card.
func _test_glass_ui() -> void:
	_check(Glass.spring(0.0) == 0.0 and Glass.spring(1.0) == 1.0, "the spring starts at 0 and settles at 1")
	var peak := 0.0
	for i in 101:
		peak = maxf(peak, Glass.spring(i / 100.0))
	_check(peak > 1.0 and peak < 1.15, "and overshoots a touch (%.3f)" % peak)
	GlassTheme.install()
	var d := ThemeDB.get_default_theme()
	var pill := d.get_stylebox("normal", "Button") as StyleBoxFlat
	_check(pill != null and pill.corner_radius_top_left >= 20, "buttons are pills")
	_check(d.default_font is FontVariation, "the theme's type is Inter")
	var p := PanelContainer.new()
	MenuStyle.panel(p)
	var style := p.get_theme_stylebox("panel") as StyleBoxFlat
	_check(style != null and style.corner_radius_top_left == Glass.RADIUS and style.bg_color.a < 0.8, "menu panels are rounded glass")
	p.free()
	Glass.allow_blur = false
	_check(not Glass.blurs(), "Low quality: no live blur")
	Glass.allow_blur = true
	# The HUD's meter and wind dial: glass in Broadcast, nothing behind the
	# classic ones.
	var wind := WindIndicator.new()
	wind.size = Vector2(90, 112)
	root.add_child(wind)
	var shapes := wind._modern_shapes()
	_check(shapes.size() == 2 and is_equal_approx(shapes[0].size.x, shapes[0].size.y)
			and shapes[1].position.y > shapes[0].end.y, "the wind dial is a disc with the speed pill under it")
	wind.modern = true
	wind.update_glass()
	_check(wind._glass.panel_count() == 2, "both on glass")
	wind.free()
	var meter := SwingMeter.new()
	meter.size = SwingMeter.MODERN_SIZE
	root.add_child(meter)
	meter.modern = true
	meter.update_glass()
	_check(meter._glass.panel_count() == 1, "the modern meter sits on glass")
	meter.modern = false
	meter.update_glass()
	_check(meter._glass.panel_count() == 0 and not meter._glass.visible, "the classic arc doesn't")
	meter.free()


func _test_click_aim() -> void:
	var flat := FlatTerrain.new(Surface.Type.FAIRWAY, 2.0)
	var hit: Variant = ClickAim.ray_ground(flat, Vector3(0, 12, 0), Vector3(0, -1, 1))
	_check(hit is Vector3 and (hit as Vector3).distance_to(Vector3(0, 2, 10)) < 0.05, "the click lands on the ground: %s" % [hit])
	_check(ClickAim.ray_ground(flat, Vector3(0, 12, 0), Vector3(0, 0.2, 1)) == null, "a click on the sky aims nowhere")
	_check(ClickAim.ray_ground(flat, Vector3(0, 1, 0), Vector3(0, -1, 1)) == null, "a camera under the ground aims nowhere")
	var reaches: Array[float] = [230.0, 200.0, 150.0, 100.0, -1.0]
	_check(ClickAim.club_for(reaches, 140.0) == 2 and ClickAim.club_for(reaches, 300.0) == 0
			and ClickAim.club_for(reaches, 10.0) == 3, "the shortest club that gets there, never the putter")
	var game := _game
	if not game.is_node_ready():
		return
	GolfRound.setup = RoundSetup.new()
	game.start_round()
	_check(game.state == GolfRound.State.AIM, "aiming on the first tee")
	var spot: Vector3 = game.ball_at + Vector3(-60, 0, 120)
	game.aim_at(spot)
	_check(absf(game.aim_deg - rad_to_deg(atan2(-60.0, 120.0))) < 0.01, "aimed at the clicked spot (%.1f)" % game.aim_deg)
	var reach: float = game._club_reach()
	var club: Club = game.clubs[game.club_index]
	_check(reach >= 134.0 and not club.is_putter, "a club that reaches it: %s, %.0f m" % [club.full_name, reach])
	if game.club_index + 1 < game.clubs.size() and not game.clubs[game.club_index + 1].is_putter:
		game.club_index += 1
		_check(game._club_reach() < 134.0, "and the shortest one")
	# The Tour hole map: a click on it is a spot on the course.
	var map := HoleMap.build(game.hole)
	var pin := Vector2(game.hole.pin.x, game.hole.pin.z)
	_check(map.from_px(map.to_px_2d(pin)).distance_to(pin) < 0.01, "map pixels turn back into the same course spot")
	var tg := TourGraphics.new()
	tg.size = Vector2(1280, 720)
	tg.set_map(map, [], game.ball_at, true)
	var r := tg.map_rect()
	var at_pin: Variant = tg.map_spot(r.position + map.to_px_2d(pin) * TourGraphics.MAP_SCALE)
	_check(at_pin is Vector2 and (at_pin as Vector2).distance_to(pin) < 0.5, "a click on the map's pin aims at the pin: %s" % [at_pin])
	_check(tg.map_spot(r.position - Vector2(10, 10)) == null, "a click beside the map isn't on it")
	tg.set_map(map, [], game.ball_at, false)
	_check(tg.map_spot(r.get_center()) == null, "nor is one while the map is hidden")
	tg.free()
	GolfRound.setup = null


## Round setup's conditions: the wind and greens hold for the round, are
## recorded, and the round replays on them whatever the player's settings.
func _test_round_conditions() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("round", "green_firmness", 2)
	cfg.set_value("round", "green_speed", 0)
	cfg.set_value("round", "wind_level", 3)
	var path := "user://conditions_test.cfg"
	cfg.save(path)
	var saved := RoundSetup.load_saved(path)
	_check(saved.green_firmness == 2 and saved.green_speed == 0 and saved.wind_level == 3, "the setup's conditions are saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var msg := OnlineRound.setup_message(saved, 5, 3, [0], "")
	var back := OnlineRound.setup_from(msg)
	_check(back != null and back.green_firmness == 2 and back.green_speed == 0, "an online round sends its greens")
	var game := _game
	if not game.is_node_ready():
		return
	var setup := RoundSetup.new()
	setup.green_firmness = LinksGround.GreenFirmness.FIRM
	setup.green_speed = LinksGround.GreenSpeed.FAST
	setup.wind_level = Wind.Level.OFF
	GolfRound.setup = setup
	game.start_round()
	_check(game.record.green_firmness == LinksGround.GreenFirmness.FIRM and game.record.green_speed == LinksGround.GreenSpeed.FAST
			and game.wind.level == Wind.Level.OFF, "the round plays the setup's conditions")
	var firm_fast := LinksGround.green_for(LinksGround.GreenFirmness.FIRM, LinksGround.GreenSpeed.FAST)
	_check(LinksGround.greens != null and is_equal_approx(LinksGround.greens.restitution, firm_fast.restitution)
			and is_equal_approx(LinksGround.greens.roll_resistance, firm_fast.roll_resistance), "on firm, fast greens")
	# Changing the settings mid-round doesn't change the round's greens.
	game._apply_graphics()
	_check(is_equal_approx(LinksGround.greens.roll_resistance, firm_fast.roll_resistance), "and they hold for the round")
	var steps := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 800:
		game.auto_play_step()
		steps += 1
	LinksGround.set_greens(LinksGround.GreenFirmness.SOFT, LinksGround.GreenSpeed.SLOW)
	var ok := RoundReplay.verify(game.record, game.shot_model, game.clubs, game.holes)
	_check(ok.ok, "the round replays on its own greens: %s" % [ok.errors])
	_check(is_equal_approx(LinksGround.greens.roll_resistance, LinksGround.green_for(0, 0).roll_resistance), "and the game's greens come back after")
	LinksGround.set_greens(game.graphics.green_firmness, game.graphics.green_speed)
	GolfRound.setup = null


func _test_pick_up() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	game.graphics.pickup = 1
	GolfRound.setup = RoundSetup.new()
	game.start_round()
	var steps := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 800:
		_check(game.strokes <= GolfRound.MAX_STROKES, "never past the limit")
		game.auto_play_step()
		steps += 1
	game.graphics.pickup = 0
	_check(game.state == GolfRound.State.ROUND_DONE, "round with pick-ups finishes")
	var ok := RoundReplay.verify(game.record, game.shot_model, game.clubs, game.holes)
	_check(ok.ok and ok.cards_checked, "a round with pick-ups replays: %s" % [ok.errors])
	GolfRound.setup = null


func _test_mulligans() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	game.graphics.mulligans = 2
	GolfRound.setup = RoundSetup.new()
	game.start_round()
	var taken := 0
	var steps := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 800:
		if game.state == GolfRound.State.SHOT_RESULT and game._can_mulligan() and game.hole_index % 2 == 0:
			var from: Vector3 = game._undo.from
			var before: int = game._undo.strokes
			game._take_mulligan()
			taken += 1
			_check(game.state == GolfRound.State.AIM and game.ball_at == from and game.strokes == before, "mulligan %d back where it was" % taken)
			_check(not game._can_mulligan(), "one per hole")
		game.auto_play_step()
		steps += 1
	game.graphics.mulligans = 0
	_check(game.state == GolfRound.State.ROUND_DONE, "round with mulligans finishes")
	_check(taken >= 3, "mulligans taken (%d)" % taken)
	var marked := 0
	for r in game.record.shots:
		marked += 1 if r.mulligan else 0
	_check(marked == taken, "mulligans marked in the record")
	var ok := RoundReplay.verify(game.record, game.shot_model, game.clubs, game.holes)
	_check(ok.ok and ok.cards_checked, "a round with mulligans replays: %s" % [ok.errors])
	print("  mulligans: %d, card %s" % [taken, str(game.card.strokes)])
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
	var card_overlay := BroadcastOverlay.new()
	card_overlay.hole_card({"number": 1, "par": 4, "yards": 400, "name": "Test"}, null)
	card_overlay._process(1.0)
	_check(card_overlay.hole_card_showing(), "hole card: shows before the tee shot")
	card_overlay.end_hole_card()
	card_overlay._process(BroadcastOverlay.HOLE_CARD_FADE + 0.05)
	_check(not card_overlay.hole_card_showing(), "hole card: fades out once the player swings")
	card_overlay.free()
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
	var cam: RoundCamera = game.camera
	# Links always shows the golfer and ball at address: the camera stays
	# close, and the real camera (not just its planned pose) has them in view.
	var rise := cam._aim_pos.y - game.ball_at.y
	var back := Vector2(cam._aim_pos.x - game.ball_at.x, cam._aim_pos.z - game.ball_at.z).length()
	_check(rise < 8.0 and back < 10.0, "tee view: the camera stays near the golfer (%.1f m up, %.1f m back)" % [rise, back])
	var forward := (cam._aim_look - cam._aim_pos).normalized()
	var half := deg_to_rad(minf(cam.fov, RoundCamera.AIM_FRAME_FOV)) * 0.5
	_check(forward.angle_to((game.ball_at - cam._aim_pos).normalized()) < half * 0.9, "tee view: the ball is in frame")
	_check(forward.angle_to((game.golfer.global_position + Vector3.UP * 1.6 - cam._aim_pos).normalized()) < half, "tee view: the golfer's head is in frame")
	_check(cam.global_position.distance_to(cam._aim_pos) < 0.01, "tee view: the camera is at its aim pose (%s, not %s)" % [cam._aim_pos, cam.global_position])
	_check(cam.is_position_in_frustum(game.ball_at + Vector3.UP * 0.1), "tee view: the ball is inside the camera's frustum")
	var seen := RoundCamera.sight_clear(game.hole.terrain, cam._aim_pos, target)
	print("  tee view: %.1f m up, %.1f m back, target %.0f m %s" % [rise, back, reach, "in sight" if seen else "behind the rise"])


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
	var boot_script := load("res://scripts/boot.gd") as GDScript
	var shell: Control = boot_script.new()
	shell._build_ui()
	_check(shell.get_node_or_null("MenuScroll") is ScrollContainer, "menu: the menus scroll when taller than the window")
	shell.free()
	_check(boot_script.primary_button(["Play with placeholders", "Career", "Players"]) == 0, "menu: Enter plays, not Players")
	_check(boot_script.primary_button(["Load disc images...", "Players", "Play a round"]) == 2, "menu: focus skips Players")
	_check(boot_script.primary_button(["Players", "Settings"]) == -1, "menu: no play button, no focus")
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


## Career mode's tour logic, without playing: the field, the schedule, the
## purse shares, the cut, a win, a withdrawal, saving and the season's end.
func _test_career() -> void:
	Career.path = "user://test_career.cfg"
	Career.remove()
	var keys: Array[String] = ["Courses/A.crz", "Courses/B.crz"]
	var titles: Array[String] = ["Alpha Golf Club", "Bravo Links"]
	var c := Career.create("Ann", 2, 4, 4, false, 2, keys, titles, 77)
	_check(c.names.size() == 132 and c.names[-1] == "Ann" and c.skills.size() == 131, "career: World Tour field of 131 plus Ann")
	var seen := {}
	for n in c.names:
		seen[n.to_lower()] = true
	_check(seen.size() == c.names.size(), "career: every golfer has their own name")
	_check(c.skills[0] < c.skills[130], "career: the field is listed best first")
	_check(c.schedule.size() == 4 and str(c.schedule[3].name) == "World Championship" and int(c.schedule[3].purse) == 16000000, "career: schedule %s" % [c.schedule])
	for ev: Dictionary in c.schedule:
		_check(keys.has(str(ev.course_key)), "career: events are on the player's courses")
	_check(Career.format_money(1234567) == "$1,234,567" and Career.format_money(0) == "$0" and Career.format_money(950) == "$950", "career: money text")

	# The purse: shares add up to it; ties split their places; a playoff
	# winner takes first alone.
	var totals: Array[int] = []
	for i in 65:
		totals.append(i - 20)
	var pay := Career.payouts(totals, 1000000, 65, 65, false)
	var sum := 0
	for p in pay:
		sum += p
	_check(absi(sum - 1000000) <= 65 and pay[0] > pay[1] and pay[1] > pay[2], "career: the purse is paid out (%d)" % sum)
	var tied := Career.payouts(_ints([-10, -8, -8, -5]), 1000000, 65, 65, false)
	_check(tied[1] == tied[2] and tied[1] == roundi(1000000.0 * (Career.PAYOUT[1] + Career.PAYOUT[2]) / 2.0 / 100.0), "career: ties split their places: %s" % [tied])
	var po := Career.payouts(_ints([-10, -10, -9]), 1000000, 65, 65, true)
	_check(po[0] > po[1] and po[1] > po[2], "career: a playoff winner takes first: %s" % [po])
	var unpaid := Career.payouts(_ints([1, 2, 3, 3, 5]), 1000, 3, 3, false)
	_check(unpaid[2] == unpaid[3] and unpaid[2] > 0 and unpaid[4] == 0, "career: ties on the last paid place are paid: %s" % [unpaid])

	# Event 1: two bad rounds miss the cut.
	var s := c.next_setup()
	_check(s != null and s.names.size() == 3 and s.names[0] == "Ann" and s.computer[0] == RoundSetup.HUMAN and s.computer[1] != RoundSetup.HUMAN, "career: Ann plays with two computer golfers")
	_check(s.problem().is_empty() and s.mode == GameModes.Mode.STROKE and s.career == c.round_id(), "career: a stroke play round of this career")
	_check(c.record_round("not this round", {"Ann": 0}, 18, 72, 72).is_empty(), "career: another round's card is ignored")
	var partner := c.names.find(s.names[1])
	var text := c.record_round(s.career, {"Ann": 20, s.names[1]: -3}, 18, 72, 92)
	_check(not text.is_empty() and c.rounds_played() == 1, "career: round 1 counts: %s" % text)
	_check(int(c.scores[partner][0]) == -3, "career: a partner's real round counts")
	s = c.next_setup()
	text = c.record_round(s.career, {"Ann": 20}, 18, 72, 92)
	_check(text.contains("Missed the cut"), "career: missed the cut: %s" % text)
	_check(c.event == 1 and str(c.results[0].status) == "MC" and int(c.stats.cuts_missed) == 1, "career: on to event 2")
	var paid := 0
	for m in c.money:
		paid += m
	_check(paid >= 8000000 * 0.95 and paid <= 8000000 * 1.15, "career: event 1 paid out its purse (%d)" % paid)
	print("  " + text)

	# Event 2: a record low wins.
	for r in 4:
		s = c.next_setup()
		_check(s != null, "career: round %d to play" % (r + 1))
		if s != null:
			text = c.record_round(s.career, {"Ann": -12}, 18, 72, 60)
	_check(c.event == 2 and int(c.results[1].pos) == 1 and int(c.stats.wins) == 1, "career: Ann wins: %s" % text)
	_check(int(c.results[1].money) == roundi(8000000.0 * Career.PAYOUT[0] / _payout_sum(65)), "career: the winner's share: %d" % int(c.results[1].money))
	print("  " + text)
	print("  " + c.career_text())

	# Saved and loaded, then a withdrawal.
	c.save()
	var d := Career.load_saved()
	_check(d != null and d.names == c.names and d.money == c.money and d.round_id() == c.round_id() and d.stats == c.stats, "career: saved and loaded")
	d.withdraw()
	_check(d.event == 3 and str(d.results[2].status) == "WD", "career: a withdrawal plays the event out")
	for r in 4:
		s = d.next_setup()
		if s != null:
			d.record_round(s.career, {"Ann": -10}, 18, 72, 62)
	_check(d.season_over() and d.next_setup() == null, "career: the season is over")
	_check(d.money_rank() <= 3 and d.season_move() == 0, "career: Ann keeps her card")
	print("  " + d.season_text())
	for line in d.money_lines(3):
		print("    " + line)
	d.start_next_season()
	_check(d.season == 2 and d.history.size() == 1 and d.tour == 2 and d.event == 0 and d.results.is_empty(), "career: season 2")

	# The Regional Tour: one-round nine-hole events, no partners, moving up.
	var e := Career.create("Bo", 0, 1, 1, true, 0, [] as Array[String], [] as Array[String], 5)
	_check(e.names.size() == 60 and e.course_keys == _strs([""]), "career: the placeholder course stands in")
	s = e.next_setup()
	_check(s.names == _strs(["Bo"]) and s.holes == RoundSetup.Holes.FRONT_NINE and s.tees == RoundSetup.Tees.MIDDLE, "career: a quick nine on your own")
	e.record_round(s.career, {"Bo": -9}, 9, 36, 27)
	_check(e.season_over() and e.money_rank() == 1 and e.season_move() == 1, "career: top of the money list moves up")
	e.start_next_season()
	_check(e.tour == 1 and e.names.size() == 96, "career: on to the Challenge Tour")

	SavedRound.save(c.next_setup(), {"hole": 0})
	_check(SavedRound.load_setup().career == c.round_id(), "career: a saved round keeps its career round")
	SavedRound.clear()
	Career.remove()


static func _payout_sum(n: int) -> float:
	var t := 0.0
	for i in n:
		t += Career.PAYOUT[i]
	return t


## A Career round played through the real round: the event takes the cards.
func _test_career_round() -> void:
	var game := _game
	if not game.is_node_ready():
		return
	Career.path = "user://test_career.cfg"
	var c := Career.create("Cara", 1, 2, 1, false, 1, [] as Array[String], [] as Array[String], 9)
	c.save()
	Career.open_on_menu = false
	var s := c.next_setup()
	GolfRound.setup = s
	game.start_round()
	_check(game._career_title.begins_with(str(c.schedule[0].name)), "career round: titled %s" % game._career_title)
	var steps := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 3000:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.ROUND_DONE, "career round finishes")
	var after := Career.load_saved()
	_check(after != null and after.event == 1 and after.results.size() == 1, "career round: the event is played")
	if after != null and after.results.size() == 1:
		_check(int(after.results[0].to_par) == game.scoring.cards[0].to_par(), "career round: Cara's score counts")
		print("  " + after.result_text(0))
	_check(Career.open_on_menu, "career round: the menu opens the Career page")
	_check(PlayerProfiles.load_saved().rounds("Cara").size() == 1, "career round: on Cara's profile too")
	Career.open_on_menu = false

	# The Career page: the season so far, then a new career from scratch.
	var panel := CareerPanel.new()
	root.add_child(panel)
	panel.open(PackedStringArray(), PackedStringArray())
	_check(panel.visible and panel._view_box.visible and panel._play.text == "Play round 1", "career page: next round (%s)" % panel._play.text)
	_check(panel._summary.text.begins_with("Cara: Challenge Tour, season 1"), "career page: %s" % panel._summary.text)
	var asked: Array[RoundSetup] = []
	panel.play_pressed.connect(func(rs: RoundSetup) -> void: asked.append(rs))
	panel._on_play()
	_check(asked.size() == 1 and asked[0].career == Career.load_saved().round_id(), "career page: plays the next round")
	panel._on_end()
	_check(Career.exists(), "career page: the first press only asks")
	panel._on_end()
	_check(not Career.exists() and panel._new_box.visible, "career page: ended")
	panel._player.text = "Dee"
	panel._tour.select(0)
	panel._on_play()
	var fresh := Career.load_saved()
	_check(fresh != null and fresh.player == "Dee" and fresh.tour == 0 and fresh.events_per_season == 8, "career page: a new career")
	panel.queue_free()
	Career.remove()
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
	game.hud.overlay._draw()
	_check(game.hud.overlay.glass.panel_count() > 0, "broadcast panels are frosted glass")
	_check(game.hud.hint.visible and not game.hud.hint_tab.visible, "key hints up on the first hole")
	game.start_hole(1)
	_check(not game.hud.hint.visible and game.hud.hint_tab.visible, "key hints folded from the second hole")
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	game._unhandled_input(f1)
	_check(game.hud.hint.visible, "F1 brings the key hints back")
	game._unhandled_input(f1)
	_check(not game.hud.hint.visible, "and folds them again")
	game.start_hole(0)
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
	game.start_hole(1)
	_check(game.hud.hint.visible, "classic keeps the key hints")
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
	# The ball at true size: 42.67 mm close up, never under 0.3% of the view
	# far away, and far smaller than Links 2003's bigger-far-away ball.
	_check_near(GolfRound.ball_radius(4.0, 50.0, true), BallPhysics.RADIUS, 1e-9, "true-size ball close up")
	var far := GolfRound.ball_radius(100.0, 50.0, true)
	_check_near(far * 2.0 / (2.0 * 100.0 * tan(deg_to_rad(25.0))), GolfRound.BALL_MIN_SCREEN, 1e-6, "true-size ball far away keeps a few pixels")
	_check(far < GolfRound.ball_radius(100.0, 50.0, false) * 0.5, "true-size ball is smaller than Links' far away")
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
	game._input(e)


func _drag(game: GolfRound, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = at
	game._input(e)
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
	# The mouse click the browser makes up from that tap doesn't click the
	# meter a second time.
	var compat := InputEventMouseButton.new()
	compat.button_index = MOUSE_BUTTON_LEFT
	compat.pressed = true
	game._unhandled_input(compat)
	_check(game.hud.meter.phase == SwingMeter.Phase.BACKSWING and game.hud.meter.power_position == 0,
			"touch: the made-up click after a tap is ignored")
	# Taps two and three set the power and the accuracy the moment they land,
	# even over the HUD's panels.
	for f in 40:
		game.hud.meter._process(1.0 / 60.0)
	_touch(game, true, from)
	_touch(game, false, from)
	_check(game.hud.meter.power_position > 0, "touch: the second tap sets the power")
	for f in 300:
		if game.hud.meter.phase != SwingMeter.Phase.DOWNSWING:
			break
		if game.hud.meter.value <= 0.02:
			break
		game.hud.meter._process(1.0 / 60.0)
	_touch(game, true, from)
	_check(game.state == GolfRound.State.FLIGHT, "touch: the third tap strikes the ball")
	# Neither that tap's release, its made-up clicks nor a quick second tap
	# skips the flight: the ball is seen in the air.
	_touch(game, false, from)
	game._unhandled_input(fake)
	game._unhandled_input(compat)
	_touch(game, true, from)
	_touch(game, false, from)
	_check(game.state == GolfRound.State.FLIGHT, "touch: the strike doesn't skip the flight")
	game.shot_time = GolfRound.FLIGHT_SKIP_GRACE_S + 0.1
	_touch(game, true, from)
	_touch(game, false, from)
	_check(game.state != GolfRound.State.FLIGHT, "touch: a later tap skips the flight")
	game._touch_ms = -100000
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
	game._touch_ms = -100000
	game.graphics.presentation = presentation
	game._apply_graphics()


## A 15% slope rising towards +z, for the buggy tests.
class TiltedTerrain:
	extends FlatTerrain

	func height_at(_x: float, z: float) -> float:
		return 0.15 * z

	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3(0.0, 1.0, -0.15).normalized()


## The named pros and made-up field golfers: their numbers, styles and
## scoring averages.
func _test_tour_pros() -> void:
	var roster := TourPro.roster()
	_check(roster.size() == 16, "16 named pros")
	var seen := {}
	for p in roster:
		seen[p.name] = true
		var avg := p.scoring_average()
		_check(avg > -4.0 and avg < 4.0, "%s averages %.2f" % [p.name, avg])
		_check(not p.profile_text().is_empty() and not p.about.is_empty(), "%s has a profile" % p.name)
	_check(seen.size() == 16, "names are unique")
	_check(TourPro.find("callum reid") != null and TourPro.find("Nobody Here") == null, "find by name")
	var avg_pro := TourPro.new()
	_check_near(avg_pro.scoring_average(), TourPro.TOUR_TO_PAR, 1e-9, "the tour average scores the tour average")
	_check(TourPro.find("Kenji Morita").stats[OpponentSkill.STAT_PUTT8] > TourPro.find("Mateo Ibarra").stats[OpponentSkill.STAT_PUTT8], "the best putter putts better")
	var back := TourPro.from_dict(TourPro.find("Marcus Bell").to_dict())
	_check(back.name == "Marcus Bell" and back.stats.size() == 6 and absf(back.aggression - 0.85) < 1e-9, "to_dict round trip")
	# Levels and generated golfers.
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var weekend := TourPro.new()
	weekend.stats = TourPro.level_stats(0.0)
	_check(weekend.scoring_average() > 12.0, "a weekend golfer is well over par (%.1f)" % weekend.scoring_average())
	_check_near(TourPro.level_stats(3.0)[OpponentSkill.STAT_DRIVE_YD], 300.0, 1e-9, "level 3 is the tour average")
	var lv := TourPro.level_for_average(2.0)
	var check := TourPro.new()
	check.stats = TourPro.level_stats(lv)
	_check_near(check.scoring_average(), 2.0, 0.3, "level_for_average")
	var man := TourPro.generate("Test Man", 3.0, false, r)
	var woman := TourPro.generate("Test Woman", 3.0, true, r)
	_check(woman.stats[OpponentSkill.STAT_DRIVE_YD] < man.stats[OpponentSkill.STAT_DRIVE_YD], "the women's tour drives shorter")
	var sk := man.skill()
	_check(sk.strength > 0.5 and sk.strength <= 1.0, "a generated pro's strength")
	# Seats: a Tour pro seat named after a roster pro plays as them.
	var s := RoundSetup.new()
	s.names.assign(["Me", "Seo-yeon Han", "Ann Other"])
	s.computer = _ints([RoundSetup.HUMAN, OpponentSkill.Level.TOUR, OpponentSkill.Level.CLUB])
	_check(s.pro_for(0) == null and s.pro_for(1) != null and s.pro_for(1).name == "Seo-yeon Han" and s.pro_for(2) == null, "pro_for")
	s.pros["Ann Other"] = man.to_dict()
	_check(s.pro_for(2) != null and s.pro_for(2).name == "Test Man", "pro_for from the setup's pros")


## Simulated holes: each golfer's odds keep a real shape and average out to
## their scoring average.
func _test_tournament_hole_odds() -> void:
	for par in [3, 4, 5]:
		for mean in [-0.5, -0.2, 0.0, 0.3, 1.0]:
			var odds := Tournament.hole_odds(par, mean)
			var m := 0.0
			var total := 0.0
			for k in odds.size():
				m += odds[k] * (k + Tournament.FIRST_SCORE)
				total += odds[k]
			_check_near(total, 1.0, 1e-9, "par %d odds add up" % par)
			_check_near(m, mean, 0.01, "par %d odds average %.2f" % [par, mean])
	var round_mean := 4.0 * Tournament.base_mean(3) + 10.0 * Tournament.base_mean(4) + 4.0 * Tournament.base_mean(5)
	_check_near(round_mean, TourPro.TOUR_TO_PAR, 0.05, "the odds add up to the tour average on a par 72")
	# 400 rounds of the average tour pro on a par 72.
	var pars: Array[int] = []
	for p in [4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5]:
		pars.append(p)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var sum := 0.0
	var sq := 0.0
	var birdies := 0
	var par4s := 0
	var n := 400
	for _k in n:
		var card := Tournament.simulate_round(pars, TourPro.TOUR_TO_PAR, r.randfn(0.0, 1.0), r)
		var to_par := 0
		for h in pars.size():
			to_par += card[h] - pars[h]
			if pars[h] == 4:
				par4s += 1
				birdies += 1 if card[h] < 4 else 0
		sum += to_par
		sq += to_par * to_par
	var mean := sum / n
	var sd := sqrt(sq / n - mean * mean)
	var birdie_rate := 100.0 * birdies / par4s
	print("  tour average: %.2f to par, sd %.2f, %.1f%% birdies on par 4s" % [mean, sd, birdie_rate])
	_check(absf(mean - TourPro.TOUR_TO_PAR) < 0.4, "average round")
	_check(sd > 2.3 and sd < 3.6, "round-to-round spread like tour players' (%.2f)" % sd)
	_check(birdie_rate > 11.0 and birdie_rate < 20.0, "birdie rate on par 4s")
	_check(Tournament.match_result(PackedInt32Array([3, 4, 4]), PackedInt32Array([4, 5, 4])).text == "2&1", "match result 2&1")
	_check(Tournament.match_result(PackedInt32Array([4, 4, 3]), PackedInt32Array([4, 4, 4])).text == "1 up", "match result 1 up")
	_check(int(Tournament.match_result(PackedInt32Array([4, 4]), PackedInt32Array([4, 4])).winner) == -1, "all square")
	var dormie := Tournament.match_result(PackedInt32Array([3, 3, 3, 4, 4]), PackedInt32Array([4, 4, 4, 4, 4]))
	_check(dormie.text == "3&2" and int(dormie.winner) == 0, "3&2 (%s)" % dormie.text)


func _tournament_pars(n: int) -> Array[int]:
	var pars: Array[int] = []
	var layout := [4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5]
	for h in n:
		pars.append(layout[h % layout.size()])
	return pars


## Plays the person's group's round: everyone makes par except the person,
## who makes `mine` on every hole.
func _play_tournament_round(t: Tournament, pars: Array[int], mine: int) -> String:
	var s := t.next_setup()
	_check(s != null and s.tournament == t.round_id(), "a setup for the next round")
	_check(t.begin_round(s.tournament, pars), "begin_round")
	var played := {}
	for i in s.names.size():
		var card: Array[int] = []
		for h in pars.size():
			card.append(pars[h] + (mine if i == 0 else 0))
		played[s.names[i]] = card
	return t.record_round(s.tournament, played, pars)


func _test_tournament_stroke_play() -> void:
	Tournament.path = "user://test_tournament.cfg"
	Tournament.remove()
	var keys: Array[String] = ["", ""]
	var titles: Array[String] = ["Kauri Cliffs Golf Club", "Kauri Cliffs Golf Club"]
	var t := Tournament.create({"player": "Tester", "format": Tournament.Format.STROKE, "rounds": 4, "strength": 3,
		"field_kind": Tournament.Field.MIXED, "field_size": 72, "cut": 2, "purse": 1000000, "weather": Tournament.Weather.CHANGEABLE,
		"tee_times": Tournament.TeeTimes.DRAW, "partners": 2, "seed": 12345}, keys, titles)
	_check(t.names.size() == 72 and t.names[-1] == "Tester", "a field of 72 with the person last")
	_check(t.title == "Kauri Cliffs Open", "named after the course (%s)" % t.title)
	var named := 0
	for n in t.names:
		if TourPro.find(n) != null:
			named += 1
	_check(named == 16, "a world tour field has the named pros (%d)" % named)
	_check(t.has_cut(), "a cut")
	var pars := _tournament_pars(18)
	var s := t.next_setup()
	_check(s.names.size() == 3 and s.pros.size() == 2 and s.wind_level >= Wind.Level.LIGHT, "the group, its pros and the wind")
	_check(s.pro_for(1) != null, "partners play as themselves")
	# The live board moves as the person plays.
	t.begin_round(s.tournament, pars)
	var early := 0
	var late := 0
	for i in t.names.size() - 1:
		early += t.live_thru(i, 0)
		late += t.live_thru(i, 18)
	_check(late > early, "the field plays on while the person does (%d, %d holes)" % [early, late])
	var rows := t.live_rows(9, {"Tester": [4, 4, 3, 4, 5, 4, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0]})
	_check(rows.size() == 72 and str(rows[0].pos) in ["1", "T1"], "live rows")
	var text := _play_tournament_round(t, pars, 0)
	print("  " + text)
	_check(text.begins_with("Kauri Cliffs Open, round 1: 72 (E)"), "round 1 text (%s)" % text)
	text = _play_tournament_round(t, pars, -1)
	print("  " + text)
	_check(not t.made_cut.is_empty() and t.made_cut[t.player_index()], "-18 after two rounds makes the cut")
	var made := t.made_cut.count(true)
	_check(made >= 50 and made < 72, "top 50 and ties make the cut (%d)" % made)
	t.save()
	var loaded := Tournament.load_saved()
	_check(loaded != null and loaded.round_id() == t.round_id() and loaded.total_of(loaded.player_index()) == -18, "save and load")
	t = loaded
	_play_tournament_round(t, pars, -1)
	text = _play_tournament_round(t, pars, -1)
	print("  " + text)
	_check(t.over() and int(t.result.pos) == 1, "-54 wins (%s)" % text)
	var paid := 0
	for m in t.money:
		paid += m
	_check(paid >= 990000 and paid < 1150000, "the purse is paid out, a little more for places past the cut number (%d)" % paid)
	_check(t.money[t.player_index()] > 150000, "the winner's share (%d)" % t.money[t.player_index()])
	# A missed cut plays the event out.
	var t2 := Tournament.create({"player": "Hacker", "format": Tournament.Format.STABLEFORD, "rounds": 3, "strength": 1,
		"field_size": 48, "cut": 0, "seed": 9}, keys, titles)
	_check(not t2.has_cut(), "no cut")
	_play_tournament_round(t2, pars, 0)
	t2.withdraw()
	_check(t2.over() and str(t2.result.status) == "WD" and t2.rounds_played() == 3, "withdraw plays it out")
	var board := t2.leaderboard_lines(5)
	_check(board.size() >= 5 and board[0].contains("pts"), "a Stableford board (%s)" % board[0])
	Tournament.remove()


func _test_tournament_match_play() -> void:
	var keys: Array[String] = [""]
	var titles: Array[String] = ["Placeholder Nine"]
	var t := Tournament.create({"player": "Tester", "format": Tournament.Format.MATCH, "field_size": 8, "strength": 4,
		"seed": 77}, keys, titles)
	_check(t.names.size() == 8 and t.rounds == 3 and t.bracket.size() == 1 and t.bracket[0].size() == 4, "an 8-player draw")
	var pars := _tournament_pars(9)
	var guard := 0
	while t.playing() and guard < 5:
		guard += 1
		var s := t.next_setup()
		_check(s.names.size() == 2 and s.mode == GameModes.Mode.MATCH, "a match")
		print("  " + _play_tournament_round(t, pars, -1))
	_check(t.over() and int(t.result.pos) == 1, "birdying every hole wins the match play")
	_check(t.bracket.size() == 3 and t.bracket_lines()[0] == "QUARTER-FINALS", "the draw (%s)" % t.bracket_lines()[0])
	var lost := Tournament.create({"player": "Tester", "format": Tournament.Format.MATCH, "field_size": 16, "seed": 78}, keys, titles)
	print("  " + _play_tournament_round(lost, pars, 2))
	_check(lost.over() and str(lost.result.status) == "OUT", "losing knocks you out and the draw plays out")
	_check(int(lost.bracket[-1][0][2]) >= 0, "someone wins it")


func _test_tournament_skins() -> void:
	var keys: Array[String] = [""]
	var titles: Array[String] = ["Placeholder Nine"]
	var t := Tournament.create({"player": "Tester", "format": Tournament.Format.SKINS, "rounds": 1, "purse": 1000000,
		"field_kind": Tournament.Field.WOMEN, "seed": 5}, keys, titles)
	_check(t.names.size() == 4, "a skins game of four")
	for i in 3:
		_check(TourPro.find(t.names[i]) != null and TourPro.find(t.names[i]).named, "against named pros")
	var pars := _tournament_pars(9)
	var s := t.next_setup()
	_check(s.mode == GameModes.Mode.SKINS and s.names.size() == 4, "everyone plays for real")
	t.begin_round(s.tournament, pars)
	var played := {}
	for i in s.names.size():
		var card: Array[int] = []
		for h in pars.size():
			card.append(pars[h] - (1 if i == 0 and h == 8 else 0))
		played[s.names[i]] = card
	print("  " + t.record_round(s.tournament, played, pars))
	var paid := 0
	for m in t.money:
		paid += m
	_check(absi(paid - 1000000) < 100, "every skin is paid (%d)" % paid)
	_check(t.money[t.player_index()] == paid, "a birdie on the last takes every carried skin")
	_check(t.over(), "over after one round")
