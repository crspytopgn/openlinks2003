class_name BuildInfo
extends RefCounted
## Filled in by CI before the game is exported (.github/workflows/ci.yml):
## the commit and time it was built from, shown small on the main menu so a
## player can tell which build they are running (handy on the web, where a
## cached page can be older than main). "dev" in a local run.

const COMMIT := "dev"
const BUILT := ""


static func label() -> String:
	if BUILT.is_empty():
		return "Build %s" % COMMIT
	return "Build %s, %s" % [COMMIT, BUILT]
