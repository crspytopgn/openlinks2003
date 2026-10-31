class_name OnlineLink
extends RefCounted
## A connection to an online room (server/README.md): JSON messages in and
## out. WebSocketLink talks to the server; LoopbackLink joins two games in
## one process for the tests.


func send(_msg: Dictionary) -> void:
	pass


## Messages that arrived since the last call.
func receive() -> Array[Dictionary]:
	return []


func is_open() -> bool:
	return false


func close() -> void:
	pass
