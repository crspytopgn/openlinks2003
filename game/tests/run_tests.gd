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
	_run("links_launch_matches_olcore", _test_links_launch_matches_olcore)
	_run("links_lie_matches_olcore", _test_links_lie_matches_olcore)
	_run("links_swing_matches_olcore", _test_links_swing_matches_olcore)
	_run("obstacles_match_olcore", _test_obstacles_match_olcore)
	_run("swing_accuracy", _test_swing_accuracy)
	_run("swing_meter", _test_swing_meter)
	_run("scorecard", _test_scorecard)
	_run("game_modes_match_olcore", _test_game_modes)
	_run("handicaps_match_olcore", _test_handicaps)
	_run("player_profiles", _test_player_profiles)
	_run("round_setup", _test_round_setup)
	_run("round_scoring", _test_round_scoring)
	_run("drop_rules_match_olcore", _test_drop_rules_match_olcore)
	_run("opponent_skill_matches_olcore", _test_opponent_skill_matches_olcore)
	_run("computer_golfer_plans", _test_computer_golfer_plans)
	_run("handicap_scoring", _test_handicap_scoring)
	_run("placeholder_course", _test_placeholder_course)
	_run("graphics_settings", _test_graphics_settings)
	_run("grass", _test_grass)
	_run("trees", _test_trees)
	_run("broadcast_pieces", _test_broadcast_pieces)
	_run("hd_pack", _test_hd_pack)
	_run("object_library_chain", _test_object_library_chain)
	_run("free_assets", _test_free_assets)
	_run("web_game_files", _test_web_game_files)
	_run("golfer_file_readers", _test_golfer_file_readers)
	_run("free_golfer", _test_free_golfer)
	_run("format_readers", _test_format_readers)
	_run("course_reader", _test_course_reader)
	_run("course_designer", _test_course_designer)
	# Nodes added here only get _ready() once the main loop runs, so the
	# full round is played from _process().
	# Fixed wind, so the shots (and what the camera sees) are the same every run.
	GolfRound.wind_seed = 20031
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as GolfRound
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _done or (not _game.is_node_ready() and _frames < 30):
		return false
	_done = true
	_run("full_round", _test_full_round)
	_run("drops_in_round", _test_drops_in_round)
	_run("multiplayer_rounds", _test_multiplayer_rounds)
	_run("computer_opponents", _test_computer_opponents)
	_run("team_ball_modes", _test_team_ball_modes)
	_run("rounds_recorded", _test_rounds_recorded)
	_run("saved_round", _test_saved_round)
	_run("players_panel", _test_players_panel)
	SavedRound.clear()
	_run("broadcast_round", _test_broadcast_round)
	_run("designer_scene", _test_designer_scene)
	_run("designed_round", _test_designed_round)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfiles.path))
	if _failures > 0:
		print("%d check(s) failed" % _failures)
		quit(1)
	else:
		print("GODOT TESTS PASSED")
		quit(0)
	return true


func _run(test_name: String, fn: Callable) -> void:
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


func _test_swing_meter() -> void:
	var meter := SwingMeter.new()
	var results := []
	meter.swing_finished.connect(func(p: float, a: float) -> void: results.append([p, a]))
	meter.click()
	_check(meter.phase == SwingMeter.Phase.BACKSWING, "first click starts the backswing")
	meter.value = 0.8
	meter.click()
	_check_near(meter.power, 0.8, 1e-6, "second click sets power")
	meter.value = 0.005
	meter.click()
	_check(results.size() == 1, "third click finishes the swing")
	if results.size() == 1:
		_check_near(results[0][1], 0.0, 1e-6, "on the line is perfect")
	meter.click()
	meter.value = 1.0
	meter.click()
	meter.value = -SwingMeter.ACCURACY_ZONE * 0.5
	meter.click()
	_check(results.size() == 2 and results[1][1] > 0.4, "late click slices")
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
	p.save()
	var again := PlayerProfiles.load_saved()
	_check(again.names() == _strs(["Ann"]) and again.index_of("Ann") == 160, "profiles saved")
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

	s.mode = GameModes.Mode.STABLEFORD
	r = RoundScoring.new(s, pars, numbers)
	r.cards[0].record(0, 3)
	r.cards[1].record(0, 4)
	r.cards[2].record(0, 6)
	_check(r.standings()[0] == ["Ann", "3 points"], "stableford leader: %s" % [r.standings()])
	_check(r.winner_text() == "Ann wins: 3 points", "stableford winner: %s" % r.winner_text())


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
	s.save(path)
	var loaded := GraphicsSettings.load_saved(path)
	_check(loaded.quality == GraphicsSettings.Quality.ULTRA, "quality saved")
	_check(loaded.msaa == 4, "msaa saved")
	_check_near(loaded.render_scale, 0.75, 1e-6, "render scale saved")
	_check_near(loaded.fov, 70.0, 1e-6, "fov saved")
	_check(loaded.wind == Wind.Level.STRONG, "wind saved")
	_check(loaded.presentation == GraphicsSettings.Presentation.CLASSIC, "presentation saved")
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
	_check(s.lighting == GraphicsSettings.Lighting.PHOTOREAL and s.grass > 0 and s.foliage_wind, "photoreal look")
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


## The MakeHuman golfer used without the original files.
func _test_free_golfer() -> void:
	var golfer := FreeGolfer.create()
	_check(golfer != null, "free_golfer.glb loads with an AnimationPlayer")
	if golfer == null:
		return
	for anim_name in [&"address", &"address_putt", &"backswing", &"swing", &"putt", &"celebrate"]:
		_check(golfer.has_animation(anim_name), "free golfer has %s" % anim_name)
	var made := PlaceholderGolferAssets.new().create_golfer()
	_check(made is FreeGolfer, "the placeholder assets use the free golfer")
	made.free()
	golfer.play(&"putt")
	golfer.play(&"address")
	golfer.free()


## Hot-seat rounds through the real round: skins over the front nine for three
## players, and a match that can end early.
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
	var steps := 0
	while game.state != GolfRound.State.ROUND_DONE and steps < 2000:
		game.auto_play_step()
		steps += 1
	_check(game.state == GolfRound.State.ROUND_DONE, "skins round finishes")
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


## The full and multiplayer rounds above went into the test profiles.
func _test_rounds_recorded() -> void:
	var p := PlayerProfiles.load_saved()
	_check(p.rounds("Player 1").size() >= 1, "the full round is on Player 1's record")
	_check(p.rounds("Ann").size() >= 1, "the skins round is on Ann's record")
	for r: Dictionary in p.rounds("Player 1"):
		_check(r.holes == 9 and r.par == 36 and r.adjusted <= r.gross, "round record: %s" % r)


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

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var holed := ShotResult.new()
	holed.outcome = ShotResult.Outcome.HOLED
	var line: Array = Commentary.pick(holed, Surface.Type.GREEN, false, 0.0, 140.0, rng)
	_check(line[1] == Commentary.Crowd.ROAR and Commentary.HOLED_LONG.has(line[0]), "holed approach roars")
	var wet := ShotResult.new()
	wet.outcome = ShotResult.Outcome.WATER
	_check(Commentary.pick(wet, Surface.Type.WATER, false, 50.0, 150.0, rng)[1] == Commentary.Crowd.GROAN, "water groans")


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
