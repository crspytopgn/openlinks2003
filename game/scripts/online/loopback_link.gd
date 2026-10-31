class_name LoopbackLink
extends OnlineLink
## Two or more games in one process, as if in one room: what one sends, the
## others receive (the server's relay without its checks). For the tests.

var _hub: Array = []  ## every link in the room
var _inbox: Array[Dictionary] = []


## `count` links joined to each other.
static func room(count: int) -> Array[LoopbackLink]:
	var hub: Array = []
	var links: Array[LoopbackLink] = []
	for i in count:
		var l := LoopbackLink.new()
		l._hub = hub
		hub.append(l)
		links.append(l)
	return links


func send(msg: Dictionary) -> void:
	# Through JSON, like the real thing (numbers come back as floats).
	var copy: Variant = JSON.parse_string(JSON.stringify(msg))
	for l: LoopbackLink in _hub:
		if l != self:
			l._inbox.append(copy)


func receive() -> Array[Dictionary]:
	var out := _inbox
	_inbox = []
	return out


func is_open() -> bool:
	return true
