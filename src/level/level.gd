class_name Level
extends Node2D


@export var players_node: Node2D

var players: Array[Character] = []


func _enter_tree() -> void:
    G.level = self

    for multiplayer_id in multiplayer.get_peers():
        _add_player(multiplayer_id)
    get_multiplayer().peer_connected.connect(_add_player)
    get_multiplayer().peer_disconnected.connect(_remove_player)

    # FIXME
    pass
    #multiplayer.has_multiplayer_peer()
    #DisplayServer.get_name() == "headless"
    #multiplayer.is_server()
    G.args.has("server")


func _exit_tree() -> void:
    if G.level == self:
        G.level = null

    get_multiplayer().peer_connected.disconnect(_add_player)
    get_multiplayer().peer_disconnected.disconnect(_remove_player)


func _add_player(multiplayer_id: int) -> void:
    var player: Player = G.settings.player_scene.instantiate()
    player.multiplayer_id = multiplayer_id
    player.global_position = _get_player_spawn_position()
    player.name = "Player_%s" % multiplayer_id
    players.append(player)
    players_node.add_child(player)


func _remove_player(multiplayer_id: int) -> void:
    # Find the player instance.
    var player: Player
    for p in players:
        if p.multiplayer_id == multiplayer_id:
            player = p
            break

    if not is_instance_valid(player):
        G.log.warning("Level._remove_player: No valid player found for the given ID: %s" %
            multiplayer_id)
        return

    players.erase(player)
    player.queue_free()


func _get_player_spawn_position() -> Vector2:
    # FIXME: Calculate player spawn position.
    return Vector2.ZERO
