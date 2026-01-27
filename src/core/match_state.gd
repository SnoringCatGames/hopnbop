class_name MatchState
extends RefCounted


# Scoring constants
const _KILL_SCORE := 100
const _DEATH_PENALTY := 90
const _BUMP_SCORE := 5
const _RANK_BONUS_PER_DIFF := 5
const _SELF_KILL_PENALTY := 45


signal player_joined(player: PlayerMatchState)
signal player_left(player: PlayerMatchState)
signal player_killed(killer: PlayerMatchState, killee: PlayerMatchState)
signal players_bumped(a: PlayerMatchState, b: PlayerMatchState)

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
		# FIXME: REMOVE
		G.print(
			"MatchState.packed_players setter: old_size=%d, new_size=%d, is_packing_locally=%s" % [
				packed_players.size(),
				value.size(),
				_is_packing_state_locally
			],
			ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
		)
		packed_players = value
		if not _is_packing_state_locally:
			_client_unpack_players()
			players_updated.emit()

## Every even index marks a 2-player pair.
##
## Every even index is the killer, and every odd index is the killee for the
## prior index.
var kills: PackedInt32Array = []

## A bump happens when two bunnies collide, but neither dies.
##
## Every even index marks a 2-player pair.
var bumps: PackedInt32Array = []

# Dictionary<int, int>
var _total_kills_by_player_id := {}
# Dictionary<int, int>
var _total_deaths_by_player_id := {}
# Dictionary<int, int>
var _total_bumps_by_player_id := {}

var _recent_interactions := CircularBuffer.new(
	G.network.frame_driver.rollback_buffer_size)

var _is_packing_state_locally := false

# Dictionary<int, int> - Maps peer_id to number of pauses used.
# Replicated from server to clients via MatchStateSynchronizer.
var pauses_used_by_peer: Dictionary = {}

# Dictionary<int, bool>
var _connected_players := {}


func clear() -> void:
	players_by_id.clear()
	packed_players.clear()
	kills.clear()
	bumps.clear()
	pauses_used_by_peer.clear()
	_total_kills_by_player_id.clear()
	_total_deaths_by_player_id.clear()
	_total_bumps_by_player_id.clear()


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
	player_joined.emit(player)
	players_updated.emit()


func server_add_kill(killer_id: int, killee_id: int) -> void:
	kills.append_array([killer_id, killee_id])
	kills = kills.duplicate()

	if not _total_kills_by_player_id.has(killer_id):
		_total_kills_by_player_id[killer_id] = 0
	_total_kills_by_player_id[killer_id] += 1

	if not _total_deaths_by_player_id.has(killee_id):
		_total_deaths_by_player_id[killee_id] = 0
	_total_deaths_by_player_id[killee_id] += 1

	var interaction := PlayerInteraction.new()
	interaction.player_1_id = killer_id
	interaction.player_2_id = killee_id
	interaction.type = PlayerInteraction.Type.KILL
	# FIXME: LEFT OFF HERE: Record in buffer at the right frame.
	#_recent_interactions

	kills_updated.emit()


func emit_kill_event(killer: PlayerMatchState, killee: PlayerMatchState) -> void:
	player_killed.emit(killer, killee)


func server_add_bump(player_1_id: int, player_2_id: int) -> void:
	bumps.append_array([player_1_id, player_2_id])
	bumps = bumps.duplicate()

	if not _total_bumps_by_player_id.has(player_1_id):
		_total_bumps_by_player_id[player_1_id] = 0
	_total_bumps_by_player_id[player_1_id] += 1

	if not _total_bumps_by_player_id.has(player_2_id):
		_total_bumps_by_player_id[player_2_id] = 0
	_total_bumps_by_player_id[player_2_id] += 1

	var interaction := PlayerInteraction.new()
	interaction.player_1_id = player_1_id
	interaction.player_2_id = player_2_id
	interaction.type = PlayerInteraction.Type.KILL
	# FIXME: LEFT OFF HERE: Record in buffer at the right frame.
	#_recent_interactions

	bumps_updated.emit()


