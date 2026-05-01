class_name NakamaMatchmakerClient
extends SessionProvider
## Client-side matchmaker that drives the Snoring Cat platform
## stack: opens a Nakama socket, calls add_matchmaker_async, and
## waits for the runtime's "match_ready" notification to arrive
## with Edgegap connection info.
##
## Replaces the legacy GameLiftClient. Server-side allocation
## happens in the Nakama runtime module (fleet_allocator.go) on
## the MatchmakerMatched hook.

const _MATCHMAKER_QUERY := "*"
const _MIN_COUNT := 2
const _MAX_COUNT := 4
const _MATCH_TIMEOUT_SEC := 120.0
const _MATCH_READY_SUBJECT := "match_ready"
const _PROGRESS_TICK_SEC := 1.0

var _socket: NakamaSocket = null
var _ticket: String = ""
var _is_searching := false
var _elapsed_timer: Timer = null
var _elapsed_sec := 0.0

# When non-empty, the matchmaker socket authenticates with a
# per-instance Nakama identity instead of the shared
# auth_token_store. Used in preview mode to give each editor
# preview slot a distinct uid so the matchmaker pool can pair
# them. Empty otherwise.
var _preview_device_id := ""
# Cached Nakama user_id from the per-instance auth call. Used
# as the session_id slot in match_ready emissions when we're
# running with a preview identity.
var _preview_user_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_elapsed_timer = Timer.new()
	_elapsed_timer.wait_time = _PROGRESS_TICK_SEC
	_elapsed_timer.one_shot = false
	_elapsed_timer.timeout.connect(_on_elapsed_tick)
	add_child(_elapsed_timer)


func is_active() -> bool:
	return true


