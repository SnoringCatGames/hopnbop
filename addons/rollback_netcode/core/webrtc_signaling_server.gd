class_name WebRTCSignalingServer
extends Node
## Lightweight WebSocket server for WebRTC signaling.
##
## Runs on the game server alongside the game. Handles
## SDP/ICE exchange so clients can establish WebRTC
## DataChannel connections.
##
## Lifecycle:
## 1. start() begins listening for WebSocket connections.
## 2. Clients connect, send SDP offers, receive answers.
## 3. ICE candidates are exchanged bidirectionally.
## 4. Once the DataChannel opens, the signaling
##    WebSocket is closed.
## 5. stop() shuts down the signaling server.

## Emitted when a client completes WebRTC signaling.
## peer_connection is the configured WebRTCPeerConnection.
## peer_id is the multiplayer peer ID for the client.
signal peer_signaled(
	peer_connection: WebRTCPeerConnection,
	peer_id: int,
)

const _SIGNALING_TIMEOUT_SEC := 30.0

var _tcp_server: TCPServer
var _ws_peers: Array[WebSocketPeer] = []
var _port: int = 0
var _is_running := false

# Maps WebSocket peer index to assigned multiplayer
# peer ID. Populated from the client's offer message.
var _ws_to_peer_id: Dictionary = {}

# Maps WebSocket peer index to its
# WebRTCPeerConnection.
var _ws_to_rtc: Dictionary = {}

# Maps WebSocket peer index to its DataChannel.
var _ws_to_data_channel: Dictionary = {}

# Tracks which ws_index peers have already emitted
# the peer_signaled signal.
var _ws_signaled: Dictionary = {}

# Tracks connection start time per WebSocket peer for
# timeout detection.
var _ws_connect_time: Dictionary = {}


