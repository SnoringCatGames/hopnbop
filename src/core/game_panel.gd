class_name GamePanel
extends Node2D

var levels: Array[Level] = []

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

    %MatchStateSynchronizer.player_joined.connect(_on_player_joined)
    %MatchStateSynchronizer.player_left.connect(_on_player_left)
    %MatchStateSynchronizer.player_killed.connect(_on_player_killed)
    %MatchStateSynchronizer.players_bumped.connect(_on_players_bumped)


func _on_player_joined(player: PlayerMatchState) -> void:
    G.print("Player joined: %s" % player.get_string(), ScaffolderLog.CATEGORY_GAME_STATE)


func _on_player_left(player: PlayerMatchState) -> void:
    G.print("Player left: %s" % player.get_string(), ScaffolderLog.CATEGORY_GAME_STATE)


func _on_player_killed(killer: PlayerMatchState, killee: PlayerMatchState) -> void:
    G.print(
        "Player killed: %s killed %s" % [killer.get_string(), killee.get_string()],
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
    G.print("Level spawned: %s" % level.get_string(), ScaffolderLog.CATEGORY_GAME_STATE)


func _client_on_level_despawned(p_level: Node) -> void:
    G.ensure(p_level is Level)
    var level: Level = p_level
    G.print("Level despawned: %s" % level.get_string(), ScaffolderLog.CATEGORY_GAME_STATE)


func _network_process() -> void:
    pass


func _client_on_server_connected() -> void:
    G.check_is_client("NetworkMain._client_on_server_connected")
    G.check(
        G.local_session.is_game_loading,
        "GamePanel._client_on_server_connected: Game load is not expected",
    )
    G.check(
        not G.local_session.is_game_active,
        "GamePanel._client_on_server_connected: Game is already active",
    )

    G.local_session.is_game_loading = false
    G.local_session.is_game_active = true

    G.screens.client_open_screen(ScreensMain.ScreenType.GAME)


func _client_on_server_disconnected() -> void:
    G.check_is_client("NetworkMain._client_on_server_disconnected")

    client_exit_game()


func client_load_game() -> void:
    G.check_is_client("NetworkMain.client_load_game")
    G.check(
        not G.local_session.is_game_active,
        "GamePanel.client_load_game: Game is already active",
    )
    G.check(
        not G.local_session.is_game_loading,
        "GamePanel.client_load_game: Game is already loading",
    )
    G.check(not is_instance_valid(G.level), "GamePanel.client_load_game: Level is already set")

    G.local_session.clear()
    G.local_session.is_game_active = false
    G.local_session.is_game_loading = true

    G.screens.client_open_screen(ScreensMain.ScreenType.LOADING)

    G.network.connector.client_connect_to_server()


func client_exit_game() -> void:
    G.check_is_client("NetworkMain.client_exit_game")

    G.local_session.is_game_active = false
    G.local_session.is_game_loading = false

    G.network.connector.client_disconnect()
    G.local_session.copy_match_state()
    G.local_session.clear()
    G.screens.client_open_screen(ScreensMain.ScreenType.GAME_OVER)
    for level in levels:
        levels.erase(level)
        level.queue_free()
    G.level = null


func server_start_game() -> void:
    G.check_is_server("NetworkMain.server_start_game")
    G.check(
        not G.local_session.is_game_active,
        "GamePanel.server_start_game: Game is already active",
    )
    G.check(not is_instance_valid(G.level), "GamePanel.server_start_game: Level is already set")

    G.local_session.is_game_active = true

    # TODO: Add in-game support for specifying which level to spawn on the server.

    _server_spawn_level(G.settings.default_level_scene)

    G.network.connector.server_enable_connections()


func server_end_game() -> void:
    G.check_is_server("NetworkMain.server_end_game")
    G.check(G.local_session.is_game_active, "GamePanel.server_end_game: Game is not active")
    G.check_valid(G.level, "GamePanel.server_end_game: Level is not valid")

    G.local_session.is_game_active = false

    G.network.connector.server_close_multiplayer_session()

    # TODO: Add support for tracking game stats in a separate backend database.

    _server_destroy_level(G.level)


func on_return_from_screen() -> void:
    G.check(G.local_session.is_game_active, "GamePanel.on_return_from_screen: Game is not active")
    G.check(
        not G.local_session.is_game_loading,
        "GamePanel.on_return_from_screen: Game is still loading",
    )


func on_left_to_screen() -> void:
    pass


func _server_spawn_level(level_scene: PackedScene) -> void:
    G.check_is_server("NetworkMain._server_spawn_level")
    G.check(
        G.settings.level_scenes.has(level_scene),
        "GamePanel._server_spawn_level: level_scene not registered in settings: %s" % level_scene,
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
    G.check_is_server("NetworkMain._server_destroy_level")
    G.check(
        levels.has(level),
        "GamePanel._server_destroy_level: level not in current list: %s" % level,
    )

    G.print("Destroying level: %s" % level.get_string(), ScaffolderLog.CATEGORY_GAME_STATE)

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
        if G.level == level:
            G.level = null
        levels.erase(level)
