class_name MatchStateSynchronizer
extends MultiplayerSynchronizer


var state := GameMatchState.new()
var _previous_state := GameMatchState.new()

var _expected_player_count: int = 0


func _ready() -> void:
	# Set back-reference so GameMatchState can call RPC methods
	# through this node.
	state.synchronizer = self

	if Netcode.is_client:
		state.players_updated.connect(_client_on_players_updated)
		state.kills_updated.connect(_client_on_kills_updated)
		state.bumps_updated.connect(_client_on_bumps_updated)

	if Netcode.is_server:
		# Listen for player count declarations instead of raw peer connections.
		Netcode.connector.peer_players_declared.connect(
			_server_on_peer_players_declared
		)
		Netcode.connector.disconnected.connect(_server_on_peer_disconnected)

	# Connect to player state events for connector notification.
	state.player_joined.connect(_on_player_joined)


func _on_player_joined(player_match_state: PlayerState) -> void:
	var player := G.get_player(player_match_state.player_id)
	if is_instance_valid(player):
		player.on_match_state_ready(player_match_state)
	Netcode.connector.client_on_player_state_connected(
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


func get_player(player_id: int) -> PlayerState:
	if state.players_by_id.has(player_id):
		return state.players_by_id[player_id]
	return null


func _server_on_peer_players_declared(
	peer_id: int,
	assigned_ids: Array[int],
	player_attributes: Array
) -> void:
	# Create PlayerState objects for each assigned player ID.
	for i in range(assigned_ids.size()):
		var player_id: int = assigned_ids[i]
		G.ensure(not state.players_by_id.has(player_id))

		var player := PlayerState.new()
		player.set_up(player_id, peer_id, i, player_attributes[i])
		player.connect_frame_index = Netcode.server_frame_index
		state.server_add_player(player)

	state.update_scores()

	# Check if all expected players have now been added to match state.
	# If so, assign outline colors based on final player count.
	if _expected_player_count > 0 and \
			state.players_by_id.size() >= _expected_player_count:
		_server_assign_outline_colors()


func server_set_expected_player_count(count: int) -> void:
	_expected_player_count = count
	G.print(
		"Expected player count set to %d" % count,
		NetworkLogger.CATEGORY_CONNECTIONS
	)


func _server_on_all_players_connected() -> void:
	G.print(
		"All players validated by session provider",
		NetworkLogger.CATEGORY_CONNECTIONS
	)


## Assigns outline colors to all players based on total player count.
func _server_assign_outline_colors() -> void:
	var player_count := state.players_by_id.size()
	G.print(
		"Assigning colors to %d players" % player_count,
		NetworkLogger.CATEGORY_GAME_STATE
	)
	var colors := PlayerAttributeGenerator.calculate_outline_colors(player_count)

	# Get sorted player IDs to ensure consistent color assignment.
	var player_ids := state.players_by_id.keys()
	player_ids.sort()

	# Assign colors to each player.
	for i in range(player_ids.size()):
		var player_id: int = player_ids[i]
		var player: PlayerState = state.players_by_id[player_id]
		player.base_color = colors[i]
		G.print(
			"Player %d color = %s" % [player_id, colors[i]],
			NetworkLogger.CATEGORY_GAME_STATE
		)

	# Repack the player state to trigger replication of updated colors.
	state._server_pack_players()


func _server_on_peer_disconnected(peer_id: int, _reason: int) -> void:
	# Handle all players for this peer.
	var players_for_peer: Array[PlayerState] = (
		state.get_players_for_peer(peer_id)
	)

	for player in players_for_peer:
		if G.ensure(state.players_by_id.has(player.player_id)):
			# Set disconnect time for this player.
			player.disconnect_frame_index = Netcode.server_frame_index

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


@rpc("authority", "call_remote", "reliable")
func _rpc_client_notify_match_started(
	match_start_frame_index: int,
	match_duration_usec: int
) -> void:
	state.client_notify_match_started(
		match_start_frame_index,
		match_duration_usec
	)


@rpc("authority", "call_remote", "reliable")
func _rpc_client_notify_match_ended() -> void:
	state.client_notify_match_ended()
