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
	_run("physics_matches_olcore", _test_physics_matches_olcore)
	_run("club_table_matches_physics", _test_club_table_matches_physics)
	_run("putting", _test_putting)
	_run("hazards", _test_hazards)
	_run("wind_matches_olcore", _test_wind_matches_olcore)
	_run("wind_conditions", _test_wind_conditions)
	_run("links_flight_matches_olcore", _test_links_flight_matches_olcore)
	_run("links_ground_matches_olcore", _test_links_ground_matches_olcore)
	_run("obstacles_match_olcore", _test_obstacles_match_olcore)
	_run("swing_accuracy", _test_swing_accuracy)
	_run("swing_meter", _test_swing_meter)
	_run("scorecard", _test_scorecard)
	_run("game_modes_match_olcore", _test_game_modes)
	_run("handicaps_match_olcore", _test_handicaps)
	_run("player_profiles", _test_player_profiles)
	_run("round_setup", _test_round_setup)
	_run("round_scoring", _test_round_scoring)
	_run("handicap_scoring", _test_handicap_scoring)
	_run("placeholder_course", _test_placeholder_course)
	_run("graphics_settings", _test_graphics_settings)
	_run("broadcast_pieces", _test_broadcast_pieces)
	_run("hd_pack", _test_hd_pack)
	_run("object_library_chain", _test_object_library_chain)
	_run("free_assets", _test_free_assets)
	_run("web_game_files", _test_web_game_files)
	_run("golfer_file_readers", _test_golfer_file_readers)
	_run("free_golfer", _test_free_golfer)
	_run("format_readers", _test_format_readers)
	_run("course_reader", _test_course_reader)
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
	_run("multiplayer_rounds", _test_multiplayer_rounds)
	_run("rounds_recorded", _test_rounds_recorded)
	_run("broadcast_round", _test_broadcast_round)
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


## The full and multiplayer rounds above went into the test profiles.
func _test_rounds_recorded() -> void:
	var p := PlayerProfiles.load_saved()
	_check(p.rounds("Player 1").size() >= 1, "the full round is on Player 1's record")
	_check(p.rounds("Ann").size() >= 1, "the skins round is on Ann's record")
	for r: Dictionary in p.rounds("Player 1"):
		_check(r.holes == 9 and r.par == 36 and r.adjusted <= r.gross, "round record: %s" % r)


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