func emit_bump_event(a: PlayerMatchState, b: PlayerMatchState) -> void:
	players_bumped.emit(a, b)


func server_on_player_disconnected(player: PlayerMatchState) -> void:
	_connected_players.erase(player.player_id)
	player_left.emit(player)
	players_updated.emit()


func get_players_for_peer(peer_id: int) -> Array[PlayerMatchState]:
	var result: Array[PlayerMatchState] = []
	for player_id in players_by_id:
		var player: PlayerMatchState = players_by_id[player_id]
		if player.peer_id == peer_id:
			result.append(player)
	return result


func _server_pack_players() -> void:
	if G.is_verbose:
		G.print(
			"MatchState._server_pack_players: packing %d players" % players_by_id.size(),
			ScaffolderLog.CATEGORY_GAME_STATE,
			ScaffolderLog.Verbosity.VERBOSE,
		)

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
	G.print(
		"MatchState._client_unpack_players: packed_players.size=%d" %
			packed_players.size(),
		ScaffolderLog.CATEGORY_GAME_STATE,
		ScaffolderLog.Verbosity.VERBOSE
	)

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
				player_joined.emit(player)
			else:
				_connected_players.erase(player_id)
				player_left.emit(player)


## Calculates the score for each player based on kills, deaths, bumps, and rank
## differences.
## - Kills: +KILL_SCORE, plus linear bonus for killing higher-ranked players
## - Deaths: -DEATH_PENALTY, plus penalty for being killed by lower-ranked
##           players
## - Self-kills: -SELF_KILL_PENALTY
## - Bumps: +BUMP_SCORE per bump
func update_scores() -> void:
	var all_player_ids := players_by_id.keys()

	# Calculate base scores.
	# Dictionary<int, int>
	var scores := {}
	for player_id in all_player_ids:
		scores[player_id] = (
			_total_kills_by_player_id.get(player_id, 0) -
			_total_deaths_by_player_id.get(player_id, 0)
		)

	# Calculate base ranks.
	all_player_ids.sort_custom(func(a, b): return scores[b] - scores[a])
	# Dictionary<int, int>
	var ranks := {}
	for i in range(all_player_ids.size()):
		ranks[all_player_ids[i]] = i

	# Calculate final scores with bonuses/penalties.
	for player_id in all_player_ids:
		var score = 0
		var bumps_count: int = _total_bumps_by_player_id.get(player_id, 0)
		score += bumps_count * _BUMP_SCORE
		for i in range(0, kills.size(), 2):
			var killer = kills[i]
			var killee = kills[i + 1]
			if killer == player_id and killee == player_id:
				score -= _SELF_KILL_PENALTY
			elif killer == player_id:
				var victim_rank = ranks.get(killee, ranks[player_id])
				var my_rank = ranks[player_id]
				var rank_diff = my_rank - victim_rank
				var bonus = 0
				if rank_diff > 0:
					bonus = rank_diff * _RANK_BONUS_PER_DIFF
				score += _KILL_SCORE + bonus
			elif killee == player_id:
				var killer_rank = ranks.get(killer, ranks[player_id])
				var my_rank = ranks[player_id]
				var rank_diff = killer_rank - my_rank
				var penalty = 0
				if rank_diff > 0:
					penalty = rank_diff * _RANK_BONUS_PER_DIFF
				score -= _DEATH_PENALTY + penalty
		scores[player_id] = score

	# Record final ranks and scores.
	all_player_ids.sort_custom(func(a, b): return scores[b] - scores[a])
	for i in range(all_player_ids.size()):
		var player_id: int = all_player_ids[i]
		players_by_id.get(player_id).rank = i + 1
		players_by_id.get(player_id).score = scores[player_id]
