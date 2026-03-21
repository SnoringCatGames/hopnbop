class_name MatchStateSynchronizer
extends MultiplayerSynchronizer


## How often the server sends stats to clients
## (in physics frames). Scales with network FPS
## so the interval is always 0.5 seconds.
var _stats_send_interval_frames: int:
	get:
		return int(
			0.5
			* Netcode.frame_driver
				.target_network_fps
		)

var state := GameMatchState.new()
var _previous_state := GameMatchState.new()

var _expected_player_count: int = 0
var _stats_frame_counter := 0


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
		Netcode.ensure(not state.players_by_id.has(player_id))

		var player := state._create_player_state()
		player.set_up(player_id, peer_id, i, player_attributes[i])
		player.connect_frame_index = Netcode.server_frame_index
		state.server_add_player(player)

	state.update_scores()

	# Check if all expected players have now been added to match state.
	# If so, assign outline colors based on final player count.
	if (_expected_player_count > 0
			and state.players_by_id.size()
				>= _expected_player_count):
		_server_assign_outline_colors()


func server_set_expected_player_count(count: int) -> void:
	_expected_player_count = count
	Netcode.print(
		"Expected player count set to %d" % count,
		NetworkLogger.CATEGORY_CONNECTIONS
	)


func _server_on_all_players_connected() -> void:
	Netcode.print(
		"All players validated by session provider",
		NetworkLogger.CATEGORY_CONNECTIONS
	)


## Assigns outline colors to all players based on total player count.
func _server_assign_outline_colors() -> void:
	var player_count := state.players_by_id.size()
	Netcode.print(
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
		Netcode.print(
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
		if Netcode.ensure(state.players_by_id.has(player.player_id)):
			# Set disconnect time for this player.
			player.disconnect_frame_index = Netcode.server_frame_index

		state.server_on_player_disconnected(player)


func _client_on_players_updated() -> void:
	state.update_scores()


func _client_on_kills_updated() -> void:
	Netcode.ensure(
		state.kills.size()
			> _previous_state.kills.size()
		or state.kills.is_empty())

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
	Netcode.ensure(
		state.bumps.size()
			> _previous_state.bumps.size()
		or state.bumps.is_empty())

	var new_bumps := state.bumps.slice(_previous_state.bumps.size())
	var i := 0
	while i < new_bumps.size():
		state.emit_bump_event(
			get_player(new_bumps[i]),
			get_player(new_bumps[i + 1]))
		i += 2

	_previous_state.bumps = state.bumps.duplicate()

	state.update_scores()


func _physics_process(_delta: float) -> void:
	if not Netcode.runs_server_logic:
		return
	if state._stats_by_player_id.is_empty():
		return

	if Netcode.is_preview or Netcode.is_local_mode:
		_stats_frame_counter += 1
		if _stats_frame_counter >= _stats_send_interval_frames:
			_stats_frame_counter = 0
			_server_send_stats_to_clients()


func _server_send_stats_to_clients() -> void:
	var packed := []
	for player_id in state._stats_by_player_id:
		var stats: PlayerMatchStats = (
		state._stats_by_player_id[player_id])
		packed.append(player_id)
		packed.append_array(
			stats.to_packed_array())
	Netcode.call_client_rpc_with_local_support(
		_rpc_client_update_stats.bind(packed))


@rpc("authority", "call_remote", "unreliable", NetworkConnector.RPC_CHANNEL_STATS)
func _rpc_client_update_stats(
	packed_data: Array,
) -> void:
	# Each entry is 1 player_id + 18 stat values
	# = 19 stride.
	var stride := 19
	var i := 0
	while i + stride <= packed_data.size():
		var player_id: int = packed_data[i]
		var stats_array := packed_data.slice(
			i + 1, i + stride)
		var stats := PlayerMatchStats.new()
		stats.populate_from_packed_array(
			stats_array)
		state.client_store_stats(
			player_id, stats)
		i += stride


## Receives critter disturbance, fly proximity,
## and poop stat deltas from clients. Each entry
## is [player_id, cricket, fish, butterfly,
## fly_time, poop] = 6 stride.
@rpc("any_peer", "call_remote", "unreliable", NetworkConnector.RPC_CHANNEL_STATS)
func _rpc_server_update_critter_stats(
	packed_data: Array,
) -> void:
	if not Netcode.is_server:
		return

	var sender_peer := (
		multiplayer.get_remote_sender_id())
	var level: NetworkedLevel = (
		G.level as NetworkedLevel)
	if not is_instance_valid(level):
		return

	# Validate peer owns the reported player_id.
	var valid_ids: Array = (
		level.peer_to_player_ids
			.get(sender_peer, []))

	var stride := 6
	var i := 0
	while i + stride <= packed_data.size():
		var player_id: int = packed_data[i]
		if not valid_ids.has(player_id):
			i += stride
			continue
		var stats: PlayerMatchStats = (
			state.server_get_or_create_stats(
				player_id))
		var cricket_d: int = (
			int(packed_data[i + 1]))
		var fish_d: int = (
			int(packed_data[i + 2]))
		var butterfly_d: int = (
			int(packed_data[i + 3]))
		var fly_time_d: float = (
			packed_data[i + 4])
		var poop_d: int = (
			int(packed_data[i + 5]))
		for _j in cricket_d:
			stats.record_cricket_disturb()
		for _j in fish_d:
			stats.record_fish_disturb()
		for _j in butterfly_d:
			stats.record_butterfly_disturb()
		stats.accumulate_fly_proximity(
			fly_time_d)
		for _j in poop_d:
			stats.record_poop()
		i += stride


@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_GAME_EVENTS)
func _rpc_client_notify_match_started(
	match_start_frame_index: int,
	match_duration_usec: int
) -> void:
	state.client_notify_match_started(
		match_start_frame_index,
		match_duration_usec
	)


@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_GAME_EVENTS)
func _rpc_client_notify_match_ended() -> void:
	state.client_notify_match_ended()