func start(port: int) -> void:
	_port = port
	_tcp_server = TCPServer.new()
	var result := _tcp_server.listen(port)
	if result != OK:
		Netcode.log.error(
			"WebRTC signaling server failed to"
			+ " listen on port %d: error=%d"
			% [port, result],
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return

	_is_running = true
	Netcode.log.print(
		"WebRTC signaling server started on"
		+ " port %d" % port,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func stop() -> void:
	_is_running = false

	for ws in _ws_peers:
		if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			ws.close()
	_ws_peers.clear()
	_ws_to_peer_id.clear()
	_ws_to_rtc.clear()
	_ws_to_data_channel.clear()
	_ws_signaled.clear()
	_ws_connect_time.clear()

	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null

	Netcode.log.print(
		"WebRTC signaling server stopped",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _process(_delta: float) -> void:
	if not _is_running:
		return

	# Accept new TCP connections.
	while _tcp_server.is_connection_available():
		var tcp := _tcp_server.take_connection()
		if tcp == null:
			continue
		var ws := WebSocketPeer.new()
		ws.accept_stream(tcp)
		var index := _ws_peers.size()
		_ws_peers.append(ws)
		_ws_connect_time[index] = (
			Time.get_ticks_msec())
		Netcode.log.print(
			"Signaling: new WebSocket connection"
			+ " (index %d)" % index,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)

	# Poll existing WebSocket peers.
	var to_remove: Array[int] = []
	for i in range(_ws_peers.size()):
		var ws: WebSocketPeer = _ws_peers[i]
		ws.poll()

		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			to_remove.append(i)
			continue

		if state != WebSocketPeer.STATE_OPEN:
			# Check timeout for connecting peers.
			var elapsed: float = (
				(Time.get_ticks_msec()
					- _ws_connect_time.get(i, 0))
				/ 1000.0)
			if elapsed > _SIGNALING_TIMEOUT_SEC:
				Netcode.log.warning(
					"Signaling: peer %d timed out"
					% i,
					NetworkLogger
						.CATEGORY_CONNECTIONS,
				)
				ws.close()
				to_remove.append(i)
			continue

		# Read all available messages.
		while ws.get_available_packet_count() > 0:
			var packet := ws.get_packet()
			var text := packet.get_string_from_utf8()
			_handle_message(i, ws, text)

	# Poll DataChannels and emit peer_signaled when
	# a channel opens.
	for ws_idx in _ws_to_data_channel:
		if _ws_signaled.has(ws_idx):
			continue
		var dc: WebRTCDataChannel = (
			_ws_to_data_channel[ws_idx])
		dc.poll()
		if (dc.get_ready_state()
				== WebRTCDataChannel.STATE_OPEN):
			_ws_signaled[ws_idx] = true
			var pid: int = (
				_ws_to_peer_id.get(ws_idx, 0))
			var rtc: WebRTCPeerConnection = (
				_ws_to_rtc.get(ws_idx))
			if rtc != null and pid > 0:
				Netcode.log.print(
					"Signaling: DataChannel open"
					+ " for peer_id=%d" % pid,
					NetworkLogger
						.CATEGORY_CONNECTIONS,
				)
				peer_signaled.emit(rtc, pid)
				notify_peer_connected(
					ws_idx, pid)

	# Clean up closed peers (reverse order to
	# preserve indices).
	to_remove.reverse()
	for i in to_remove:
		_cleanup_ws_peer(i)


func _handle_message(
	ws_index: int,
	ws: WebSocketPeer,
	text: String,
) -> void:
	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		Netcode.log.warning(
			"Signaling: invalid JSON from peer %d"
			% ws_index,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return

	var msg_type: String = data.get("type", "")
	match msg_type:
		"offer":
			_handle_offer(ws_index, ws, data)
		"ice":
			_handle_client_ice(ws_index, data)
		_:
			Netcode.log.warning(
				"Signaling: unknown message type"
				+ " '%s' from peer %d"
				% [msg_type, ws_index],
				NetworkLogger.CATEGORY_CONNECTIONS,
			)


func _handle_offer(
	ws_index: int,
	ws: WebSocketPeer,
	data: Dictionary,
) -> void:
	var peer_id: int = data.get("peer_id", 0)
	if peer_id <= 0:
		Netcode.log.warning(
			"Signaling: offer missing peer_id",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return

	var sdp: String = data.get("sdp", "")
	if sdp.is_empty():
		Netcode.log.warning(
			"Signaling: offer missing SDP",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return

	_ws_to_peer_id[ws_index] = peer_id

	Netcode.log.print(
		"Signaling: received offer from"
		+ " peer_id=%d (ws_index=%d)"
		% [peer_id, ws_index],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Create a WebRTCPeerConnection for this client.
	var rtc := WebRTCPeerConnection.new()
	_ws_to_rtc[ws_index] = rtc

	# Create a matching negotiated DataChannel. Must
	# use the same id and parameters as the client.
	var dc: WebRTCDataChannel = (
		rtc.create_data_channel(
			"game",
			{
				"negotiated": true,
				"id": 1,
				"maxRetransmits": 0,
				"ordered": false,
			},
		))
	_ws_to_data_channel[ws_index] = dc

	# Connect ICE candidate signal to forward
	# server-side candidates to the client.
	rtc.ice_candidate_created.connect(
		_on_server_ice_candidate.bind(ws_index))

	# Connect session description signal.
	rtc.session_description_created.connect(
		_on_session_description.bind(ws_index))

	# Set the remote description (client's offer).
	rtc.set_remote_description("offer", sdp)


func _on_session_description(
	type: String,
	sdp: String,
	ws_index: int,
) -> void:
	if not _ws_to_rtc.has(ws_index):
		return

	var rtc: WebRTCPeerConnection = (
		_ws_to_rtc[ws_index])

	if type == "answer":
		# Set local description and send answer to
		# client.
		rtc.set_local_description(type, sdp)

		var ws_idx := ws_index
		if ws_idx >= _ws_peers.size():
			return
		var ws: WebSocketPeer = _ws_peers[ws_idx]
		if (ws.get_ready_state()
				!= WebSocketPeer.STATE_OPEN):
			return

		var answer := JSON.stringify({
			"type": "answer",
			"sdp": sdp,
		})
		ws.send_text(answer)

		Netcode.log.print(
			"Signaling: sent answer to"
			+ " ws_index=%d" % ws_index,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)


func _on_server_ice_candidate(
	media: String,
	index: int,
	candidate_name: String,
	ws_index: int,
) -> void:
	if ws_index >= _ws_peers.size():
		return
	var ws: WebSocketPeer = _ws_peers[ws_index]
	if (ws.get_ready_state()
			!= WebSocketPeer.STATE_OPEN):
		return

	var msg := JSON.stringify({
		"type": "ice",
		"candidate": candidate_name,
		"mid": media,
		"index": index,
	})
	ws.send_text(msg)


func _handle_client_ice(
	ws_index: int,
	data: Dictionary,
) -> void:
	if not _ws_to_rtc.has(ws_index):
		return

	var rtc: WebRTCPeerConnection = (
		_ws_to_rtc[ws_index])
	var candidate: String = data.get("candidate", "")
	var mid: String = data.get("mid", "")
	var index: int = data.get("index", 0)

	if candidate.is_empty():
		return

	rtc.add_ice_candidate(mid, index, candidate)


## Called by NetworkConnector when a WebRTC peer
## finishes signaling and the DataChannel is ready.
## Returns the WebRTCPeerConnection for the given
## multiplayer peer ID, or null if not found.
func get_peer_connection(
	peer_id: int,
) -> WebRTCPeerConnection:
	for ws_index in _ws_to_peer_id:
		if _ws_to_peer_id[ws_index] == peer_id:
			return _ws_to_rtc.get(ws_index)
	return null


## Returns all completed WebRTCPeerConnections mapped
## by their multiplayer peer ID.
func get_all_peer_connections() -> Dictionary:
	var result := {}
	for ws_index in _ws_to_peer_id:
		var pid: int = _ws_to_peer_id[ws_index]
		if _ws_to_rtc.has(ws_index):
			result[pid] = _ws_to_rtc[ws_index]
	return result


## Notify the signaling server that a peer's
## DataChannel is open. Sends a "connected" message
## and closes the signaling WebSocket.
func notify_peer_connected(
	ws_index: int,
	peer_id: int,
) -> void:
	if ws_index >= _ws_peers.size():
		return
	var ws: WebSocketPeer = _ws_peers[ws_index]
	if (ws.get_ready_state()
			!= WebSocketPeer.STATE_OPEN):
		return

	var msg := JSON.stringify({
		"type": "connected",
		"peer_id": peer_id,
	})
	ws.send_text(msg)

	# Close signaling WebSocket after a short delay
	# to ensure the message is sent.
	_close_ws_deferred.call_deferred(ws_index)


func _close_ws_deferred(ws_index: int) -> void:
	if ws_index < _ws_peers.size():
		_ws_peers[ws_index].close()


func _cleanup_ws_peer(index: int) -> void:
	var was_signaled := _ws_signaled.has(index)
	_ws_to_peer_id.erase(index)
	_ws_to_data_channel.erase(index)
	_ws_signaled.erase(index)
	if _ws_to_rtc.has(index):
		# Only close the RTC connection if signaling
		# did not complete. Completed connections are
		# owned by the WebRTCMultiplayerPeer.
		if not was_signaled:
			var rtc: WebRTCPeerConnection = (
				_ws_to_rtc[index])
			rtc.close()
		_ws_to_rtc.erase(index)
	_ws_connect_time.erase(index)


## Parses a signaling message from JSON text.
## Returns a Dictionary with type, sdp, candidate,
## mid, index, and peer_id fields. Returns an empty
## Dictionary if parsing fails.
static func parse_message(
	text: String,
) -> Dictionary:
	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		return {}
	return data


## Serializes a signaling message to JSON text.
static func serialize_message(
	data: Dictionary,
) -> String:
	return JSON.stringify(data)
