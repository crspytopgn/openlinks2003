class_name WebSocketLink
extends OnlineLink
## An online room over a WebSocket (works in the web build too). Call
## receive() every frame: it also polls the socket.

var socket := WebSocketPeer.new()
var _outbox: Array[String] = []


## Opens `url` (wss://server/rooms/CODE); `hello` is sent once it opens.
func _init(url: String, hello: Dictionary) -> void:
	socket.inbound_buffer_size = 256 * 1024
	socket.outbound_buffer_size = 256 * 1024
	socket.connect_to_url(url)
	_outbox.append(JSON.stringify(hello))


func send(msg: Dictionary) -> void:
	_outbox.append(JSON.stringify(msg))


func receive() -> Array[Dictionary]:
	socket.poll()
	var out: Array[Dictionary] = []
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return out
	while not _outbox.is_empty():
		socket.send_text(_outbox.pop_front())
	while socket.get_available_packet_count() > 0:
		var d: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if d is Dictionary:
			out.append(d)
	return out


func is_open() -> bool:
	var s := socket.get_ready_state()
	return s == WebSocketPeer.STATE_OPEN or s == WebSocketPeer.STATE_CONNECTING


func close() -> void:
	socket.close()
