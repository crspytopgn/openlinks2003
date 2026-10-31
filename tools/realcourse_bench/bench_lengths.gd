extends SceneTree
# bench_lengths.gd -- slug: each hole's length (back tee, along the line, to the pin) in yards, to set against the scorecard.
func _initialize() -> void:
	var slug: String = OS.get_cmdline_user_args()[0]
	var c := DesignedCourse.load_file("/tmp/bench/%s.olc" % slug)
	var out := []
	var tot := 0.0
	for h in c.holes:
		var y := h.length_m() / 0.9144
		out.append("%d" % roundi(y))
		tot += y
	print(slug, " par ", c.holes.map(func(h): return h.par), "\n yards ", " ".join(out), "\n total ", roundi(tot))
	quit()
