class_name GamePanel
extends Node2D


## This is triggered from LobbyLevel.
@warning_ignore("unused_signal")
signal lobby_players_updated


var levels: Array[Level] = []

var is_level_fully_loaded := false

var match_state: MatchState:
	get:
		return %MatchStateSynchronizer.state
var match_state_synchronizer: MatchStateSynchronizer:
	get:
		return %MatchStateSynchronizer


func _enter_tree() -> void:
	G.game_panel = self
	G.local_session = LocalSession.new()


func _ready() -> void:
	G.log.log_system_ready("GamePanel")

	G.match_state = match_state

	%PlayerOverheadLabels.set_up()

	%MatchStateSynchronizer.set_multiplayer_authority(NetworkConnector.SERVER_ID)
	%LevelSpawner.set_multiplayer_authority(NetworkConnector.SERVER_ID)

	for level_scene in G.settings.level_scenes:
		%LevelSpawner.add_spawnable_scene(level_scene.resource_path)

	if G.network.is_client:
		if G.network.is_connected_to_server:
			_client_on_server_connected()
		multiplayer.connected_to_server.connect(_client_on_server_connected)
		multiplayer.server_disconnected.connect(_client_on_server_disconnected)

		%LevelSpawner.spawned.connect(_client_on_level_spawned)
		%LevelSpawner.despawned.connect(_client_on_level_despawned)

		G.network.local_authority_added.connect(
			_client_on_local_player_loaded,
		)

		G.network.session_manager.local_session_ids_received.connect(
			_client_on_session_ids_received
		)
		G.network.session_manager.session_request_failed.connect(
			_client_on_session_request_failed
		)

	G.match_state.player_joined.connect(_on_player_joined)
	G.match_state.player_left.connect(_on_player_left)
	G.match_state.player_killed.connect(_on_player_killed)
	G.match_state.players_bumped.connect(_on_players_bumped)


func _on_player_joined(player: PlayerMatchState) -> void:
	# Check if this player belongs to the local peer.
	var is_local_peer := (
		G.network.is_client and
		player.peer_id == G.network.local_peer_id
	)
	var self_suffix := " (local)" if is_local_peer else ""
	G.print(
		"Player joined: %s%s" % [player.get_string(), self_suffix],
		ScaffolderLog.CATEGORY_GAME_STATE,
	)


func _on_player_left(player: PlayerMatchState) -> void:
	G.print("Player left: %s" % player.get_string(),
		ScaffolderLog.CATEGORY_GAME_STATE)


func _on_player_killed(killer: PlayerMatchState, killee: PlayerMatchState) -> void:
	G.print(
		"Player killed: %s killed %s" %
		[killer.get_string(), killee.get_string()],
		ScaffolderLog.CATEGORY_GAME_STATE,
	)


func _on_players_bumped(a: PlayerMatchState, b: PlayerMatchState) -> void:
	G.print(
		"Players bumped: %s, %s" % [a.get_string(), b.get_string()],
		ScaffolderLog.CATEGORY_GAME_STATE,
	)


func _client_on_level_spawned(p_level: Node) -> void:
	G.ensure(p_level is Level)
	var level: Level = p_level
	G.print("Level spawned: %s" % level.get_string(),
		ScaffolderLog.CATEGORY_GAME_STATE)


func _client_on_level_despawned(p_level: Node) -> void:
	G.ensure(p_level is Level)
	var level: Level = p_level
	G.print("Level despawned: %s" % level.get_string(),
		ScaffolderLog.CATEGORY_GAME_STATE)


func _client_on_local_player_loaded(
		_input_from_client: PlayerInputFromClient,
) -> void:
	is_level_fully_loaded = true


func _client_on_server_connected() -> void:
	G.check_is_client()
	G.check(G.local_session.is_game_loading, "Game load is not expected")
	G.check(not G.local_session.is_game_active, "Game is already active")

	G.local_session.is_game_loading = false
	G.local_session.is_game_active = true

	# Stay on the loading screen. We will transition to GAME when server
	# unpauses.


