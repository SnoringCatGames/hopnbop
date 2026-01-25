class_name GameLiftManager
extends Node
## Manages AWS GameLift Server SDK integration for production multiplayer.
##
## GameLiftManager handles the lifecycle of GameLift game sessions including:
## - SDK initialization (managed and Anywhere fleets)
## - Game session activation and termination
## - Player session validation and tracking
## - Health checks and process lifecycle callbacks
##
## This manager is only active when G.settings.use_gamelift is true. In preview
## mode (use_gamelift = false), all GameLift functionality is disabled and the
## game uses standard ENet networking.
##
## Usage:
## - Server: GameLift calls on_start_game_session → activate → wait for players
## - Clients: Connect via ENet → send player_session_id for validation
## - Both: Listen to all_players_connected signal when match is ready to start

# FIXME: Review this.

## Emitted when all expected players have connected and been validated.
signal all_players_connected()

## Emitted when GameLift sends a game session to this server process.
## Parameter is GameLiftGameSession when extension is loaded, null otherwise.
signal game_session_started(session)

## Emitted when a player session is successfully validated.
signal player_session_validated(peer_id: int, session_id: StringName)

var _gamelift = null # GameLiftServer when extension loaded
var _game_session = null # GameLiftGameSession when active
var _is_initialized := false
var _is_process_ready := false

# Maps player_id <-> player_session_id (1:1 per player)
# Dictionary<StringName, StringName>
var _player_to_session: Dictionary = {}
# Dictionary<StringName, StringName>
var _session_to_player: Dictionary = {}

# Pending connections awaiting validation (peer_id -> player_count)
# Dictionary<int, int>
var _pending_peers := {}

# Expected player count from matchmaking (total players across all peers)
var _expected_player_count: int = 0
var _validated_player_count: int = 0


func _ready() -> void:
	if not G.settings.use_gamelift:
		G.print(
			"[GameLift] Disabled via settings (use_gamelift = false)",
			ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		)
		return

	if not G.network.is_server:
		G.print(
			"[GameLift] Client mode, skipping server SDK initialization",
			ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		)
		return

	_initialize_sdk()
	G.log.log_system_ready("GameLiftManager")


## Returns true if GameLift is active and initialized.
func is_active() -> bool:
	return G.settings.use_gamelift and _is_initialized


## Returns true if the server process is ready to host sessions.
func is_process_ready() -> bool:
	return _is_process_ready


## Set the expected number of players for this game session.
func set_expected_player_count(count: int) -> void:
	_expected_player_count = count
	G.print(
		"[GameLift] Expected player count: %d" % count,
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	)


## Validate multiple player sessions for a single peer.
## This is called when a client declares how many players they have.
## All session_ids must be valid or the entire peer will be disconnected.
func validate_player_sessions(
	peer_id: int,
	player_count: int,
	session_ids: Array
) -> void:
	G.check_is_server()

	if not is_active():
		# In preview mode, auto-accept without validation.
		G.print(
			"[GameLift] Preview: Auto-accepting %d player(s) for peer %d" % [
				player_count,
				peer_id,
			],
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
		)
		for i in range(player_count):
			var player_id := NetworkConnector.get_player_id(peer_id, i)
			var session_id: StringName = (
				session_ids[i]
				if i < session_ids.size()
				else ""
			)
			_on_validation_success(player_id, session_id)
		return

	if _gamelift == null:
		G.warning("[GameLift] SDK not initialized, auto-accepting")
		for i in range(player_count):
			var player_id := NetworkConnector.get_player_id(peer_id, i)
			var session_id: StringName = (
				session_ids[i]
				if i < session_ids.size()
				else ""
			)
			_on_validation_success(player_id, session_id)
		return

	# Validate all session IDs for this peer.
	var all_valid := true
	for i in range(player_count):
		if i >= session_ids.size():
			G.warning(
				(
					"[GameLift] Missing session ID for player %d:%d"
					% [peer_id, i]
				),
				ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
			)
			all_valid = false
			break

		var session_id: StringName = session_ids[i]
		var outcome = _gamelift.accept_player_session(session_id)

		if outcome.is_success():
			G.print(
				(
					"[GameLift] Player session validated: %s (peer %d, "
					+"local index %d)"
				)
				% [session_id, peer_id, i],
				ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
			)
		else:
			G.warning(
				(
					"[GameLift] Player session validation failed for %s: %s"
					% [session_id, outcome.get_error_message()]
				),
				ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
			)
			all_valid = false
			break

	if not all_valid:
		# Disconnect the entire peer if any validation fails.
		G.warning(
			"[GameLift] Disconnecting peer %d due to validation failure"
			% peer_id,
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
		)
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	# All sessions valid - record mappings.
	for i in range(player_count):
		var player_id := NetworkConnector.get_player_id(peer_id, i)
		var session_id: StringName = session_ids[i]
		_on_validation_success(player_id, session_id)


