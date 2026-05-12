class_name NotificationSocketClient
extends Node
## Long-lived Nakama realtime socket for receiving persistent and
## transient notifications. Opens on authentication (non-anonymous)
## and stays connected for the life of the session; reconnects with
## exponential backoff if dropped. Consumers connect to
## `notification_received` and filter by subject — there's no
## subscription registry to keep in sync.
##
## Stage 5.4: replaces the 3 s / 10 s polling cadence in
## PartyManager with event-driven refresh, and gives
## FriendsNotificationPoller a near-instant path for
## `party_matchmaking_start` while keeping its 10 s HTTP poll as a
## catch-up fallback. Future stages can route any other Nakama
## persistent-notification subject through the same bus.


## Fires once per notification delivered over the socket. Content is
## the parsed JSON body; an empty dict means the payload wasn't a
## JSON object (in which case consumers should ignore it).
signal notification_received(
	subject: String,
	content: Dictionary,
	notification_id: String,
)

## Fires when the socket transitions to connected (initial connect
## or successful reconnect). Consumers that maintain local state
## from persistent server state should refetch on this so they
## catch up on any events missed during the down window.
signal socket_connected

## Fires when the socket closes for any reason. The reconnect logic
## kicks in automatically afterward when start() was called and
## the auth token is valid.
signal socket_disconnected


const _RECONNECT_INITIAL_DELAY_SEC := 1.0
const _RECONNECT_MAX_DELAY_SEC := 30.0
const _RECONNECT_BACKOFF_MULTIPLIER := 2.0


var _socket: NakamaSocket = null
var _wants_connection := false
var _is_connecting := false
var _reconnect_delay_sec := _RECONNECT_INITIAL_DELAY_SEC
var _reconnect_timer: Timer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_reconnect_timer = Timer.new()
	_reconnect_timer.name = "ReconnectTimer"
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_attempt_connect)
	add_child(_reconnect_timer)

	G.auth_client.auth_completed.connect(_on_auth_completed)


## Whether the socket is currently connected to Nakama.
func is_socket_connected() -> bool:
	return (
		_socket != null
		and _socket.is_connected_to_host()
	)


## Open the socket and keep it open with reconnect on drop. Safe to
## call multiple times; no-ops if already connecting/connected.
func start() -> void:
	_wants_connection = true
	if _is_connecting:
		return
	if is_socket_connected():
		return
	_reconnect_delay_sec = _RECONNECT_INITIAL_DELAY_SEC
	_attempt_connect()


## Close the socket and stop reconnecting. Called on logout.
func stop() -> void:
	_wants_connection = false
	_reconnect_timer.stop()
	_reconnect_delay_sec = _RECONNECT_INITIAL_DELAY_SEC
	if _socket != null:
		_socket.close()
		_socket = null


# --------------------------------------------------------------
# Internals
# --------------------------------------------------------------


func _attempt_connect() -> void:
	if not _wants_connection:
		return
	if _is_connecting:
		return
	if is_socket_connected():
		return
	# Don't attempt when there's no valid token; defer until
	# _on_auth_completed fires again.
	if not G.auth_token_store.is_token_valid():
		return
	# Anonymous users don't have a Nakama JWT we can authenticate
	# the socket with. Skip silently; the socket re-evaluates on
	# the next auth_completed.
	if G.auth_token_store.is_anonymous:
		return

	var session: NakamaSession = (
		G.auth_client._build_session_from_store())
	if session == null:
		_schedule_reconnect()
		return

	_is_connecting = true
	_socket = Nakama.create_socket_from(
		G.auth_client._get_nakama_client())
	_socket.received_notification.connect(
		_on_received_notification)
	_socket.closed.connect(_on_socket_closed)
	_socket.connection_error.connect(
		_on_socket_connection_error)

	var result: NakamaAsyncResult = (
		await _socket.connect_async(session))
	_is_connecting = false

	if result.is_exception():
		var ex: NakamaException = result.get_exception()
		Netcode.log.warning(
			(
				"[NotificationSocket] connect failed: %s"
				% ex.message
			),
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		# Drop the failed socket so a future _attempt_connect
		# doesn't see is_connected_to_host()=false on a stale
		# handle and short-circuit.
		_socket = null
		_schedule_reconnect()
		return

	_reconnect_delay_sec = _RECONNECT_INITIAL_DELAY_SEC
	Netcode.log.print(
		"[NotificationSocket] connected",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	socket_connected.emit()


func _schedule_reconnect() -> void:
	if not _wants_connection:
		return
	_reconnect_timer.start(_reconnect_delay_sec)
	_reconnect_delay_sec = min(
		_reconnect_delay_sec * _RECONNECT_BACKOFF_MULTIPLIER,
		_RECONNECT_MAX_DELAY_SEC,
	)


func _on_received_notification(p_notification) -> void:
	var subject: String = str(p_notification.subject)
	var raw_id: String = str(p_notification.id)
	var content_dict: Dictionary = {}
	# Nakama wraps the notification content as a JSON string. Empty
	# string is legal (notifications without bodies); parse_string
	# returns null on empty input.
	var raw_content: String = str(p_notification.content)
	if not raw_content.is_empty():
		var parsed: Variant = JSON.parse_string(raw_content)
		if parsed is Dictionary:
			content_dict = parsed
	notification_received.emit(
		subject, content_dict, raw_id)


func _on_socket_closed() -> void:
	Netcode.log.print(
		"[NotificationSocket] closed",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	socket_disconnected.emit()
	if _wants_connection:
		_schedule_reconnect()


func _on_socket_connection_error(error) -> void:
	# _on_socket_closed typically fires too; reconnect there.
	Netcode.log.warning(
		"[NotificationSocket] connection error: %s" % error,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _on_auth_completed(
	success: bool, _error: String,
) -> void:
	if not success:
		stop()
		return
	if not G.auth_token_store.is_token_valid():
		stop()
		return
	if G.auth_token_store.is_anonymous:
		# Anonymous users don't have a Nakama JWT; the platform-
		# level features that rely on this socket (party state,
		# friend notifications) all require a non-anonymous
		# account anyway.
		stop()
		return
	start()
