class_name GameLiftServerProvider
extends SessionProvider
## Server-side GameLift session validation and lifecycle management.
##
## Handles AWS GameLift Server SDK integration including:
## - SDK initialization (managed and Anywhere fleets)
## - Player session validation
## - Process lifecycle callbacks

# FIXME: Review this.


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

# Expected player count from matchmaking (total players across all peers).
var _expected_player_count: int = 0
var _validated_player_count: int = 0

# Selected level from game session properties.
var _selected_level_id: StringName = ""


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
	session_ids: Array
) -> void:
	var player_count := session_ids.size()

	if not is_active():
		# Preview mode: auto-accept without validation.
		Netcode.log.print(
			"Preview: Auto-accepting %d player(s) for peer %d" % [
				player_count,
				peer_id
			],
			NetworkLogger.CATEGORY_CONNECTIONS
		)
		for i in range(player_count):
			var player_id: int = player_ids[i]
			var session_id: String = (
				str(session_ids[i])
				if i < session_ids.size()
				else ""
			)
			_on_validation_success(player_id, session_id)
		return

	# Validate all session IDs for this peer.
	var all_valid := true
	for i in range(player_count):
		if i >= session_ids.size():
			Netcode.log.warning(
				"Missing session ID for player %d" % player_ids[i],
				NetworkLogger.CATEGORY_CONNECTIONS
			)
			all_valid = false
			break

		var session_id: String = str(session_ids[i])
		var outcome = _gamelift.accept_player_session(session_id)

		if outcome.is_success():
			Netcode.log.print(
				"Player session validated: %s (peer %d, index %d)" % [
					session_id,
					peer_id,
					i
				],
				NetworkLogger.CATEGORY_CONNECTIONS
			)
		else:
			Netcode.log.warning(
				"Player session validation failed for %s: %s" % [
					session_id,
					outcome.get_error_message()
				],
				NetworkLogger.CATEGORY_CONNECTIONS
			)
			all_valid = false
			break

	if not all_valid:
		session_request_failed.emit("Player session validation failed")
		return

	# All sessions valid - record mappings and emit signals.
	for i in range(player_count):
		var player_id: int = player_ids[i]
		var session_id: String = str(session_ids[i])
		_on_validation_success(player_id, session_id)


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

	# Check if all matched players connected.
	if _validated_player_count >= _expected_player_count:
		_on_all_players_ready()


func _on_all_players_ready() -> void:
	Netcode.log.print(
		"All players connected and validated",
		NetworkLogger.CATEGORY_CONNECTIONS
	)
	all_players_connected.emit()


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

	# Connect signals.
	if _gamelift.has_signal("game_session_started"):
		_gamelift.game_session_started.connect(_on_game_session_started)
	if _gamelift.has_signal("process_terminate_requested"):
		_gamelift.process_terminate_requested.connect(
			_on_process_terminate_requested
		)
	if _gamelift.has_signal("health_check_requested"):
		_gamelift.health_check_requested.connect(_on_health_check)

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
		if GameliftTestEnvironmentDetector.is_running_in_test_env(self ):
			Netcode.log.print(
				"GameLift SDK init failed (expected in tests/preview): %s" % outcome.get_error_message(),
				NetworkLogger.CATEGORY_CONNECTIONS
			)
		else:
			Netcode.log.fatal(
				"Init failed: %s" % outcome.get_error_message(),
				NetworkLogger.CATEGORY_CONNECTIONS
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
		"Game session started: %s" % session.game_session_id,
		NetworkLogger.CATEGORY_CONNECTIONS
	)
	Netcode.log.print(
		"Max players: %d" % session.maximum_player_session_count,
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Parse expected player count from matchmaker data or session config.
	var expected_count = session.maximum_player_session_count

	if not session.matchmaker_data.is_empty():
		var data = JSON.parse_string(session.matchmaker_data)
		if data and data is Dictionary:
			expected_count = _parse_player_count_from_matchmaker(data)

	server_set_expected_player_count(expected_count)

	# Parse selected level from game properties (set by backend).
	_selected_level_id = _parse_level_from_session(session)
	if not _selected_level_id.is_empty():
		Netcode.log.print(
			"Selected level: %s" % _selected_level_id,
			NetworkLogger.CATEGORY_CONNECTIONS
		)
		level_selected.emit(String(_selected_level_id))


func _parse_player_count_from_matchmaker(data: Dictionary) -> int:
	# Count players across all teams.
	var count = 0
	if data.has("teams") and data.teams is Array:
		for team in data.teams:
			if team.has("players") and team.players is Array:
				count += team.players.size()
	return count if count > 0 else 2 # Default to 2 if parsing fails.


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

	# Get termination time if available.
	var termination_time = _gamelift.get_termination_time()
	if termination_time > 0:
		Netcode.log.print(
			"Termination scheduled for: %d" % termination_time,
			NetworkLogger.CATEGORY_CONNECTIONS
		)

	# Stop accepting new players.
	_gamelift.update_player_session_creation_policy(_gamelift.DENY_ALL)

	# Signal process ending.
	var outcome = _gamelift.process_ending()
	if not outcome.is_success():
		Netcode.log.warning(
			"ProcessEnding failed: %s" % outcome.get_error_message(),
			NetworkLogger.CATEGORY_CONNECTIONS
		)

	# Destroy SDK.
	_gamelift.destroy()


func _on_health_check() -> void:
	# GameLift calls this every ~60 seconds.
	# Return true (healthy) by default.
	# TODO: Add custom health check logic if needed.
	pass


func _exit_tree() -> void:
	cleanup()