func client_request_session_ids(
	player_count: int,
	session_prefs: Dictionary = {},
) -> void:
	if _is_searching:
		Netcode.log.warning(
			"[NakamaMatchmaker] Already searching",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return

	# Resolve the Nakama session for the socket. Two paths:
	#   - Preview multi-client (instance > 0): mint a fresh
	#     per-instance device identity so each preview slot
	#     looks like a distinct user to Nakama. Without this
	#     all preview clients share auth_token_store under a
	#     single user:// directory and the matchmaker pool
	#     sees one user holding multiple tickets, never
	#     reaching min_count.
	#   - Production / preview slot 0: use the persisted
	#     auth_token_store session (and obtain a guest JWT if
	#     anonymous).
	var session: NakamaSession = (
		await _resolve_socket_session())
	if session == null:
		# _resolve_socket_session emits the failure already.
		return

	# Open the realtime socket if it isn't already.
	if _socket == null or not _socket.is_connected_to_host():
		_socket = Nakama.create_socket_from(
			G.auth_client._get_nakama_client())
		_socket.received_matchmaker_matched.connect(
			_on_matchmaker_matched)
		_socket.received_notification.connect(
			_on_notification)
		_socket.closed.connect(_on_socket_closed)
		_socket.connection_error.connect(
			_on_socket_connection_error)
		var connect_result: NakamaAsyncResult = (
			await _socket.connect_async(session))
		if connect_result.is_exception():
			var connect_ex: NakamaException = (
				connect_result.get_exception())
			_socket = null
			session_request_failed.emit(
				"Nakama socket connect failed: %s"
				% connect_ex.message)
			return

	# Record this client's public IP server-side before joining
	# the pool. The runtime's MatchmakerMatched hook reads the
	# recorded IPs and feeds them to Edgegap as `ip_list` for
	# region selection. Best-effort: if the call fails the
	# runtime falls back to a fixed geography, so we proceed
	# either way.
	await _record_client_ip()

	var query := _build_query(session_prefs)
	var string_props := _build_string_props(
		player_count, session_prefs)
	var numeric_props := _build_numeric_props(
		player_count, session_prefs)

	Netcode.log.print(
		(
			"[NakamaMatchmaker] Joining matchmaker"
			+ " query=%s min=%d max=%d"
		) % [query, _MIN_COUNT, _MAX_COUNT],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	var ticket_result: NakamaRTAPI.MatchmakerTicket = (
		await _socket.add_matchmaker_async(
			query,
			_MIN_COUNT,
			_MAX_COUNT,
			string_props,
			numeric_props,
		))
	if ticket_result.is_exception():
		var ticket_ex: NakamaException = (
			ticket_result.get_exception())
		session_request_failed.emit(
			"Matchmaker add failed: %s" % ticket_ex.message)
		return

	_ticket = ticket_result.ticket
	_is_searching = true
	_elapsed_sec = 0.0
	_elapsed_timer.start()

	Netcode.log.print(
		"[NakamaMatchmaker] Ticket: %s" % _ticket,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	matchmaking_progress_updated.emit(
		"queued", 0.0, -1.0)


func clear_session() -> void:
	if not _is_searching:
		return
	_is_searching = false
	_elapsed_timer.stop()
	if _socket != null and not _ticket.is_empty():
		_socket.remove_matchmaker_async(_ticket)
	_ticket = ""


func cleanup() -> void:
	clear_session()
	if _socket != null:
		_socket.close()
		_socket = null


# --------------------------------------------------------------
# Internals
# --------------------------------------------------------------


func _record_client_ip() -> void:
	# Calls the runtime's record_client_ip RPC over the open
	# socket. The runtime reads our public IP from
	# RUNTIME_CTX_CLIENT_IP and writes it to storage under our
	# user_id; the matchmaker hook reads it back when pairing.
	# Failures here are non-fatal — the runtime falls back to a
	# default geography when no IPs are recorded.
	if _socket == null or not _socket.is_connected_to_host():
		return
	var result: NakamaAPI.ApiRpc = (
		await _socket.rpc_async("record_client_ip", "{}"))
	if result.is_exception():
		var ex: NakamaException = result.get_exception()
		Netcode.log.warning(
			"[NakamaMatchmaker] record_client_ip failed: %s"
			% ex.message,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)


func _resolve_socket_session() -> NakamaSession:
	if Netcode.is_preview and Netcode.preview_client_number > 0:
		return await _authenticate_preview_instance()

	var store := G.auth_token_store
	if store.is_anonymous and not store.is_token_valid():
		G.auth_client.get_guest_jwt()
		var result: Array = (
			await G.auth_client.guest_jwt_obtained)
		var success: bool = result[0]
		var error: String = result[1]
		if not success:
			session_request_failed.emit(
				"Failed to get session token: " + error)
			return null

	var session: NakamaSession = (
		G.auth_client._build_session_from_store())
	if session == null:
		session_request_failed.emit("Not authenticated")
	return session


func _authenticate_preview_instance() -> NakamaSession:
	# Stable per (machine, preview slot) so re-runs reuse the
	# same Nakama account and don't sprawl test users across
	# Nakama. Distinct between preview slots and between
	# machines.
	if _preview_device_id.is_empty():
		var base := OS.get_unique_id()
		if base.is_empty():
			base = "preview"
		_preview_device_id = "preview_%s_C%d" % [
			base, Netcode.preview_client_number]

	var client := G.auth_client._get_nakama_client()
	var session: NakamaSession = (
		await client.authenticate_device_async(
			_preview_device_id))
	if session.is_exception():
		var ex: NakamaException = session.get_exception()
		session_request_failed.emit(
			"Preview matchmaker auth failed: %s"
			% ex.message)
		return null

	_preview_user_id = session.user_id
	Netcode.log.print(
		(
			"[NakamaMatchmaker] Preview C%d device_id=%s"
			+ " uid=%s"
		) % [
			Netcode.preview_client_number,
			_preview_device_id,
			_preview_user_id,
		],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	return session


func _build_query(_session_prefs: Dictionary) -> String:
	# Wide-open FFA query for now. Per-level / per-region
	# matchmaking can refine this once the runtime echoes the
	# selected level back through the match_ready payload.
	return _MATCHMAKER_QUERY


func _build_string_props(
	player_count: int,
	session_prefs: Dictionary,
) -> Dictionary:
	# `client_ip` is consumed by fleet_allocator.go to hint
	# Edgegap region selection; the runtime reads it off
	# entry.GetProperties() and falls back gracefully when
	# absent.
	var props := {
		"platform": (
			"web" if OS.has_feature("web") else "native"),
		"player_count": str(player_count),
	}
	if session_prefs.has("selected_level_id"):
		props["level_id"] = str(
			session_prefs["selected_level_id"])
	return props


func _build_numeric_props(
	_player_count: int,
	_session_prefs: Dictionary,
) -> Dictionary:
	# Reserved for rating-based matchmaking later.
	return {}


func _on_matchmaker_matched(matched) -> void:
	Netcode.log.print(
		(
			"[NakamaMatchmaker] Matched match_id=%s"
			+ " users=%d"
		) % [matched.match_id, matched.users.size()],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	matchmaking_progress_updated.emit(
		"placing", _elapsed_sec, -1.0)


func _on_notification(p_notification) -> void:
	if p_notification.subject != _MATCH_READY_SUBJECT:
		return
	if not _is_searching:
		# Stale notification arriving after we already
		# cancelled or moved on.
		return
	_is_searching = false
	_elapsed_timer.stop()

	# p_notification.content is a JSON string the runtime
	# built from `map[string]any{"connection": <json>}`. The
	# inner `connection` value was JSON-stringified before
	# wrapping, so we have to parse twice.
	var outer: Variant = JSON.parse_string(
		p_notification.content)
	if not (outer is Dictionary):
		session_request_failed.emit(
			"Invalid match_ready payload (outer)")
		return
	var conn_raw: String = str(
		outer.get("connection", ""))
	var conn: Variant = JSON.parse_string(conn_raw)
	if not (conn is Dictionary):
		session_request_failed.emit(
			"Invalid match_ready payload (connection)")
		return

	var server_ip: String = str(conn.get("server_ip", ""))
	var server_fqdn: String = str(
		conn.get("server_fqdn", ""))
	var ports_dict: Variant = conn.get("ports", {})
	if server_ip.is_empty() and server_fqdn.is_empty():
		session_request_failed.emit(
			"match_ready missing server address")
		return

	# Prefer FQDN over raw IP (TLS cert matching for WSS).
	var server_address := (
		server_fqdn
		if not server_fqdn.is_empty()
		else server_ip)

	var server_port := _pick_port(ports_dict)
	if server_port <= 0:
		session_request_failed.emit(
			"match_ready missing usable port")
		return

	# Use the Nakama user_id as the session id slot. The game
	# server validates the player by their Nakama JWT, not by
	# this id; it just keeps GameSessionManager's existing
	# slot-tracking flow intact. Prefer the preview-instance
	# uid when running per-slot identity so the slot tracker
	# matches the user the runtime actually notified.
	var session_ids: Array
	if not _preview_user_id.is_empty():
		session_ids = [_preview_user_id]
	else:
		session_ids = [G.auth_token_store.player_id]

	# Level was chosen client-side and stored on
	# G.client_session before matchmaking began. The runtime
	# doesn't echo it yet, so leave it empty here and let the
	# existing local copy stand.
	var level_id := ""

	Netcode.log.print(
		(
			"[NakamaMatchmaker] match_ready %s:%d"
			+ " (level=%s)"
		) % [server_address, server_port, level_id],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	session_ids_received.emit(
		session_ids,
		server_address,
		server_port,
		level_id,
	)


func _pick_port(ports: Variant) -> int:
	# Edgegap status response shape:
	#   {"<name>": {"external": int, "internal": int,
	#               "protocol": "UDP"|"TCP"}, ...}
	# Pick the first UDP port (typical for ENet); fall back
	# to whatever's there if none are UDP.
	if not (ports is Dictionary):
		return 0
	var fallback := 0
	for key in ports.keys():
		var entry: Variant = ports[key]
		if not (entry is Dictionary):
			continue
		var ext: int = int(entry.get("external", 0))
		if ext <= 0:
			continue
		if fallback == 0:
			fallback = ext
		var protocol: String = str(
			entry.get("protocol", "")).to_upper()
		if protocol == "UDP":
			return ext
	return fallback


func _on_elapsed_tick() -> void:
	_elapsed_sec += _PROGRESS_TICK_SEC
	if _elapsed_sec > _MATCH_TIMEOUT_SEC:
		clear_session()
		session_request_failed.emit(
			"Matchmaking timed out after %.0f seconds"
			% _MATCH_TIMEOUT_SEC)
		return
	matchmaking_progress_updated.emit(
		"searching", _elapsed_sec, -1.0)


func _on_socket_closed() -> void:
	Netcode.log.print(
		"[NakamaMatchmaker] Socket closed",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _on_socket_connection_error(error) -> void:
	Netcode.log.warning(
		"[NakamaMatchmaker] Socket error: %s" % error,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	if _is_searching:
		_is_searching = false
		_elapsed_timer.stop()
		session_request_failed.emit(
			"Matchmaker socket disconnected")
