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
	_run("obstacles_match_olcore", _test_obstacles_match_olcore)
	_run("swing_accuracy", _test_swing_accuracy)
	_run("swing_meter", _test_swing_meter)
	_run("scorecard", _test_scorecard)
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
