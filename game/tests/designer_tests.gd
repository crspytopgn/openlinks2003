extends RefCounted
## Checks for the course designer's data side: DesignedCourse, CourseShape,
## DesignedTerrain and DesignedCourseLoader. run_tests.gd calls run_all() and
## reports what it returns; it also opens the designer scene and plays a
## round on a designed course.

const TEST_PATH := "user://designer_test.olc"

var failures: Array[String] = []


func run_all() -> Array[String]:
	_test_scripts_compile()
	_test_shapes()
	_test_starter_surfaces()
	_test_save_round_trip()
	_test_sculpt()
	_test_edit_surfaces()
	_test_trees()
	_test_loader()
	_test_objects()
	_test_paths()
	_test_object_info()
	_test_bad_files()
	_test_water_surface()
	_test_splat_and_stakes()
	return failures


## The ground's splat map is the surface raster, and ponds get stakes.
func _test_splat_and_stakes() -> void:
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)])
	var pts := DesignedTerrain.stake_points(poly, 10.0)
	check(pts.size() == 20 and pts[0] == Vector2.ZERO and pts[1].is_equal_approx(Vector2(10, 0)), "stakes every 10 m round a 200 m outline")
	var c := DesignedCourse.starter()
	var t := DesignedTerrain.new(c)
	var mat := t.material()
	var splat := mat.get_shader_parameter("splat_tex") as Texture2D
	check(mat.get_shader_parameter("has_splat") == true and splat != null, "the ground has a splat map")
	if splat != null:
		check(splat.get_width() == ceili(c.area.size.x / DesignedTerrain.RES), "splat map at the raster's 0.5 m")
	var stakes := t.build_stakes()
	check(stakes != null and stakes.multimesh.instance_count > 5, "the starter pond has hazard stakes")
	if stakes != null:
		stakes.free()


## A pond's water carries how far each vertex is from the bank, for the
## shallows and shoreline.
func _test_water_surface() -> void:
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)])
	var m := DesignedTerrain.water_surface_mesh(poly, 1.5)
	var verts: PackedVector3Array = m[0]
	var open: PackedColorArray = m[1]
	var indices: PackedInt32Array = m[2]
	check(verts.size() > poly.size() and indices.size() >= 6 and indices.size() % 3 == 0, "water: grid inside the outline (%d vertices)" % verts.size())
	check(open[0].r == 0.0 and open[2].r == 0.0, "water: open is 0 on the bank")
	var deepest := 0.0
	for c in open:
		deepest = maxf(deepest, c.r)
	check(deepest == 1.0, "water: open water in the middle")
	check(is_equal_approx(verts[verts.size() - 1].y, 1.5), "water: at its level")


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _test_scripts_compile() -> void:
	for path in ["res://scripts/designer/course_designer.gd", "res://scripts/designer/designer_panel.gd",
			"res://scripts/designer/designer_camera.gd", "res://scripts/designer/designer_files.gd",
			"res://scripts/designer/designed_terrain.gd", "res://scripts/designer/designer_objects.gd", "res://scripts/designer/course_path.gd", "res://scripts/course/designed_course_loader.gd"]:
		var script: GDScript = load(path)
		check(script != null and script.can_instantiate(), "%s compiles" % path)


func _test_shapes() -> void:
	var square := CourseShape.new(Surface.Type.GREEN, PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]))
	check(square.contains(Vector2(5, 5)), "a square shape contains its centre")
	check(not square.contains(Vector2(15, 5)), "and not a point outside")
	check(square.signed_distance(Vector2(5, 5)) < -3.0, "inside is negative")
	check(square.signed_distance(Vector2(20, 5)) > 8.0, "outside is positive")
	check(square.outline().size() == 4 * CourseShape.SUBDIVISIONS, "smoothed outline")
	check(square.area() > 100.0 and square.area() < 150.0, "area of the smoothed square: %f" % square.area())
	var n := square.insert_point(Vector2(5, -1))
	check(n == 1 and square.points.size() == 5, "a point goes into the nearest edge")
	check(square.nearest_point(Vector2(10.5, 10.2), 2.0) == 3, "nearest control point")
	var back := CourseShape.from_dict(square.to_dict())
	check(back.surface == Surface.Type.GREEN and back.points == square.points, "shape survives to_dict")


