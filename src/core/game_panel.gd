class_name GamePanel
extends Node2D


var levels: Array[Level] = []


func _enter_tree() -> void:
    G.game_panel = self
    G.session = Session.new()


func _ready() -> void:
    G.log.print("GamePanel._ready", ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION)

    for level_scene in G.settings.level_scenes:
        %MultiplayerSpawner.add_spawnable_scene(level_scene.resource_path)


func client_load_game() -> void:
    if G.session.is_game_active:
        G.log.error("GamePanel.client_load_game: Game is already active")
        return
    if G.session.is_game_loading:
        G.log.error("GamePanel.client_load_game: Game is already loading")
        return
    if is_instance_valid(G.level):
        G.log.error("GamePanel.client_on_connected: Level is already set")
        return

    G.session.reset()
    G.session.is_game_active = false
    G.session.is_game_loading = true

    # FIXME: LEFT OFF HERE: ACTUALLY: !!!!!!!!!!!


func client_on_connected() -> void:
    # FIXME: Call this.
    if not G.session.is_game_loading:
        G.log.error("GamePanel.client_on_connected: Game load is not expected")
        return
    if G.session.is_game_active:
        G.log.error("GamePanel.client_on_connected: Game is already active")
        return
    G.session.is_game_loading = false
    G.session.is_game_active = true


func client_exit_game() -> void:
    G.session.is_game_active = false
    G.session.is_game_loading = false

    # FIXME: LEFT OFF HERE: ACTUALLY: !!!!!!!!!!!


func server_start_game() -> void:
    if G.session.is_game_active:
        G.log.error("GamePanel.server_end_game: Game is already active")
        return
    if is_instance_valid(G.level):
        G.log.error("GamePanel.server_end_game: Level is already set")
        return

    G.session.is_game_active = true

    # FIXME: LEFT OFF HERE: ACTUALLY: !!!!!!!!!!!

    # FIXME: Add support for configuring which level to spawn on the server.

    _server_spawn_level(G.settings.default_level_scene)


func server_end_game() -> void:
    if not G.session.is_game_active:
        G.log.error("GamePanel.server_end_game: Game is not active")
        return
    if not is_instance_valid(G.level):
        G.log.error("GamePanel.server_end_game: Level is not valid")
        return

    G.session.is_game_active = false

    # FIXME: LEFT OFF HERE: ACTUALLY: !!!!!!!!!!!

    _server_destroy_level(G.level)


func reset() -> void:
    # TODO
    pass


func on_return_from_screen() -> void:
    if not G.session.is_game_active:
        G.log.error("GamePanel.on_return_from_screen: Game is not active")
        return
    if G.session.is_game_loading:
        G.log.error("GamePanel.on_return_from_screen: Game is still loading")
        return


func _server_spawn_level(level_scene: PackedScene) -> void:
    if not G.settings.level_scenes.has(level_scene):
        G.log.error(
            "GamePanel._server_spawn_level: level_scene not registered in settings: %s" %
            level_scene)
        return

    var level: Level = level_scene.instantiate()
    levels.push_back(level)
    %Levels.add_child(level)
    G.level = level


func _server_destroy_level(level: Level) -> void:
    if not levels.has(level):
        G.log.error(
            "GamePanel._server_destroy_level: level not in current list: %s" %
            level)
        return

    if G.level == level:
        G.level = null
    levels.erase(level)
    level.queue_free()


func on_level_added(level: Level) -> void:
    if G.network.is_client:
        G.level = level
        levels.push_back(level)


func on_level_removed(level: Level) -> void:
    if G.network.is_client:
        if G.level == level:
            G.level = null
        levels.erase(level)
