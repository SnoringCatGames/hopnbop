class_name MatchStateSynchronizer
extends MultiplayerSynchronizer


signal player_joined(multiplayer_id: int)
signal player_left(multiplayer_id: int)
signal players_updated
signal kills_updated
signal bumps_updated

var state := MatchState.new()


func _ready() -> void:
    if G.network.is_client:
        state.players_updated.connect(_client_on_players_updated)

    if G.network.is_server:
        multiplayer.peer_connected.connect(_server_on_peer_connected)
        multiplayer.peer_disconnected.connect(_server_on_peer_disconnected)


func clear() -> void:
    state.clear()


func _server_on_peer_connected(multiplayer_id: int) -> void:
    _server_recalculate_players()

    # Set connect time for this player.
    var player: PlayerMatchState = state.players_by_id[multiplayer_id]
    player.connect_time_usec = G.network.time.get_server_time_usec()

    _server_trigger_player_replication()

    G.print("Player joined game: %s" % player.get_string(),
        ScaffolderLog.CATEGORY_GAME_STATE)

    player_joined.emit(multiplayer_id)


func _server_on_peer_disconnected(multiplayer_id: int) -> void:
    _server_recalculate_players()

    # Set disconnect time for this player.
    var player: PlayerMatchState = state.players_by_id[multiplayer_id]
    player.connect_time_usec = G.network.disconnect_time_usec

    _server_trigger_player_replication()

    G.print("Player left game: %s" % player.get_string(),
        ScaffolderLog.CATEGORY_GAME_STATE)

    player_left.emit(multiplayer_id)


## This will ensure all connect peers are accounted for, and will then trigger
## an RPC to update clients with the latest player match state.
func server_update_players() -> void:
    _server_recalculate_players()
    _server_trigger_player_replication()


func _server_recalculate_players() -> void:
    for peer_id in multiplayer.get_peers():
        if not state.players_by_id.has(peer_id):
            var new_state := PlayerMatchState.new()
            new_state.set_up(peer_id, true)

            state.players.push_back(new_state)
            state.players_by_id[peer_id] = new_state


func _server_trigger_player_replication() -> void:
    # Assign a new instance of the array in order to force replication of the
    # mutated state (otherwise, Godot's networking logic won't detect that the
    # array was changed).
    state.players = state.players.duplicate()

    players_updated.emit()


func _client_on_players_updated() -> void:
    # Sync the Dictionary to match the Array.
    state.players_by_id.clear()
    for player in state.players:
        state.players_by_id[player.multiplayer_id] = player


# TODO: Call server_add_kill.
func server_add_kill(killer_id: int, killee_id: int) -> void:
    state.kills.append_array([killer_id, killee_id])
    state.kills = state.kills.duplicate()

    G.print("KILL: %s killed %s" % [killer_id, killee_id],
        ScaffolderLog.CATEGORY_GAME_STATE)

    kills_updated.emit()


# TODO: Call server_add_bump.
func server_add_bump(player_1_id: int, player_2_id: int) -> void:
    state.bumps.append_array([player_1_id, player_2_id])
    state.bumps = state.bumps.duplicate()

    G.print("BUMP: %s bumped %s" % [player_1_id, player_2_id],
        ScaffolderLog.CATEGORY_GAME_STATE)

    bumps_updated.emit()
