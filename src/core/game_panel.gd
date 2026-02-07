class_name GamePanel
extends Node2D


## This is triggered from LobbyLevel.
@warning_ignore("unused_signal")
signal lobby_players_updated


var levels: Array[Level] = []

var is_level_fully_loaded := false

var session_manager: GameSessionManager

var match_state: GameMatchState:
	get:
		return %MatchStateSynchronizer.state
var match_state_synchronizer: MatchStateSynchronizer:
	get:
		return %MatchStateSynchronizer


func _enter_tree() -> void:
	G.game_panel = self
	G.client_session = ClientSession.new()


func _ready() -> void:
	G.log.log_system_ready("GamePanel")

	G.match_state = match_state

	%PlayerOverheadLabels.set_up()

	%MatchStateSynchronizer.set_multiplayer_authority(NetworkConnector.SERVER_ID)
	%LevelSpawner.set_multiplayer_authority(NetworkConnector.SERVER_ID)

	for level_info in G.settings.levels:
		if level_info.scene != null:
			%LevelSpawner.add_spawnable_scene(level_info.scene.resource_path)

	# Set up session manager for network coordination.
	session_manager = GameSessionManager.new()
	session_manager.name = "SessionManager"
	add_child(session_manager)

	# Configure local session provider for NetworkConnector handshake.
	Netcode.connector.client_session_provider = func() -> Dictionary:
		return {
			"session_ids": G.client_session.client_session_ids,
			"player_count": G.client_session.local_player_count,
			"attributes": G.client_session.local_player_attributes
		}

	# Configure player attribute validator for bunny validation.
	Netcode.connector.player_attribute_validator = _validate_player_attributes

	# Connect to high-level session events.
	session_manager.session_established.connect(_on_session_established)
	session_manager.connection_lost.connect(_on_connection_lost)

	if Netcode.is_server:
		session_manager.match_ready.connect(_on_match_ready)
		session_manager.server_should_reset.connect(_on_server_should_reset)
		session_manager.session_provider.all_players_connected.connect(
			_server_on_all_players_connected
		)

	if Netcode.is_client:
		if Netcode.is_connected_to_server:
			_client_on_server_connected()
		multiplayer.connected_to_server.connect(_client_on_server_connected)

		%LevelSpawner.spawned.connect(_client_on_level_spawned)
		%LevelSpawner.despawned.connect(_client_on_level_despawned)

		Netcode.local_authority_added.connect(
			_client_on_local_player_loaded,
		)

		# Transition from LOADING to GAME when server unpauses.
		Netcode.frame_driver.pause_state_changed.connect(
			_client_on_pause_state_changed
		)

		# Show countdown UI when match start countdown begins.
		Netcode.frame_driver.match_start_countdown_started.connect(
			_on_match_start_countdown_started
		)

	if Netcode.is_server:
		# In preview mode, spawn new level when first client connects after match end.
		if Netcode.is_preview:
			G.print(
				"Connecting to peer_connected signal for preview mode",
				NetworkLogger.CATEGORY_CONNECTIONS
			)
			multiplayer.peer_connected.connect(_server_on_preview_peer_connected)

	G.match_state.player_joined.connect(_on_player_joined)
	G.match_state.player_left.connect(_on_player_left)
	G.match_state.player_killed.connect(_on_player_killed)
	G.match_state.players_bumped.connect(_on_players_bumped)

	# Set up PerfTracker callback for level ready state.
	if Netcode.perf_tracker != null:
		Netcode.perf_tracker.is_ready_callback = func() -> bool:
			return is_level_fully_loaded