func _starter_points(c: DesignedCourse) -> Dictionary:
	var z0 := c.area.position.y + 80.0
	return {
		"green": Vector2(-16, z0 + 365), "bunker": Vector2(26, z0 + 262), "pond": Vector2(-42, z0 + 190),
		"fairway": Vector2(8, z0 + 230), "tee": Vector2(2, z0 + 25),
	}


func _test_starter_surfaces() -> void:
	var c := DesignedCourse.starter()
	var data := c.to_course_data()
	check(data.holes.size() == 1, "the starter course has a hole")
	if data.holes.is_empty():
		return
	var h := data.holes[0]
	var t := h.terrain as DesignedTerrain
	check(t != null, "holes use a DesignedTerrain")
	check(h.tees.size() == 3, "three tees")
	for tee in h.tees:
		check(t.surface_at(tee.x, tee.z) == Surface.Type.TEE, "tee %s is on the tee box" % tee)
		check(absf(tee.y - t.height_at(tee.x, tee.z)) < 1e-3, "tee height")
	check(t.surface_at(h.pin.x, h.pin.z) == Surface.Type.GREEN, "the pin is on the green")
	check(h.par == 4 and h.length_m() > 330.0 and h.length_m() < 400.0, "par 4 of %d m" % roundi(h.length_m()))
	var pts := _starter_points(c)
	check(t.surface_at(pts.fairway.x, pts.fairway.y) == Surface.Type.FAIRWAY, "fairway")
	check(t.surface_at(pts.bunker.x, pts.bunker.y) == Surface.Type.SAND, "bunker")
	check(t.surface_at(pts.pond.x, pts.pond.y) == Surface.Type.WATER, "pond")
	check(t.surface_at(c.area.position.x + 3, c.area.position.y + 3) == Surface.Type.ROUGH, "rough elsewhere")
	check(t.surface_at(c.area.end.x + 5, 0) == Surface.Type.OUT_OF_BOUNDS, "out of bounds off the course")
	# The bunker is dug in below the ground round it.
	var b: Vector2 = pts.bunker
	check(t.height_at(b.x, b.y) < c.base_height(b.x, b.y) - 0.5, "bunker is dug in")
	# The pond's bed is under its water line.
	var pond := -1
	for i in c.shapes.size():
		if c.shapes[i].surface == Surface.Type.WATER:
			pond = i
	var p: Vector2 = pts.pond
	check(pond >= 0 and t.height_at(p.x, p.y) < t.water_level(c.shapes[pond]) - 0.5, "pond bed under the water")
	# Tee pads are level.
	var tee2: Vector2 = pts.tee
	check(absf(t.height_at(tee2.x, tee2.y + 10) - t.height_at(tee2.x, tee2.y - 10)) < 0.05, "tee box is level")
	# A fringe ring round the green.
	var g: Vector2 = pts.green
	var edge := g
	while t.surface_at(edge.x, edge.y) == Surface.Type.GREEN:
		edge.y -= 0.25
	check(t.surface_at(edge.x, edge.y - 0.6) == Surface.Type.FRINGE, "fringe round the green")
	var visual := t.build_visual()
	var n := t.chunk_count()
	check(visual.get_child_count() == n.x * n.y + 3, "a mesh per chunk, the apron, the paths and the water")
	var water := visual.get_child(visual.get_child_count() - 1)
	check(water.find_children("*", "MeshInstance3D", false, false).size() == 1, "one pond mesh")
	check(water.get_node_or_null("Stakes") != null, "and its hazard stakes")
	visual.free()


