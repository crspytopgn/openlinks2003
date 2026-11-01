extends Node
## Small HTTP helper over HTTPRequest: JSON GETs from the GitHub API and file
## downloads with progress. Honours HTTPS_PROXY / HTTP_PROXY like most
## command-line tools, for players behind a proxy.

const USER_AGENT := "OpenLinks2003-Launcher"
const TIMEOUT_JSON := 20.0

## Bytes downloaded so far and the total (0 when unknown) of the download
## in progress.
signal download_progress(done: int, total: int)

var _download: HTTPRequest


func _new_request() -> HTTPRequest:
	var r := HTTPRequest.new()
	r.use_threads = true
	r.max_redirects = 10
	_apply_proxy(r)
	add_child(r)
	return r


static func _proxy(names: Array) -> Array:
	for n: String in names:
		var v := OS.get_environment(n)
		if v.is_empty():
			continue
		var re := RegEx.create_from_string("^(?:https?://)?(?:[^@/]*@)?([^:/]+):(\\d+)")
		var m := re.search(v)
		if m != null:
			return [m.get_string(1), int(m.get_string(2))]
	return []


static func _apply_proxy(r: HTTPRequest) -> void:
	var https := _proxy(["HTTPS_PROXY", "https_proxy"])
	if not https.is_empty():
		r.set_https_proxy(https[0], https[1])
	var http := _proxy(["HTTP_PROXY", "http_proxy"])
	if not http.is_empty():
		r.set_http_proxy(http[0], http[1])


## GETs `url` and decodes the JSON. {ok, data, code, error}.
func get_json(url: String) -> Dictionary:
	var r := _new_request()
	r.timeout = TIMEOUT_JSON
	var headers := PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/vnd.github+json"])
	var err := r.request(url, headers)
	if err != OK:
		r.queue_free()
		return {"ok": false, "error": "Couldn't start the request (%s)." % error_string(err)}
	var res: Array = await r.request_completed
	r.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": code, "error": "No connection (%d)." % result}
	if code != 200:
		var why := "GitHub's limit for checks this hour was reached." if code == 403 or code == 429 else "GitHub answered %d." % code
		return {"ok": false, "code": code, "error": why}
	var data: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if data == null:
		return {"ok": false, "code": code, "error": "GitHub's answer couldn't be read."}
	return {"ok": true, "code": code, "data": data}


## Downloads `url` to `path`, emitting download_progress. {ok, error}.
func download(url: String, path: String) -> Dictionary:
	cancel()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_download = _new_request()
	_download.download_file = path
	_download.download_chunk_size = 1 << 20
	var err := _download.request(url, PackedStringArray(["User-Agent: " + USER_AGENT]))
	if err != OK:
		_download.queue_free()
		_download = null
		return {"ok": false, "error": "Couldn't start the download (%s)." % error_string(err)}
	set_process(true)
	var res: Array = await _download.request_completed
	if _download != null:
		_download.queue_free()
		_download = null
	set_process(false)
	var result: int = res[0]
	var code: int = res[1]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(path)
		return {"ok": false, "error": "The download stopped (%s)." % ("no connection" if result != HTTPRequest.RESULT_SUCCESS else "GitHub answered %d" % code)}
	return {"ok": true}


func downloading() -> bool:
	return _download != null


func cancel() -> void:
	if _download != null:
		_download.cancel_request()
		_download.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if _download != null:
		download_progress.emit(_download.get_downloaded_bytes(), maxi(_download.get_body_size(), 0))
