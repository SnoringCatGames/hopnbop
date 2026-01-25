class_name MatchState
extends RefCounted

signal player_connected(player: PlayerMatchState)
signal player_disconnected(player: PlayerMatchState)

signal players_updated
signal kills_updated
signal bumps_updated

# Dictionary<int, PlayerMatchState>
var players_by_id: Dictionary = {}

## - We maintain both a packed Array of player state as well as a redundant
##   Dictionary of player state.
## - The Array is used for replicating state more efficiently from the server.
## - The Dictionary is then derived from the Array, and is used for more
##   efficient local look-ups.
var packed_players := []:
	set(value):
		packed_players = value
		if not _is_packing_state_locally:
			_client_unpack_players()
			players_updated.emit()

## Every even index marks a 2-player pair.
##
## Every even index is the killer, and every odd index is the killee for the
## prior index.
var kills: PackedInt32Array = []:
	set(value):
		kills = value
		kills_updated.emit()

## A bump happens when two bunnies collide, but neither dies.
##
## Every even index marks a 2-player pair.
var bumps: PackedInt32Array = []:
	set(value):
		bumps = value
		bumps_updated.emit()

var _is_packing_state_locally := false

# Dictionary<int, bool>
var _connected_players := {}


func clear() -> void:
	players_by_id.clear()
	packed_players.clear()
	kills.clear()
	bumps.clear()


func duplicate() -> MatchState:
	var copy := MatchState.new()
	copy.players_by_id = players_by_id.duplicate()
	copy.packed_players = packed_players.duplicate()
	copy.kills = kills.duplicate()
	copy.bumps = bumps.duplicate()
	return copy


func server_add_player(player: PlayerMatchState) -> void:
	players_by_id[player.player_id] = player
	_server_pack_players()
	_connected_players[player.player_id] = true
	player_connected.emit(player)
	players_updated.emit()


func server_on_player_disconnected(player: PlayerMatchState) -> void:
	_connected_players.erase(player.player_id)
	player_disconnected.emit(player)


func get_players_for_peer(peer_id: int) -> Array[PlayerMatchState]:
	var result: Array[PlayerMatchState] = []
	for player_id in players_by_id:
		var player: PlayerMatchState = players_by_id[player_id]
		if player.peer_id == peer_id:
			result.append(player)
	return result


func _server_pack_players() -> void:
	var new_packed_players := []
	new_packed_players.resize(players_by_id.size())
	var i := 0
	for player_id in players_by_id:
		new_packed_players[i] = players_by_id[player_id].get_packed_state()
		i += 1

	_is_packing_state_locally = true
	packed_players = new_packed_players
	_is_packing_state_locally = false


func _client_unpack_players() -> void:
	players_by_id.clear()

	for packed_player in packed_players:
		var player_id := PlayerMatchState.get_player_id_from_packed_state(packed_player)

		if not players_by_id.has(player_id):
			players_by_id[player_id] = PlayerMatchState.new()

		var player: PlayerMatchState = players_by_id[player_id]
		player.populate_from_packed_state(packed_player)

	# Trigger connected/disconnected events.
	for player_id in players_by_id:
		var player: PlayerMatchState = players_by_id[player_id]
		if player.is_connected_to_server != _connected_players.has(player_id):
			if player.is_connected_to_server:
				_connected_players[player_id] = true
				player_connected.emit(player)
			else:
				_connected_players.erase(player_id)
				player_disconnected.emit(player)
