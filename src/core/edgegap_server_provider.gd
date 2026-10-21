class_name EdgegapServerProvider
extends SessionProvider
## Server-side session validation for Edgegap deployments.
##
## The Nakama runtime allocates a fresh Edgegap deployment per
## matched lobby (see snoringcat-platform's
## `runtime/fleet_allocator.go`). At
## allocation time, the runtime injects two env vars into the
## container:
##
##   EXPECTED_PLAYER_COUNT   total players across all peers
##   EXPECTED_SESSION_IDS    comma-separated list of every
##                           session ID the runtime issued
##
## This provider parses those vars on boot and rejects any
## connecting peer whose declared session IDs aren't on the
## allowlist. Once the validated count meets the expected
## count, `all_players_connected` fires and the match starts.
##
## Replaces the `PreviewSessionProvider` stand-in that was
## auto-accepting every connection on Edgegap servers.

## Seconds to wait for any player to connect after the server
## boots. If nobody arrives, terminate to free the container.
const _SESSION_IDLE_TIMEOUT_SEC := 60.0

## Seconds to wait for late-joining players after the first
## one validates. If the rest don't arrive in time, start the
## match with whoever's present. Mirrors the GameLift provider.
const _CONNECTION_GRACE_SEC := 10.0


# Allowlist of valid session tokens as parsed from the env.
# Uses a Dictionary as a set (key=token, value=true).
var _allowed_session_ids: Dictionary = {}

# Token -> Nakama user id, parsed from EXPECTED_SESSION_TOKENS
# (SP27). The server derives each player's backend id from the
# token they present instead of trusting the id a client
# declares (H17). Empty in list-only mode (pre-SP27 runtime),
# where derivation is impossible and the declared id stands.
# Dictionary<String, String>
var _session_id_to_user_id: Dictionary = {}

# Token -> peer that currently holds the claim. A re-claim from
# a new peer transfers the claim (the connector disconnects the
# stale peer, H43); the validated count does not grow twice for
# one slot.
# Dictionary<String, int>
var _session_to_peer: Dictionary = {}

# Session IDs that have been claimed by a connecting peer. A
# given allowed ID can only be used once.
var _claimed_session_ids: Dictionary = {}

# Maps player_id <-> session_id (1:1 per player).
# Dictionary<int, String>
var _player_to_session: Dictionary = {}
# Dictionary<String, int>
var _session_to_player: Dictionary = {}

# Maps game player_id -> backend player_id and profile image
# URL, populated from each peer's declaration.
# Dictionary<int, String>
var _player_to_backend_id: Dictionary = {}
# Dictionary<int, String>
var _player_to_profile_image_url: Dictionary = {}

var _expected_player_count: int = 0
var _validated_player_count: int = 0

var _idle_timer: Timer
var _grace_timer: Timer
var _grace_active := false

# H48: when each peer's transport finished signaling (server
# clock, msec), and when this provider booted. The connection
# grace used to tick from the first validation while later
# peers were still signaling (WebRTC setup can eat most of
# the 10s window); the grace now restarts when a peer's
# signaling completes, and these stamps let a WebRTC run's
# log show the measured signaling times.
var _boot_msec := 0
# Dictionary<int, int>
var _peer_signaling_msec: Dictionary = {}


func _ready() -> void:
	_boot_msec = Time.get_ticks_msec()
	_load_allowlist_from_env()
	_start_idle_timer()
	if not multiplayer.peer_connected.is_connected(
		_on_peer_connected
	):
		multiplayer.peer_connected.connect(_on_peer_connected)


