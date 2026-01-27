class_name MatchStateSynchronizer
extends MultiplayerSynchronizer


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

		# Assign outline colors once when all players have connected.
		G.network.game_lift_manager.all_players_connected.connect(
			_server_on_all_players_connected
		)

	# Connect to player state events for connector notification.
	state.player_joined.connect(_on_player_joined)


func _on_player_joined(player_match_state: PlayerMatchState) -> void:
	var player := G.get_player(player_match_state.player_id)
	if is_instance_valid(player):
		player.on_match_state_ready(player_match_state)
	G.network.connector.client_on_player_state_connected(
		player_match_state.player_id,
		player_match_state.peer_id,
		player_match_state.local_player_index)

	# Now that the peer_id mapping is established, update authority on the
	# player's networked state nodes. This is necessary for remote players
	# whose player_id was set before the mapping existed (during initial
	# replication). The player_id setter guards against calling
	# update_authority() without a mapping, so we call it explicitly here.
	if is_instance_valid(player):
		player.update_authority()


func clear() -> void:
	state.clear()
	_previous_state.clear()


func get_player(player_id: int) -> PlayerMatchState:
	if state.players_by_id.has(player_id):
		return state.players_by_id[player_id]
	return null


func _server_on_peer_players_declared(
	peer_id: int,
	assigned_ids: Array[int],
	player_attributes: Array
) -> void:
	# Create PlayerMatchState objects for each assigned player ID.
	for i in range(assigned_ids.size()):
		var player_id: int = assigned_ids[i]
		G.ensure(not state.players_by_id.has(player_id))

		var player := PlayerMatchState.new()
		player.set_up(player_id, peer_id, i, player_attributes[i])
		player.connect_time_usec = (
			G.network.server_time_usec_not_frame_aligned
		)
		state.server_add_player(player)

	state.update_scores()

	# FIXME: LEFT OFF HERE: This seems wrong? The all_players_connected signal should also work in preview mode.

	# In preview mode, assign colors when all players have been added.
	# In non-preview (GameLift) mode, colors are assigned via
	# all_players_connected signal.
	if G.network.is_preview:
		var expected_player_count := G.settings.preview_client_count
		var current_player_count := state.players_by_id.size()
		if current_player_count >= expected_player_count:
			_server_assign_outline_colors()


func _server_on_all_players_connected() -> void:
	# Assign outline colors once when all players have connected.
	# This ensures colors are distributed evenly across all players.
	_server_assign_outline_colors()


## Assigns outline colors to all players based on total player count.
func _server_assign_outline_colors() -> void:
	var player_count := state.players_by_id.size()
	var colors := PlayerAttributeGenerator.calculate_outline_colors(player_count)

	# Get sorted player IDs to ensure consistent color assignment.
	var player_ids := state.players_by_id.keys()
	player_ids.sort()

	# Assign colors to each player.
	for i in range(player_ids.size()):
		var player_id: int = player_ids[i]
		var player: PlayerMatchState = state.players_by_id[player_id]
		player.outline_color = colors[i]

	# Repack the player state to trigger replication of updated colors.
	state._server_pack_players()


func _server_on_peer_disconnected(peer_id: int) -> void:
	# Handle all players for this peer.
	var players_for_peer: Array[PlayerMatchState] = (
		state.get_players_for_peer(peer_id)
	)

	for player in players_for_peer:
		if G.ensure(state.players_by_id.has(player.player_id)):
			# Set disconnect time for this player.
			player.disconnect_time_usec = (
				G.network.server_time_usec_not_frame_aligned
			)

		state.server_on_player_disconnected(player)


func _client_on_players_updated() -> void:
	state.update_scores()


func _client_on_kills_updated() -> void:
	G.ensure(
		state.kills.size() > _previous_state.kills.size() or
		state.kills.is_empty())

	var new_kills := state.kills.slice(_previous_state.kills.size())
	var i := 0
	while i < new_kills.size():
		state.emit_kill_event(
			get_player(new_kills[i]),
			get_player(new_kills[i + 1]))
		i += 2

	_previous_state.kills = state.kills.duplicate()

	state.update_scores()


func _client_on_bumps_updated() -> void:
	G.ensure(
		state.bumps.size() > _previous_state.bumps.size() or
		state.bumps.is_empty())

	var new_bumps := state.bumps.slice(_previous_state.bumps.size())
	var i := 0
	while i < new_bumps.size():
		state.emit_bump_event(
			get_player(new_bumps[i]),
			get_player(new_bumps[i + 1]))
		i += 2

	_previous_state.bumps = state.bumps.duplicate()

	state.update_scores()


# TODO: Call server_add_kill.
func server_add_kill(killer_id: int, killee_id: int) -> void:
	_previous_state.kills = state.kills.duplicate()

	state.server_add_kill(killer_id, killee_id)

	G.print(
		"KILL: %s killed %s" % [killer_id, killee_id],
		ScaffolderLog.CATEGORY_GAME_STATE
	)

	state.update_scores()
	state.emit_kill_event(get_player(killer_id), get_player(killee_id))


# TODO: Call server_add_bump.
func server_add_bump(player_1_id: int, player_2_id: int) -> void:
	_previous_state.bumps = state.bumps.duplicate()

	state.server_add_bump(player_1_id, player_2_id)

	G.print(
		"BUMP: %s bumped %s" % [player_1_id, player_2_id],
		ScaffolderLog.CATEGORY_GAME_STATE
	)

	state.update_scores()
	state.emit_bump_event(get_player(player_1_id), get_player(player_2_id))
