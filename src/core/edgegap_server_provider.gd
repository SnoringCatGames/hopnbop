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


# Allowlist of valid session IDs as parsed from
# EXPECTED_SESSION_IDS env var. Uses a Dictionary as a set
# (key=session_id, value=true).
var _allowed_session_ids: Dictionary = {}

# Session IDs that have been claimed by a connecting peer. A
# given allowed ID can only be used once.
var _claimed_session_ids: Dictionary = {}

# Maps player_id <-> session_id (1:1 per player).
# Dictionary<int, String>
var _player_to_session: Dictionary = {}
# Dictionary<String, int>
var _session_to_player: Dictionary = {}

# Maps game player_id -> backend player_id, profile image URL,
# and display name, populated from each peer's declaration.
# Dictionary<int, String>
var _player_to_backend_id: Dictionary = {}
# Dictionary<int, String>
var _player_to_profile_image_url: Dictionary = {}
# Dictionary<int, String>
var _player_to_display_name: Dictionary = {}

var _expected_player_count: int = 0
var _validated_player_count: int = 0

var _idle_timer: Timer
var _grace_timer: Timer


func _ready() -> void:
	_load_allowlist_from_env()
	_start_idle_timer()


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
	player_ids: Array[int],
	session_ids: Array,
	backend_player_id: String = "",
	profile_image_url: String = "",
	auth_display_name: String = "",
) -> void:
	var player_count := session_ids.size()

	Netcode.log.print(
		(
			"[Edgegap] Validating %d session(s) for peer %d"
			+ " (expected=%d, validated=%d)"
		) % [
			player_count,
			peer_id,
			_expected_player_count,
			_validated_player_count,
		],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# All-or-nothing: validate every declared ID before
	# committing any. Half-accepted peers leave _claimed_*
	# inconsistent and confuse the validated_count.
	var resolved_ids: Array[String] = []
	resolved_ids.resize(player_count)
	for i in range(player_count):
		if i >= session_ids.size():
			Netcode.log.warning(
				(
					"[Edgegap] Missing session ID for"
					+ " player %d (peer %d)"
				) % [player_ids[i], peer_id],
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			session_request_failed.emit(
				"Player session validation failed")
			return

		var session_id: String = str(session_ids[i])
		if not _allowed_session_ids.has(session_id):
			Netcode.log.warning(
				(
					"[Edgegap] Rejecting session_id %s"
					+ " (not on allowlist) for peer %d"
				) % [session_id, peer_id],
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			session_request_failed.emit(
				"Player session validation failed")
			return
		if _claimed_session_ids.has(session_id):
			Netcode.log.warning(
				(
					"[Edgegap] Rejecting session_id %s"
					+ " (already claimed) for peer %d"
				) % [session_id, peer_id],
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			session_request_failed.emit(
				"Player session validation failed")
			return
		resolved_ids[i] = session_id

	# All IDs valid. Commit and notify.
	for i in range(player_count):
		var player_id: int = player_ids[i]
		var session_id: String = resolved_ids[i]
		_claimed_session_ids[session_id] = true
		_on_validation_success(player_id, session_id)

	_store_backend_ids(player_ids, backend_player_id)
	_store_profile_image_urls(player_ids, profile_image_url)
	_store_display_names(player_ids, auth_display_name)


func server_get_selected_level_id() -> StringName:
	# Edgegap runtime doesn't echo level back yet. The level
	# selected client-side stays on G.client_session and the
	# server picks its default.
	return ""


func get_backend_player_id_map() -> Dictionary:
	return _player_to_backend_id


func get_profile_image_url_map() -> Dictionary:
	return _player_to_profile_image_url


func get_display_name_map() -> Dictionary:
	return _player_to_display_name


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
	backend_player_id: String,
) -> void:
	if backend_player_id.is_empty():
		return
	for player_id in player_ids:
		_player_to_backend_id[player_id] = (
			backend_player_id)


func _store_profile_image_urls(
	player_ids: Array[int],
	profile_image_url: String,
) -> void:
	if profile_image_url.is_empty():
		return
	for player_id in player_ids:
		_player_to_profile_image_url[player_id] = (
			profile_image_url)


func _store_display_names(
	player_ids: Array[int],
	auth_display_name: String,
) -> void:
	if auth_display_name.is_empty():
		return
	for player_id in player_ids:
		_player_to_display_name[player_id] = (
			auth_display_name)


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
	get_tree().quit()


func _start_grace_timer() -> void:
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