## Receives dynamic adjective assignments from the
## server. packed_data is an Array of
## [player_id, adj_list_id, adj_index, ...] triples
## (stride of 3).
@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_GAME_EVENTS)
func _rpc_client_notify_dynamic_adjectives(
	packed_data: Array,
) -> void:
	var adjective_map := {}
	for i in range(0, packed_data.size(), 3):
		var player_id: int = packed_data[i]
		var list_id: int = packed_data[i + 1]
		var adj_idx: int = packed_data[i + 2]
		adjective_map[player_id] = {
			"adj_list_id": list_id,
			"adj_index": adj_idx,
		}

	# Update local player states.
	for player_id in adjective_map:
		var ps: GamePlayerState = (
			state.players_by_id.get(player_id))
		if ps:
			var data: Dictionary = (
				adjective_map[player_id])
			ps.adj_list_id = data.adj_list_id
			ps.adj_index = data.adj_index

	# Trigger celebration adjective reveals.
	# Pass resolved adjective strings for the
	# reveal popup.
	if is_instance_valid(G.celebration):
		var string_map := {}
		for player_id in adjective_map:
			var data: Dictionary = (
				adjective_map[player_id])
			string_map[player_id] = (
				DynamicAdjectiveConfig
					.get_localized_adjective(
						data.adj_list_id,
						data.adj_index))
		G.celebration.reveal_adjectives(
			string_map)


## Receives backend player ID mapping from the
## server before match end. packed_data is an Array
## of [player_id, backend_player_id, ...] pairs
## (stride of 2).
@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_GAME_EVENTS)
func _rpc_client_receive_backend_ids(
	packed_data: Array,
) -> void:
	for i in range(0, packed_data.size(), 2):
		var player_id: int = packed_data[i]
		var backend_id: String = packed_data[i + 1]
		G.client_session.backend_player_id_map[
			player_id] = backend_id


## Receives profile image URLs from the server.
## packed_data is [player_id, url, ...] pairs
## (stride of 2).
@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_GAME_EVENTS)
func _rpc_client_receive_profile_images(
	packed_data: Array,
) -> void:
	for i in range(0, packed_data.size(), 2):
		var player_id: int = packed_data[i]
		var url: String = packed_data[i + 1]
		G.client_session.profile_image_urls[
			player_id] = url
		# Trigger download so ProfileImageDisplay
		# instances update via image_loaded signal.
		if not url.is_empty():
			G.profile_image_cache.request_image(
				player_id, url)
