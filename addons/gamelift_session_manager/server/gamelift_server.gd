class_name GameLiftServerProvider
extends SessionProvider
## Server-side GameLift session validation and lifecycle management.
##
## Handles AWS GameLift Server SDK integration including:
## - SDK initialization (managed and Anywhere fleets)
## - Player session validation
## - Process lifecycle callbacks

## Seconds to wait for players to connect after a
## game session starts. If no players arrive in
## time, the server terminates to free capacity.
const _SESSION_IDLE_TIMEOUT_SEC := 60.0

## Seconds to wait for remaining players after the
## first player validates. If not all expected
## players arrive in time, the match starts with
## whoever is present.
const _CONNECTION_GRACE_SEC := 10.0


## GameLift configuration.
var config: Dictionary

var _gamelift = null # GameLiftServer when extension loaded.
var _game_session = null # GameLiftGameSession when active.
var _is_initialized := false
var _is_process_ready := false

# Maps player_id <-> player_session_id (1:1 per player).
# Dictionary<int, String>
var _player_to_session: Dictionary = {}
# Dictionary<String, int>
var _session_to_player: Dictionary = {}

# Maps game player_id -> backend player_id (for match
# result reporting). Built from client-declared IDs.
# Dictionary<int, String>
var _player_to_backend_id: Dictionary = {}

# Maps game player_id -> profile image URL. Built from
# client-declared data during session validation.
# Dictionary<int, String>
var _player_to_profile_image_url: Dictionary = {}

# Backend player IDs identified as anonymous from
# matchmaker data (is_authenticated == 0).
# Dictionary<String, bool>
var _anonymous_backend_ids: Dictionary = {}

# Expected player count from matchmaking (total players across all peers).
var _expected_player_count: int = 0
var _validated_player_count: int = 0

# Selected level from game session properties.
var _selected_level_id: StringName = ""

var _idle_timer: Timer
var _grace_timer: Timer


func _init(p_config: Dictionary = {}) -> void:
	config = p_config


func _ready() -> void:
	_initialize_sdk()


func is_active() -> bool:
	return _is_initialized and _gamelift != null


func server_set_expected_player_count(count: int) -> void:
	_expected_player_count = count
	Netcode.log.print(
		"Expected player count: %d" % count,
		NetworkLogger.CATEGORY_CONNECTIONS
	)


func server_get_selected_level_id() -> StringName:
	return _selected_level_id