## Records a peer's signaling completion (its transport came
## up) and, once validation has begun, restarts the connection
## grace so the 10s window starts after signaling instead of
## being consumed by it (H48).
func _on_peer_connected(peer_id: int) -> void:
	var now := Time.get_ticks_msec()
	_peer_signaling_msec[peer_id] = now
	Netcode.log.print(
		(
			"[Edgegap] Peer %d signaling complete"
			+ " %dms after server boot"
		) % [peer_id, now - _boot_msec],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	if _grace_active and _validated_player_count > 0:
		_stop_grace_timer()
		_start_grace_timer()


## Posts the register_server RPC to the Nakama runtime so the
## matchmaker hook can confirm the in-container WS port is bound
## and accepting connections. Call AFTER the signaling server's
## listen() returns ok — the matchmaker hook uses the storage
## row's existence as the readiness signal that gates match_ready
## notifications, so calling this before the bind would race the
## clients in.
func register_with_runtime() -> void:
	var nakama_url := OS.get_environment("NAKAMA_URL")
	if nakama_url.is_empty():
		nakama_url = "https://nakama.snoringcat.games"
	var http_key := OS.get_environment("NAKAMA_HTTP_KEY")
	if http_key.is_empty():
		Netcode.log.warning(
			"[Edgegap] NAKAMA_HTTP_KEY not set; skipping"
			+ " register_server (matchmaker hook will time"
			+ " out waiting for server registration)",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return
	var request_id := OS.get_environment("ARBITRIUM_REQUEST_ID")
	var public_ip := OS.get_environment("ARBITRIUM_PUBLIC_IP")
	var port_str := OS.get_environment(
		"ARBITRIUM_PORT_GAME_EXTERNAL")
	if (request_id.is_empty()
			or public_ip.is_empty()
			or port_str.is_empty()):
		Netcode.log.warning(
			(
				"[Edgegap] Arbitrium env vars missing"
				+ " (request_id=%s public_ip=%s port=%s);"
				+ " skipping register_server"
			) % [request_id, public_ip, port_str],
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return

	# JSON body wrapped in a JSON string per Nakama's RPC over
	# HTTP convention.
	var body := JSON.stringify({
		"request_id": request_id,
		"server_ip": public_ip,
		"server_port": int(port_str),
	})
	var url := (
		"%s/v2/rpc/register_server?http_key=%s"
		% [
			nakama_url,
			http_key.uri_encode(),
		])
	var headers := PackedStringArray([
		"Content-Type: application/json",
	])
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(
		_on_register_server_completed.bind(req))
	var err := req.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body))
	if err != OK:
		Netcode.log.warning(
			"[Edgegap] register_server request failed to"
			+ " start: error=%d" % err,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		req.queue_free()
		return
	Netcode.log.print(
		"[Edgegap] register_server posted (request_id=%s)"
		% request_id,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _on_register_server_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	req: HTTPRequest,
) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 300:
		Netcode.log.warning(
			(
				"[Edgegap] register_server failed:"
				+ " result=%d code=%d body=%s"
			) % [
				result,
				response_code,
				body.get_string_from_utf8(),
			],
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return
	Netcode.log.print(
		"[Edgegap] register_server ok (code=%d)" % response_code,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func is_active() -> bool:
	# This provider validates against a real allowlist. Reports
	# active so peers route through real validation rather than
	# the auto-accept fallback paths in callers.
	return true


func server_set_expected_player_count(count: int) -> void:
	_expected_player_count = count
	Netcode.log.print(
		"[Edgegap] Expected player count: %d" % count,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func server_validate_player_sessions(
	peer_id: int,
	session_ids: Array,
	backend_player_id: String = "",
) -> Dictionary:
	Netcode.log.print(
		(
			"[Edgegap] Validating %d session(s) for peer %d"
			+ " (expected=%d, validated=%d)"
		) % [
			session_ids.size(),
			peer_id,
			_expected_player_count,
			_validated_player_count,
		],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# All-or-nothing: vet every declared token before the
	# connector assigns anything. A token already claimed is not
	# a rejection: the same slot may be re-claimed by a new peer
	# (the connector disconnects the stale peer, H43), and with
	# unguessable tokens (SP27) possession is the credential.
	var derived_ids: Array = []
	var seen: Dictionary = {}
	var derived_user := ""
	for i in range(session_ids.size()):
		var session_id: String = str(session_ids[i])
		if session_id.is_empty() or seen.has(session_id):
			return _reject(peer_id, session_id, "empty or duplicate")
		seen[session_id] = true
		if not _allowed_session_ids.has(session_id):
			return _reject(peer_id, session_id, "not on allowlist")
		var owner: String = str(
			_session_id_to_user_id.get(session_id, ""))
		if not owner.is_empty():
			if derived_user.is_empty():
				derived_user = owner
			elif derived_user != owner:
				return _reject(
					peer_id, session_id, "tokens for two accounts")
			derived_ids.append(owner)
		else:
			# List-only mode (pre-SP27 runtime): no owner map,
			# so the declared id stands, as before SP27.
			derived_ids.append(backend_player_id)

	# Bind the claim to its account (H17): when the runtime's
	# token map is present, a declared backend id that is not
	# the token's owner is a forgery, not a fallback.
	if (not derived_user.is_empty()
			and not backend_player_id.is_empty()
			and backend_player_id != derived_user):
		Netcode.log.warning(
			(
				"[Edgegap] Rejecting peer %d: declared backend"
				+ " id is not the session owner"
			) % peer_id,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		session_request_failed.emit(
			"Player session validation failed")
		return {"accepted": false, "backend_player_ids": []}

	return {
		"accepted": true,
		"backend_player_ids": derived_ids,
	}


func _reject(
	peer_id: int,
	session_id: String,
	reason: String,
) -> Dictionary:
	Netcode.log.warning(
		(
			"[Edgegap] Rejecting session_id %s"
			+ " (%s) for peer %d"
		) % [session_id, reason, peer_id],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	session_request_failed.emit(
		"Player session validation failed")
	return {"accepted": false, "backend_player_ids": []}


func server_commit_player_sessions(
	peer_id: int,
	player_ids: Array[int],
	session_ids: Array,
	backend_player_ids: Array,
	profile_image_url: String = "",
	_auth_display_name: String = "",
) -> void:
	for i in range(session_ids.size()):
		var player_id: int = player_ids[i]
		var session_id: String = str(session_ids[i])
		var first_claim := not _claimed_session_ids.has(session_id)
		_claimed_session_ids[session_id] = true
		_session_to_peer[session_id] = peer_id
		if first_claim:
			_on_validation_success(player_id, session_id)
		else:
			# Re-claim of the same slot: keep the maps current
			# without counting the player twice.
			_player_to_session[player_id] = session_id
			_session_to_player[session_id] = player_id
			player_session_validated.emit(player_id, session_id)

	_store_backend_ids(player_ids, backend_player_ids)
	_store_profile_image_urls(player_ids, profile_image_url)


func server_get_selected_level_id() -> StringName:
	# Edgegap runtime doesn't echo level back yet. The level
	# selected client-side stays on G.client_session and the
	# server picks its default.
	return ""


func get_backend_player_id_map() -> Dictionary:
	return _player_to_backend_id


func get_profile_image_url_map() -> Dictionary:
	return _player_to_profile_image_url


func get_anonymous_backend_ids() -> Dictionary:
	# Anonymous-player tracking flows through the matchmaker's
	# is_authenticated attribute on GameLift. Nakama doesn't
	# yet propagate that here, so report none and let the
	# friend-add UI gate via its own checks.
	return {}


func cleanup() -> void:
	_stop_idle_timer()
	_stop_grace_timer()


# --- Internals ---


func _load_allowlist_from_env() -> void:
	# SP27: the token -> user_id map is authoritative when the
	# runtime provides it; backend ids are derived from it.
	var raw_map := OS.get_environment("EXPECTED_SESSION_TOKENS")
	if not raw_map.is_empty():
		var parsed: Variant = JSON.parse_string(raw_map)
		if parsed is Dictionary:
			for token in parsed:
				var trimmed: String = str(token).strip_edges()
				if not trimmed.is_empty():
					_allowed_session_ids[trimmed] = true
					_session_id_to_user_id[trimmed] = str(
						parsed[token])
			Netcode.log.print(
				"[Edgegap] Loaded %d session token(s) with owners"
					% _allowed_session_ids.size(),
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			return
		Netcode.log.warning(
			"[Edgegap] EXPECTED_SESSION_TOKENS is not a JSON"
			+ " object; falling back to the id list",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
	var raw := OS.get_environment("EXPECTED_SESSION_IDS")
	if raw.is_empty():
		Netcode.log.warning(
			(
				"[Edgegap] EXPECTED_SESSION_IDS env var"
				+ " missing; allowlist empty (every"
				+ " connection will be rejected)"
			),
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return
	for sid in raw.split(","):
		var trimmed: String = sid.strip_edges()
		if not trimmed.is_empty():
			_allowed_session_ids[trimmed] = true
	Netcode.log.print(
		"[Edgegap] Loaded %d allowed session_id(s)"
			% _allowed_session_ids.size(),
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _on_validation_success(
	player_id: int,
	session_id: String,
) -> void:
	_player_to_session[player_id] = session_id
	_session_to_player[session_id] = player_id
	_validated_player_count += 1

	Netcode.log.print(
		(
			"[Edgegap] Player validated:"
			+ " player_id=%d session=%s (%d/%d)"
		) % [
			player_id,
			session_id,
			_validated_player_count,
			_expected_player_count,
		],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	player_session_validated.emit(player_id, session_id)

	# Start the late-joiner grace window on the first
	# validation so a stuck peer doesn't block the match
	# forever. The full count check below short-circuits this
	# in the happy path.
	if _validated_player_count == 1:
		_stop_idle_timer()
		_start_grace_timer()

	if _validated_player_count >= _expected_player_count:
		_on_all_players_ready()


func _on_all_players_ready() -> void:
	_stop_idle_timer()
	_stop_grace_timer()
	Netcode.log.print(
		"[Edgegap] All players connected and validated",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	all_players_connected.emit()


func _store_backend_ids(
	player_ids: Array[int],
	backend_player_ids: Array,
) -> void:
	# Derived ids (SP27) win per player; the single declared id
	# reaches here only as an already-derived element because the
	# connector passes validation's output through.
	for i in range(player_ids.size()):
		if i >= backend_player_ids.size():
			return
		var backend_id: String = str(backend_player_ids[i])
		if backend_id.is_empty():
			continue
		_player_to_backend_id[player_ids[i]] = backend_id


func _store_profile_image_urls(
	player_ids: Array[int],
	profile_image_url: String,
) -> void:
	if profile_image_url.is_empty():
		return
	for player_id in player_ids:
		_player_to_profile_image_url[player_id] = (
			profile_image_url)


func _start_idle_timer() -> void:
	_idle_timer = Timer.new()
	_idle_timer.one_shot = true
	_idle_timer.wait_time = _SESSION_IDLE_TIMEOUT_SEC
	_idle_timer.timeout.connect(_on_idle_timeout)
	add_child(_idle_timer)
	_idle_timer.start()


func _stop_idle_timer() -> void:
	if is_instance_valid(_idle_timer):
		_idle_timer.stop()
		_idle_timer.queue_free()
		_idle_timer = null


func _on_idle_timeout() -> void:
	Netcode.log.warning(
		(
			"[Edgegap] No players connected within %.0fs."
			+ " Terminating to free capacity."
		) % _SESSION_IDLE_TIMEOUT_SEC,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	# Tell the runtime to terminate the Edgegap deployment
	# before quitting. Without this, Edgegap auto-restarts the
	# container after exit and the deployment keeps spinning
	# (idle → quit → restart → idle → ...) until the 24h
	# max_duration cap fires.
	var request_id := OS.get_environment("ARBITRIUM_REQUEST_ID")
	if not request_id.is_empty():
		await G.match_result_reporter.cancel(
			request_id, "idle_timeout")
	get_tree().quit()


func _start_grace_timer() -> void:
	_grace_active = true
	_grace_timer = Timer.new()
	_grace_timer.one_shot = true
	_grace_timer.wait_time = _CONNECTION_GRACE_SEC
	_grace_timer.timeout.connect(_on_grace_timeout)
	add_child(_grace_timer)
	_grace_timer.start()
	Netcode.log.print(
		"[Edgegap] Connection grace period: %.0fs"
			% _CONNECTION_GRACE_SEC,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _stop_grace_timer() -> void:
	_grace_active = false
	if is_instance_valid(_grace_timer):
		_grace_timer.stop()
		_grace_timer.queue_free()
		_grace_timer = null


func _on_grace_timeout() -> void:
	if _validated_player_count >= _expected_player_count:
		return

	# Count distinct peers behind the validated players. A
	# single-peer match isn't really a match; bail rather
	# than start a 1-player game.
	var unique_peers := {}
	for player_id in _player_to_session:
		var peer_id: int = (
			Netcode.connector
				.get_peer_id_from_player_id(player_id))
		if peer_id > 0:
			unique_peers[peer_id] = true

	if unique_peers.size() <= 1:
		Netcode.log.warning(
			(
				"[Edgegap] Grace expired with only %d"
				+ " peer(s); cancelling match"
			) % unique_peers.size(),
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		Netcode.connector.server_notify_shutdown()
		(Netcode.connector
			.server_close_multiplayer_session
			.call_deferred())
		# Same rationale as _on_idle_timeout: tell the runtime
		# to Stop the Edgegap deployment before exit so it
		# doesn't auto-restart-cycle until max_duration.
		var request_id := OS.get_environment(
			"ARBITRIUM_REQUEST_ID")
		if not request_id.is_empty():
			await G.match_result_reporter.cancel(
				request_id, "grace_only_one_peer")
		get_tree().quit.call_deferred()
		return

	Netcode.log.warning(
		(
			"[Edgegap] Grace expired: %d/%d players"
			+ " (%d peers); starting with present"
			+ " players"
		) % [
			_validated_player_count,
			_expected_player_count,
			unique_peers.size(),
		],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	_on_all_players_ready()


func _exit_tree() -> void:
	cleanup()