## Deprecated: Use validate_player_sessions() for multi-player support.
func validate_player_session(peer_id: int, session_id: StringName) -> void:
	# Redirect to new method with single player.
	validate_player_sessions(peer_id, 1, [session_id])


func _on_validation_success(player_id: StringName, session_id: StringName) -> void:
	_player_to_session[player_id] = session_id
	_session_to_player[session_id] = player_id
	_validated_player_count += 1

	# Extract peer_id for logging and signal.
	var peer_id: int = 0
	if not player_id.is_empty():
		var parts := player_id.split(":")
		if parts.size() >= 1:
			peer_id = int(parts[0])

	G.print(
		"[GameLift] Player validated: player_id=%s, session=%s (%d/%d)" % [
			player_id,
			session_id,
			_validated_player_count,
			_expected_player_count,
		],
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
	)

	player_session_validated.emit(peer_id, session_id)

	# Check if all matched players connected.
	if _validated_player_count >= _expected_player_count:
		_on_all_players_ready()


func _on_all_players_ready() -> void:
	G.print(
		"[GameLift] All players connected, starting game",
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	)

	# Unpause frame simulation
	G.network.frame_driver.server_set_is_paused(false)

	all_players_connected.emit()


## Get the player_session_id for a given player_id.
func get_session_id_for_player(player_id: StringName) -> StringName:
	return _player_to_session.get(player_id, "")


## Get the player_id for a given player_session_id.
func get_player_id_for_session(session_id: StringName) -> StringName:
	return _session_to_player.get(session_id, "")


## Deprecated: Use get_session_id_for_player() with player_id string.
func get_session_id_for_peer(peer_id: int) -> StringName:
	var player_id := "%d:0" % peer_id
	return get_session_id_for_player(player_id)


## Deprecated: Use get_player_id_for_session() which returns player_id.
func get_peer_id_for_session(session_id: StringName) -> int:
	var player_id := get_player_id_for_session(session_id)
	if player_id.is_empty():
		return 0
	var parts := player_id.split(":")
	if parts.size() >= 1:
		return int(parts[0])
	return 0


## Remove a player session when a player disconnects.
func remove_player_session(session_id: StringName) -> void:
	if not is_active() or _gamelift == null:
		return

	var outcome = _gamelift.remove_player_session(session_id)
	if outcome.is_success():
		G.print(
			"[GameLift] Player session removed: %s" % session_id,
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
		)
	else:
		G.warning(
			(
                "[GameLift] Failed to remove player session: %s"
				% outcome.get_error_message()
			),
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
		)


## End the game session (called on server shutdown).
func end_game_session() -> void:
	if not is_active() or _gamelift == null:
		return

	# Stop accepting new players
	_gamelift.update_player_session_creation_policy(_gamelift.DENY_ALL)

	G.print(
		"[GameLift] Game session ended, no longer accepting players",
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	)


## Activate the game session after setup is complete.
func activate_game_session() -> void:
	if not is_active():
		return

	if _gamelift == null:
		G.warning("[GameLift] Cannot activate: SDK not initialized")
		return

	var outcome = _gamelift.activate_game_session()
	if outcome.is_success():
		G.print(
			"[GameLift] Game session activated, ready for players",
			ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		)
	else:
		G.warning(
			(
                "[GameLift] Failed to activate session: %s"
				% outcome.get_error_message()
			),
		)

# =============================================================================
# SDK Initialization
# =============================================================================


