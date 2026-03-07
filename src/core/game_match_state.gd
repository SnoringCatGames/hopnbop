class_name GameMatchState
extends MatchState
## Hop 'n Bop specific match state with kills, bumps, and scoring.

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
const _DEATH_PENALTY := 20
const _BUMP_SCORE := 5
const _RANK_BONUS_PER_DIFF := 5
const _SELF_KILL_PENALTY := 45

## Interaction deduplication window (frames).
const _INTERACTION_DEDUPLICATION_WINDOW_FRAMES := 4

# --- Game-Specific Signals ---

## Emitted when a player kills another player.
signal player_killed(killer: PlayerState, killee: PlayerState)

## Emitted when two players bump.
signal players_bumped(a: PlayerState, b: PlayerState)

## Emitted when kills array changes.
signal kills_updated

## Emitted when bumps array changes.
signal bumps_updated

# --- Game-Specific State ---

## Every even index is the killer, every odd index is the killee.
## Has a setter to trigger kills_updated signal when replicated to clients.
var kills: PackedInt32Array = []:
	set(value):
		kills = value
		if not _is_modifying_kills_locally:
			kills_updated.emit()

## Every even index marks a 2-player bump pair.
## Has a setter to trigger bumps_updated signal when replicated to clients.
var bumps: PackedInt32Array = []:
	set(value):
		bumps = value
		if not _is_modifying_bumps_locally:
			bumps_updated.emit()

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

# --- Gameplay Stats Tracking ---

# Dictionary<int, PlayerMatchStats>
var _stats_by_player_id := {}

var _is_packing_state_locally := false
var _is_modifying_kills_locally := false
var _is_modifying_bumps_locally := false


# --- Public API ---


func _create_player_state() -> PlayerState:
	return GamePlayerState.new()


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
	_stats_by_player_id.clear()
	# Reset interaction deduplication buffer and tracker if they exist.
	if _server_recent_interactions != null:
		_server_recent_interactions = null
		_interaction_tracker = null
	match_start_frame_index = -1
	match_duration_usec = 0
	is_match_ended = false


## Returns the PlayerMatchStats for the given
## player, creating one if it doesn't exist yet.
func server_get_or_create_stats(
	player_id: int,
) -> PlayerMatchStats:
	if not _stats_by_player_id.has(player_id):
		_stats_by_player_id[player_id] = (
			PlayerMatchStats.new())
	return _stats_by_player_id[player_id]


## Returns the PlayerMatchStats for the given
## player, or null if none exists. Works on both
## server (where stats accumulate locally) and
## client (where stats arrive via RPC).
func get_player_stats(
	player_id: int,
) -> PlayerMatchStats:
	return _stats_by_player_id.get(player_id)


