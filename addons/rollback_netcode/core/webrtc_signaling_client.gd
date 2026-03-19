class_name WebRTCSignalingClient
extends Node
## Client-side WebRTC signaling via WebSocket.
##
## Connects to the game server's signaling WebSocket,
## exchanges SDP offer/answer and ICE candidates, then
## signals completion with the configured
## WebRTCPeerConnection ready for gameplay.
##
## Includes automatic retry for the Firefox DTLS bug
## in webrtc-native v1.0.9 (mbedTLS lacks ClientHello
## defragmentation).

## Emitted when signaling completes and the
## DataChannel is open.
signal completed(
	peer_connection: WebRTCPeerConnection,
)

## Emitted when signaling fails after all retries.
signal failed(error: String)

const _ATTEMPT_TIMEOUT_SEC := 5.0
const _MAX_RETRY_ATTEMPTS := 5

var _ws: WebSocketPeer
var _rtc: WebRTCPeerConnection
var _data_channel: WebRTCDataChannel
var _signaling_url := ""
var _peer_id: int = 0
var _attempt_count := 0
var _attempt_start_msec := 0
var _is_active := false
var _is_completed := false


## Begin signaling. url is the WebSocket URL to the
## server's signaling endpoint. peer_id is the
## multiplayer peer ID assigned to this client.
func start(
	url: String,
	peer_id: int = 0,
) -> void:
	_signaling_url = url
	_peer_id = peer_id
	_attempt_count = 0
	_is_completed = false
	_attempt_connect()


func stop() -> void:
	_is_active = false
	_is_completed = true
	_cleanup()


func _attempt_connect() -> void:
	_attempt_count += 1
	_is_active = true

	if _attempt_count > _MAX_RETRY_ATTEMPTS:
		_is_active = false
		Netcode.log.error(
			("WebRTC signaling failed after %d"
			+ " attempts") % _MAX_RETRY_ATTEMPTS,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		failed.emit(
			("WebRTC signaling failed after %d"
			+ " attempts") % _MAX_RETRY_ATTEMPTS)
		return

	Netcode.log.print(
		"WebRTC signaling attempt %d/%d: %s"
		% [
			_attempt_count,
			_MAX_RETRY_ATTEMPTS,
			_signaling_url,
		],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	_cleanup()

	# Create WebSocket connection to signaling
	# server.
	_ws = WebSocketPeer.new()
	var result := _ws.connect_to_url(_signaling_url)
	if result != OK:
		Netcode.log.error(
			"WebSocket connect failed: %d"
			% result,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		_retry_or_fail()
		return

	_attempt_start_msec = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not _is_active:
		return

	if _ws == null:
		return

	_ws.poll()

	var state := _ws.get_ready_state()

	# Check timeout.
	var elapsed := (
		(Time.get_ticks_msec()
			- _attempt_start_msec)
		/ 1000.0)
	if elapsed > _ATTEMPT_TIMEOUT_SEC:
		Netcode.log.warning(
			"WebRTC signaling attempt %d timed out"
			% _attempt_count,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		_retry_or_fail()
		return

	if state == WebSocketPeer.STATE_CLOSED:
		if not _is_completed:
			Netcode.log.warning(
				"Signaling WebSocket closed"
				+ " unexpectedly",
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			_retry_or_fail()
		return

	if state != WebSocketPeer.STATE_OPEN:
		return

	# WebSocket is open. If we haven't created the
	# RTC connection yet, do it now.
	if _rtc == null:
		_create_rtc_and_offer()

	# Read messages from signaling server.
	while _ws.get_available_packet_count() > 0:
		var packet := _ws.get_packet()
		var text := packet.get_string_from_utf8()
		_handle_message(text)

	# Check DataChannel state.
	if _data_channel != null:
		_data_channel.poll()
		if (_data_channel.get_ready_state()
				== WebRTCDataChannel.STATE_OPEN):
			_on_data_channel_open()


func _create_rtc_and_offer() -> void:
	_rtc = WebRTCPeerConnection.new()

	# Connect signals.
	_rtc.ice_candidate_created.connect(
		_on_local_ice_candidate)
	_rtc.session_description_created.connect(
		_on_session_description)

	# Create the DataChannel. This triggers SDP
	# offer generation.
	_data_channel = _rtc.create_data_channel(
		"game",
		{
			"negotiated": true,
			"id": 1,
			"maxRetransmits": 0,
			"ordered": false,
		},
	)

	# Create the offer.
	_rtc.create_offer()

	Netcode.log.print(
		"WebRTC: created offer",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _on_session_description(
	type: String,
	sdp: String,
) -> void:
	if type == "offer":
		_rtc.set_local_description(type, sdp)

		# Send offer to signaling server.
		var msg := JSON.stringify({
			"type": "offer",
			"sdp": sdp,
			"peer_id": _peer_id,
		})
		if (_ws != null
				and _ws.get_ready_state()
					== WebSocketPeer.STATE_OPEN):
			_ws.send_text(msg)
			Netcode.log.print(
				"WebRTC: sent offer to server",
				NetworkLogger.CATEGORY_CONNECTIONS,
			)


func _on_local_ice_candidate(
	media: String,
	index: int,
	candidate_name: String,
) -> void:
	if (_ws == null
			or _ws.get_ready_state()
				!= WebSocketPeer.STATE_OPEN):
		return

	var msg := JSON.stringify({
		"type": "ice",
		"candidate": candidate_name,
		"mid": media,
		"index": index,
	})
	_ws.send_text(msg)


func _handle_message(text: String) -> void:
	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		return

	var msg_type: String = data.get("type", "")
	match msg_type:
		"answer":
			_handle_answer(data)
		"ice":
			_handle_server_ice(data)
		"connected":
			_handle_connected(data)


func _handle_answer(data: Dictionary) -> void:
	var sdp: String = data.get("sdp", "")
	if sdp.is_empty() or _rtc == null:
		return

	_rtc.set_remote_description("answer", sdp)
	Netcode.log.print(
		"WebRTC: received answer from server",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _handle_server_ice(data: Dictionary) -> void:
	if _rtc == null:
		return

	var candidate: String = data.get("candidate", "")
	var mid: String = data.get("mid", "")
	var index: int = data.get("index", 0)

	if candidate.is_empty():
		return

	_rtc.add_ice_candidate(mid, index, candidate)


func _handle_connected(_data: Dictionary) -> void:
	Netcode.log.print(
		"WebRTC: server confirmed connection",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	# The server may send this before the
	# DataChannel is fully open on the client side.
	# The _process loop checks DataChannel state.


func _on_data_channel_open() -> void:
	if _is_completed:
		return
	_is_completed = true
	_is_active = false

	Netcode.log.print(
		"WebRTC: DataChannel open,"
		+ " signaling complete",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Close the signaling WebSocket.
	if (_ws != null
			and _ws.get_ready_state()
				!= WebSocketPeer.STATE_CLOSED):
		_ws.close()

	completed.emit(_rtc)


func _retry_or_fail() -> void:
	_cleanup()
	if _attempt_count < _MAX_RETRY_ATTEMPTS:
		_attempt_connect()
	else:
		_is_active = false
		failed.emit(
			("WebRTC signaling failed after %d"
			+ " attempts") % _MAX_RETRY_ATTEMPTS)


func _cleanup() -> void:
	if (_ws != null
			and _ws.get_ready_state()
				!= WebSocketPeer.STATE_CLOSED):
		_ws.close()
	_ws = null

	if _rtc != null and not _is_completed:
		_rtc.close()
	if not _is_completed:
		_rtc = null
		_data_channel = null