func _on_player_joined(player: PlayerMatchState) -> void:
	# Check if this player belongs to the local peer.
	var is_local_peer := (
		Netcode.is_client and
		player.peer_id == Netcode.local_peer_id
	)
	var self_suffix := " (local)" if is_local_peer else ""
	G.print(
		"Player joined: %s%s" % [player.get_string(), self_suffix],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


func _on_player_left(player: PlayerMatchState) -> void:
	G.print("Player left: %s" % player.get_string(),
		NetworkLogger.CATEGORY_GAME_STATE)


func _on_player_killed(killer: PlayerMatchState, killee: PlayerMatchState) -> void:
	G.print(
		"Player killed: %s killed %s" %
		[killer.get_string(), killee.get_string()],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# Trigger respawn on server (moved from MatchState).
	if Netcode.is_server:
		var killee_actor: Player = G.get_player(killee.player_id)
		if is_instance_valid(killee_actor):
			killee_actor.server_trigger_death()


func _on_players_bumped(a: PlayerMatchState, b: PlayerMatchState) -> void:
	G.print(
		"Players bumped: %s, %s" % [a.get_string(), b.get_string()],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


func _client_on_level_spawned(p_level: Level) -> void:
	G.ensure(p_level is Level)
	var level: Level = p_level
	G.print("Level spawned: %s" % level.get_string(),
		NetworkLogger.CATEGORY_GAME_STATE)


func _client_on_level_despawned(p_level: Level) -> void:
	G.ensure(p_level is Level)
	var level: Level = p_level
	G.print("Level despawned: %s" % level.get_string(),
		NetworkLogger.CATEGORY_GAME_STATE)


func _client_on_local_player_loaded(
		_input_from_client: PlayerInputFromClient,
) -> void:
	is_level_fully_loaded = true


func _client_on_server_connected() -> void:
	Netcode.check_is_client()

	# Guard against being called multiple times (can happen if GamePanel._ready
	# runs after connection is already established, causing both the direct call
	# and the signal handler to fire).
	if G.client_session.is_game_active:
		G.print(
			"Already connected to server, ignoring duplicate call",
			NetworkLogger.CATEGORY_CONNECTIONS
		)
		return

	G.check(G.client_session.is_game_loading, "Game load is not expected")
	G.check(not G.client_session.is_game_active, "Game is already active")

	G.client_session.is_game_active = true

	# Stay on the loading screen. We will transition to GAME when server
	# unpauses (handled in _client_on_pause_state_changed).
	# But if game is already unpaused, transition immediately.
	if not Netcode.frame_driver.is_paused:
		_client_transition_to_game_if_ready()


# --- High-Level Session Event Handlers ---


func _on_session_established(player_ids: Array[int]) -> void:
	# Player IDs already stored in ClientSession by GameSessionManager.
	G.print(
		"Session established with %d player(s): %s" % [
			player_ids.size(),
			player_ids
		],
		NetworkLogger.CATEGORY_GAME_STATE
	)


func _client_on_pause_state_changed(is_paused: bool, _initiator_peer_id: int) -> void:
	Netcode.check_is_client()

	# When game unpauses, transition from LOADING to GAME.
	if not is_paused:
		_client_transition_to_game_if_ready()


func _client_transition_to_game_if_ready() -> void:
	Netcode.check_is_client()

	# Only transition if game is active and we're on LOADING screen.
	if G.client_session.is_game_active:
		if G.screens.current_screen == ScreensMain.ScreenType.LOADING:
			# Game is no longer loading - we're entering the game now.
			G.client_session.is_game_loading = false
			G.screens.client_open_screen(ScreensMain.ScreenType.GAME)


func _on_connection_lost(reason_name: String, is_expected: bool) -> void:
	# Only clients handle connection loss UI.
	if Netcode.is_client:
		# Store disconnect reason for display on game over screen.
		if not is_expected:
			G.client_session.latest_server_message = (
				"Disconnected: %s" % reason_name
			)

		if is_expected:
			G.print(
				"Match ended, returning to lobby",
				NetworkLogger.CATEGORY_GAME_STATE
			)
		else:
			G.warning(
				"Unexpected disconnect: %s" % reason_name,
				NetworkLogger.CATEGORY_CONNECTIONS
			)
		client_exit_match()


func _on_match_ready() -> void:
	# All players connected and validated (server only).
	Netcode.check_is_server()
	G.print(
		"Match ready, all players validated",
		NetworkLogger.CATEGORY_GAME_STATE
	)

	# Set expected player count for color assignment. This tells
	# MatchStateSynchronizer how many players to expect, so it can assign colors
	# when the last player is added to match state.
	# In preview mode, this is the number of client instances.
	# In production, it's the number returned by the matchmaker.
	var expected_count: int
	if Netcode.is_preview:
		expected_count = Netcode.settings.preview_client_count
	else:
		# Production: get from session provider or use connected peer count
		expected_count = multiplayer.get_peers().size()

	%MatchStateSynchronizer.server_set_expected_player_count(expected_count)

	# Game-specific logic can go here (e.g., start countdown)


func _on_server_should_reset() -> void:
	# Server should reset for new match (preview mode only).
	Netcode.check_is_server()
	G.print(
		"Resetting server for new match",
		NetworkLogger.CATEGORY_CORE_SYSTEMS
	)
	_server_reset_for_new_match()


func _server_reset_for_new_match() -> void:
	Netcode.check_is_server()

	# Clear match state.
	G.match_state.match_start_frame_index = -1
	G.match_state.is_match_ended = false
	G.match_state.clear()

	# Despawn current level.
	if is_instance_valid(G.level):
		G.level.queue_free()
		G.level = null

	# Reset frame driver.
	Netcode.frame_driver.server_frame_index = 0

	G.print(
		"Server reset complete, ready for new clients",
		NetworkLogger.CATEGORY_CORE_SYSTEMS
	)


## Spawn lobby level (client-only, no server connection).
func _client_spawn_lobby() -> void:
	Netcode.check_is_client()

	if G.is_lobby_active:
		# Lobby is already ready.
		return

	G.print("Spawning lobby level", NetworkLogger.CATEGORY_CORE_SYSTEMS)

	var lobby_level: LobbyLevel = G.settings.lobby_level_scene.instantiate()
	levels.append(lobby_level)
	%Levels.add_child(lobby_level)
	G.level = lobby_level


## Despawn lobby level before connecting to server.
func _client_despawn_lobby_if_present() -> void:
	if not G.is_lobby_active:
		return

	G.print("Despawning lobby level", NetworkLogger.CATEGORY_CORE_SYSTEMS)

	var lobby_level: LobbyLevel = G.level
	levels.erase(lobby_level)
	lobby_level.queue_free()
	G.level = null


func client_load_game() -> void:
	Netcode.check_is_client()
	G.check(not G.client_session.is_game_active, "Game is already active")
	G.check(not G.client_session.is_game_loading, "Game is already loading")

	# Despawn lobby if present.
	_client_despawn_lobby_if_present()

	G.client_session.clear_latest_state()
	G.client_session.is_game_active = false
	G.client_session.is_game_loading = true

	# Reset frame index for new match to sync with server's reset.
	Netcode.frame_driver.client_reset()

	G.screens.client_open_screen(ScreensMain.ScreenType.LOADING)

	# Request session IDs from backend before connecting.
	_client_client_request_session_ids()


func _client_client_request_session_ids() -> void:
	Netcode.check_is_client()
	session_manager.client_request_session()


func client_exit_match() -> void:
	Netcode.check_is_client()

	G.client_session.is_game_active = false
	G.client_session.is_game_loading = false

	Netcode.connector.client_disconnect()
	G.client_session.copy_latest_state(G.match_state)
	G.client_session.clear()

	# Reset match timer state for next game.
	G.match_state.match_start_frame_index = -1
	G.match_state.is_match_ended = false

	G.screens.client_open_screen(ScreensMain.ScreenType.GAME_OVER)
	for level in levels:
		levels.erase(level)
		level.queue_free()
	G.level = null


func server_start_match() -> void:
	Netcode.check_is_server()
	G.check(not G.client_session.is_game_active, "Game is already active")
	G.check(not is_instance_valid(G.level), "Level is already set")

	G.client_session.is_game_active = true

	# Reset timer state.
	G.match_state.match_start_frame_index = -1
	G.match_state.is_match_ended = false

	# Set expected player count for session validation.
	# In preview mode, this is the number of client instances.
	# In production, GameLiftServerProvider sets this from session properties.
	if Netcode.is_preview:
		var expected_client_count := Netcode.settings.preview_client_count
		session_manager.server_set_expected_players(expected_client_count)

	# Get selected level from session provider (GameLift or preview mode).
	var level_scene := _server_get_selected_level_scene()

	_server_spawn_level(level_scene)

	Netcode.connector.server_enable_connections(Netcode.server_port)


func server_end_match() -> void:
	Netcode.check_is_server()

	# Guard against multiple calls (from delayed timer callbacks).
	if not G.client_session.is_game_active:
		return
	if not is_instance_valid(G.level):
		return

	G.client_session.is_game_active = false
	G.match_state.match_start_frame_index = -1
	G.match_state.is_match_ended = false

	# In preview mode, disconnect clients but keep session open for next match.
	# In production, close entire session.
	if Netcode.is_preview:
		Netcode.connector.server_disconnect_all_clients()
	else:
		Netcode.connector.server_close_multiplayer_session()

	# TODO: Add support for tracking game stats in a separate backend database.

	_server_destroy_level(G.level)


func _server_on_all_players_connected() -> void:
	Netcode.check_is_server()

	G.print(
		"All players validated, starting match",
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Unpause frame driver to start simulation.
	# The framework automatically triggers countdown if enabled in settings.
	Netcode.frame_driver.server_set_is_paused(false)


func _on_match_start_countdown_started(_countdown_end_frame: int) -> void:
	# Show match start countdown UI on clients.
	if is_instance_valid(G.hud):
		G.hud.start_match_countdown()


func _server_on_preview_peer_connected(_peer_id: int) -> void:
	Netcode.check_is_server()

	# If no level exists or match has ended, spawn a new level for the new match.
	if not is_instance_valid(G.level) or G.match_state.is_match_ended:
		G.print(
			"Spawning new level for next match",
			NetworkLogger.CATEGORY_GAME_STATE
		)
		# Clean up old level if it still exists.
		if is_instance_valid(G.level):
			_server_destroy_level(G.level)
		# Clear match state (removes old players, kills, bumps, etc.).
		G.match_state.clear()
		# Mark game as active for new match.
		G.client_session.is_game_active = true
		# Reset timer state for new match.
		G.match_state.match_start_frame_index = -1
		G.match_state.is_match_ended = false
		# Reset expected client count for session validation (preview mode).
		var expected_client_count := Netcode.settings.preview_client_count
		session_manager.server_set_expected_players(expected_client_count)
		# NOTE: MatchStateSynchronizer expected count set in _on_match_ready().
		# Reset frame counter for fresh match start.
		Netcode.frame_driver.server_frame_index = 0
		# Start grace period to suppress expected frame sync warnings.
		Netcode.frame_driver._frame_reset_time_usec = Time.get_ticks_usec()
		# Reconnect preview mode auto-unpause signal for new match.
		Netcode.frame_driver.server_reset_preview_mode_unpause()
		# Get selected level (may use preferences from preview mode).
		var level_scene := _server_get_selected_level_scene()
		_server_spawn_level(level_scene)


func _process(_delta: float) -> void:
	if not Netcode.is_server:
		return

	# Start timer when ready.
	if G.match_state.match_start_frame_index < 0:
		_server_check_start_match_timer()
		return

	# Check if time has expired.
	if not G.match_state.is_match_ended and G.match_state.is_match_time_expired:
		_server_initiate_match_end()


func _server_check_start_match_timer() -> void:
	if G.match_state.match_start_frame_index >= 0:
		return
	if not is_level_fully_loaded:
		return
	if not is_instance_valid(G.level):
		return

	var match_duration_sec := G.settings.match_duration_sec

	# Start timer once level is loaded (sets match_start_frame_index).
	G.match_state.server_start_match_timer(match_duration_sec)

	G.print(
		"Match timer started: %d seconds" % match_duration_sec,
		NetworkLogger.CATEGORY_GAME_STATE
	)


func _server_initiate_match_end() -> void:
	Netcode.check_is_server()
	G.check(not G.match_state.is_match_ended, "Match end already initiated")

	G.print("Match time expired - initiating end sequence",
		NetworkLogger.CATEGORY_GAME_STATE)

	# Set flag to enable invincibility for all players and notify clients.
	G.match_state.is_match_ended = true
	G.match_state.match_ended.emit()
	match_state_synchronizer._rpc_client_notify_match_ended.rpc()

	# Schedule server shutdown after wait period.
	Netcode.time.set_timeout(
		server_end_match,
		G.settings.match_end_disconnect_delay_sec
	)


func on_return_to_game_from_screen(
		_previous_screen_type: ScreensMain.ScreenType) -> void:
	G.check(G.client_session.is_game_active, "Game is not active")
	G.check(
		not G.client_session.is_game_loading,
		"Game is still loading",
	)


func on_left_game_to_screen(_next_screen_type: ScreensMain.ScreenType) -> void:
	pass


func on_return_to_lobby_from_screen(
		_previous_screen_type: ScreensMain.ScreenType) -> void:
	_client_spawn_lobby()


func on_left_lobby_to_screen(_next_screen_type: ScreensMain.ScreenType) -> void:
	pass


## Get the level scene to spawn based on session provider selection.
## If no level is selected, picks a random enabled level.
func _server_get_selected_level_scene() -> PackedScene:
	var level_id := session_manager.server_get_selected_level_id()

	if not level_id.is_empty():
		var level_info := G.level_registry.get_level_by_id(level_id)
		if level_info != null and level_info.scene != null:
			G.print(
				"Using selected level: %s (%s)" % [level_id, level_info.display_name],
				NetworkLogger.CATEGORY_GAME_STATE
			)
			return level_info.scene
		else:
			G.warning(
				"Selected level '%s' not found in registry" % level_id,
				NetworkLogger.CATEGORY_GAME_STATE
			)

	# No level selected or not found - pick random from enabled levels.
	var random_level := G.level_registry.get_random_enabled_level()
	if random_level != null:
		G.print(
			"Randomly selected level: %s (%s)" % [
				random_level.id,
				random_level.display_name
			],
			NetworkLogger.CATEGORY_GAME_STATE
		)
		return random_level.scene

	G.warning(
		"No enabled levels available",
		NetworkLogger.CATEGORY_GAME_STATE
	)
	return null


func _server_spawn_level(level_scene: PackedScene) -> void:
	Netcode.check_is_server()
	G.check(
		G.level_registry.get_level_id_for_scene(level_scene) != "",
		"level_scene not registered in level registry: %s" % level_scene,
	)

	# Pause server to wait for all clients to connect before starting match.
	# In preview mode, frame_driver will auto-unpause when all clients join.
	Netcode.frame_driver.server_set_is_paused(true)

	G.print(
		"Spawning level: %s" % Utils.get_display_name(level_scene),
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	var level: Level = level_scene.instantiate()
	levels.append(level)
	%Levels.add_child(level)
	G.level = level


func _server_destroy_level(level: Level) -> void:
	Netcode.check_is_server()
	G.check(
		levels.has(level),
		"level not in current list: %s" % level,
	)

	G.print("Destroying level: %s" % level.get_string(),
		NetworkLogger.CATEGORY_GAME_STATE)

	if G.level == level:
		G.level = null
	levels.erase(level)
	level.queue_free()


func on_level_added(level: Level) -> void:
	if Netcode.is_client:
		G.level = level
		levels.append(level)


func on_level_removed(level: Level) -> void:
	if Netcode.is_client:
		is_level_fully_loaded = false
		if G.level == level:
			G.level = null
		levels.erase(level)


## Validates and sanitizes player attributes for bunny configuration.
## Called by NetworkConnector when players declare their attributes.
func _validate_player_attributes(
	attributes: Array,
	expected_count: int,
	peer_id: int
) -> Array:
	var validated: Array = []

	for i in range(min(attributes.size(), expected_count)):
		var attr: Dictionary = attributes[i].duplicate()

		# Validate/sanitize bunny_name.
		if not BunnyWords.NAMES.has(attr.get("bunny_name", "")):
			attr["bunny_name"] = BunnyWords.NAMES.pick_random()
			G.warning(
				"Peer %d: Invalid bunny_name, assigned random: %s" % [
					peer_id,
					attr["bunny_name"]
				],
				NetworkLogger.CATEGORY_CONNECTIONS
			)

		# Validate/sanitize adjective.
		var is_soft: bool = attr.get("is_soft", true)
		var valid_adjectives := (
			BunnyWords.SOFT_ADJECTIVES if is_soft
			else BunnyWords.HARD_ADJECTIVES
		)
		if not valid_adjectives.has(attr.get("adjective", "")):
			attr["adjective"] = valid_adjectives.pick_random()
			G.warning(
				"Peer %d: Invalid adjective, assigned random: %s" % [
					peer_id,
					attr["adjective"]
				],
				NetworkLogger.CATEGORY_CONNECTIONS
			)

		# Ensure required fields exist with defaults.
		if not attr.has("body_type_index"):
			G.warning(
				"Peer %d: Invalid body_type_index, assigned 0: %s" % [
					peer_id,
					attr["body_type_index"]
				],
				NetworkLogger.CATEGORY_CONNECTIONS
			)
			attr["body_type_index"] = 0
		if not attr.has("costume_index"):
			G.warning(
				"Peer %d: Invalid costume_index, assigned 0: %s" % [
					peer_id,
					attr["costume_index"]
				],
				NetworkLogger.CATEGORY_CONNECTIONS
			)
			attr["costume_index"] = 0

		validated.append(attr)

	return validated