func _client_on_server_disconnected() -> void:
	G.check_is_client()

	var reason := G.network.connector.last_disconnect_reason
	G.print(
		"Disconnected: %s" %
			NetworkConnector.DisconnectReason.keys()[reason],
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
	)

	client_exit_game()


## Spawn lobby level (client-only, no server connection).
func _client_spawn_lobby() -> void:
	G.check_is_client()

	if G.is_lobby_active:
		# Lobby is already ready.
		return

	G.print("Spawning lobby level", ScaffolderLog.CATEGORY_CORE_SYSTEMS)

	var lobby_level: LobbyLevel = G.settings.lobby_level_scene.instantiate()
	levels.append(lobby_level)
	%Levels.add_child(lobby_level)
	G.level = lobby_level


## Despawn lobby level before connecting to server.
func _client_despawn_lobby_if_present() -> void:
	if not G.is_lobby_active:
		return

	G.print("Despawning lobby level", ScaffolderLog.CATEGORY_CORE_SYSTEMS)

	var lobby_level: LobbyLevel = G.level
	levels.erase(lobby_level)
	lobby_level.queue_free()
	G.level = null


func client_load_game() -> void:
	G.check_is_client()
	G.check(not G.local_session.is_game_active, "Game is already active")
	G.check(not G.local_session.is_game_loading, "Game is already loading")

	# Despawn lobby if present.
	_client_despawn_lobby_if_present()

	G.local_session.clear_latest_state()
	G.local_session.is_game_active = false
	G.local_session.is_game_loading = true

	G.screens.client_open_screen(ScreensMain.ScreenType.LOADING)

	# Request session IDs from backend before connecting.
	_client_request_session_ids()


func _client_request_session_ids() -> void:
	G.check_is_client()

	var player_count := G.local_session.local_player_count

	# Make request.
	G.network.session_manager.request_session_ids(player_count)


func _client_on_session_ids_received(
		session_ids: Array,
		server_ip: String,
		server_port: int) -> void:
	G.check_is_client()

	# Store in LocalSession.
	G.local_session.local_session_ids.clear()
	for session_id in session_ids:
		G.local_session.local_session_ids.append(str(session_id))

	G.print(
		"Received %d session ID(s)" % G.local_session.local_session_ids.size(),
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS
	)

	# Player attributes were already generated when players joined lobby.
	# Verify they match the player count.
	if (
		G.local_session.local_player_attributes.size() !=
		G.local_session.local_session_ids.size()
	):
		G.error(
			"Attribute count mismatch: %d attributes, %d session IDs" % [
				G.local_session.local_player_attributes.size(),
				G.local_session.local_session_ids.size()
			]
		)

	# Connect to server.
	G.network.connector.client_connect_to_server(server_ip, server_port)


func _client_on_session_request_failed(error_message: String) -> void:
	G.check_is_client()

	G.log.alert_user(
		":( Something's busted on the backend!\n\n" +
		"Failed to obtain session IDs:\n%s" % error_message,
		ScaffolderLog.CATEGORY_CORE_SYSTEMS
	)

	client_exit_game()


func client_exit_game() -> void:
	G.check_is_client()

	G.local_session.is_game_active = false
	G.local_session.is_game_loading = false

	G.network.connector.client_disconnect()
	G.local_session.copy_latest_state()
	G.local_session.clear()
	G.screens.client_open_screen(ScreensMain.ScreenType.GAME_OVER)
	for level in levels:
		levels.erase(level)
		level.queue_free()
	G.level = null


