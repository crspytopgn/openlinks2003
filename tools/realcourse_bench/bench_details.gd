extends SceneTree
# bench_details.gd -- slug: close-ups round every pin of a bench course.
func _initialize() -> void:
	var slug: String = OS.get_cmdline_user_args()[0]
	var c := DesignedCourse.load_file("/tmp/bench/%s.olc" % slug)
	var frame := GeoFrame.new(float(c.source["lat"]), float(c.source["lon"]))
	var f := RealCourseFetcher.new()
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
	await process_frame
	var srcs := AerialPhotos.sources_for(float(c.source["lat"]), float(c.source["lon"]))
	for src in srcs:
		if AerialPhotos.has_detail(src) and await _try(c, frame, f, src, slug):
			quit()
			return
	print(slug, " no detail source")
	quit()


func _try(c: DesignedCourse, frame: GeoFrame, f: RealCourseFetcher, src: Dictionary, slug: String) -> bool:
	var srcs := [src]
	var areas := []
	var parts: Array[AerialPhotos] = []
	var urls := PackedStringArray()
	for h in c.holes:
		var a := AerialPhotos.detail_area(h.pin)
		var part := AerialPhotos.new(srcs[0], AerialPhotos.geo_box_of(frame, a), AerialPhotos.DETAIL_ZOOM)
		parts.append(part)
		urls.append_array(part.urls())
	var got: Array = await f._fetch_all(urls, "details")
	var at := 0
	var meta := []
	for k in parts.size():
		var n := parts[k].urls().size()
		for i in n:
			if got[at + i][0] == 200:
				parts[k].add_tile(i, got[at + i][1])
		at += n
		var a := AerialPhotos.detail_area(c.holes[k].pin)
		var img := parts[k].course_photo(frame, a, AerialPhotos.DETAIL_RES)
		if img != null and parts[k].loaded * 4 >= n * 3:
			img.save_png("/tmp/bench/%s.d%d.png" % [slug, k])
			meta.append({"k": k, "x": a.position.x, "y": a.position.y, "s": a.size.x})
	FileAccess.open("/tmp/bench/%s.details.json" % slug, FileAccess.WRITE).store_string(JSON.stringify(meta))
	print(slug, " details ", meta.size(), " of ", parts.size(), " zoom ", parts[0].zoom, " ", src["id"])
	return meta.size() * 2 >= parts.size()