func _test_save_round_trip() -> void:
	var c := DesignedCourse.starter()
	c.course_name = "Round trip"
	c.author = "Tests"
	var text := c.to_json()
	check(text.length() < 600000, "the save file is compact: %d bytes" % text.length())
	var back := DesignedCourse.from_json(text)
	check(back != null, "a saved course loads")
	if back == null:
		return
	check(back.course_name == "Round trip" and back.author == "Tests", "name and author")
	check(back.area == c.area and back.heights.size() == c.heights.size(), "area and grid")
	var worst := 0.0
	for k in range(0, c.heights.size(), 97):
		worst = maxf(worst, absf(back.heights[k] - c.heights[k]))
	check(worst <= 0.0051, "heights to the centimetre (worst %f)" % worst)
	check(back.shapes.size() == c.shapes.size(), "shapes")
	check(back.holes.size() == 1 and back.holes[0].tees == c.holes[0].tees and back.holes[0].pin == c.holes[0].pin, "holes")
	check(back.objects.size() == c.objects.size(), "trees")
	var t1 := DesignedTerrain.new(c)
	var t2 := DesignedTerrain.new(back)
	var same := true
	for p: Vector2 in _starter_points(c).values():
		same = same and t1.surface_at(p.x, p.y) == t2.surface_at(p.x, p.y)
	check(same, "same surfaces after loading")


func _test_sculpt() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	var t := DesignedTerrain.new(c)
	var cells := c.sculpt("raise", Vector2(10, 10), 12.0, 2.0)
	t.update_heights(cells)
	check(absf(t.height_at(10, 10) - 2.0) < 0.05, "raise lifts the centre by the amount: %f" % t.height_at(10, 10))
	check(absf(t.height_at(10, 30)) < 1e-4, "and leaves ground outside the brush alone")
	check(t.height_at(16, 10) > 0.3 and t.height_at(16, 10) < 1.7, "with a smooth falloff")
	cells = c.sculpt("smooth", Vector2(10, 10), 12.0, 1.0)
	t.update_heights(cells)
	check(t.height_at(10, 10) < 1.95, "smoothing takes the top off")
	cells = c.sculpt("flatten", Vector2(10, 10), 20.0, 1.0, 0.5)
	t.update_heights(cells)
	check(absf(t.height_at(10, 10) - 0.5) < 0.01, "flatten levels the centre")
	c.sculpt("raise", Vector2(0, 0), 5.0, 1000.0)
	check(c.base_height(0, 0) <= DesignedCourse.MAX_HEIGHT, "heights stay in range")


func _test_edit_surfaces() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	var t := DesignedTerrain.new(c)
	var bunker := CourseShape.oval(Surface.Type.SAND, Vector2(0, 0), Vector2(6, 6))
	c.shapes.append(bunker)
	t.update_surfaces(bunker.bounds())
	check(t.surface_at(0, 0) == Surface.Type.SAND, "a new bunker shows up")
	check(t.height_at(0, 0) < -0.5, "and is dug in")
	var old := bunker.bounds()
	bunker.translate(Vector2(40, 0))
	t.update_surfaces(old.merge(bunker.bounds()))
	check(t.surface_at(0, 0) == Surface.Type.ROUGH, "a moved bunker leaves rough behind")
	check(absf(t.height_at(0, 0)) < 1e-4, "and level ground")
	check(t.surface_at(40, 0) == Surface.Type.SAND, "and is where it was moved to")
	check(c.shape_at(Vector2(40, 0)) == 0 and c.shape_at(Vector2(0, 0)) == -1, "shape_at")


func _test_trees() -> void:
	var c := DesignedCourse.starter()
	var t := DesignedTerrain.new(c)
	check(c.objects.size() == 90, "the starter course has trees")
	check(t.obstacles.size() == 2 * c.objects.size(), "a trunk and a canopy per tree")
	var o := c.objects[0]
	var y := t.height_at(o.position.x, o.position.z)
	var hit := t.obstacle_hit(Vector3(o.position.x - 5, y + 1.0, o.position.z), Vector3(o.position.x + 5, y + 1.0, o.position.z))
	check(not hit.is_empty(), "a ball hits a tree trunk")
	var data := c.to_course_data()
	check(not data.holes[0].objects.is_empty(), "the hole lists the trees near it")