func server_validate_player_sessions(
	peer_id: int,
	player_ids: Array[int],
	session_ids: Array,
	backend_player_id: String = "",
	profile_image_url: String = "",
) -> void:
	var player_count := session_ids.size()

	Netcode.log.print(
		("Validating %d session(s) for"
		+ " peer %d (is_active=%s,"
		+ " expected=%d, validated=%d)")
		% [
			player_count,
			peer_id,
			is_active(),
			_expected_player_count,
			_validated_player_count,
		],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	if not is_active():
		# Preview mode: auto-accept without validation.
		Netcode.log.print(
			("Preview: Auto-accepting %d player(s)"
			+" for peer %d")
			% [player_count, peer_id],
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		for i in range(player_count):
			var player_id: int = player_ids[i]
			var session_id: String = (
				str(session_ids[i])
				if i < session_ids.size()
				else ""
			)
			_on_validation_success(
				player_id, session_id)
		_store_backend_ids(
			player_ids, backend_player_id)
		_store_profile_image_urls(
			player_ids, profile_image_url)
		return

	# Validate all session IDs for this peer.
	var all_valid := true
	for i in range(player_count):
		if i >= session_ids.size():
			Netcode.log.warning(
				"Missing session ID for player %d"
				% player_ids[i],
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			all_valid = false
			break

		var session_id: String = str(session_ids[i])
		var outcome = (
			_gamelift.accept_player_session(
				session_id))

		if outcome.is_success():
			Netcode.log.print(
				("Player session validated:"
				+" %s (peer %d, index %d)")
				% [session_id, peer_id, i],
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
		else:
			Netcode.log.warning(
				("Player session validation"
				+" failed for %s: %s")
				% [session_id,
					outcome.get_error_message()],
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			all_valid = false
			break

	if not all_valid:
		session_request_failed.emit(
			"Player session validation failed")
		return

	# All sessions valid. Record mappings and emit
	# signals.
	for i in range(player_count):
		var player_id: int = player_ids[i]
		var session_id: String = str(session_ids[i])
		_on_validation_success(
			player_id, session_id)
	_store_backend_ids(
		player_ids, backend_player_id)
	_store_profile_image_urls(
		player_ids, profile_image_url)


## Returns the mapping from in-game int player_id
## to backend string player_id. Built from client
## declarations during session validation.
func get_backend_player_id_map() -> Dictionary:
	return _player_to_backend_id


## Returns the mapping from in-game int player_id
## to profile image URL string.
func get_profile_image_url_map() -> Dictionary:
	return _player_to_profile_image_url


## Returns backend player IDs identified as
## anonymous from matchmaker data.
func get_anonymous_backend_ids() -> Dictionary:
	return _anonymous_backend_ids


## Stores backend player ID for each game player.
## For couch co-op, multiple game players from the
## same client share the same backend_player_id.
func _store_backend_ids(
	player_ids: Array[int],
	backend_player_id: String,
) -> void:
	if backend_player_id.is_empty():
		return
	for i in range(player_ids.size()):
		_player_to_backend_id[player_ids[i]] = (
			backend_player_id)
		Netcode.log.print(
			"Backend ID: player %d -> %s"
			% [player_ids[i], backend_player_id],
			NetworkLogger.CATEGORY_CONNECTIONS,
		)


## Stores profile image URL for each game player.
## For couch co-op, multiple game players from the
## same client share the same profile image URL.
func _store_profile_image_urls(
	player_ids: Array[int],
	profile_image_url: String,
) -> void:
	if profile_image_url.is_empty():
		return
	for i in range(player_ids.size()):
		_player_to_profile_image_url[
			player_ids[i]] = profile_image_url


func cleanup() -> void:
	if _gamelift and _is_initialized:
		_gamelift.process_ending()
		_gamelift.destroy()
		_is_initialized = false


func _on_validation_success(player_id: int, session_id: String) -> void:
	_player_to_session[player_id] = session_id
	_session_to_player[session_id] = player_id
	_validated_player_count += 1

	Netcode.log.print(
		"Player validated: player_id=%d, session=%s (%d/%d)" % [
			player_id,
			session_id,
			_validated_player_count,
			_expected_player_count
		],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	player_session_validated.emit(player_id, session_id)

	# Start grace timer on first validation so late
	# joiners do not block the match indefinitely.
	if _validated_player_count == 1:
		_start_grace_timer()

	# Check if all matched players connected.
	if _validated_player_count >= _expected_player_count:
		_on_all_players_ready()


func _on_all_players_ready() -> void:
	_stop_idle_timer()
	_stop_grace_timer()
	Netcode.log.print(
		"All players connected and validated",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	all_players_connected.emit()


func _start_idle_timer() -> void:
	_idle_timer = Timer.new()
	_idle_timer.one_shot = true
	_idle_timer.wait_time = _SESSION_IDLE_TIMEOUT_SEC
	_idle_timer.timeout.connect(
		_on_idle_timeout)
	add_child(_idle_timer)
	_idle_timer.start()
	Netcode.log.print(
		"Idle timeout: %.0fs"
		% _SESSION_IDLE_TIMEOUT_SEC,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _stop_idle_timer() -> void:
	if is_instance_valid(_idle_timer):
		_idle_timer.stop()
		_idle_timer.queue_free()
		_idle_timer = null


func _on_idle_timeout() -> void:
	Netcode.log.warning(
		("No players connected within %.0fs."
		+" Terminating to free capacity.")
		% _SESSION_IDLE_TIMEOUT_SEC,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	_end_process()


func _start_grace_timer() -> void:
	_grace_timer = Timer.new()
	_grace_timer.one_shot = true
	_grace_timer.wait_time = _CONNECTION_GRACE_SEC
	_grace_timer.timeout.connect(
		_on_grace_timeout)
	add_child(_grace_timer)
	_grace_timer.start()
	Netcode.log.print(
		"Connection grace period: %.0fs"
		% _CONNECTION_GRACE_SEC,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


func _stop_grace_timer() -> void:
	if is_instance_valid(_grace_timer):
		_grace_timer.stop()
		_grace_timer.queue_free()
		_grace_timer = null


func _on_grace_timeout() -> void:
	if (
		_validated_player_count
			>= _expected_player_count
	):
		return

	var unique_peers := {}
	for player_id in _player_to_session:
		var peer_id: int = (
			Netcode.connector
				.get_peer_id_from_player_id(
					player_id))
		if peer_id > 0:
			unique_peers[peer_id] = true

	if unique_peers.size() <= 1:
		Netcode.log.warning(
			("Grace period expired: only %d peer(s)."
			+ " Cancelling match.")
			% unique_peers.size(),
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		# Notify clients before terminating so they
		# see SERVER_SHUTDOWN instead of
		# CONNECTION_LOST.
		Netcode.connector.server_notify_shutdown()
		_end_process.call_deferred()
		return

	Netcode.log.warning(
		("Grace period expired: %d/%d players"
		+ " (%d peers). Starting with present"
		+ " players.")
		% [
			_validated_player_count,
			_expected_player_count,
			unique_peers.size(),
		],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	_on_all_players_ready()


# =============================================================================
# SDK Initialization
# =============================================================================


func _initialize_sdk() -> void:
	# Try to load GameLift extension.
	if not ClassDB.class_exists("GameLiftServer"):
		Netcode.log.warning(
			"GameLiftServer class not found (extension not loaded)",
			NetworkLogger.CATEGORY_CONNECTIONS
		)
		return

	_gamelift = ClassDB.instantiate("GameLiftServer")
	add_child(_gamelift)

	# Connect signals with CONNECT_DEFERRED so
	# callbacks run on the main thread. The
	# GameLift GDExtension fires these from a
	# background thread, and GDScript is not
	# thread-safe.
	if _gamelift.has_signal("game_session_started"):
		_gamelift.game_session_started.connect(
			_on_game_session_started,
			CONNECT_DEFERRED,
		)
	if _gamelift.has_signal(
			"process_terminate_requested"):
		_gamelift.process_terminate_requested.connect(
			_on_process_terminate_requested,
			CONNECT_DEFERRED,
		)
	if _gamelift.has_signal("health_check_requested"):
		_gamelift.health_check_requested.connect(
			_on_health_check,
			CONNECT_DEFERRED,
		)

	# Initialize SDK.
	var outcome
	var anywhere_mode: bool = config.get("anywhere_mode", false)

	if anywhere_mode:
		Netcode.log.print(
			"Initializing for Anywhere fleet",
			NetworkLogger.CATEGORY_CONNECTIONS
		)
		outcome = _gamelift.init_sdk_anywhere(
			config.get("anywhere_websocket", ""),
			config.get("anywhere_auth_token", ""),
			config.get("anywhere_fleet_id", ""),
			config.get("anywhere_host_id", ""),
			config.get("anywhere_process_id", "")
		)
	else:
		Netcode.log.print(
			"Initializing for managed EC2 fleet",
			NetworkLogger.CATEGORY_CONNECTIONS
		)
		outcome = _gamelift.init_sdk()

	if not outcome.is_success():
		var is_expected := (
			Netcode.is_preview
			or GameliftTestEnvironmentDetector
				.is_running_in_test_env(self )
		)
		if is_expected:
			Netcode.log.print(
				"GameLift SDK init failed"
				+" (expected in tests/preview):"
				+" %s"
				% outcome.get_error_message(),
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
		else:
			Netcode.log.fatal(
				"Init failed: %s"
				% outcome.get_error_message(),
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
		return

	_is_initialized = true

	var sdk_version = _gamelift.get_sdk_version()
	Netcode.log.print(
		"SDK version: %s" % sdk_version,
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Signal process ready.
	_call_process_ready()


func _call_process_ready() -> void:
	var port: int = config.get("server_port", 4433)
	var log_paths := PackedStringArray(["logs/server.log"])

	Netcode.log.print(
		"Calling ProcessReady on port %d" % port,
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	var outcome = _gamelift.process_ready(port, log_paths)

	if not outcome.is_success():
		Netcode.log.fatal(
			"ProcessReady failed: %s" % outcome.get_error_message(),
			NetworkLogger.CATEGORY_CONNECTIONS
		)
		return

	_is_process_ready = true
	Netcode.log.print(
		"Server ready, waiting for game sessions",
		NetworkLogger.CATEGORY_CONNECTIONS
	)


# =============================================================================
# GameLift Callback Handlers
# =============================================================================


func _on_game_session_started(session) -> void:
	_game_session = session

	Netcode.log.print(
		"Game session started: %s"
		% session.game_session_id,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	Netcode.log.print(
		"Max players: %d"
		% session.maximum_player_session_count,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Tell GameLift this server is ready to accept
	# players for this game session.
	Netcode.log.print(
		"Calling activate_game_session",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	var activate_outcome = (
		_gamelift.activate_game_session())
	Netcode.log.print(
		"activate_game_session returned: %s"
		% type_string(typeof(activate_outcome)),
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	if activate_outcome == null:
		Netcode.log.fatal(
			"activate_game_session returned null",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return
	if activate_outcome.is_success():
		Netcode.log.print(
			"Game session activated",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
	else:
		Netcode.log.fatal(
			"ActivateGameSession failed: %s"
			% activate_outcome.get_error_message(),
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return

	# Parse expected player count from matchmaker
	# data or session config.
	var expected_count: int = (
		session.maximum_player_session_count)

	Netcode.log.print(
		"Matchmaker data: %s"
		% session.matchmaker_data.left(500),
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	if not session.matchmaker_data.is_empty():
		var data = JSON.parse_string(
			session.matchmaker_data)
		if data and data is Dictionary:
			expected_count = (
				_parse_player_count_from_matchmaker(
					data))
			# Set transport based on whether any
			# matched player is on web.
			_set_transport_from_matchmaker(data)
			# Identify anonymous players so their
			# backend IDs are not shared with
			# other clients for friend-add.
			_parse_anonymous_from_matchmaker(data)

	server_set_expected_player_count(expected_count)

	# Restart the server listener with the correct
	# transport type. server_enable_connections()
	# was already called during startup (in
	# server_start_match), but at that point the
	# transport type was the default (ENet). Now
	# that we know the actual transport from
	# matchmaker data, re-create the peer so web
	# clients can connect via WebSocket.
	Netcode.connector.server_enable_connections(
		Netcode.server_port)

	# Parse selected level from game properties
	# (set by backend).
	_selected_level_id = (
		_parse_level_from_session(session))
	if not _selected_level_id.is_empty():
		Netcode.log.print(
			"Selected level: %s"
			% _selected_level_id,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		level_selected.emit(
			String(_selected_level_id))

	Netcode.log.print(
		"Game session setup complete,"
		+ " starting idle timer",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Start idle timeout. If no players connect in
	# time, the server terminates to free capacity.
	_start_idle_timer()


func _parse_player_count_from_matchmaker(data: Dictionary) -> int:
	# Count players across all teams.
	var count = 0
	if data.has("teams") and data.teams is Array:
		for team in data.teams:
			if team.has("players") and team.players is Array:
				count += team.players.size()
	return count if count > 0 else 2 # Default to 2 if parsing fails.


## Determine transport from matchmaker player
## attributes. If any player has is_web=1, the
## entire match uses WebSocket.
func _set_transport_from_matchmaker(
	data: Dictionary,
) -> void:
	var has_web_player := false
	if data.has("teams") and data.teams is Array:
		for team in data.teams:
			if (
				not team.has("players")
				or not team.players is Array
			):
				continue
			for player in team.players:
				var attrs: Dictionary = (
					player.get("attributes", {}))
				var is_web = attrs.get(
					"is_web", {})
				if (
					is_web is Dictionary
					and is_web.get(
						"valueAttribute", 0) == 1
				):
					has_web_player = true
					break
			if has_web_player:
				break

	if has_web_player:
		Netcode.settings.transport_type = (
			NetworkSettings.TransportType.WEBSOCKET)
		Netcode.log.print(
			"Web player detected,"
			+ " using WebSocket transport",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
	else:
		Netcode.settings.transport_type = (
			NetworkSettings.TransportType.ENET)
		Netcode.log.print(
			"All native players,"
			+ " using ENet transport",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)


## Identify anonymous players from matchmaker
## data. A player with is_authenticated == 0 is
## anonymous. FlexMatch player IDs use the format
## "backendId_N" (e.g., "abc123_0"), so the
## trailing suffix is stripped to match the raw
## backend player IDs used elsewhere.
func _parse_anonymous_from_matchmaker(
	data: Dictionary,
) -> void:
	_anonymous_backend_ids.clear()
	if (
		not data.has("teams")
		or not data.teams is Array
	):
		return
	for team in data.teams:
		if (
			not team.has("players")
			or not team.players is Array
		):
			continue
		for player in team.players:
			var flexmatch_id: String = player.get(
				"playerId", "")
			if flexmatch_id.is_empty():
				continue
			var attrs: Dictionary = player.get(
				"attributes", {})
			var is_auth = attrs.get(
				"is_authenticated", {})
			if (
				is_auth is Dictionary
				and is_auth.get(
					"valueAttribute", 1) == 0
			):
				var backend_id := (
					_strip_flexmatch_suffix(
						flexmatch_id))
				_anonymous_backend_ids[
					backend_id] = true
	if not _anonymous_backend_ids.is_empty():
		Netcode.log.print(
			"Anonymous players: %s"
			% str(_anonymous_backend_ids.keys()),
			NetworkLogger.CATEGORY_CONNECTIONS,
		)


## Strip the trailing "_N" couch co-op suffix
## from a FlexMatch player ID to recover the raw
## backend player ID. Returns the input unchanged
## if no suffix is found.
func _strip_flexmatch_suffix(
	flexmatch_id: String,
) -> String:
	var last_underscore := (
		flexmatch_id.rfind("_"))
	if last_underscore < 0:
		return flexmatch_id
	var suffix := flexmatch_id.substr(
		last_underscore + 1)
	if suffix.is_valid_int():
		return flexmatch_id.left(last_underscore)
	return flexmatch_id


## Parse selected level from game session.
## Checks game_properties first, then falls back to game_session_data.
func _parse_level_from_session(session) -> StringName:
	# Check game_properties (dictionary).
	if session.game_properties is Dictionary:
		var level_id = session.game_properties.get("level_id", "")
		if not str(level_id).is_empty():
			return StringName(str(level_id))

	# Check game_session_data (JSON string).
	if not session.game_session_data.is_empty():
		var data = JSON.parse_string(session.game_session_data)
		if data and data is Dictionary:
			var level_id = data.get("level_id", "")
			if not str(level_id).is_empty():
				return StringName(str(level_id))

	return ""


func _on_process_terminate_requested() -> void:
	Netcode.log.print(
		"Process termination requested",
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Stop accepting new players.
	_gamelift.update_player_session_creation_policy(
		_gamelift.DENY_ALL
	)

	# Calculate remaining time before forced termination.
	var seconds_remaining := 0.0
	var termination_time = _gamelift.get_termination_time()
	if termination_time > 0:
		var now_unix := Time.get_unix_time_from_system()
		seconds_remaining = maxf(
			float(termination_time) - now_unix,
			0.0,
		)
		Netcode.log.print(
			"Termination in ~%.0f seconds" % seconds_remaining,
			NetworkLogger.CATEGORY_CONNECTIONS
		)

	# Let the game layer finish gracefully.
	shutdown_requested.emit(seconds_remaining)

	# Defer process_ending so listeners can react first.
	_end_process.call_deferred()


func _end_process() -> void:
	var outcome = _gamelift.process_ending()
	if not outcome.is_success():
		Netcode.log.warning(
			"ProcessEnding failed: %s"
				% outcome.get_error_message(),
			NetworkLogger.CATEGORY_CONNECTIONS
		)
	_gamelift.destroy()


func _on_health_check() -> void:
	# GameLift calls this every ~60 seconds.
	# Return true (healthy) by default.
	# TODO: Add custom health check logic if needed.
	pass


func _exit_tree() -> void:
	cleanup()
