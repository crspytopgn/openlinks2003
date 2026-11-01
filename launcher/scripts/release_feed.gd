extends RefCounted
## Reads what GitHub says about the game: the rolling "latest" release that
## CI publishes from main (the builds to download) and the commits on main
## (the changelog). Pure functions over the decoded JSON, so they're tested
## without the network (tests/run_tests.gd).

const API := "https://api.github.com/repos/crspytopgn/openlinks2003"
const RELEASE_URL := API + "/releases/tags/latest"
const COMMITS_URL := API + "/commits?sha=main&per_page=40"
## The top folder of main, for the tree id of launcher/.
const CONTENTS_URL := API + "/contents/?ref=main"

## Lines that end the part of a commit message worth showing.
const STOP := ["co-authored-by:", "claude-session:", "---------", "signed-off-by:"]
const MAX_POINTS := 5
const MAX_SUMMARY := 280


## The release and this platform's download from the release JSON:
## {commit, title, published, url, size, digest, page}, or {} when the
## release or the download is missing.
static func parse_release(json: Variant, asset_name: String) -> Dictionary:
	if not json is Dictionary:
		return {}
	var rel: Dictionary = json
	for a: Variant in rel.get("assets", []):
		if not a is Dictionary or str(a.get("name", "")) != asset_name:
			continue
		var digest := str(a.get("digest", ""))
		return {
			"commit": str(rel.get("target_commitish", "")),
			"title": str(rel.get("name", "")),
			"published": str(rel.get("published_at", "")),
			"url": str(a.get("browser_download_url", "")),
			"size": int(a.get("size", 0)),
			"digest": digest.trim_prefix("sha256:") if digest.begins_with("sha256:") else "",
			"page": str(rel.get("html_url", "")),
		}
	return {}


## Changelog entries from the commits JSON, newest first:
## {sha, title, pr, date, points: PackedStringArray, summary}. Merges of
## main into a branch are left out.
static func parse_commits(json: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not json is Array:
		return out
	for c: Variant in json:
		if not c is Dictionary:
			continue
		var commit: Dictionary = c.get("commit", {})
		var entry := parse_message(str(commit.get("message", "")))
		if entry.is_empty():
			continue
		entry["sha"] = str(c.get("sha", ""))
		var who: Dictionary = commit.get("committer", commit.get("author", {}))
		entry["date"] = str(who.get("date", ""))
		out.append(entry)
	return out


## A commit message as {title, pr, points, summary}, or {} to leave it out.
## Squash merges list their commits as "* title" lines: those become the
## points. Otherwise the first paragraph is the summary.
static func parse_message(message: String) -> Dictionary:
	var lines := message.replace("\r", "").split("\n")
	if lines.is_empty():
		return {}
	var title := lines[0].strip_edges()
	var body := lines.slice(1)
	var pr := 0
	var merge := RegEx.create_from_string("^Merge pull request #(\\d+)")
	var m := merge.search(title)
	if m != null:
		pr = int(m.get_string(1))
		title = ""
		for i in body.size():
			if not body[i].strip_edges().is_empty():
				title = body[i].strip_edges()
				body = body.slice(i + 1)
				break
	elif title.begins_with("Merge branch") or title.begins_with("Merge remote-tracking"):
		return {}
	var ref := RegEx.create_from_string("\\s*\\(#(\\d+)\\)")
	# GitHub appends the squash-merged PR's number last: "Title (#154) (#165)".
	if pr == 0:
		var all := ref.search_all(title)
		if not all.is_empty():
			pr = int(all[-1].get_string(1))
	title = ref.sub(title, "", true).strip_edges()
	if title.is_empty():
		return {}

	var points := PackedStringArray()
	var paragraph := PackedStringArray()
	var in_paragraph := false
	var paragraph_done := false
	for raw in body:
		var line := raw.strip_edges()
		var lower := line.to_lower()
		var stop := false
		for s: String in STOP:
			if lower.begins_with(s):
				stop = true
		if stop:
			if lower.begins_with("---------"):
				break
			continue
		if line.begins_with("* "):
			var point := ref.sub(line.substr(2), "", true).strip_edges()
			if not point.is_empty() and point != title and not points.has(point):
				points.append(point)
			paragraph_done = true
			continue
		if paragraph_done:
			continue
		if line.is_empty():
			if in_paragraph:
				paragraph_done = true
			continue
		in_paragraph = true
		paragraph.append(line)
	var summary := " ".join(paragraph)
	if summary.length() > MAX_SUMMARY:
		var cut := summary.left(MAX_SUMMARY)
		var space := cut.rfind(" ")
		summary = (cut.left(space) if space > 200 else cut) + "..."
	if points.size() > MAX_POINTS:
		points = points.slice(points.size() - MAX_POINTS)  # the last ones are the newest work
	return {"title": title, "pr": pr, "points": points, "summary": summary}


## How many entries are newer than the installed build `commit`: all of
## them when it isn't in the list (or nothing is installed).
static func count_new(entries: Array[Dictionary], commit: String) -> int:
	if commit.is_empty():
		return 0
	for i in entries.size():
		if str(entries[i].get("sha", "")).begins_with(commit) or commit.begins_with(str(entries[i].get("sha", "@"))):
			return i
	return entries.size()


## "Just now", "5 min ago", "3 h ago", "Yesterday", "Tuesday" or "12 Oct".
static func relative_date(iso: String, now_unix: float = -1.0) -> String:
	if iso.is_empty():
		return ""
	var t := Time.get_unix_time_from_datetime_string(iso)
	var now := now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	var ago := now - t
	if ago < 90:
		return "Just now"
	if ago < 3600:
		return "%d min ago" % roundi(ago / 60.0)
	if ago < 86400:
		return "%d h ago" % floori(ago / 3600.0)
	if ago < 2 * 86400:
		return "Yesterday"
	var d := Time.get_datetime_dict_from_unix_time(int(t))
	if ago < 6 * 86400:
		return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][int(d.weekday)]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s" % [int(d.day), months[int(d.month) - 1]]


## The tree id of launcher/ in the contents JSON of the top folder, or "".
static func launcher_tree(json: Variant) -> String:
	if json is Array:
		for e: Variant in json:
			if e is Dictionary and str(e.get("name", "")) == "launcher" and str(e.get("type", "")) == "dir":
				return str(e.get("sha", ""))
	return ""


## The short form of a commit id.
static func short(commit: String) -> String:
	return commit.left(7)
