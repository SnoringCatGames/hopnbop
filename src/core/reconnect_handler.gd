class_name ReconnectHandler
extends Node
## Drives the client-side reconnect loop during the 30s
## server-side grace window (Stage 7.10 + 7.10b).
##
## Captures the latest match-ready connection params
## (server_ip, server_port, signaling_url, session_ids) so a
## subsequent unexpected disconnect can retry
## `Netcode.connector.client_connect_to_server(...)` with the
## same arguments. The framework's session_id -> player_id
## mapping (added in 7.10 to NetworkConnector) ensures the
## reconnecting client's PlayerState slot + score survive
## the disconnect.
##
## Supports all three transports (ENet, WebSocket, WebRTC)
## as of 7.10b. The NetworkConnector's transport-specific
## re-dial paths handle their own setup (WebRTC re-runs
## signaling, WebSocket re-handshakes TLS). The retry
## interval is shared across transports; WebRTC reconnects
## may use most of a 5s window on the signaling exchange
## while ENet redials in milliseconds.

## Emitted when a reconnect attempt cycle begins (i.e., an
## unexpected disconnect arrived during an active match and
## we have valid connection params to retry).
signal reconnect_started(grace_sec: float)

## Emitted once per retry attempt so UI can update the
## "Reconnecting (attempt N/M, Xs remaining)..." overlay.
signal reconnect_attempt(
	attempt: int, max_attempts: int, sec_remaining: float)

## Emitted when the client successfully reconnects within
## the grace window.
signal reconnect_succeeded

## Emitted when every retry within the grace window has
## failed. game_panel falls through to the normal
## exit-match path.
signal reconnect_failed(reason: String)


## Grace window in seconds. Matches the server-side
## MatchStateSynchronizer.RECONNECT_GRACE_SEC; mismatches
## would either give up before the server forgets us
## (false-negative) or keep retrying past server-side
## cleanup (false-positive but harmless).
const _GRACE_SEC: float = 30.0

## Time between retry attempts. With a 30s window and a
## 5s interval, we get up to 6 attempts.
const _RETRY_INTERVAL_SEC: float = 5.0


## Latest captured connection params. Populated from
## `game_session_manager.session_ids_received`. Empty
## until the first match starts.
var _server_ip: String = ""
var _server_port: int = 0
var _signaling_url: String = ""
var _transport_type: int = -1

var _is_reconnecting: bool = false
var _elapsed_sec: float = 0.0
var _attempt: int = 0

var _retry_timer: Timer
var _tick_timer: Timer


func _ready() -> void:
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.wait_time = _RETRY_INTERVAL_SEC
	_retry_timer.timeout.connect(_on_retry_due)
	add_child(_retry_timer)

	_tick_timer = Timer.new()
	_tick_timer.one_shot = false
	_tick_timer.wait_time = 0.5
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)


## Record the connection params from the latest match-ready
## fan-out. Called by game_session_manager when it receives
## session_ids_received.
func capture_match_params(
	server_ip: String,
	server_port: int,
	signaling_url: String,
	transport_type: int,
) -> void:
	_server_ip = server_ip
	_server_port = server_port
	_signaling_url = signaling_url
	_transport_type = transport_type


## Drop captured params (e.g., on match end). Stops any
## in-flight reconnect attempts too.
func clear() -> void:
	stop()
	_server_ip = ""
	_server_port = 0
	_signaling_url = ""
	_transport_type = -1


func is_reconnecting() -> bool:
	return _is_reconnecting


## Can we usefully retry? True iff we have valid match
## params. All three transports (ENet, WebSocket, WebRTC)
## route through the same `client_connect_to_server` path
## which handles their respective re-dial mechanics.
func can_attempt_reconnect() -> bool:
	if _server_ip.is_empty() or _server_port <= 0:
		return false
	return true


## Kick off the reconnect loop. Called by game_panel from
## `_on_connection_lost` when the disconnect is
## unexpected, the match is active, and
## can_attempt_reconnect() returned true.
func start() -> void:
	if _is_reconnecting:
		return
	_is_reconnecting = true
	_elapsed_sec = 0.0
	_attempt = 0
	reconnect_started.emit(_GRACE_SEC)
	_tick_timer.start()
	# Try immediately, then retry on a timer.
	_attempt_reconnect()


## Stop any in-flight reconnect. Called on successful
## reconnect or on giving-up.
func stop() -> void:
	if not _is_reconnecting:
		return
	_is_reconnecting = false
	_retry_timer.stop()
	_tick_timer.stop()


## Notification from game_panel: the client successfully
## reconnected (saw the `connected` signal again while we
## were retrying). Closes the loop.
func notify_reconnected() -> void:
	if not _is_reconnecting:
		return
	stop()
	reconnect_succeeded.emit()


func _on_tick() -> void:
	if not _is_reconnecting:
		return
	_elapsed_sec += _tick_timer.wait_time
	if _elapsed_sec >= _GRACE_SEC:
		_give_up("grace_window_expired")
		return
	reconnect_attempt.emit(
		_attempt,
		int(_GRACE_SEC / _RETRY_INTERVAL_SEC),
		_GRACE_SEC - _elapsed_sec,
	)


func _on_retry_due() -> void:
	if not _is_reconnecting:
		return
	_attempt_reconnect()


func _attempt_reconnect() -> void:
	_attempt += 1
	Netcode.print(
		"Reconnect attempt %d (elapsed=%.1fs)"
		% [_attempt, _elapsed_sec],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	# Re-dial. On success the framework will emit
	# `connected`; game_panel routes that through
	# notify_reconnected. On failure the framework will
	# emit `disconnected` again with CONNECTION_FAILED,
	# which game_panel will route back here to schedule
	# another retry via the timer.
	Netcode.connector.client_connect_to_server(
		_server_ip, _server_port, _signaling_url)
	_retry_timer.start()


func _give_up(reason: String) -> void:
	stop()
	reconnect_failed.emit(reason)