func _initialize_sdk() -> void:
	# Try to load GameLift extension
	if ClassDB.class_exists("GameLiftServer"):
		_gamelift = ClassDB.instantiate("GameLiftServer")
		add_child(_gamelift)

		# Connect signals
		_gamelift.game_session_started.connect(_on_game_session_started)
		_gamelift.process_terminate_requested.connect(
			_on_process_terminate_requested,
		)
		_gamelift.health_check_requested.connect(_on_health_check)
	else:
		G.warning(
			"[GameLift] GameLiftServer class not found (extension not loaded)",
		)
		return

	# Initialize SDK
	var outcome
	if G.settings.gamelift_anywhere_mode:
		G.print(
			"[GameLift] Initializing for Anywhere fleet",
			ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		)
		outcome = _gamelift.init_sdk_anywhere(
			G.settings.gamelift_anywhere_websocket,
			G.settings.gamelift_anywhere_auth_token,
			G.settings.gamelift_anywhere_fleet_id,
			G.settings.gamelift_anywhere_host_id,
			G.settings.gamelift_anywhere_process_id,
		)
	else:
		G.print(
			"[GameLift] Initializing for managed EC2 fleet",
			ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		)
		outcome = _gamelift.init_sdk()

	if not outcome.is_success():
		G.error(
			"[GameLift] Init failed: %s" % outcome.get_error_message(),
			ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		)
		return

	_is_initialized = true

	var sdk_version = _gamelift.get_sdk_version()
	G.print(
		"[GameLift] SDK version: %s" % sdk_version,
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	)

	# Signal process ready
	_call_process_ready()


func _call_process_ready() -> void:
	var port = G.settings.local_server_port
	var log_paths = PackedStringArray(["logs/server.log"])

	G.print(
		"[GameLift] Calling ProcessReady on port %d" % port,
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	)

	var outcome = _gamelift.process_ready(port, log_paths)

	if not outcome.is_success():
		G.error(
			(
                "[GameLift] ProcessReady failed: %s"
				% outcome.get_error_message()
			),
			ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		)
		return

	_is_process_ready = true
	G.print(
		"[GameLift] Server ready, waiting for game sessions",
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	)

# =============================================================================
# GameLift Callback Handlers
# =============================================================================


func _on_game_session_started(session) -> void:
	_game_session = session

	G.print(
		"[GameLift] Game session started: %s" % session.game_session_id,
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	)
	G.print(
		"[GameLift] Max players: %d" % session.maximum_player_session_count,
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	)

	# Parse expected player count from matchmaker data or session config
	var expected_count = session.maximum_player_session_count

	if not session.matchmaker_data.is_empty():
		var data = JSON.parse_string(session.matchmaker_data)
		if data and data is Dictionary:
			expected_count = _parse_player_count_from_matchmaker(data)

	set_expected_player_count(expected_count)

	# Emit signal for game_panel to handle
	game_session_started.emit(session)


func _parse_player_count_from_matchmaker(data: Dictionary) -> int:
	# Count players across all teams
	var count = 0
	if data.has("teams") and data.teams is Array:
		for team in data.teams:
			if team.has("players") and team.players is Array:
				count += team.players.size()
	return count if count > 0 else 2 # Default to 2 if parsing fails


func _on_process_terminate_requested() -> void:
	G.print(
		"[GameLift] Process termination requested",
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	)

	# Get termination time if available
	var termination_time = _gamelift.get_termination_time()
	if termination_time > 0:
		G.print(
			"[GameLift] Termination scheduled for: %d" % termination_time,
			ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		)

	# Stop accepting new players
	_gamelift.update_player_session_creation_policy(_gamelift.DENY_ALL)

	# Notify game panel to shut down gracefully
	if is_instance_valid(G.game_panel):
		G.game_panel.server_end_game()

	# Signal process ending
	var outcome = _gamelift.process_ending()
	if not outcome.is_success():
		G.warning(
			(
                "[GameLift] ProcessEnding failed: %s"
				% outcome.get_error_message()
			),
		)

	# Destroy SDK
	_gamelift.destroy()

	# Exit after brief delay
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


func _on_health_check() -> void:
	# GameLift calls this every ~60 seconds
	# Return true (healthy) by default
	# TODO: Add custom health check logic if needed
	pass


func _exit_tree() -> void:
	if _gamelift and _is_initialized:
		_gamelift.process_ending()
		_gamelift.destroy()
