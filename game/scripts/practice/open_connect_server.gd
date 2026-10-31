class_name OpenConnectServer
extends Node
## Listens for a launch monitor app on port 921 (OpenConnect) and emits each
## real shot. Desktop only: browsers can't open a listening socket.

signal shot_received(launch: OpenConnect.Launch)
signal connected_changed(connected: bool)

var _server := TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _buffers: Array[String] = []
var _player := ""


static func supported() -> bool:
	return not OS.has_feature("web")


## Starts listening; false if the port is taken (another simulator running).
func start(port := OpenConnect.PORT) -> bool:
	if not supported():
		return false
	return _server.listen(port) == OK


func stop() -> void:
	for p in _peers:
		p.disconnect_from_host()
	_peers.clear()
	_buffers.clear()
	_server.stop()


func is_listening() -> bool:
	return _server.is_listening()


func has_connection() -> bool:
	return not _peers.is_empty()


## Tells the app which club is up, so it can pick its own club setting.
func send_player(right_handed: bool, club_short_name: String) -> void:
	_player = OpenConnect.reply_player(right_handed, OpenConnect.club_code(club_short_name))
	for p in _peers:
		_send(p, _player)


func _process(_delta: float) -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		_peers.append(peer)
		_buffers.append("")
		if not _player.is_empty():
			_send(peer, _player)
		connected_changed.emit(true)
	for i in range(_peers.size() - 1, -1, -1):
		var peer := _peers[i]
		peer.poll()
		var status := peer.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED and status != StreamPeerTCP.STATUS_CONNECTING:
			_peers.remove_at(i)
			_buffers.remove_at(i)
			connected_changed.emit(not _peers.is_empty())
			continue
		var n := peer.get_available_bytes()
		if n <= 0:
			continue
		var got: Array = peer.get_partial_data(n)
		if got[0] != OK:
			continue
		var split := OpenConnect.split_messages(_buffers[i] + (got[1] as PackedByteArray).get_string_from_utf8())
		_buffers[i] = split[1]
		for msg: Dictionary in split[0]:
			_send(peer, OpenConnect.reply_ok())
			var launch := OpenConnect.launch_of(msg)
			if launch != null:
				shot_received.emit(launch)


func _send(peer: StreamPeerTCP, text: String) -> void:
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data(text.to_utf8_buffer())
