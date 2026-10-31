extends SceneTree
# Builds one course for the benchmark (see bench_one.sh): args query; SLUG names the files.
var f: RealCourseFetcher
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	f = RealCourseFetcher.new()
	f.servers = [OS.get_environment("OVERPASS") if OS.get_environment("OVERPASS") != "" else "https://maps.mail.ru/osm/tools/overpass/api/interpreter"]
	# Behind a proxy (as in the cloud containers): HTTPS_PROXY on localhost
	# and its CA bundle in BENCH_CA.
	if OS.get_environment("HTTPS_PROXY") != "":
		var ca := X509Certificate.new()
		ca.load(OS.get_environment("BENCH_CA") if OS.get_environment("BENCH_CA") != "" else "/root/.ccr/ca-bundle.crt")
		var port := int(OS.get_environment("HTTPS_PROXY").get_slice(":", 2))
		f.configure_request = func(r: HTTPRequest) -> void:
			r.set_https_proxy("127.0.0.1", port)
			r.set_tls_options(TLSOptions.client(ca))
	root.add_child(f)
	f.progress.connect(func(t: String) -> void: if not t.contains(" of "): print("  ", t))
	f.failed.connect(func(t: String) -> void: print("FAILED ", t); quit(1))
	f.found.connect(func(r: Array) -> void:
		for p in r.slice(0, 3): print("found ", p["golf"], " ", p["label"])
		if r.is_empty(): print("nothing"); quit(1); return
		var t0 := Time.get_ticks_msec()
		f.built.connect(func(c: DesignedCourse, s: Dictionary) -> void:
			print("BUILT in %d ms: %s" % [Time.get_ticks_msec() - t0, str(s).replace(str(s.get("photo")), "img")])
			print("credits: ", c.credits)
			if s.has("photo"):
				var file := c.default_path().get_basename().get_file() + ".photo.jpg"
				DirAccess.make_dir_recursive_absolute(DesignedCourse.FOLDER)
				(s["photo"] as Image).save_jpg(DesignedCourse.FOLDER.path_join(file), 0.85)
				(s["photo"] as Image).save_jpg("/tmp/bench/" + OS.get_environment("SLUG") + ".photo.jpg", 0.8)
				c.source["photo"] = file
			c.save_file(c.default_path())
			c.save_file("/tmp/bench/" + OS.get_environment("SLUG") + ".olc")
			print("saved ", ProjectSettings.globalize_path(c.default_path()))
			for i in c.holes.size(): print("hole %d par %d si %d len %.0f" % [i + 1, c.holes[i].par, c.holes[i].stroke_index, c.holes[i].length_m()])
			quit(0))
		f.build(r[0]))
	await process_frame
	f.search(a[0])
