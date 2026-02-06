class_name GameMatchState
extends MatchManager
## Jump 'n Thump specific match state with kills, bumps, and scoring.

# --- Game-Specific Interaction Types ---

## Interaction types for deduplication.
enum InteractionType {
	UNKNOWN,
	BUMP,
	KILL,
}

# --- Game-Specific Constants ---

## Scoring constants.
const _KILL_SCORE := 100
const _DEATH_PENALTY := 90
const _BUMP_SCORE := 5
const _RANK_BONUS_PER_DIFF := 5
const _SELF_KILL_PENALTY := 45

## Interaction deduplication window (frames).
const _INTERACTION_DEDUPLICATION_WINDOW_FRAMES := 4

# --- Game-Specific Signals ---

## Emitted when a player kills another player.
signal player_killed(killer: PlayerMatchState, killee: PlayerMatchState)

## Emitted when two players bump.
signal players_bumped(a: PlayerMatchState, b: PlayerMatchState)

## Emitted when kills array changes.
signal kills_updated

## Emitted when bumps array changes.
signal bumps_updated

# --- Game-Specific State ---

## Every even index is the killer, every odd index is the killee.
var kills: PackedInt32Array = []

## Every even index marks a 2-player bump pair.
var bumps: PackedInt32Array = []

# Dictionary<int, int>
var _total_kills_by_player_id := {}
# Dictionary<int, int>
var _total_deaths_by_player_id := {}
# Dictionary<int, int>
var _total_bumps_by_player_id := {}

# Dictionary<int, int> - Maps peer_id to number of pauses used.
# Replicated from server to clients via MatchStateSynchronizer.
var pauses_used_by_peer: Dictionary = {}

# Interaction deduplication.
var _server_recent_interactions: RollbackBuffer
var _interaction_tracker: InteractionTracker

# Dictionary<int, bool>
var _connected_players := {}

var _is_packing_state_locally := false

## Shadow parent's packed_players to add game-specific unpacking logic.
## When this property changes from network replication, trigger
## _client_unpack_players().
var packed_players := []:
	set(value):
		if Netcode.log.is_verbose:
			Netcode.log.verbose(
				("GameMatchState.packed_players setter: " +
				"old_size=%d, new_size=%d, is_packing_locally=%s") % [
					packed_players.size(),
					value.size(),
					_is_packing_state_locally
				],
				NetworkLogger.CATEGORY_NETWORK_SYNC,
			)
		packed_players = value
		if not _is_packing_state_locally:
			_client_unpack_players()
			players_updated.emit()


# --- Public API ---


func clear() -> void:
	players_by_id.clear()
	packed_players.clear()
	kills.clear()
	bumps.clear()
	pauses_used_by_peer.clear()
	_total_kills_by_player_id.clear()
	_total_deaths_by_player_id.clear()
	_total_bumps_by_player_id.clear()
	_connected_players.clear()
	# Reset interaction deduplication buffer and tracker if they exist.
	if _server_recent_interactions != null:
		_server_recent_interactions = null
		_interaction_tracker = null
	match_start_frame_index = -1
	match_duration_usec = 0
	is_match_ended = false


func client_notify_match_started(
	_match_start_frame_index: int,
	_match_duration_usec: int
) -> void:
	match_start_frame_index = _match_start_frame_index
	match_duration_usec = _match_duration_usec


func client_notify_match_ended() -> void:
	is_match_ended = true
	match_ended.emit()


func duplicate() -> GameMatchState:
	var copy := GameMatchState.new()
	copy.players_by_id = players_by_id.duplicate()
	copy.packed_players = packed_players.duplicate()
	copy.kills = kills.duplicate()
	copy.bumps = bumps.duplicate()
	return copy


func server_start_match_timer(duration_sec: float) -> void:
	match_start_frame_index = Netcode.server_frame_index
	match_duration_usec = int(duration_sec * 1_000_000)

	# Notify all clients.
	if synchronizer:
		synchronizer._rpc_client_notify_match_started.rpc(
			match_start_frame_index,
			match_duration_usec
		)


