class_name OnlineRound
extends RefCounted
## One player's side of a live online round (docs/online-play.md).
##
## Every game in the room plays the whole round itself, in step: the same
## setup and seed, and the same stream of events (each shot's inputs, each
## drop), numbered from 0. A player's own shots are played at once and sent;
## everyone else's are played when they arrive, and each game checks that the
## ball stops where the sender's did. So no game has to trust another's
## scores, and the round needs nothing from the server but the relay.

const QUICK_CHAT := ["Nice shot!", "Unlucky.", "Good putt!", "Great drive!", "Oops.", "Your turn.", "Well played.", "Good game!"]

var link: OnlineLink
## My seat in the room, and the room seat that plays each player of the round
## (computer golfers belong to the host).
var my_seat := 0
var owners: Array[int] = []
## Number of the next event in the round.
var seq := 0
## Events that arrived ahead of the round.
var _pending: Dictionary = {}
## Things to show: quick chat, players leaving, a replay that disagreed.
var notices: Array[String] = []
## Shots whose replay here stopped somewhere else than the sender's.
var mismatches := 0
var host_seat := 0


func _init(p_link: OnlineLink, p_seat: int, p_owners: Array[int]) -> void:
	link = p_link
	my_seat = p_seat
	owners = p_owners.duplicate()


## True when this game plays player `i` (a seat of the round's setup).
func owns(i: int) -> bool:
	return i < 0 or i >= owners.size() or owners[i] == my_seat


## Reads the link: events go in order, the rest become notices.
func poll() -> void:
	for msg in link.receive():
		match str(msg.get("type", "")):
			"event":
				var n := int(msg.get("seq", -1))
				if n >= seq:
					_pending[n] = msg
			"chat":
				var id := int(msg.get("id", -1))
				if id >= 0 and id < QUICK_CHAT.size():
					notices.append("%s: %s" % [msg.get("name", "?"), QUICK_CHAT[id]])
			"mismatch":
				notices.append("%s's game saw shot %d differently." % [msg.get("name", "?"), int(msg.get("shot", 0)) + 1])
			"owners":
				# Someone left: the host plays their seats from here on.
				var o: Array = msg.get("owners", [])
				for i in mini(o.size(), owners.size()):
					owners[i] = int(o[i])
				if msg.has("host"):
					host_seat = int(msg.host)
			"left", "host_left":
				notices.append("%s left the round." % msg.get("name", "?"))
			"error":
				notices.append("Server: %s" % msg.get("reason", "error"))


## The next event of the round if it has arrived, else {}.
func next_event() -> Dictionary:
	return _pending.get(seq, {})


## The event was played: on to the next.
func done_event() -> void:
	_pending.erase(seq)
	seq += 1


## Sends a shot this game played (and counts it).
func send_shot(rec: ShotRecord) -> void:
	link.send({"type": "event", "seq": seq, "player": rec.player, "kind": "shot", "shot": rec.to_dict()})
	seq += 1


## Sends a drop this game took: the reason, the option and the spot.
func send_drop(player: int, reason: int, choice: int, spot: Vector3) -> void:
	link.send({"type": "event", "seq": seq, "player": player, "kind": "drop",
		"reason": reason, "choice": choice, "spot": [spot.x, spot.y, spot.z]})
	seq += 1


func report_mismatch(event_seq: int) -> void:
	mismatches += 1
	link.send({"type": "mismatch", "shot": event_seq})


func chat(id: int) -> void:
	link.send({"type": "chat", "id": id})


## The host's round setup as a message: everything another game needs to play
## the same round. `owners` says which room seat plays each player.
static func setup_message(setup: RoundSetup, round_seed: int, wind_level: int, p_owners: Array[int], course_hash: String) -> Dictionary:
	return {
		"type": "setup", "seed": round_seed, "wind_level": wind_level, "owners": p_owners,
		"course_file": setup.course_path.get_file(), "course_name": setup.course_name, "course_hash": course_hash,
		"mode": setup.mode, "holes": setup.holes, "tees": setup.tees, "names": setup.names,
		"teams": setup.teams, "computer": setup.computer, "handicaps": setup.handicaps, "indexes": setup.indexes,
	}


## The RoundSetup in a setup message (course_path left for the caller to
## find from course_file), or null if it isn't one.
static func setup_from(msg: Dictionary) -> RoundSetup:
	if str(msg.get("type", "")) != "setup":
		return null
	var s := RoundSetup.new()
	s.course_name = str(msg.get("course_name", ""))
	s.mode = int(msg.get("mode", 0)) as GameModes.Mode
	s.holes = int(msg.get("holes", 0)) as RoundSetup.Holes
	s.tees = int(msg.get("tees", 0)) as RoundSetup.Tees
	s.names.clear()
	for n: Variant in msg.get("names", []):
		s.names.append(str(n))
	s.teams.clear()
	for t: Variant in msg.get("teams", []):
		s.teams.append(int(t))
	s.computer.clear()
	for c: Variant in msg.get("computer", []):
		s.computer.append(int(c))
	s.indexes.clear()
	for x: Variant in msg.get("indexes", []):
		s.indexes.append(int(x))
	s.handicaps = bool(msg.get("handicaps", false))
	s.round_seed = int(msg.get("seed", 0))
	s.wind_level = int(msg.get("wind_level", -1))
	if s.names.is_empty() or s.problem() != "":
		return null
	return s


static func owners_from(msg: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for o: Variant in msg.get("owners", []):
		out.append(int(o))
	return out
