class_name MatchStateSynchronizer
extends MultiplayerSynchronizer

signal player_joined(player: PlayerMatchState)
signal player_left(player: PlayerMatchState)
signal player_killed(killer: PlayerMatchState, killee: PlayerMatchState)
signal players_bumped(a: PlayerMatchState, b: PlayerMatchState)

signal players_updated
signal kills_updated
signal bumps_updated

var state := MatchState.new()
var _previous_state := MatchState.new()


func _ready() -> void:
	if G.network.is_client:
		state.players_updated.connect(_client_on_players_updated)
		state.kills_updated.connect(_client_on_kills_updated)
		state.bumps_updated.connect(_client_on_bumps_updated)

	if G.network.is_server:
		# Listen for player count declarations instead of raw peer connections.
		G.network.connector.peer_players_declared.connect(
			_server_on_peer_players_declared
		)
		multiplayer.peer_disconnected.connect(_server_on_peer_disconnected)

	state.player_connected.connect(_on_underlying_player_state_connected)
	state.player_disconnected.connect(_on_underlying_player_state_disconnected)


func clear() -> void:
	state.clear()
	_previous_state.clear()


func get_player(player_id: StringName) -> PlayerMatchState:
	if state.players.has(player_id):
		return state.players[player_id]
	else:
		return null


func _server_on_peer_players_declared(
	peer_id: int,
	player_count: int,
	_session_ids: Array
) -> void:
	# Create N PlayerMatchState objects for this peer.
	for i in range(player_count):
		var player_id := NetworkConnector.get_player_id(peer_id, i)
		G.ensure(not state.players.has(player_id))

		var player := PlayerMatchState.new()
		player.set_up(player_id, true)
		player.connect_time_usec = (
			G.network.server_time_usec_not_frame_aligned
		)
		state.server_add_player(player)

	players_updated.emit()


func _server_on_peer_disconnected(peer_id: int) -> void:
	# Handle all players for this peer.
	var players_for_peer: Array[PlayerMatchState] = (
		state.get_players_for_peer(peer_id)
	)

	for player in players_for_peer:
		if G.ensure(state.players.has(player.player_id)):
			# Set disconnect time for this player.
			player.disconnect_time_usec = (
				G.network.server_time_usec_not_frame_aligned
			)

		state.server_on_player_disconnected(player)

	players_updated.emit()


func _client_on_players_updated() -> void:
	players_updated.emit()


func _client_on_kills_updated() -> void:
	G.ensure(state.kills.size() > _previous_state.kills.size() or state.kills.is_empty())

	var new_kills := state.kills.slice(_previous_state.kills.size())
	var i := 0
	while i < new_kills.size():
		player_killed.emit(get_player(new_kills[i]), get_player(new_kills[i + 1]))
		i += 2

	_previous_state.kills = state.kills.duplicate()

	kills_updated.emit()


func _client_on_bumps_updated() -> void:
	G.ensure(state.bumps.size() > _previous_state.bumps.size() or state.bumps.is_empty())

	var new_bumps := state.bumps.slice(_previous_state.bumps.size())
	var i := 0
	while i < new_bumps.size():
		players_bumped.emit(get_player(new_bumps[i]), get_player(new_bumps[i + 1]))
		i += 2

	_previous_state.bumps = state.bumps.duplicate()

	bumps_updated.emit()


func _on_underlying_player_state_connected(player: PlayerMatchState) -> void:
	player_joined.emit(player)


func _on_underlying_player_state_disconnected(player: PlayerMatchState) -> void:
	player_left.emit(player)


# TODO: Call server_add_kill.
func server_add_kill(killer_id: StringName, killee_id: StringName) -> void:
	_previous_state.kills = state.kills.duplicate()

	state.kills.append_array([killer_id, killee_id])
	state.kills = state.kills.duplicate()

	G.print(
		"KILL: %s killed %s" % [killer_id, killee_id],
		ScaffolderLog.CATEGORY_GAME_STATE
	)

	player_killed.emit(get_player(killer_id), get_player(killee_id))
	kills_updated.emit()


# TODO: Call server_add_bump.
func server_add_bump(player_1_id: StringName, player_2_id: StringName) -> void:
	_previous_state.bumps = state.bumps.duplicate()

	state.bumps.append_array([player_1_id, player_2_id])
	state.bumps = state.bumps.duplicate()

	G.print(
		"BUMP: %s bumped %s" % [player_1_id, player_2_id],
		ScaffolderLog.CATEGORY_GAME_STATE
	)

	players_bumped.emit(get_player(player_1_id), get_player(player_2_id))
	bumps_updated.emit()
