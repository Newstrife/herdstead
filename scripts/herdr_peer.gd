class_name HerdrPeer
extends RefCounted
## One connection to a herdr socket, over a Unix socket (the desktop) or a
## WebSocket to a herdr gateway (`--gateway=`, and every web build, which has
## no Unix sockets). The wire is the same either way: NDJSON lines, one
## request per connection, only `events.subscribe` held open. HerdrClient and
## HerdrCommands know nothing of which side they are on.
##
## A WebSocket target is one `ws://` or `wss://` URL; anything else is read as
## a Unix socket path. The gateway forwards chunks, not messages, so lines can
## arrive split across packets exactly as they do across socket reads; the
## callers' LineReader reassembles them, unchanged.

var _uds: StreamPeerUDS
var _ws: WebSocketPeer


## The socket file a UDS target must exist at, as open_peer() always checked.
static func open(target: String) -> HerdrPeer:
	var peer := HerdrPeer.new()
	if target.begins_with("ws://") or target.begins_with("wss://"):
		peer._ws = WebSocketPeer.new()
		# Inbound: the gateway sends 32 KiB chunks, so 8 MiB is ~256 queued
		# chunks of headroom for a stalled frame (the connection errors at the
		# cap instead of applying backpressure, unlike UDS; the 32 MiB line cap
		# stays with the callers' LineReader).
		# Outbound: the write boundary's largest payload is a 64 KiB paste,
		# past the 65535-byte default, and a WebSocket send is all or none.
		peer._ws.inbound_buffer_size = 8388608
		peer._ws.outbound_buffer_size = 8388608
		if peer._ws.connect_to_url(target) != OK:
			return null
		return peer
	var dir := DirAccess.open(target.get_base_dir())
	# FileAccess cannot see a unix socket; DirAccess can.
	if dir == null or not dir.file_exists(target.get_file()):
		return null
	peer._uds = StreamPeerUDS.new()
	if peer._uds.connect_to_host(target) != OK:
		return null
	return peer


## Drive the connection: the WebSocket handshake and reads need it, the socket
## always took it.
func poll() -> void:
	if _ws != null:
		_ws.poll()
	elif _uds != null:
		_uds.poll()


## StreamPeerSocket.Status, whichever side this is: CONNECTING during the
## handshake, CONNECTED once bytes may flow, ERROR once the connection is gone
## (a failed handshake included: the caller's retry and backoff treat both
## alike). A closed WebSocket still holding packets reports CONNECTED until
## they are drained, the way a closed socket reports until its bytes are read.
func status() -> StreamPeerSocket.Status:
	if _ws != null:
		match _ws.get_ready_state():
			WebSocketPeer.STATE_CONNECTING:
				return StreamPeerSocket.STATUS_CONNECTING
			WebSocketPeer.STATE_OPEN:
				return StreamPeerSocket.STATUS_CONNECTED
			WebSocketPeer.STATE_CLOSING:
				return StreamPeerSocket.STATUS_CONNECTED
			_:
				return (
					StreamPeerSocket.STATUS_CONNECTED
					if _ws.get_available_packet_count() > 0
					else StreamPeerSocket.STATUS_ERROR
				)
	return _uds.get_status() if _uds != null else StreamPeerSocket.STATUS_ERROR


## The bytes arrived since the last pull, as one buffer. Drains the
## WebSocket's packets, which stay readable after a close, like the socket's
## own bytes do.
func read_available() -> PackedByteArray:
	var bytes := PackedByteArray()
	if _ws != null:
		while _ws.get_available_packet_count() > 0:
			bytes.append_array(_ws.get_packet())
		return bytes
	if _uds == null or _uds.get_status() != StreamPeerSocket.STATUS_CONNECTED:
		return bytes
	var available := _uds.get_available_bytes()
	if available <= 0:
		return bytes
	var chunk: Array = _uds.get_partial_data(available)
	if chunk[0] == OK:
		bytes = chunk[1]
	return bytes


## Write the whole payload, or fail: put_data's contract, blocking included —
## a socket whose buffer is full takes a moment, exactly as the office's
## requests always did (envelopes are bounded lines, so the block is bounded).
## A WebSocket takes the payload as one binary message; a socket loops until
## every byte is out. HerdrClient's envelopes are one line each and never
## retried, so a half-sent line would hang the request until its timeout.
func write(bytes: PackedByteArray) -> Error:
	if _ws != null:
		if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			return ERR_UNAVAILABLE
		return _ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)
	if _uds == null:
		return ERR_UNAVAILABLE
	return _uds.put_data(bytes)


## Write what can go now: [error, bytes taken], put_partial_data's contract,
## for HerdrCommands' staged payloads. A WebSocket takes the whole payload as
## one binary message or none of it (its buffer is sized for the boundary's
## largest payload), so over a gateway a write is still one indivisible line.
func write_partial(bytes: PackedByteArray) -> Array:
	if _ws != null:
		if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			return [ERR_UNAVAILABLE, 0]
		var error := _ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)
		return [error, 0 if error != OK else bytes.size()]
	if _uds == null:
		return [ERR_UNAVAILABLE, 0]
	return _uds.put_partial_data(bytes)


## End it. Both sides keep already-arrived bytes readable until drained.
func close() -> void:
	if _ws != null:
		if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			_ws.close()
	elif _uds != null:
		_uds.disconnect_from_host()
