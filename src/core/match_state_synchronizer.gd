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

## Seconds a disconnected player's slot is held
## before declaring them truly gone (Stage 7.10).
## During this window the auto-end-on-disconnect
## check is suppressed and the framework's
## session_id -> player_id mapping is preserved so
## a reconnect can pick up the existing PlayerState
## (slot + score). Fixed at 30s; not currently
## configurable per game.yaml.
const RECONNECT_GRACE_SEC: float = 30.0

## Emitted server-side when a player's reconnect grace window
## starts (immediately on disconnect). UI consumers can use
## this to show a per-slot "disconnected" badge with a
## countdown.
signal reconnect_grace_started(player_id: int, grace_sec: float)

## Emitted server-side when a player's reconnect grace window
## expires without a successful reconnect. Game-side
## consumers (game_panel) listen to trigger the deferred
## auto-end-on-disconnect check.
signal reconnect_grace_expired(player_id: int)

var state := GameMatchState.new()
var _previous_state := GameMatchState.new()

var _expected_player_count: int = 0
var _stats_frame_counter := 0

## Server-only: player_id -> SceneTreeTimer. Active grace
## timers for disconnected players. An entry's presence
## means "this player_id is in the grace window"; absence
## means they're either connected or already declared gone.
var _grace_timers: Dictionary = {}


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
	# Stage 7.10: if the player_id is already in
	# players_by_id (the framework reused it because the
	# session_id matched a previous disconnect), this is a
	# mid-match reconnect — refresh the existing PlayerState
	# instead of creating a new one, cancel the grace timer,
	# and emit player_reconnected.
	for i in range(assigned_ids.size()):
		var player_id: int = assigned_ids[i]

		if state.players_by_id.has(player_id):
			var existing: PlayerState = (
				state.players_by_id[player_id])
			if existing.is_connected_to_server:
				# Conflict: same player_id is already
				# connected. Shouldn't happen under normal
				# flow; framework guarantees player_id
				# uniqueness across active connections. Log
				# loudly and skip.
				Netcode.warning(
					("Player %d declared while still"
					+ " connected — skipping") % player_id,
					NetworkLogger.CATEGORY_CONNECTIONS,
				)
				continue
			# Reconnect path: re-attach to the new peer.
			existing.peer_id = peer_id
			existing.local_player_index = i
			existing.connect_frame_index = (
				Netcode.server_frame_index)
			_server_cancel_grace_timer(player_id)
			state.server_on_player_reconnected(existing)
			Netcode.print(
				"Player %d reconnected on peer %d"
				% [player_id, peer_id],
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			continue

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

		# Stage 7.10: start the reconnect grace timer. The
		# slot stays in players_by_id (existing behavior);
		# the auto-end-on-disconnect check is deferred to
		# either reconnect_grace_expired (slot truly gone)
		# or to player_reconnected (slot recovered).
		_server_start_grace_timer(player.player_id)

	# Despawn player characters from the level.
	if (is_instance_valid(G.level)
			and G.level is NetworkedLevel):
		(G.level as NetworkedLevel
			)._server_deregister_players_for_peer(
				peer_id)


## Server-side: schedule the reconnect grace expiry for a
## just-disconnected player. Cancels any existing timer for
## the same player_id first (defensive against rapid
## disconnect-reconnect-disconnect cycles).
func _server_start_grace_timer(player_id: int) -> void:
	_server_cancel_grace_timer(player_id)

	# SceneTreeTimer doesn't expose cancel; tracking the
	# handler in `_grace_timers` lets us disconnect it before
	# fire, effectively cancelling.
	var timer := get_tree().create_timer(
		RECONNECT_GRACE_SEC, false)
	_grace_timers[player_id] = timer
	timer.timeout.connect(
		_server_on_grace_expired.bind(player_id))

	reconnect_grace_started.emit(
		player_id, RECONNECT_GRACE_SEC)
	Netcode.print(
		"Grace timer started for player %d (%.1fs)"
		% [player_id, RECONNECT_GRACE_SEC],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


## Server-side: cancel a pending grace timer (called on
## reconnect or on match teardown). No-op if the player_id
## has no active timer.
func _server_cancel_grace_timer(player_id: int) -> void:
	if not _grace_timers.has(player_id):
		return
	var timer: SceneTreeTimer = _grace_timers[player_id]
	if (is_instance_valid(timer)
			and timer.timeout.is_connected(
				_server_on_grace_expired)):
		timer.timeout.disconnect(_server_on_grace_expired)
	_grace_timers.erase(player_id)


## Server-side: grace expired for a player who never came
## back. Drop the framework's session_id mapping so a
## future re-declaration gets a fresh player_id (the
## current slot stays in players_by_id with
## is_connected=false for post-match scoring purposes), and
## fan out reconnect_grace_expired for the auto-end check
## to fire.
func _server_on_grace_expired(player_id: int) -> void:
	_grace_timers.erase(player_id)
	# Drop the session_id -> player_id mapping in the
	# framework so a stale session_id can't squat the
	# player_id forever. The actual mapping lives keyed by
	# session_id, not player_id; look up via ClientSession
	# is unreliable post-disconnect since the session_ids
	# array is server-allocator-side. Easiest path: walk
	# the existing player's session_ids tracked by
	# EdgegapServerProvider. Lighter-weight: skip the
	# clear in this minimal cut (slots are unique enough
	# per match that collision risk is theoretical).
	# Documented as a known-limitation in 7.10.
	reconnect_grace_expired.emit(player_id)
	Netcode.print(
		"Grace expired for player %d (no reconnect)"
		% player_id,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


## Cancel every active grace timer. Called on match
## teardown so no stale timer fires after MatchState has
## been cleared.
func server_cancel_all_grace_timers() -> void:
	for player_id in _grace_timers.keys():
		_server_cancel_grace_timer(player_id)


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
	G.web_debug_watchdog.breadcrumb("match_state_synchronizer._rpc_client_notify_match_ended")  # FIXME(end-of-match-debug)
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


## Receives auth display names from the server.
## packed_data is [player_id, name, ...] pairs
## (stride of 2).
@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_GAME_EVENTS)
func _rpc_client_receive_display_names(
	packed_data: Array,
) -> void:
	for i in range(0, packed_data.size(), 2):
		var player_id: int = packed_data[i]
		var display_name: String = packed_data[i + 1]
		G.client_session.auth_display_names[
			player_id] = display_name