func _test_loader() -> void:
	var c := DesignedCourse.starter()
	check(c.save_file(TEST_PATH) == OK, "saves")
	var loader := DesignedCourseLoader.new()
	check(loader.can_load(TEST_PATH) and loader.can_load("x/Y.OLC") and not loader.can_load("a.crz"), "can_load")
	var course := AssetProviders.load_course(TEST_PATH)
	check(course != null and course.course_name == c.course_name, "AssetProviders loads a designed course")
	check(course != null and course.holes.size() == 1 and course.holes[0].terrain is DesignedTerrain, "with its hole")
	check(CourseFiles.display_name(TEST_PATH) == "designer_test (your design)", "shown as a design")
	DirAccess.remove_absolute(TEST_PATH)
	var blank := DesignedCourse.blank(Vector2(100, 100))
	blank.save_file(TEST_PATH)
	check(loader.load_course(TEST_PATH) == null, "a course without holes isn't playable")
	DirAccess.remove_absolute(TEST_PATH)


func _test_bad_files() -> void:
	check(DesignedCourse.from_json("not json") == null, "garbage is refused")
	check(DesignedCourse.from_json("{\"format\": \"something else\"}") == null, "other JSON is refused")
	var d := DesignedCourse.starter().to_dict()
	d.version = DesignedCourse.VERSION + 1
	check(DesignedCourse.from_dict(d) == null, "newer versions are refused")
	d = DesignedCourse.starter().to_dict()
	d.heights.count = 5
	check(DesignedCourse.from_dict(d) == null, "a height grid of the wrong size is refused")
	d = DesignedCourse.starter().to_dict()
	d.shapes = [{"surface": "Green", "points": [0, 0, 1]}, "junk"]
	var c := DesignedCourse.from_dict(d)
	check(c != null and c.shapes.is_empty(), "broken shapes are skipped")


func _test_objects() -> void:
	var cats := DesignerObjects.categories()
	check(not cats.is_empty() and cats[0].items.size() == 3, "the built-in trees and bush come first")
	var field := ObstacleField.new()
	DesignerObjects.add_obstacles(field, PlacedObject.new("tree_pine", Vector3(0, 0, 0)), 0.0)
	DesignerObjects.add_obstacles(field, PlacedObject.new("Nothing like this.btx", Vector3(20, 0, 0)), 0.0)
	field.finalize()
	check(field.size() == 3, "a trunk and canopy for a tree, a post for an object the library doesn't know")
	check(not field.segment_hit(Vector3(15, 1, 0), Vector3(25, 1, 0)).is_empty(), "the unknown object still stops the ball")
	var bush := ObstacleField.new()
	DesignerObjects.add_obstacles(bush, PlacedObject.new("bush", Vector3(0, 0, 0)), 0.0)
	bush.finalize()
	check(bush.size() == 1 and not bush.segment_hit(Vector3(-5, 0.8, 0), Vector3(5, 0.8, 0)).is_empty(), "a bush catches a low ball")
	check(bush.segment_hit(Vector3(-5, 3.0, 0), Vector3(5, 3.0, 0)).is_empty(), "and not one over it")
	var node := AssetProviders.object_library.instantiate("bush") if AssetProviders.object_library != null else null
	check(AssetProviders.object_library == null or node != null, "the built-in bush can be drawn")
	if node != null:
		node.free()


