@tool
class_name Level
extends Node2D


@export var player_spawner: MultiplayerSpawner:
    set(value):
        player_spawner = value
        update_configuration_warnings()

## This is the location where all player nodes should be spawned.
@export var players_node: Node2D:
    set(value):
        players_node = value
        update_configuration_warnings()

var players: Array[Player] = []
# Dictionary<int, Player
var players_by_id := {}


func _enter_tree() -> void:
    G.game_panel.on_level_added(self)

    if G.network.is_server:
        # Add players nodes for already-connected clients.
        for multiplayer_id in multiplayer.get_peers():
            _server_add_player(multiplayer_id)

        # Listen for added/removed client connections, to maintain player nodes.
        multiplayer.peer_connected.connect(_server_add_player)
        multiplayer.peer_disconnected.connect(_server_remove_player)


func _ready() -> void:
    G.log.log_system_ready("Level")

    var warnings := _get_configuration_warnings()
    if not warnings.is_empty():
        G.error("Level._ready: %s (%s)" % [warnings[0], get_scene_file_path()])
        return

    for player_scene in G.settings.player_scenes:
        player_spawner.add_spawnable_scene(player_scene.resource_path)


func _exit_tree() -> void:
    G.game_panel.on_level_removed(self)
    multiplayer.peer_connected.disconnect(_server_add_player)
    multiplayer.peer_disconnected.disconnect(_server_remove_player)


func _server_add_player(multiplayer_id: int) -> void:
    var player: Player = G.settings.default_player_scene.instantiate()
    player.multiplayer_id = multiplayer_id
    player.global_position = _get_player_spawn_position()
    player.name = "Player_%s" % multiplayer_id
    players.append(player)
    players_by_id[multiplayer_id] = player
    players_node.add_child(player)


func _server_remove_player(multiplayer_id: int) -> void:
    # Find the player instance.
    var player: Player
    for p in players:
        if p.multiplayer_id == multiplayer_id:
            player = p
            break

    if not is_instance_valid(player):
        G.warning("Level._remove_player: No valid player found for the given ID: %s" %
            multiplayer_id,
            ScaffolderLog.CATEGORY_CORE_SYSTEMS)
        return

    players.erase(player)
    players_by_id.erase(multiplayer_id)
    player.queue_free()


func on_player_added(player: Player) -> void:
    if G.network.is_client:
        players.push_back(player)
        players_by_id[player.multiplayer_id] = player


func on_player_removed(player: Player) -> void:
    if G.network.is_client:
        players.erase(player)
        players_by_id.erase(player.multiplayer_id)


func _get_player_spawn_position() -> Vector2:
    # FIXME: Calculate player spawn position.
    return Vector2.ZERO


func _get_configuration_warnings() -> PackedStringArray:
    var warnings: PackedStringArray = []

    if not is_instance_valid(player_spawner):
        warnings.push_back("player_spawner must be set")
    if not is_instance_valid(players_node):
        warnings.push_back("players_node not set")

    return warnings
