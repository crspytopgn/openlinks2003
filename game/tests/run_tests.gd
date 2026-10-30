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
	_run("physics_matches_olcore", _test_physics_matches_olcore)
	_run("club_table_matches_physics", _test_club_table_matches_physics)
	_run("putting", _test_putting)
	_run("hazards", _test_hazards)
	_run("swing_accuracy", _test_swing_accuracy)
	_run("swing_meter", _test_swing_meter)
	_run("scorecard", _test_scorecard)
	_run("game_modes_match_olcore", _test_game_modes)
	_run("round_setup", _test_round_setup)
	_run("round_scoring", _test_round_scoring)
	_run("placeholder_course", _test_placeholder_course)
	_run("graphics_settings", _test_graphics_settings)
	_run("object_library_chain", _test_object_library_chain)
	_run("free_assets", _test_free_assets)
	_run("web_game_files", _test_web_game_files)
	_run("golfer_file_readers", _test_golfer_file_readers)
	_run("format_readers", _test_format_readers)
	_run("course_reader", _test_course_reader)
	# Nodes added here only get _ready() once the main loop runs, so the
	# full round is played from _process().
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
	s.save(path)
	var loaded := GraphicsSettings.load_saved(path)
	_check(loaded.quality == GraphicsSettings.Quality.ULTRA, "quality saved")
	_check(loaded.msaa == 4, "msaa saved")
	_check_near(loaded.render_scale, 0.75, 1e-6, "render scale saved")
	_check_near(loaded.fov, 70.0, 1e-6, "fov saved")
	cfg = ConfigFile.new()
	cfg.load(path)
	_check(cfg.get_value("game", "folder", "") == "/somewhere", "other sections kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(Materials.terrain().shader != null, "terrain shader loads")
	_check(Materials.water().shader != null, "water shader loads")


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