func server_start_game() -> void:
	G.check_is_server()
	G.check(not G.local_session.is_game_active, "Game is already active")
	G.check(not is_instance_valid(G.level), "Level is already set")

	G.local_session.is_game_active = true

	# Reset timer state.
	G.match_state.match_start_time_usec = -1
	G.match_state.is_match_ended = false

	# TODO: Add in-game support for specifying which level to spawn on the server.

	_server_spawn_level(G.settings.default_level_scene)

	G.network.connector.server_enable_connections(G.network.server_port)


func server_end_game() -> void:
	G.check_is_server()
	G.check(G.local_session.is_game_active, "Game is not active")
	G.check_valid(G.level, "Level is not valid")

	G.local_session.is_game_active = false
	G.match_state.match_start_time_usec = -1
	G.match_state.is_match_ended = false

	G.network.connector.server_close_multiplayer_session()

	# TODO: Add support for tracking game stats in a separate backend database.

	_server_destroy_level(G.level)


func _process(_delta: float) -> void:
	if not G.network.is_server:
		return

	# Start timer when ready.
	if G.match_state.match_start_time_usec < 0:
		_server_check_start_match_timer()
		return

	# Check if time has expired.
	if not G.match_state.is_match_ended and G.match_state.is_match_time_expired:
		_server_initiate_match_end()


func _server_check_start_match_timer() -> void:
	if G.match_state.match_start_time_usec >= 0:
		return
	if not is_level_fully_loaded:
		return
	if not is_instance_valid(G.level):
		return

	# Start timer once level is loaded (sets match_start_time_usec).
	G.match_state.server_start_match_timer(G.settings.match_duration_sec)

	G.print(
		"Match timer started: %d seconds" % G.settings.match_duration_sec,
		ScaffolderLog.CATEGORY_GAME_STATE
	)


func _server_initiate_match_end() -> void:
	G.check_is_server()
	G.check(not G.match_state.is_match_ended, "Match end already initiated")

	G.print("Match time expired - initiating end sequence",
		ScaffolderLog.CATEGORY_GAME_STATE)

	# Set flag to enable invincibility for all players and notify clients.
	G.match_state.is_match_ended = true
	G.match_state._client_notify_match_ended.rpc()

	# Schedule server shutdown after wait period.
	G.time.set_timeout(
		server_end_game,
		G.settings.match_end_disconnect_delay_sec
	)


func on_return_to_game_from_screen(
		_previous_screen_type: ScreensMain.ScreenType) -> void:
	G.check(G.local_session.is_game_active, "Game is not active")
	G.check(
		not G.local_session.is_game_loading,
		"Game is still loading",
	)


func on_left_game_to_screen(_next_screen_type: ScreensMain.ScreenType) -> void:
	pass


func on_return_to_lobby_from_screen(
		_previous_screen_type: ScreensMain.ScreenType) -> void:
	_client_spawn_lobby()


func on_left_lobby_to_screen(_next_screen_type: ScreensMain.ScreenType) -> void:
	pass


func _server_spawn_level(level_scene: PackedScene) -> void:
	G.check_is_server()
	G.check(
		G.settings.level_scenes.has(level_scene),
		"level_scene not registered in settings: %s" % level_scene,
	)

	G.print(
		"Spawning level: %s" % Utils.get_display_name(level_scene),
		ScaffolderLog.CATEGORY_GAME_STATE,
	)

	var level: Level = level_scene.instantiate()
	levels.append(level)
	%Levels.add_child(level)
	G.level = level


func _server_destroy_level(level: Level) -> void:
	G.check_is_server()
	G.check(
		levels.has(level),
		"level not in current list: %s" % level,
	)

	G.print("Destroying level: %s" % level.get_string(),
		ScaffolderLog.CATEGORY_GAME_STATE)

	if G.level == level:
		G.level = null
	levels.erase(level)
	level.queue_free()


func on_level_added(level: Level) -> void:
	if G.network.is_client:
		G.level = level
		levels.append(level)


func on_level_removed(level: Level) -> void:
	if G.network.is_client:
		is_level_fully_loaded = false
		if G.level == level:
			G.level = null
		levels.erase(level)