func server_add_kill(killer_id: int, killee_id: int) -> void:
	var current_frame: int = Netcode.frame_driver.server_frame_index

	# Check for recent interaction to prevent duplicates.
	if _server_has_recent_interaction(
		killer_id,
		killee_id,
		current_frame,
		InteractionType.KILL
	):
		return # Already recorded within window.

	# Record in replicated arrays.
	kills.append_array([killer_id, killee_id])
	kills = kills.duplicate()

	# Update kill/death counts.
	if not _total_kills_by_player_id.has(killer_id):
		_total_kills_by_player_id[killer_id] = 0
	_total_kills_by_player_id[killer_id] += 1

	if not _total_deaths_by_player_id.has(killee_id):
		_total_deaths_by_player_id[killee_id] = 0
	_total_deaths_by_player_id[killee_id] += 1

	# Store in indelible interaction buffer.
	_server_store_interaction(
		killer_id,
		killee_id,
		InteractionType.KILL,
		current_frame
	)

	# Update scores and emit events.
	# Note: Game code should connect to player_killed signal to handle
	# respawn logic.
	Netcode.log.verbose(
		"KILL: %s killed %s" % [killer_id, killee_id],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	update_scores()

	var killer_match_state: PlayerMatchState = players_by_id.get(killer_id)
	var killee_match_state: PlayerMatchState = players_by_id.get(killee_id)
	if killer_match_state and killee_match_state:
		emit_kill_event(killer_match_state, killee_match_state)

	kills_updated.emit()


func emit_kill_event(
	killer: PlayerMatchState,
	killee: PlayerMatchState
) -> void:
	player_killed.emit(killer, killee)


func server_add_bump(player_1_id: int, player_2_id: int) -> void:
	var current_frame: int = Netcode.frame_driver.server_frame_index

	# Check for recent interaction to prevent duplicates.
	if _server_has_recent_interaction(
		player_1_id,
		player_2_id,
		current_frame,
		InteractionType.BUMP
	):
		return # Already recorded within window.

	# Record in replicated arrays.
	bumps.append_array([player_1_id, player_2_id])
	bumps = bumps.duplicate()

	# Update bump counts for both players.
	if not _total_bumps_by_player_id.has(player_1_id):
		_total_bumps_by_player_id[player_1_id] = 0
	_total_bumps_by_player_id[player_1_id] += 1

	if not _total_bumps_by_player_id.has(player_2_id):
		_total_bumps_by_player_id[player_2_id] = 0
	_total_bumps_by_player_id[player_2_id] += 1

	# Store in indelible interaction buffer.
	_server_store_interaction(
		player_1_id,
		player_2_id,
		InteractionType.BUMP,
		current_frame
	)

	# Update scores and emit events.
	Netcode.log.verbose(
		"BUMP: %s bumped %s" % [player_1_id, player_2_id],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	update_scores()

	var player_1_match_state: PlayerMatchState = \
			players_by_id.get(player_1_id)
	var player_2_match_state: PlayerMatchState = \
			players_by_id.get(player_2_id)
	if player_1_match_state and player_2_match_state:
		emit_bump_event(player_1_match_state, player_2_match_state)

	bumps_updated.emit()


func emit_bump_event(a: PlayerMatchState, b: PlayerMatchState) -> void:
	players_bumped.emit(a, b)


func server_on_player_disconnected(player: PlayerMatchState) -> void:
	_connected_players.erase(player.player_id)
	player_left.emit(player)
	players_updated.emit()


## Calculates the score for each player based on kills, deaths, bumps, and
## rank differences.
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


# --- Internal Methods ---


func _get_server_recent_interactions() -> RollbackBuffer:
	if _server_recent_interactions == null:
		_server_recent_interactions = RollbackBuffer.new(
			Netcode.frame_driver.rollback_buffer_size,
			0, # current_frame_index (start at 0)
			[] # default_frame_state (empty array for interactions)
		)
		# Initialize interaction tracker with rollback buffer.
		_interaction_tracker = InteractionTracker.new(
			_server_recent_interactions
		)
		_interaction_tracker.deduplication_window_frames = \
			_INTERACTION_DEDUPLICATION_WINDOW_FRAMES
	return _server_recent_interactions


func _server_has_recent_interaction(
	player_1_id: int,
	player_2_id: int,
	current_frame: int,
	interaction_type: int
) -> bool:
	# Ensure interaction tracker is initialized.
	if _interaction_tracker == null:
		_get_server_recent_interactions()

	return _interaction_tracker.has_recent_interaction(
		player_1_id,
		player_2_id,
		current_frame,
		interaction_type
	)


func _server_store_interaction(
	player_1_id: int,
	player_2_id: int,
	interaction_type: int,
	frame_index: int
) -> void:
	# Ensure interaction tracker is initialized.
	if _interaction_tracker == null:
		_get_server_recent_interactions()

	_interaction_tracker.record_interaction(
		player_1_id,
		player_2_id,
		frame_index,
		interaction_type
	)


## Override parent to handle game-specific unpacking logic.
func _client_unpack_players() -> void:
	Netcode.log.verbose(
		"GameMatchState._client_unpack_players: " + \
				"packed_players.size=%d" % packed_players.size(),
		NetworkLogger.CATEGORY_GAME_STATE
	)

	players_by_id.clear()

	for packed_player in packed_players:
		var player_id := \
				PlayerMatchState.get_player_id_from_packed_state(
					packed_player
				)

		if not players_by_id.has(player_id):
			players_by_id[player_id] = PlayerMatchState.new()

		var player: PlayerMatchState = players_by_id[player_id]
		player.populate_from_packed_state(packed_player)

	# Trigger connected/disconnected events.
	for player_id in players_by_id:
		var player: PlayerMatchState = players_by_id[player_id]
		if player.is_connected_to_server != \
				_connected_players.has(player_id):
			if player.is_connected_to_server:
				_connected_players[player_id] = true
				player_joined.emit(player)
			else:
				_connected_players.erase(player_id)
				player_left.emit(player)


## Override parent to handle synchronizer packing flag.
func _server_pack_players() -> void:
	if Netcode.log.is_verbose:
		Netcode.log.verbose(
			"GameMatchState._server_pack_players: " + \
					"packing %d players" % players_by_id.size(),
			NetworkLogger.CATEGORY_GAME_STATE,
		)

	var new_packed_players := []
	new_packed_players.resize(players_by_id.size())
	var i := 0
	for player_id in players_by_id:
		new_packed_players[i] = \
				players_by_id[player_id].get_packed_state()
		i += 1

	_is_packing_state_locally = true
	packed_players = new_packed_players
	_is_packing_state_locally = false

	# Emit players_updated on server side (clients get it via replication
	# setter).
	players_updated.emit()