## Stores replicated stats for a player
## (client-side).
func client_store_stats(
	player_id: int,
	stats: PlayerMatchStats,
) -> void:
	_stats_by_player_id[player_id] = stats


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
	copy._stats_by_player_id = (
		_stats_by_player_id.duplicate())
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
	# Use flag to prevent setter from emitting signal (we emit manually below).
	_is_modifying_kills_locally = true
	kills.append_array([killer_id, killee_id])
	kills = kills.duplicate()
	_is_modifying_kills_locally = false

	# Update kill/death counts.
	if not _total_kills_by_player_id.has(killer_id):
		_total_kills_by_player_id[killer_id] = 0
	_total_kills_by_player_id[killer_id] += 1

	if not _total_deaths_by_player_id.has(killee_id):
		_total_deaths_by_player_id[killee_id] = 0
	_total_deaths_by_player_id[killee_id] += 1

	# Record gameplay stats.
	server_get_or_create_stats(
		killer_id).record_kill()
	server_get_or_create_stats(
		killee_id).record_death()

	# Track regicide (killing the crowned player).
	var crown_id := get_crown_player_id(
		G.settings.crown_kill_lead)
	if killee_id == crown_id:
		server_get_or_create_stats(
			killer_id).record_regicide()

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
	Netcode.verbose(
		"KILL: %s killed %s" % [killer_id, killee_id],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	update_scores()

	var killer_match_state: PlayerState = players_by_id.get(killer_id)
	var killee_match_state: PlayerState = players_by_id.get(killee_id)
	if killer_match_state and killee_match_state:
		emit_kill_event(killer_match_state, killee_match_state)

	kills_updated.emit()


func emit_kill_event(
	killer: PlayerState,
	killee: PlayerState
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
	# Use flag to prevent setter from emitting signal (we emit manually below).
	_is_modifying_bumps_locally = true
	bumps.append_array([player_1_id, player_2_id])
	bumps = bumps.duplicate()
	_is_modifying_bumps_locally = false

	# Update bump counts for both players.
	if not _total_bumps_by_player_id.has(player_1_id):
		_total_bumps_by_player_id[player_1_id] = 0
	_total_bumps_by_player_id[player_1_id] += 1

	if not _total_bumps_by_player_id.has(player_2_id):
		_total_bumps_by_player_id[player_2_id] = 0
	_total_bumps_by_player_id[player_2_id] += 1

	# Note: bump stats are recorded at the collision
	# detection site (bunny.gd) regardless of bump_mode,
	# so dynamic adjective tracking sees all collisions.

	# Store in indelible interaction buffer.
	_server_store_interaction(
		player_1_id,
		player_2_id,
		InteractionType.BUMP,
		current_frame
	)

	# Update scores and emit events.
	Netcode.verbose(
		"BUMP: %s bumped %s" % [player_1_id, player_2_id],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	update_scores()

	var player_1_match_state: PlayerState = (
		players_by_id.get(player_1_id))
	var player_2_match_state: PlayerState = (
		players_by_id.get(player_2_id))
	if player_1_match_state and player_2_match_state:
		emit_bump_event(player_1_match_state, player_2_match_state)

	bumps_updated.emit()


func emit_bump_event(a: PlayerState, b: PlayerState) -> void:
	players_bumped.emit(a, b)


func server_on_player_disconnected(player: PlayerState) -> void:
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

	# Derive kill/death counts from replicated kills array.
	# (The _total_* dictionaries are only updated on server, so we derive
	# from the replicated arrays to ensure clients calculate correctly.)
	# Dictionary<int, int>
	var kills_count := {}
	var deaths_count := {}
	for player_id in all_player_ids:
		kills_count[player_id] = 0
		deaths_count[player_id] = 0
	for i in range(0, kills.size(), 2):
		var killer: int = kills[i]
		var killee: int = kills[i + 1]
		if kills_count.has(killer):
			kills_count[killer] += 1
		if deaths_count.has(killee):
			deaths_count[killee] += 1

	# Derive bump counts from replicated bumps array.
	# Dictionary<int, int>
	var bumps_count := {}
	for player_id in all_player_ids:
		bumps_count[player_id] = 0
	for i in range(0, bumps.size(), 2):
		var player_1: int = bumps[i]
		var player_2: int = bumps[i + 1]
		if bumps_count.has(player_1):
			bumps_count[player_1] += 1
		if bumps_count.has(player_2):
			bumps_count[player_2] += 1

	# Dictionary<int, int>
	var scores := {}
	# Dictionary<int, int>
	var ranks := {}

	if G.settings.use_simple_score:
		for player_id in all_player_ids:
			scores[player_id] = kills_count[player_id]
	else:
		# Calculate base scores.
		for player_id in all_player_ids:
			scores[player_id] = kills_count[player_id] - deaths_count[player_id]

		# Calculate base ranks.
		all_player_ids.sort_custom(func(a, b): return scores[a] > scores[b])
		for i in range(all_player_ids.size()):
			ranks[all_player_ids[i]] = i

		# Calculate final scores with bonuses/penalties.
		for player_id in all_player_ids:
			var score = 0
			score += bumps_count[player_id] * _BUMP_SCORE
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
	all_player_ids.sort_custom(func(a, b): return scores[a] > scores[b])
	for i in range(all_player_ids.size()):
		var player_id: int = all_player_ids[i]
		players_by_id.get(player_id).rank = i + 1
		players_by_id.get(player_id).score = scores[player_id]


## Returns the player_id that should wear the crown
## (at least kill_lead more kills than all other
## players), or -1 if no one qualifies.
func get_crown_player_id(kill_lead: int) -> int:
	var counts := _get_kill_counts()
	if counts.is_empty():
		return -1

	# Find the player with the most kills.
	var max_kills := 0
	var max_player_id := -1
	for pid in counts:
		if counts[pid] > max_kills:
			max_kills = counts[pid]
			max_player_id = pid

	if max_kills == 0:
		return -1

	# Check if they lead all others by at least
	# kill_lead.
	for pid in counts:
		if pid == max_player_id:
			continue
		if max_kills - counts[pid] < kill_lead:
			return -1

	return max_player_id


## Returns the kill lead of the top-scoring player
## over the runner-up. Returns 0 if there's a tie
## for first, or -1 if there are no players.
func get_winner_kill_lead() -> int:
	var counts := _get_kill_counts()
	if counts.is_empty():
		return -1

	# Find highest and second-highest kill counts.
	var first := 0
	var second := 0
	for pid in counts:
		var kc: int = counts[pid]
		if kc > first:
			second = first
			first = kc
		elif kc > second:
			second = kc

	return first - second


## Builds a Dictionary<int, int> of player_id to
## kill count from the replicated kills array.
func _get_kill_counts() -> Dictionary:
	var all_player_ids := players_by_id.keys()
	var counts := {}
	for pid in all_player_ids:
		counts[pid] = 0
	for i in range(0, kills.size(), 2):
		var killer: int = kills[i]
		if counts.has(killer):
			counts[killer] += 1
	return counts


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
		_interaction_tracker.deduplication_window_frames = (
			_INTERACTION_DEDUPLICATION_WINDOW_FRAMES)
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
	Netcode.verbose(
		"GameMatchState._client_unpack_players:"
		+ " packed_players.size=%d"
		% packed_players.size(),
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	players_by_id.clear()

	for packed_player in packed_players:
		var player_id := (
			PlayerState
				.get_player_id_from_packed_state(
					packed_player))

		if not players_by_id.has(player_id):
			players_by_id[player_id] = _create_player_state()

		var player: PlayerState = players_by_id[player_id]
		player.populate_from_packed_state(packed_player)

	# Trigger connected/disconnected events.
	for player_id in players_by_id:
		var player: PlayerState = players_by_id[player_id]
		if (player.is_connected_to_server
				!= _connected_players.has(
					player_id)):
			if player.is_connected_to_server:
				_connected_players[player_id] = true
				player_joined.emit(player)
			else:
				_connected_players.erase(player_id)
				player_left.emit(player)


## Override parent to handle synchronizer packing flag.
func _server_pack_players() -> void:
	if Netcode.log.is_verbose:
		Netcode.verbose(
			"GameMatchState"
			+ "._server_pack_players:"
			+ " packing %d players"
			% players_by_id.size(),
			NetworkLogger.CATEGORY_GAME_STATE,
		)

	var new_packed_players := []
	new_packed_players.resize(players_by_id.size())
	var i := 0
	for player_id in players_by_id:
		new_packed_players[i] = (
			players_by_id[player_id]
				.get_packed_state())
		i += 1

	_is_packing_state_locally = true
	packed_players = new_packed_players
	_is_packing_state_locally = false

	# Emit players_updated on server side (clients get it via replication
	# setter).
	players_updated.emit()


## Override parent's virtual method to trigger game-specific unpacking.
func _on_packed_players_changed() -> void:
	# Only unpack if this change came from network replication (not local
	# packing).
	if not _is_packing_state_locally:
		_client_unpack_players()
		players_updated.emit()
