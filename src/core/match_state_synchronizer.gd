class_name MatchStateSynchronizer
extends MultiplayerSynchronizer


# FIXME: LEFT OFF HERE: Listen for these signals and log.
signal player_joined(player: PlayerMatchState)
signal player_left(player: PlayerMatchState)
signal player_killed(killer: PlayerMatchState, killee: PlayerMatchState)
signal players_bumped(a: PlayerMatchState, b: PlayerMatchState)

signal players_updated
signal kills_updated
signal bumps_updated


var state := MatchStateOld.new()
var _previous_state := MatchStateOld.new()


func _ready() -> void:
    if G.network.is_client:
        state.players_updated.connect(_client_on_players_updated)
        state.kills_updated.connect(_client_on_kills_updated)
        state.bumps_updated.connect(_client_on_bumps_updated)

    if G.network.is_server:
        multiplayer.peer_connected.connect(_server_on_peer_connected)
        multiplayer.peer_disconnected.connect(_server_on_peer_disconnected)


func clear() -> void:
    state.clear()
    _previous_state.clear()


func get_player(multiplayer_id: int) -> PlayerMatchState:
    if state.players_by_id.has(multiplayer_id):
        return state.players_by_id[multiplayer_id]
    else:
        return null


func _server_on_peer_connected(multiplayer_id: int) -> void:
    _server_recalculate_players()

    # Set connect time for this player.
    var player := get_player(multiplayer_id)
    player.connect_time_usec = G.network.server_time_usec_not_frame_aligned

    player_joined.emit(get_player(multiplayer_id))

    _server_trigger_player_replication()


func _server_on_peer_disconnected(multiplayer_id: int) -> void:
    _server_recalculate_players()

    # Set disconnect time for this player.
    var player := get_player(multiplayer_id)
    player.disconnect_time_usec = G.network.server_time_usec_not_frame_aligned

    player_left.emit(get_player(multiplayer_id))

    _server_trigger_player_replication()


func _server_recalculate_players() -> void:
    _previous_state.players = state.players.duplicate()
    _previous_state.players_by_id = state.players_by_id.duplicate()

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

    _client_report_added_and_removed_players()

    _previous_state.players = state.players.duplicate()
    _previous_state.players_by_id = state.players_by_id.duplicate()

    players_updated.emit()


func _client_report_added_and_removed_players() -> void:
    for player in state.players:
        if not _previous_state.players_by_id.has(player.multiplayer_id):
            player_joined.emit(player)

    for player in _previous_state.players:
        if not state.players_by_id.has(player.multiplayer_id):
            player_left.emit(player)


func _client_on_kills_updated() -> void:
    G.ensure(state.kills.size() > _previous_state.kills.size() or
        state.kills.is_empty())

    var new_kills := state.kills.slice(_previous_state.kills.size())
    var i := 0
    while i < new_kills.size():
        player_killed.emit(
            get_player(new_kills[i]),
            get_player(new_kills[i + 1]))
        i += 2

    _previous_state.kills = state.kills.duplicate()

    kills_updated.emit()


func _client_on_bumps_updated() -> void:
    G.ensure(state.bumps.size() > _previous_state.bumps.size() or
        state.bumps.is_empty())

    var new_bumps := state.bumps.slice(_previous_state.bumps.size())
    var i := 0
    while i < new_bumps.size():
        players_bumped.emit(
            get_player(new_bumps[i]),
            get_player(new_bumps[i + 1]))
        i += 2

    _previous_state.bumps = state.bumps.duplicate()

    bumps_updated.emit()


# TODO: Call server_add_kill.
func server_add_kill(killer_id: int, killee_id: int) -> void:
    _previous_state.kills = state.kills.duplicate()

    state.kills.append_array([killer_id, killee_id])
    state.kills = state.kills.duplicate()

    G.print("KILL: %s killed %s" % [killer_id, killee_id],
        ScaffolderLog.CATEGORY_GAME_STATE)

    player_killed.emit(get_player(killer_id), get_player(killee_id))
    kills_updated.emit()


# TODO: Call server_add_bump.
func server_add_bump(player_1_id: int, player_2_id: int) -> void:
    _previous_state.bumps = state.bumps.duplicate()

    state.bumps.append_array([player_1_id, player_2_id])
    state.bumps = state.bumps.duplicate()

    G.print("BUMP: %s bumped %s" % [player_1_id, player_2_id],
        ScaffolderLog.CATEGORY_GAME_STATE)

    players_bumped.emit(get_player(player_1_id), get_player(player_2_id))
    bumps_updated.emit()