func _test_paths() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	var cart := CoursePath.new(PackedVector2Array([Vector2(-50, -20), Vector2(0, 0), Vector2(50, 20)]), 3.0)
	var span := CoursePath.new(PackedVector2Array([Vector2(-20, 60), Vector2(20, 60)]), 3.0, true)
	c.paths.append(cart)
	c.paths.append(span)
	var t := DesignedTerrain.new(c)
	check(t.surface_at(0, 0) == Surface.Type.FAIRWAY, "a cart path plays as fairway")
	check(t.surface_at(0, 5) == Surface.Type.ROUGH, "rough beside the path")
	check(t.free_drop_at(0, 0) and not t.free_drop_at(0, 5), "a free drop from the cart path")
	var y := t.height_at(0, 60)
	check(not t.obstacle_hit(Vector3(0, y + 3.0, 60), Vector3(0, y + 0.1, 60)).is_empty(), "a ball lands on the bridge deck")
	check(t.obstacle_hit(Vector3(0, y + 3.0, 70), Vector3(0, y + 0.1, 70)).is_empty(), "and nowhere else")
	var back := DesignedCourse.from_json(c.to_json())
	check(back != null and back.paths.size() == 2, "paths are saved")
	if back != null and back.paths.size() == 2:
		check(back.paths[0].points == cart.points and is_equal_approx(back.paths[0].width, 3.0) and not back.paths[0].bridge, "a path's points and width")
		check(back.paths[1].bridge, "a bridge stays a bridge")
	check(CoursePath.new(PackedVector2Array([Vector2(1, 1)])).is_valid() == false, "a path needs two points")
	var visual := t.build_paths()
	check(visual.get_child_count() == 2, "a mesh per path")
	visual.free()


func _test_object_info() -> void:
	# A course made with the player's game files, opened without them: the
	# saved sizes keep its obstacles, and its trees get built-in stand-ins.
	var c := DesignedCourse.blank(Vector2(200, 200))
	c.objects.append(PlacedObject.new("Oak big.btx", Vector3(0, 0, 0), 0.0, 1.0))
	c.objects.append(PlacedObject.new("Barn.mdl", Vector3(40, 0, 0), 90.0, 1.0))
	c.object_info = {
		"Oak big.btx": {"kind": "tree", "size": [12.0, 20.0, 12.0], "centre": [0.0, 10.0, 0.0]},
		"Barn.mdl": {"kind": "model", "size": [10.0, 6.0, 20.0], "centre": [0.0, 3.0, 0.0]},
		"Unused.btx": {"kind": "solid", "size": [1.0, 1.0, 1.0], "centre": [0.0, 0.5, 0.0]},
	}
	var d := c.to_dict()
	check(not (d.object_info as Dictionary).has("Unused.btx"), "unused object sizes aren't saved")
	var back := DesignedCourse.from_dict(d)
	check(back != null and back.object_info.has("Barn.mdl") and back.object_info.has("Oak big.btx"), "object sizes are saved")
	if back == null:
		return
	var tree := DesignerObjects.stand_in(back.objects[0], back.object_info)
	check(tree != null and tree.id == "tree_broadleaf" and is_equal_approx(tree.scale, 2.0), "a missing tree gets a built-in one of its height")
	check(DesignerObjects.stand_in(back.objects[1], back.object_info) == null, "a missing building isn't drawn")
	var t := DesignedTerrain.new(back)
	var y := t.height_at(40, 0)
	# The barn is turned 90 degrees, so its 20 m length runs along x.
	check(not t.obstacle_hit(Vector3(40 + 8, y + 3, -10), Vector3(40 + 8, y + 3, 10)).is_empty(), "the barn is as long as it was measured")
	check(t.obstacle_hit(Vector3(40 + 12, y + 3, -10), Vector3(40 + 12, y + 3, 10)).is_empty(), "and no longer")
	check(t.obstacle_hit(Vector3(40, y + 7, -10), Vector3(40, y + 7, 10)).is_empty(), "and no taller")
	var ty := t.height_at(0, 0)
	check(not t.obstacle_hit(Vector3(-10, ty + 12, 0), Vector3(10, ty + 12, 0)).is_empty(), "the tree's canopy is where it was measured")
