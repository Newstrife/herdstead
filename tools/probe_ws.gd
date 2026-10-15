extends SceneTree
## A HerdrPeer ping over a gateway WebSocket: the smallest end-to-end proof of
## the web transport. tools/test_gateway.py runs it against a real gateway and
## a fake herdr; by hand:
##
## godot --headless --path . --script tools/probe_ws.gd -- --url=ws://127.0.0.1:8765/ws/local
##
## Prints GOT LINE and exits 0 on an answer; exits 2 on a dead connection, 3 on
## a timeout, 2 on a harness error (no --url=).

var _exit := 3


func _initialize() -> void:
	var url := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--url="):
			url = argument.trim_prefix("--url=")
	if url.is_empty():
		print("PROBE_WS_ERROR: pass --url=ws://…")
		quit(2)
		return
	_probe(url)


func _probe(url: String) -> void:
	var peer := HerdrPeer.open(url)
	if peer == null:
		print("PROBE_WS_ERROR: could not open " + url)
		quit(2)
		return
	var sent := false
	var buffer := PackedByteArray()
	var left := 8.0
	while left > 0.0:
		peer.poll()
		var state := peer.status()
		if state == StreamPeerSocket.STATUS_CONNECTED and not sent:
			sent = true
			if peer.write(HerdrClient.request_line("1", "ping", {})) != OK:
				print("PROBE_WS_ERROR: the ping could not be written")
				quit(2)
				return
		buffer.append_array(peer.read_available())
		if buffer.find(10) >= 0:
			print("GOT LINE: " + buffer.get_string_from_utf8().strip_edges())
			quit(0)
			return
		if state == StreamPeerSocket.STATUS_ERROR and buffer.is_empty():
			print("PROBE_WS_ERROR: the connection died unanswered")
			quit(2)
			return
		await create_timer(0.05).timeout
		left -= 0.05
	print("PROBE_WS_ERROR: timeout, no answer")
	quit(3)
