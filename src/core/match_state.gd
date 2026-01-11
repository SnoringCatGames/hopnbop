class_name MatchState
extends MultiplayerSynchronizer


signal players_updated
signal kills_updated
signal bumps_updated


## - We maintain both an Array of players as well as a redundant Dictionary of
##   players.
## - The Array is used for replicating state more efficiently from the server.
## - The Dictionary is then derived from the Array, and is used for more
##   efficient local look-ups.
var players: Array[PlayerMatchState] = []:
    set(value):
        players = value
        if G.network.is_client:
            _client_on_players_updated()
# Dictionary<int, PlayerMatchState>
var players_by_id: Dictionary = {}

## Every even index marks a 2-player pair.
##
## Every even index is the killer, and every odd index is the killee for the
## prior index.
var kills: PackedInt32Array = []

## A bump happens when two bunnies collide, but neither dies.
##
## Every even index marks a 2-player pair.
var bumps: PackedInt32Array = []


func _ready() -> void:
    if G.network.is_server:
        multiplayer.peer_connected.connect(_server_on_peer_connected)
        multiplayer.peer_disconnected.connect(_server_on_peer_disconnected)


func _server_on_peer_connected(multiplayer_id: int) -> void:
    _server_recalculate_players()

    # Set connect time for this player.
    for player in players:
        if player.multiplayer_id == multiplayer_id:
            player.connect_time_usec = G.network.server_time_usec
            break

    _server_trigger_player_replication()


func _server_on_peer_disconnected(multiplayer_id: int) -> void:
    _server_recalculate_players()

    # Set disconnect time for this player.
    for player in players:
        if player.multiplayer_id == multiplayer_id:
            player.disconnect_time_usec = G.network.server_time_usec
            break

    _server_trigger_player_replication()


## This will ensure all connect peers are accounted for, and will then trigger
## an RPC to update clients with the latest player match state.
func server_update_players() -> void:
    _server_recalculate_players()
    _server_trigger_player_replication()


func _server_recalculate_players() -> void:
    for peer_id in multiplayer.get_peers():
        if not players_by_id.has(peer_id):
            var new_state := PlayerMatchState.new()
            new_state.set_up(peer_id, true)

            players.push_back(new_state)
            players_by_id[peer_id] = new_state


func _server_trigger_player_replication() -> void:
    # Assign a new instance of the array in order to force replication of the
    # mutated state (otherwise, Godot's networking logic won't detect that the
    # array was changed).
    players = players.duplicate()

    players_updated.emit()


func _client_on_players_updated() -> void:
    # Sync the Dictionary to match the Array.
    players_by_id.clear()
    for player in players:
        players_by_id[player.multiplayer_id] = player


# FIXME: Call server_add_kill.
func server_add_kill(killer_id: int, killee_id: int) -> void:
    kills.append_array([killer_id, killee_id])
    kills = kills.duplicate()

    kills_updated.emit()


# FIXME: Call server_add_bump.
func server_add_bump(player_1_id: int, player_2_id: int) -> void:
    bumps.append_array([player_1_id, player_2_id])
    bumps = bumps.duplicate()

    bumps_updated.emit()
