class_name OpenConnect
extends RefCounted
## Real swings from a home launch monitor, over the open "GSPro Connect"
## protocol (version 1) that most launch monitors and their connector apps
## speak: JSON shot messages on a TCP socket (port 921 on this machine), each
## answered with a JSON status. See docs/game-shell.md#launch-monitors.
##
## Shot message (the parts we read):
##   {"DeviceID": "...", "Units": "Yards", "ShotNumber": 3, "APIversion": "1",
##    "BallData": {"Speed": 147.5, "SpinAxis": -3.2, "TotalSpin": 2680,
##                 "HLA": 1.4, "VLA": 11.8},
##    "ShotDataOptions": {"ContainsBallData": true, "IsHeartBeat": false}}
## Speed is in mph, spin in rpm, angles in degrees. HLA (horizontal launch)
## and SpinAxis are positive to the right, as launch monitors report them:
## a positive spin axis curves the ball right. BackSpin and SideSpin may come
## instead of TotalSpin and SpinAxis.

const PORT := 921
const MPS_PER_MPH := 0.44704
const RPM_TO_RAD_S := TAU / 60.0


## A launch monitor's reading of one shot, in the protocol's units.
class Launch:
	var speed_mph := 0.0
	var vla_deg := 0.0
	var hla_deg := 0.0  ## positive right
	var total_rpm := 0.0
	var axis_deg := 0.0  ## positive tilts the spin to curve the ball right

	func to_array() -> Array:
		return [speed_mph, vla_deg, hla_deg, total_rpm, axis_deg]

	static func from_array(a: Array) -> Launch:
		var l := Launch.new()
		if a.size() == 5:
			l.speed_mph = float(a[0])
			l.vla_deg = float(a[1])
			l.hla_deg = float(a[2])
			l.total_rpm = float(a[3])
			l.axis_deg = float(a[4])
		return l


## Splits the start of `buffer` into whole JSON objects (messages arrive back
## to back, sometimes split across reads). Returns [messages, rest]: the
## parsed Dictionaries and the text still waiting for the end of an object.
static func split_messages(buffer: String) -> Array:
	var out: Array[Dictionary] = []
	var depth := 0
	var start := -1
	var in_string := false
	var escaped := false
	var consumed := 0
	for i in buffer.length():
		var c := buffer[i]
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_string = false
			continue
		match c:
			"\"":
				in_string = true
			"{":
				if depth == 0:
					start = i
				depth += 1
			"}":
				if depth > 0:
					depth -= 1
					if depth == 0 and start >= 0:
						var parsed: Variant = JSON.parse_string(buffer.substr(start, i - start + 1))
						if parsed is Dictionary:
							out.append(parsed)
						consumed = i + 1
						start = -1
	if depth == 0:
		consumed = buffer.length()
	return [out, buffer.substr(consumed)]


## The ball data of a shot message, or null for a heartbeat, a message
## without ball data, or a shot too weak to be one.
static func launch_of(msg: Dictionary) -> Launch:
	var opts: Variant = msg.get("ShotDataOptions", {})
	if opts is Dictionary:
		var o := opts as Dictionary
		if bool(o.get("IsHeartBeat", false)) or not bool(o.get("ContainsBallData", true)):
			return null
	var ball: Variant = msg.get("BallData")
	if not ball is Dictionary:
		return null
	var b := ball as Dictionary
	var l := Launch.new()
	l.speed_mph = float(b.get("Speed", 0.0))
	l.vla_deg = float(b.get("VLA", 0.0))
	l.hla_deg = float(b.get("HLA", 0.0))
	if b.has("TotalSpin") and float(b.get("TotalSpin", 0.0)) > 0.0:
		l.total_rpm = float(b.TotalSpin)
		l.axis_deg = float(b.get("SpinAxis", 0.0))
	else:
		var back := float(b.get("BackSpin", 0.0))
		var side := float(b.get("SideSpin", 0.0))
		l.total_rpm = Vector2(back, side).length()
		l.axis_deg = rad_to_deg(atan2(side, back)) if l.total_rpm > 0.0 else 0.0
	if l.speed_mph < 1.0:
		return null
	return l


## The ball leaving the club for `launch` hit along heading `aim_deg`
## (positive left of +z), at the origin.
static func ball_state(launch: Launch, aim_deg: float) -> BallState:
	var axis := deg_to_rad(launch.axis_deg)
	# Our sidespin is positive for a ball curving left.
	return BallPhysics.make_launch(launch.speed_mph * MPS_PER_MPH, launch.vla_deg, aim_deg - launch.hla_deg,
			launch.total_rpm * cos(axis), -launch.total_rpm * sin(axis))


## The status sent back for each message.
static func reply_ok() -> String:
	return JSON.stringify({"Code": 200, "Message": "Shot received successfully"})


## Tells the launch monitor app who is up and with what club (GSPro's
## "player information", code 201). `club` is a short name such as "DR".
static func reply_player(right_handed: bool, club: String) -> String:
	return JSON.stringify({"Code": 201, "Message": "GSPro Player Information",
		"Player": {"Handed": "RH" if right_handed else "LH", "Club": club}})


## Launch monitor apps name clubs as GSPro does ("DR", "3W", "7I", "PW",
## "PT").
static func club_code(short_name: String) -> String:
	match short_name:
		"Dr":
			return "DR"
		"Pt", "Putter", "P":
			return "PT"
	return short_name.to_upper()
