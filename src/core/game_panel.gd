class_name GamePanel
extends Node2D


## This is triggered from LobbyLevel.
@warning_ignore("unused_signal")
signal lobby_players_updated


var levels: Array[Level] = []

var is_level_fully_loaded := false

var session_manager: GameSessionManager

## Seconds between active-session polls during a
## match. The poll detects if another device started
## matchmaking for the same account.
const _SESSION_POLL_INTERVAL_SEC := 15.0

# Active-session polling now lives on the
# snoringcat-platform stack at /v1/session/active.
const _PLATFORM_API_URL := (
	"https://r20b7wqop6.execute-api.us-west-2.amazonaws.com"
	+ "/prod/v1"
)

## True while the client is being kicked due to a
## concurrent session override. Prevents re-entrant
## disconnect handling and skips clear_session().
var _is_session_override_kick := false

var _session_poll_timer: Timer
var _session_poll_http: HTTPRequest

var match_state: GameMatchState:
	get:
		return %MatchStateSynchronizer.state
var match_state_synchronizer: MatchStateSynchronizer:
	get:
		return %MatchStateSynchronizer


func _enter_tree() -> void:
	G.game_panel = self
	G.client_session = ClientSession.new()


func _ready() -> void:
	G.log.log_system_ready("GamePanel")

	G.match_state = match_state

	%MatchStateSynchronizer.set_multiplayer_authority(
		NetworkConnector.SERVER_ID)
	%LevelSpawner.set_multiplayer_authority(
		NetworkConnector.SERVER_ID)

	for level_info in G.settings.levels:
		if level_info.scene != null:
			%LevelSpawner.add_spawnable_scene(
				level_info.scene.resource_path)

	# Set up session manager for network coordination.
	session_manager = GameSessionManager.new()
	session_manager.name = "SessionManager"
	add_child(session_manager)

	# Configure local session provider for
	# NetworkConnector handshake.
	Netcode.connector.client_session_provider = (
		func() -> Dictionary:
			var bid := ""
			if (G.auth_token_store != null
					and not G.auth_token_store
						.player_id.is_empty()):
				bid = G.auth_token_store.player_id
			var piu := ""
			if (G.auth_token_store != null
					and not G.auth_token_store
						.profile_image_url
						.is_empty()):
				piu = (
					G.auth_token_store
						.profile_image_url)
			var dn := ""
			if (G.auth_token_store != null
					and not G.auth_token_store
						.display_name.is_empty()
					and not G.auth_token_store
						.is_anonymous):
				dn = G.auth_token_store.display_name
			return {
				"session_ids":
					G.client_session
						.client_session_ids,
				"player_count":
					G.client_session
						.local_player_count,
				"attributes":
					G.client_session
						.local_player_attributes,
				"backend_player_id": bid,
				"profile_image_url": piu,
				"display_name": dn,
			}
	)

	# Configure player attribute validator for
	# bunny validation.
	Netcode.connector.player_attribute_validator = (
		_validate_player_attributes)

	# Connect to high-level session events.
	session_manager.session_established.connect(
		_on_session_established)
	session_manager.connection_lost.connect(
		_on_connection_lost)
	session_manager.matchmaking_failed.connect(
		_on_matchmaking_failed)
	(session_manager
		.local_mode_fallback_requested
		.connect(_on_local_mode_fallback))

	if Netcode.is_server:
		session_manager.match_ready.connect(
			_on_match_ready)
		session_manager.server_should_reset.connect(
			_on_server_should_reset)
		(session_manager.server_shutdown_imminent
			.connect(
				_on_server_shutdown_imminent))
		(session_manager.session_provider
			.all_players_connected.connect(
				_server_on_all_players_connected))
		Netcode.frame_driver.server_pause_validator = (
			_server_validate_pause_request)

	if Netcode.is_client:
		if Netcode.is_connected_to_server:
			_client_on_server_connected()
		multiplayer.connected_to_server.connect(
			_client_on_server_connected)

		%LevelSpawner.spawned.connect(
			_client_on_level_spawned)
		%LevelSpawner.despawned.connect(
			_client_on_level_despawned)

		Netcode.local_authority_added.connect(
			_client_on_local_player_loaded,
		)

		# Transition from LOADING to GAME when
		# server unpauses.
		(Netcode.frame_driver
			.pause_state_changed.connect(
				_client_on_pause_state_changed))

		# Show countdown UI when match start
		# countdown begins.
		(Netcode.frame_driver
			.match_start_countdown_started
			.connect(
				_on_match_start_countdown_started))

		# Start match music when countdown ends.
		(Netcode.frame_driver
			.match_start_countdown_ended
			.connect(
				_on_match_start_countdown_ended))

	if Netcode.is_server:
		# In preview mode, spawn new level when
		# first client connects after match end.
		if Netcode.is_preview:
			Netcode.print(
				"Connecting to peer_connected"
				+" signal for preview mode",
				NetworkLogger
					.CATEGORY_CONNECTIONS,
			)
			multiplayer.peer_connected.connect(
				_server_on_preview_peer_connected)

	G.match_state.player_joined.connect(
		_on_player_joined)
	G.match_state.player_left.connect(
		_on_player_left)
	G.match_state.player_killed.connect(
		_on_player_killed)
	G.match_state.players_bumped.connect(
		_on_players_bumped)
	G.match_state.match_ended.connect(
		_on_match_ended)

	# Set up PerfTracker callback for level
	# ready state.
	if Netcode.perf_tracker != null:
		Netcode.perf_tracker.is_ready_callback = (
			func() -> bool:
				return is_level_fully_loaded
		)


func _on_player_joined(
	player: PlayerState,
) -> void:
	# Check if this player belongs to the local
	# peer.
	var is_local_peer := (
		Netcode.is_client
		and player.peer_id
			== Netcode.local_peer_id
	)
	var self_suffix := (
		" (local)" if is_local_peer else "")
	Netcode.print(
		"Player joined: %s%s" % [
			player.get_string(), self_suffix],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


func _on_player_left(
	player: PlayerState,
) -> void:
	Netcode.print(
		"Player left: %s" % player.get_string(),
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	if Netcode.runs_server_logic:
		_server_check_auto_end_on_disconnect()


func _on_match_ended() -> void:
	if not Netcode.is_client:
		return
	# Stop session polling. The match is ending
	# normally so we do not need to detect overrides.
	_stop_session_poll()
	# Start a client-side timer to transition to
	# game-over after the celebration sequence
	# completes. This avoids depending on WebRTC
	# disconnect detection, which can take 5-30
	# seconds due to ICE timeouts. The timer
	# matches the server's disconnect delay so
	# the client transitions at the same time
	# the server drops the connection.
	Netcode.print(
		"Match ended, starting client-side"
		+ " game-over timer (%.1fs)"
		% G.settings.match_end_disconnect_delay_sec,
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	Netcode.time.set_timeout(
		_client_transition_to_game_over,
		G.settings.match_end_disconnect_delay_sec,
	)


func _on_player_killed(
	killer: PlayerState,
	killee: PlayerState,
) -> void:
	Netcode.print(
		"Player killed: %s killed %s" % [
			killer.get_string(),
			killee.get_string()],
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# Trigger respawn on server (moved from
	# MatchState).
	if Netcode.runs_server_logic:
		var killee_actor: Player = (
			G.get_player(killee.player_id))
		if is_instance_valid(killee_actor):
			killee_actor.server_trigger_death()


func _on_players_bumped(
	a: PlayerState,
	b: PlayerState,
) -> void:
	Netcode.print(
		"Players bumped: %s, %s" % [
			a.get_string(), b.get_string()],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


func _client_on_level_spawned(
	p_level: Level,
) -> void:
	Netcode.ensure(p_level is Level)
	var level: Level = p_level
	Netcode.print(
		"Level spawned: %s"
		% level.get_string(),
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	if is_instance_valid(level.level_camera):
		level.level_camera.make_current()


func _client_on_level_despawned(
	p_level: Level,
) -> void:
	Netcode.ensure(p_level is Level)
	var level: Level = p_level
	Netcode.print(
		"Level despawned: %s"
		% level.get_string(),
		NetworkLogger.CATEGORY_GAME_STATE,
	)


func _client_on_local_player_loaded(
		_input_from_client: PlayerInputFromClient,
) -> void:
	is_level_fully_loaded = true


func _client_on_server_connected() -> void:
	Netcode.check_is_client()

	# Guard against being called multiple times
	# (can happen if GamePanel._ready runs after
	# connection is already established, causing
	# both the direct call and the signal handler
	# to fire).
	if G.client_session.is_game_active:
		Netcode.print(
			"Already connected to server,"
			+" ignoring duplicate call",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return

	Netcode.check(
		G.client_session.is_game_loading,
		"Game load is not expected",
	)
	Netcode.check(
		not G.client_session.is_game_active,
		"Game is already active",
	)

	G.client_session.is_game_active = true

	# Poll the backend to detect if another device
	# overrides this session (same account starts
	# matchmaking elsewhere).
	_start_session_poll()

	# Stay on the loading screen. We will
	# transition to GAME when server unpauses
	# (handled in _client_on_pause_state_changed).
	# But if game is already unpaused, transition
	# immediately.
	if not Netcode.frame_driver.is_paused:
		_client_transition_to_game_if_ready()


# --- High-Level Session Event Handlers ---


func _on_session_established(
	player_ids: Array[int],
) -> void:
	# Player IDs already stored in ClientSession
	# by GameSessionManager.
	Netcode.print(
		("Session established with %d player(s):"
		+" %s") % [player_ids.size(), player_ids],
		NetworkLogger.CATEGORY_GAME_STATE,
	)


func _client_on_pause_state_changed(
	is_paused: bool,
	_initiator_peer_id: int,
) -> void:
	Netcode.check_is_client()

	if is_paused:
		# Update pauses_used_by_peer immediately
		# from the RPC data, so the pause screen
		# has accurate counts before
		# MatchStateSynchronizer replication
		# arrives.
		if _initiator_peer_id > 0:
			G.match_state.pauses_used_by_peer[
				_initiator_peer_id] = (
					Netcode.frame_driver
						._pause_initiator_pauses_used)

		# Open pause screen if game is active and
		# we're in-game.
		if (
			G.client_session.is_game_active
			and not G.client_session.is_game_loading
			and G.screens.current_screen
				== ScreensMain.ScreenType.GAME
		):
			G.screens.client_open_screen(
				ScreensMain.ScreenType.PAUSE)
	else:
		# Return to game from pause screen.
		if (G.screens.current_screen
				== ScreensMain.ScreenType.PAUSE):
			G.screens.client_open_screen(
				ScreensMain.ScreenType.GAME)
		# Transition from LOADING to GAME when
		# server unpauses.
		_client_transition_to_game_if_ready()


func _client_transition_to_game_if_ready() -> void:
	Netcode.check_is_client()

	# Only transition if game is active and we're
	# on LOADING screen.
	if G.client_session.is_game_active:
		if (G.screens.current_screen
				== ScreensMain.ScreenType.LOADING):
			# Game is no longer loading - we're
			# entering the game now.
			G.client_session.is_game_loading = false
			G.screens.client_open_screen(
				ScreensMain.ScreenType.GAME)


func _on_connection_lost(
	reason_name: String,
	is_expected: bool,
) -> void:
	# Only clients handle connection loss UI.
	if Netcode.is_client:
		# Session override kick already handled
		# the disconnect. Do not re-enter.
		if _is_session_override_kick:
			return
		if is_expected:
			Netcode.print(
				"Match ended, showing results",
				NetworkLogger.CATEGORY_GAME_STATE,
			)
			_client_transition_to_game_over()
		else:
			Netcode.warning(
				"Unexpected disconnect: %s"
				% reason_name,
				NetworkLogger
					.CATEGORY_CONNECTIONS,
			)
			# Show a friendly message when the
			# server shuts down before the match
			# started (e.g., not enough players
			# connected in time).
			var is_pre_match_shutdown: bool = (
				reason_name == "SERVER_SHUTDOWN"
				and not G.match_state
					.is_match_active
			)
			var toast_message: String
			if is_pre_match_shutdown:
				toast_message = tr(
					"TOAST.NOT_ENOUGH_PLAYERS")
			else:
				toast_message = reason_name
			G.client_session.latest_server_message = (
				"Disconnected: %s" % reason_name)
			if is_instance_valid(G.toast_overlay):
				G.toast_overlay.show_toast(
					toast_message,
					ToastOverlay.Type.ERROR,
				)
			client_exit_match()


func _on_matchmaking_failed(reason: String) -> void:
	Netcode.warning(
		"Matchmaking failed: %s" % reason,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	G.client_session.is_game_loading = false

	# Release the backend session lock so the
	# player can re-queue immediately. Skip for
	# concurrent session overrides: the session
	# now belongs to another device, and clearing
	# it would cancel their matchmaking.
	var is_concurrent_override := (
		reason == tr(
			"TOAST.MATCHMAKING_CANCELLED"
			+ "_OTHER_SESSION")
	)
	if (
		not is_concurrent_override
		and Netcode.should_connect_to_remote_server
		and session_manager.session_provider
			.has_method("clear_session")
	):
		session_manager.session_provider.clear_session()

	# On timeout, stay on loading screen and show
	# a retry button instead of returning to lobby.
	var is_timeout := (
		"timeout" in reason.to_lower()
		or "timed out" in reason.to_lower()
	)
	if is_timeout and is_instance_valid(
		G.loading_screen
	):
		G.loading_screen.show_matchmaking_timeout()
		return

	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			reason,
			ToastOverlay.Type.INFO,
		)

	G.screens.client_open_screen(
		ScreensMain.ScreenType.LOBBY)


func _on_match_ready() -> void:
	# All players connected and validated
	# (server only).
	Netcode.check_is_server()
	Netcode.print(
		"Match ready, all players validated",
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# Set expected player count for color
	# assignment. This tells
	# MatchStateSynchronizer how many players to
	# expect, so it can assign colors when the
	# last player is added to match state.
	# In preview mode, this is the number of
	# client instances. In production, it's the
	# number returned by the matchmaker.
	var expected_count: int
	if Netcode.is_local_mode:
		expected_count = (
			G.client_session.local_player_count)
	elif Netcode.is_preview:
		expected_count = (
			Netcode.settings.preview_client_count)
	else:
		# Production: get from session provider
		# or use connected peer count.
		expected_count = (
			multiplayer.get_peers().size())

	(%MatchStateSynchronizer
		.server_set_expected_player_count(
			expected_count))

	# Resolve critter preference via majority
	# vote, then spawn snails if enabled.
	_server_resolve_critter_preference()


func _on_server_shutdown_imminent(
	seconds_remaining: float,
) -> void:
	Netcode.check_is_server()

	# Notify clients so they see the correct
	# disconnect reason.
	Netcode.connector.server_notify_shutdown()

	# If a match is active and there is enough
	# time, let it finish naturally.
	if (G.match_state.is_match_active
			and not G.match_state.is_match_ended
			and seconds_remaining > 10.0):
		Netcode.print(
			"Match active, allowing finish"
			+" before shutdown (%.0fs remaining)"
			% seconds_remaining,
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	# No active match or not enough time.
	# Force end and disconnect.
	if (G.match_state.is_match_active
			and not G.match_state.is_match_ended):
		_server_initiate_match_end()
	else:
		# No match in progress. Disconnect clients
		# immediately to stop state replication
		# and prevent buffer overflow.
		(Netcode.connector
			.server_close_multiplayer_session())


func _on_server_should_reset() -> void:
	# Server should reset for new match
	# (preview mode only).
	Netcode.check_is_server()
	Netcode.print(
		"Resetting server for new match",
		NetworkLogger.CATEGORY_CORE_SYSTEMS,
	)
	_server_reset_for_new_match()


func _server_reset_for_new_match() -> void:
	Netcode.check_is_server()

	# Reset cheat state for new match.
	if is_instance_valid(G.cheat_manager):
		G.cheat_manager.reset()

	# Clear match state.
	G.match_state.match_start_frame_index = -1
	G.match_state.is_match_ended = false
	G.match_state.clear()

	# Despawn current level.
	if is_instance_valid(G.level):
		G.level.queue_free()
		G.level = null

	# Reset frame driver.
	Netcode.frame_driver.server_frame_index = 0

	Netcode.print(
		"Server reset complete,"
		+" ready for new clients",
		NetworkLogger.CATEGORY_CORE_SYSTEMS,
	)


## Spawn lobby level (client-only, no server
## connection).
func _client_spawn_lobby() -> void:
	Netcode.check_is_client()

	if G.is_lobby_active:
		# Lobby is already ready.
		return

	Netcode.print(
		"Spawning lobby level",
		NetworkLogger.CATEGORY_CORE_SYSTEMS,
	)

	# Clear stale match state from previous game.
	G.match_state.clear()

	var lobby_level: LobbyLevel = (
		G.settings.lobby_level_scene.instantiate())
	levels.append(lobby_level)
	%Levels.add_child(lobby_level)
	G.level = lobby_level

	# Ensure the lobby camera is the active one.
	if is_instance_valid(lobby_level.level_camera):
		lobby_level.level_camera.make_current()

	# Restore players from previous match
	# (preserves device configs and attributes
	# except color).
	(lobby_level
		.restore_players_from_previous_match())


## Despawn lobby level before connecting to
## server.
func _client_despawn_lobby_if_present() -> void:
	if not G.is_lobby_active:
		return

	Netcode.print(
		"Despawning lobby level",
		NetworkLogger.CATEGORY_CORE_SYSTEMS,
	)

	# Close settings menu if open.
	for child in G.side_panel_layer.get_children():
		if child is SidePanelManager:
			child.close_all()
			break


	var lobby_level: LobbyLevel = G.level
	levels.erase(lobby_level)
	lobby_level.queue_free()
	G.level = null


func client_load_game() -> void:
	Netcode.check_is_client()
	Netcode.check(
		not G.client_session.is_game_active,
		"Game is already active",
	)
	Netcode.check(
		not G.client_session.is_game_loading,
		"Game is already loading",
	)

	# Despawn lobby if present.
	_client_despawn_lobby_if_present()

	G.client_session.clear_latest_state()
	G.client_session.is_game_active = false
	G.client_session.is_game_loading = true

	# Reset frame index for new match to sync
	# with server's reset.
	Netcode.frame_driver.client_reset()

	# Hide overhead labels before the tile-wipe
	# captures the screen.
	if is_instance_valid(
		G.player_overhead_labels
	):
		G.player_overhead_labels.hide_all()

	G.screens.client_open_screen(
		ScreensMain.ScreenType.LOADING)

	# Check offline mode preference.
	var is_offline: bool = (
		G.local_settings != null
		and G.local_settings.get_value(
			&"prefer_offline_mode"))

	if is_offline:
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.PLAYING_OFFLINE"))
		_client_start_local_mode()
	else:
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.PLAYING_ONLINE"))
		# Request session IDs from backend
		# before connecting.
		_client_client_request_session_ids()


func _client_client_request_session_ids() -> void:
	Netcode.check_is_client()
	var session_prefs: SessionPreferences = null
	if G.local_settings != null:
		session_prefs = SessionPreferences.new()
		session_prefs.level_preferences = (
			G.local_settings
				.load_level_preferences())
		session_prefs.are_critters_enabled = (
			G.local_settings.get_value(
				&"are_critters_enabled"))
		session_prefs.are_cheats_enabled = (
			G.local_settings.get_value(
				&"are_cheats_enabled"))
	session_manager.client_request_session(
		session_prefs)


func _on_local_mode_fallback() -> void:
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.LOCAL_MODE_FALLBACK"))
	_client_start_local_mode()


## Sets up offline local-only mode. The process
## stays a client but also runs server-side
## game logic via is_local_mode.
func _client_start_local_mode() -> void:
	# Clear lobby player state from match state.
	# The lobby writes directly to
	# G.match_state.players_by_id, and queue_free
	# on the lobby level does not remove them.
	G.match_state.clear()

	# Initialize local mode in session manager.
	session_manager.start_local_mode()

	# Connect late server-side signals that are
	# normally connected in _ready() under
	# if Netcode.is_server.
	session_manager.match_ready.connect(
		_on_match_ready)
	(session_manager.session_provider
		.all_players_connected.connect(
			_server_on_all_players_connected))
	Netcode.frame_driver.server_pause_validator = (
		_server_validate_pause_request)

	# Connect MatchStateSynchronizer server
	# signals (normally connected in its _ready
	# under if Netcode.is_server).
	(Netcode.connector
		.peer_players_declared.connect(
			match_state_synchronizer
				._server_on_peer_players_declared))
	(Netcode.connector
		.disconnected.connect(
			match_state_synchronizer
				._server_on_peer_disconnected))

	# Mark game as active (normally done by
	# _client_on_server_connected via signal).
	G.client_session.is_game_active = true

	# Set expected player count.
	var player_count := (
		G.client_session.local_player_count)
	(session_manager
		.server_set_expected_players(
			player_count))

	# Get selected level and spawn it.
	var level_scene := (
		_server_get_selected_level_scene())
	_server_spawn_level(level_scene)

	# Generate fake session IDs and simulate
	# player declaration.
	var session_ids: Array = []
	for i in range(player_count):
		session_ids.append(
			"local_%d" % (i + 1))

	Netcode.connector.local_mode_setup(
		G.client_session
			.local_player_attributes,
		session_ids,
	)


## Tear down local-mode state: disconnect late
## signals, reset the pause validator, and clear
## the local-mode flag.
func _cleanup_local_mode() -> void:
	# Disconnect late server-side signals
	# connected in _client_start_local_mode().
	if session_manager.match_ready.is_connected(
			_on_match_ready):
		session_manager.match_ready.disconnect(
			_on_match_ready)
	var provider := session_manager.session_provider
	if (is_instance_valid(provider)
			and provider.all_players_connected
				.is_connected(
					_server_on_all_players_connected
				)):
		(provider.all_players_connected
			.disconnect(
				_server_on_all_players_connected))

	# Disconnect MatchStateSynchronizer signals.
	if (Netcode.connector
			.peer_players_declared.is_connected(
				match_state_synchronizer
					._server_on_peer_players_declared
			)):
		(Netcode.connector
			.peer_players_declared.disconnect(
				match_state_synchronizer
					._server_on_peer_players_declared
			))
	if (Netcode.connector
			.disconnected.is_connected(
				match_state_synchronizer
					._server_on_peer_disconnected
			)):
		(Netcode.connector
			.disconnected.disconnect(
				match_state_synchronizer
					._server_on_peer_disconnected))

	# Reset pause validator.
	Netcode.frame_driver.server_pause_validator = Callable()

	# Restore original session provider and
	# reset multiplayer peer.
	session_manager.cleanup_local_mode()

	Netcode.is_local_mode = false


## Shared cleanup after a match ends. Disconnects
## from the server, saves state, and resets the
## frame driver. Does NOT open any screen or free
## levels.
func _client_cleanup_after_match() -> void:
	_stop_session_poll()

	# Reset cheat state when leaving match.
	if is_instance_valid(G.cheat_manager):
		G.cheat_manager.reset()

	G.client_session.is_game_active = false
	G.client_session.is_game_loading = false

	if Netcode.is_local_mode:
		_cleanup_local_mode()
	else:
		Netcode.connector.client_disconnect()
		# Null out the peer so persistent
		# MultiplayerSynchronizer nodes (e.g.
		# MatchStateSynchronizer) stop trying to
		# sync on an inactive ENet peer.
		multiplayer.multiplayer_peer = null
	G.client_session.copy_latest_state(
		G.match_state)

	# Sync updated adjectives from match state
	# back into latest attributes so they persist
	# into the lobby.
	for i in range(
		G.client_session
			.latest_local_player_ids.size()
	):
		var pid: int = (
			G.client_session
				.latest_local_player_ids[i])
		var ps: GamePlayerState = (
			G.match_state.players_by_id.get(pid))
		if (ps
				and i < G.client_session
					.latest_local_player_attributes
					.size()):
			(G.client_session
				.latest_local_player_attributes[
					i])["adj_list_id"] = (
				ps.adj_list_id)
			(G.client_session
				.latest_local_player_attributes[
					i])["adj_index"] = (
				ps.adj_index)
			(G.client_session
				.latest_local_player_attributes[
					i])["is_soft"] = false

	# Build participants list for post-match
	# friend add. Uses backend_player_id_map
	# received from server via RPC.
	_populate_match_participants()

	G.client_session.clear()

	# Track rounds played for settings book gating.
	G.local_settings.increment_rounds_played()

	# Pause frame driver so it stops running
	# network processing (rollback, buffers,
	# etc.) in the lobby.
	Netcode.frame_driver.client_reset()

	# Reset match timer state for next game.
	G.match_state.match_start_frame_index = -1
	G.match_state.is_match_ended = false


## Populate latest_match_participants from match
## state and backend ID mapping. Skips local
## players since they are on the same device.
func _populate_match_participants() -> void:
	G.client_session.latest_match_participants.clear()
	for pid in G.match_state.players_by_id:
		if pid in G.client_session.local_player_ids:
			continue
		var ps: GamePlayerState = (
			G.match_state.players_by_id[pid])
		var backend_id: String = (
			G.client_session
				.backend_player_id_map
				.get(pid, ""))
		var has_profile_image := (
			G.client_session.profile_image_urls
				.has(pid))
		var name: String = (
			G.client_session.auth_display_names
				.get(pid, ""))
		if name.is_empty():
			name = String(ps.full_name)
		var entry := {
			"player_id": pid,
			"display_name": name,
			"backend_player_id": backend_id,
			"is_anonymous": (
				backend_id.is_empty()
				or not has_profile_image),
		}
		G.client_session.latest_match_participants.append(
			entry)


## Free game levels, open the given screen with
## a tile-wipe transition, and reset the
## celebration overlay.
func _client_free_levels_and_open_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	# Snapshot existing levels before switching
	# screens. _client_spawn_lobby() will add
	# the new lobby to the levels array, so we
	# must only free the old ones.
	var old_levels := levels.duplicate()

	# Hide overhead labels before the tile-wipe
	# captures the screen.
	if is_instance_valid(
		G.player_overhead_labels
	):
		G.player_overhead_labels.hide_all()

	# Open screen. The tile-wipe transition
	# captures the current viewport (which
	# includes the iris overlay if the celebration
	# ran) before switching.
	G.screens.client_open_screen(screen_type)

	# Reset celebration AFTER the screen capture
	# so the iris overlay is still visible (black)
	# when the tile-wipe captures the screen.
	if is_instance_valid(G.celebration):
		G.celebration.reset()

	# Free only the pre-existing levels (game
	# level), not the newly spawned lobby.
	for level in old_levels:
		levels.erase(level)
		level.queue_free()


## Clean up after match and return to the lobby.
## Used for unexpected disconnects and session
## override kicks.
func client_exit_match() -> void:
	Netcode.check_is_client()
	_has_transitioned_to_game_over = false

	# Restore default physics tick rate.
	Netcode.restore_default_physics_fps()

	# Release the backend session lock so the
	# player can re-queue immediately. Skip for
	# session override kicks: the session belongs
	# to another device now.
	if (
		not _is_session_override_kick
		and Netcode.should_connect_to_remote_server
		and session_manager.session_provider
			.has_method("clear_session")
	):
		session_manager.session_provider.clear_session()

	_is_session_override_kick = false

	_client_cleanup_after_match()
	_client_free_levels_and_open_screen(
		ScreensMain.ScreenType.LOBBY)


## Clean up after match and show the game over
## screen with results. Used for expected
## (normal) match endings. May be called twice
## (client-side timer + disconnect handler).
## The guard prevents double-transition.
var _has_transitioned_to_game_over := false

func _client_transition_to_game_over() -> void:
	if _has_transitioned_to_game_over:
		return
	# Guard: session override kick already exited
	# the match and freed levels.
	if not G.client_session.is_game_active:
		return
	_has_transitioned_to_game_over = true
	# Defer cleanup so we don't tear down the multiplayer
	# peer from inside its own peer_disconnected callback.
	# Godot 4.7-beta1 crashes the preview client silently
	# when `multiplayer.multiplayer_peer = null` fires
	# while the multiplayer dispatcher is still processing
	# the disconnect event (no error, no Main.close_app,
	# process just exits ~60ms after the transition starts).
	# Deferred runs from the next idle tick when the
	# dispatcher is idle.
	_client_cleanup_after_match.call_deferred()
	_client_free_levels_and_open_screen.call_deferred(
		ScreensMain.ScreenType.GAME_OVER)


## Start a new match from the game over screen
## without returning to the lobby first.
func client_play_again() -> void:
	Netcode.check_is_client()
	_has_transitioned_to_game_over = false

	# Restore player configs from last match.
	G.client_session.local_device_configs = (
		G.client_session
			.latest_local_device_configs
			.duplicate())
	G.client_session.local_player_attributes = (
		G.client_session
			.latest_local_player_attributes
			.duplicate(true))

	G.client_session.is_game_loading = true

	# Reset frame index for new match.
	Netcode.frame_driver.client_reset()

	# Hide overhead labels before the tile-wipe
	# captures the screen.
	if is_instance_valid(
		G.player_overhead_labels
	):
		G.player_overhead_labels.hide_all()

	G.screens.client_open_screen(
		ScreensMain.ScreenType.LOADING)

	# Check offline mode preference.
	var is_offline: bool = (
		G.local_settings != null
		and G.local_settings.get_value(
			&"prefer_offline_mode"))

	if is_offline:
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.PLAYING_OFFLINE"))
		_client_start_local_mode()
	else:
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.PLAYING_ONLINE"))
		_client_client_request_session_ids()


func server_start_match() -> void:
	Netcode.check_is_server()
	Netcode.check(
		not G.client_session.is_game_active,
		"Game is already active",
	)
	Netcode.check(
		not is_instance_valid(G.level),
		"Level is already set",
	)

	G.client_session.is_game_active = true

	# Reset timer state.
	G.match_state.match_start_frame_index = -1
	G.match_state.is_match_ended = false

	# Set expected player count for session
	# validation. In preview mode, this is the
	# number of client instances. In production,
	# GameLiftServerProvider sets this from
	# session properties.
	if Netcode.is_preview:
		var expected_client_count := (
			Netcode.settings.preview_client_count)
		(session_manager
			.server_set_expected_players(
				expected_client_count))
	elif OS.get_environment("PLATFORM") == "edgegap":
		# Nakama runtime injects EXPECTED_PLAYER_COUNT into
		# the Edgegap deploy when allocating this server. If
		# missing or unparseable, fall back to the
		# matchmaker's min_count so the match can still
		# start (an unset count would leave
		# all_players_connected stuck and the match would
		# never begin).
		var raw := OS.get_environment(
			"EXPECTED_PLAYER_COUNT")
		var expected_count := raw.to_int()
		if expected_count <= 0:
			Netcode.log.warning(
				(
					"EXPECTED_PLAYER_COUNT env missing"
					+ " or invalid (raw=%s); falling"
					+ " back to 2"
				) % raw,
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			expected_count = 2
		session_manager.server_set_expected_players(
			expected_count)

	# Get selected level from session provider
	# (GameLift or preview mode).
	var level_scene := (
		_server_get_selected_level_scene())

	_server_spawn_level(level_scene)

	Netcode.connector.server_enable_connections(
		Netcode.server_port)


func server_end_match() -> void:
	# Guard against calls after local mode cleanup
	# (delayed timer callbacks can fire after the
	# client-side game-over flow already tore down
	# local mode).
	if not Netcode.runs_server_logic:
		return

	# Guard against multiple calls (from delayed
	# timer callbacks).
	if not G.client_session.is_game_active:
		return
	if not is_instance_valid(G.level):
		return

	G.client_session.is_game_active = false
	G.match_state.match_start_frame_index = -1
	G.match_state.is_match_ended = false

	if Netcode.is_local_mode:
		# Local mode: client_exit_match handles
		# cleanup, level free, and lobby transition.
		client_exit_match()
		return
	elif Netcode.is_preview:
		# Preview mode: disconnect clients but
		# keep session open for next match.
		(Netcode.connector
			.server_disconnect_all_clients())
	else:
		# Production: close entire session.
		(Netcode.connector
			.server_close_multiplayer_session())

	_server_report_match_result()

	# G.level may already be null if the disconnect
	# above triggered a server reset callback that
	# destroyed the level.
	if is_instance_valid(G.level):
		_server_destroy_level(G.level)


## Sends the backend player ID mapping to all
## clients via RPC so they can friend-add after
## the match. Packs as flat array [pid, bid, ...].
func _server_send_backend_ids_to_clients() -> void:
	var provider := (
		session_manager.session_provider)
	if not provider.has_method(
			"get_backend_player_id_map"):
		return
	var backend_id_map: Dictionary = (
		provider.get_backend_player_id_map())
	if backend_id_map.is_empty():
		return
	# Skip anonymous players so clients cannot
	# friend-add them. Providers that don't track
	# anonymity (e.g. EdgegapServerProvider today)
	# return an empty dict, so every player is
	# treated as a friend-addable identity.
	var anonymous_ids: Dictionary = {}
	if provider.has_method("get_anonymous_backend_ids"):
		anonymous_ids = provider.get_anonymous_backend_ids()
	var packed_data: Array = []
	for player_id in backend_id_map:
		var backend_id: String = (
			backend_id_map[player_id])
		if backend_id in anonymous_ids:
			continue
		packed_data.append(player_id)
		packed_data.append(backend_id)
	if packed_data.is_empty():
		return
	Netcode.call_client_rpc_with_local_support(
		match_state_synchronizer
			._rpc_client_receive_backend_ids
			.bind(packed_data))


## Sends profile image URLs to all clients via
## RPC so they can render avatars. Packs as flat
## array [pid, url, ...].
func _server_send_profile_images_to_clients(
) -> void:
	var provider := (
		session_manager.session_provider)
	if not provider.has_method(
			"get_profile_image_url_map"):
		return
	var image_url_map: Dictionary = (
		provider.get_profile_image_url_map())
	if image_url_map.is_empty():
		return
	var packed_data: Array = []
	for player_id in image_url_map:
		packed_data.append(player_id)
		packed_data.append(
			image_url_map[player_id])
	Netcode.call_client_rpc_with_local_support(
		match_state_synchronizer
			._rpc_client_receive_profile_images
			.bind(packed_data))


## Sends auth display names to all clients via
## RPC. Packs as flat array [pid, name, ...].
func _server_send_display_names_to_clients(
) -> void:
	var provider := (
		session_manager.session_provider)
	if not provider.has_method(
			"get_display_name_map"):
		return
	var name_map: Dictionary = (
		provider.get_display_name_map())
	if name_map.is_empty():
		return
	var packed_data: Array = []
	for player_id in name_map:
		packed_data.append(player_id)
		packed_data.append(name_map[player_id])
	Netcode.call_client_rpc_with_local_support(
		match_state_synchronizer
			._rpc_client_receive_display_names
			.bind(packed_data))


## Reports match results to the Nakama runtime via the
## match_end RPC. Only runs on production servers (preview
## skipped: no match history written for local tests).
func _server_report_match_result() -> void:
	var provider := (
		session_manager.session_provider)
	if not provider.has_method(
			"get_backend_player_id_map"):
		return
	var backend_id_map: Dictionary = (
		provider.get_backend_player_id_map())
	if backend_id_map.is_empty():
		Netcode.print(
			"No backend player ID mapping."
			+ " Skipping match report.",
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	# Build one result per backend_player_id. When couch
	# co-op players share an account, keep the entry with
	# the best (lowest) rank.
	var best_by_backend_id: Dictionary = {}
	for pid in G.match_state.players_by_id:
		var ps: GamePlayerState = (
			G.match_state.players_by_id[pid])
		var backend_id: String = (
			backend_id_map.get(pid, ""))
		if backend_id.is_empty():
			continue
		var existing: Dictionary = (
			best_by_backend_id.get(backend_id, {}))
		if (not existing.is_empty()
				and existing["rank"] <= ps.rank):
			continue
		var per_player_stats: PlayerMatchStats = (
			G.match_state.get_player_stats(pid))
		# Shape matches the runtime's matchEndPlayer
		# struct: user_id + score + kills + bumps. Rank
		# is consumed locally to derive winner_id.
		var entry := {
			"user_id": backend_id,
			"score": ps.score,
			"kills": (per_player_stats.kill_count
				if per_player_stats != null else 0),
			"bumps": (per_player_stats.bump_count
				if per_player_stats != null else 0),
			"_rank": ps.rank,
		}
		best_by_backend_id[backend_id] = entry

	var winner_id := ""
	var players: Array = []
	for entry in best_by_backend_id.values():
		if entry["_rank"] == 1:
			winner_id = entry["user_id"]
		entry.erase("_rank")
		players.append(entry)

	var duration_sec: float = (
		G.match_state.match_duration_usec
		/ 1_000_000.0)
	var level_id: String = String(
		provider.server_get_selected_level_id())
	var request_id: String = OS.get_environment(
		"ARBITRIUM_DEPLOY_REQUEST_ID")
	if request_id.is_empty():
		request_id = OS.get_environment(
			"ARBITRARIUM_DEPLOY_REQUEST_ID")
	var match_stats := {
		"duration_sec": duration_sec,
		"level_id": level_id,
	}

	G.match_result_reporter.report(
		request_id,
		winner_id,
		players,
		match_stats,
	)


## Resolves critter preference and spawns snails
## if enabled.
func _server_resolve_critter_preference() -> void:
	var critters_enabled := true
	if G.local_settings != null:
		critters_enabled = (
			G.local_settings.get_value(
				&"are_critters_enabled"))

	Netcode.print(
		"Critters: %s" % (
			"enabled"
			if critters_enabled
			else "disabled"),
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	if (critters_enabled
			and G.level is NetworkedLevel):
		G.level.server_spawn_snails()


func _server_validate_pause_request(
	peer_id: int,
) -> Dictionary:
	Netcode.check_is_server()

	# Block pauses after match has ended.
	if G.match_state.is_match_ended:
		Netcode.print(
			"Client %d pause rejected:"
			+" match has ended" % peer_id,
			NetworkLogger.CATEGORY_NETWORK_SYNC,
		)
		return {"allowed": false}

	# Check pause limit.
	var max_pauses := (
		G.settings.max_pauses_per_client)
	var used: int = (
		G.match_state.pauses_used_by_peer
			.get(peer_id, 0))
	if used >= max_pauses:
		Netcode.print(
			"Client %d pause rejected:"
			+" limit reached (%d/%d)" % [
				peer_id, used, max_pauses],
			NetworkLogger.CATEGORY_NETWORK_SYNC,
		)
		return {"allowed": false}

	# Increment and allow.
	used += 1
	G.match_state.pauses_used_by_peer[
		peer_id] = used
	return {"allowed": true, "pauses_used": used}


func _server_on_all_players_connected() -> void:
	Netcode.check_is_server()

	# In preview mode, hot-reload settings and
	# level from local storage before starting.
	# Skip in local mode: hot-reload replays
	# peer declarations via get_peers(), which
	# is empty in local mode.
	if Netcode.is_preview and not Netcode.is_local_mode:
		_server_preview_hot_reload()

	Netcode.print(
		"All players validated, starting match",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Send profile images and display names to
	# clients now that all peers have declared.
	_server_send_profile_images_to_clients()
	_server_send_display_names_to_clients()

	# Unpause frame driver to start simulation.
	# The framework automatically triggers
	# countdown if enabled in settings.
	Netcode.frame_driver.server_set_is_paused(
		false)


## Re-reads local_settings.cfg from disk, applies
## overrides to G.settings, then destroys and
## re-spawns the level with fresh preferences.
## Called in preview mode before countdown starts.
func _server_preview_hot_reload() -> void:
	Netcode.check_is_server()
	Netcode.print(
		"Hot-reloading settings and level"
		+" for preview mode",
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# 1. Reload settings from disk.
	G.local_settings.load_settings()
	G.local_settings.apply_all_overrides()

	# 2. Save peer declarations before
	#    destroying the level.
	var declarations := (
		Netcode.connector
			.server_get_peer_declarations())

	# 3. Clear match state (players, scores).
	G.match_state.clear()

	# 4. Destroy current level and its players.
	#    Remove from tree immediately (not
	#    deferred) so MultiplayerSpawner sends
	#    the despawn before we add the new level,
	#    and the old camera releases.
	if is_instance_valid(G.level):
		var old_level := G.level
		_server_destroy_level(old_level)
		if old_level.get_parent() != null:
			(old_level.get_parent()
				.remove_child(old_level))

	# 5. Spawn new level with fresh preferences.
	var level_scene := (
		_server_get_selected_level_scene())
	_server_spawn_level(level_scene)

	# 6. Re-set expected player count (cleared
	#    with match state).
	var expected_count: int = (
		Netcode.settings.preview_client_count)
	(%MatchStateSynchronizer
		.server_set_expected_player_count(
			expected_count))

	# 7. Replay peer declarations so the new
	#    level spawns players and
	#    MatchStateSynchronizer re-creates
	#    PlayerState objects. Only replay for
	#    currently connected peers. Stale entries
	#    from prior matches (old peer IDs) are
	#    skipped.
	var connected_peers := (
		multiplayer.get_peers())
	for peer_id in declarations:
		if peer_id not in connected_peers:
			continue
		var decl: Dictionary = (
			declarations[peer_id])
		(Netcode.connector
			.peer_players_declared.emit(
				peer_id,
				decl["assigned_ids"],
				decl["attributes"],
			))

	# 8. Re-resolve critter preference (was
	#    done in _on_match_ready, but match
	#    state was cleared).
	_server_resolve_critter_preference()


func _on_match_start_countdown_started(
	_countdown_end_frame: int,
) -> void:
	# Show match start countdown UI on clients.
	if is_instance_valid(G.hud):
		G.hud.start_match_countdown()


func _on_match_start_countdown_ended() -> void:
	G.audio.fade_in_main_theme()


func _server_on_preview_peer_connected(
	_peer_id: int,
) -> void:
	Netcode.check_is_server()

	# If no level exists or match has ended,
	# spawn a new level for the new match.
	if (not is_instance_valid(G.level)
			or G.match_state.is_match_ended):
		Netcode.print(
			"Spawning new level for next match",
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		# Clean up old level if it still exists.
		if is_instance_valid(G.level):
			_server_destroy_level(G.level)
		# Clear match state (removes old players,
		# kills, bumps, etc.).
		G.match_state.clear()
		# Mark game as active for new match.
		G.client_session.is_game_active = true
		# Reset timer state for new match.
		G.match_state.match_start_frame_index = -1
		G.match_state.is_match_ended = false
		# Reset expected client count for session
		# validation (preview mode).
		var expected_client_count := (
			Netcode.settings
				.preview_client_count)
		(session_manager
			.server_set_expected_players(
				expected_client_count))
		# NOTE: MatchStateSynchronizer expected
		# count set in _on_match_ready().
		# Reset frame counter for fresh match
		# start.
		Netcode.frame_driver.server_frame_index = 0
		# Start grace period to suppress expected
		# frame sync warnings.
		Netcode.frame_driver._frame_reset_time_usec = (
			Time.get_ticks_usec())
		# Reset match start countdown state from
		# previous match.
		Netcode.frame_driver.match_start_countdown_end_frame_index = -1
		Netcode.frame_driver._has_match_start_countdown_started = false
		Netcode.frame_driver._has_match_start_countdown_ended = false
		# Reconnect preview mode auto-unpause
		# signal for new match.
		(Netcode.frame_driver
			.server_reset_preview_mode_unpause())
		# Get selected level (may use preferences
		# from preview mode).
		var level_scene := (
			_server_get_selected_level_scene())
		_server_spawn_level(level_scene)


func _process(_delta: float) -> void:
	if not Netcode.runs_server_logic:
		return

	# Start timer when ready.
	if G.match_state.match_start_frame_index < 0:
		_server_check_start_match_timer()
		return

	# Check if time has expired.
	if (not G.match_state.is_match_ended
			and G.match_state
				.is_match_time_expired):
		_server_initiate_match_end()


func _server_check_start_match_timer() -> void:
	if G.match_state.match_start_frame_index >= 0:
		return
	if not is_level_fully_loaded:
		return
	if not is_instance_valid(G.level):
		return

	var match_duration_sec := (
		G.settings.match_duration_sec)

	# Start timer once level is loaded (sets
	# match_start_frame_index).
	G.match_state.server_start_match_timer(
		match_duration_sec)

	Netcode.print(
		"Match timer started: %d seconds"
		% match_duration_sec,
		NetworkLogger.CATEGORY_GAME_STATE,
	)


## Checks whether a mid-match disconnect has left
## only one peer (or zero) remaining. If so, ends
## the match early with the remaining player(s)
## winning by default.
func _server_check_auto_end_on_disconnect() -> void:
	if Netcode.is_local_mode:
		return
	if G.match_state.is_match_ended:
		return
	if not G.match_state.is_match_active:
		return

	var remaining_players := 0
	for pid in G.match_state.players_by_id:
		var ps: PlayerState = (
			G.match_state.players_by_id[pid])
		if ps.is_connected_to_server:
			remaining_players += 1

	if remaining_players > 1:
		return

	# 0 players: nobody left. Existing
	# _server_on_all_clients_disconnected handles
	# cleanup. Skip the celebration sequence since
	# nobody would see it.
	if remaining_players == 0:
		return

	Netcode.print(
		"Only 1 player remaining."
		+ " Auto-ending match (forfeit win).",
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# Mark as forfeit so celebration is altered.
	G.match_state.is_forfeit_win = true

	# Demote disconnected players so remaining
	# player(s) are rank 1.
	G.match_state.server_demote_disconnected_players()

	_server_initiate_match_end()


func _server_initiate_match_end() -> void:
	Netcode.check_is_server()
	Netcode.check(
		not G.match_state.is_match_ended,
		"Match end already initiated",
	)

	Netcode.print(
		"Match time expired"
		+" - initiating end sequence",
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	# Assign dynamic adjectives based on stats.
	var new_adjectives := (
		DynamicAdjectiveConfig
			.assign_adjectives(
				G.match_state
					._stats_by_player_id))
	for player_id in new_adjectives:
		var ps: GamePlayerState = (
			G.match_state.players_by_id
				.get(player_id))
		if ps:
			var data: Dictionary = (
				new_adjectives[player_id])
			ps.adj_list_id = data.adj_list_id
			ps.adj_index = data.adj_index
	# Repack to replicate updated adjectives.
	G.match_state._server_pack_players()

	# Send final stats to all clients so they
	# have complete data for the game over screen.
	(match_state_synchronizer
		._server_send_stats_to_clients())

	# Send backend player ID mapping to clients
	# so they can friend-add post-match.
	_server_send_backend_ids_to_clients()

	# Send profile image URLs and display names
	# to all clients.
	_server_send_profile_images_to_clients()
	_server_send_display_names_to_clients()

	# Set flag to enable invincibility for all
	# players and notify clients.
	G.match_state.is_match_ended = true
	G.match_state.match_ended.emit()
	Netcode.call_client_rpc_with_local_support(
		match_state_synchronizer
			._rpc_client_notify_match_ended)

	# Send dynamic adjectives to clients for
	# celebration reveal. Stride of 3:
	# [player_id, adj_list_id, adj_index, ...].
	var packed_adjective_data: Array = []
	for player_id in new_adjectives:
		var data: Dictionary = (
			new_adjectives[player_id])
		packed_adjective_data.append(player_id)
		packed_adjective_data.append(
			data.adj_list_id)
		packed_adjective_data.append(
			data.adj_index)
	Netcode.call_client_rpc_with_local_support(
		match_state_synchronizer
			._rpc_client_notify_dynamic_adjectives
			.bind(packed_adjective_data))

	# Schedule server shutdown after wait period.
	Netcode.time.set_timeout(
		server_end_match,
		G.settings.match_end_disconnect_delay_sec,
	)


func on_return_to_game_from_screen(
	_previous_screen_type: ScreensMain.ScreenType,
) -> void:
	Netcode.check(
		G.client_session.is_game_active,
		"Game is not active",
	)
	Netcode.check(
		not G.client_session.is_game_loading,
		"Game is still loading",
	)


func on_left_game_to_screen(
	_next_screen_type: ScreensMain.ScreenType,
) -> void:
	pass


func on_return_to_lobby_from_screen(
	_previous_screen_type: ScreensMain.ScreenType,
) -> void:
	_client_spawn_lobby()


func on_left_lobby_to_screen(
	_next_screen_type: ScreensMain.ScreenType,
) -> void:
	pass


## Get the level scene to spawn based on session
## provider selection. If no level is selected,
## picks a random enabled level.
func _server_get_selected_level_scene() -> PackedScene:
	Netcode.check(G.level_registry != null)

	# In preview mode, check for level index
	# override from settings.
	if Netcode.is_preview:
		var override_index := -1
		if G.settings.level_override_for_preview >= 0:
			override_index = (
				G.settings
					.level_override_for_preview)

		if override_index >= 0:
			var max_index := (
				G.level_registry
					.get_level_count() - 1)
			var clamped := clampi(
				override_index, 0, max_index)
			var info := (
				G.level_registry
					.get_level_by_index(clamped))
			if info != null and info.scene != null:
				Netcode.print(
					"Using level override"
					+" index %d: %s (%s)" % [
						clamped,
						info.id,
						info.display_name],
					NetworkLogger
						.CATEGORY_GAME_STATE,
				)
				return info.scene

	var level_id := (
		session_manager
			.server_get_selected_level_id())

	if not level_id.is_empty():
		var level_info := (
			G.level_registry
				.get_level_by_id(level_id))
		if (level_info != null
				and level_info.scene != null):
			Netcode.print(
				"Using selected level:"
				+" %s (%s)" % [
					level_id,
					level_info.display_name],
				NetworkLogger
					.CATEGORY_GAME_STATE,
			)
			return level_info.scene
		else:
			Netcode.warning(
				"Selected level '%s' not found"
				+" in registry" % level_id,
				NetworkLogger
					.CATEGORY_GAME_STATE,
			)

	# Check local settings for level preferences
	# (shared filesystem in preview mode).
	if G.local_settings != null:
		var prefs: LevelPreferences = (
			G.local_settings
				.load_level_preferences())
		if (prefs != null
				and prefs.has_preferences()):
			var selected := (
				_server_select_from_prefs(prefs))
			if selected != null:
				return selected

	# No level selected. Pick random from enabled
	# levels.
	var random_level := (
		G.level_registry
			.get_random_enabled_level())
	if random_level != null:
		Netcode.print(
			"Randomly selected level:"
			+" %s (%s)" % [
				random_level.id,
				random_level.display_name],
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return random_level.scene

	Netcode.warning(
		"No enabled levels available",
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	return null


## Selects a level scene based on local level
## preferences.
func _server_select_from_prefs(
	prefs: LevelPreferences,
) -> PackedScene:
	# Use preferred level if set.
	if not prefs.preferred_level.is_empty():
		var info := (
			G.level_registry.get_level_by_id(
				prefs.preferred_level))
		if info != null and info.scene != null:
			Netcode.print(
				"Using preferred level:"
				+" %s (%s)" % [
					info.id,
					info.display_name],
				NetworkLogger
					.CATEGORY_GAME_STATE,
			)
			return info.scene

	# Filter enabled levels by preferences.
	var allowed: Array[LevelInfo] = []
	for info: LevelInfo in (
		G.level_registry._levels
	):
		if (info.is_enabled
				and prefs.is_level_allowed(
					info.id)):
			allowed.append(info)

	if allowed.is_empty():
		return null

	var pick: LevelInfo = allowed.pick_random()
	Netcode.print(
		"Selected level from prefs:"
		+" %s (%s)" % [
			pick.id, pick.display_name],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
	return pick.scene


func _server_spawn_level(
	level_scene: PackedScene,
) -> void:
	Netcode.check_is_server()
	Netcode.check(level_scene != null)

	Netcode.check(
		G.level_registry
			.get_level_id_for_scene(
				level_scene) != "",
		"level_scene not registered in"
		+" level registry: %s" % level_scene,
	)

	# Pause server to wait for all clients to
	# connect before starting match. In preview
	# mode, frame_driver will auto-unpause when
	# all clients join.
	Netcode.frame_driver.server_set_is_paused(
		true)

	Netcode.print(
		"Spawning level: %s"
		% Utils.get_display_name(level_scene),
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	var level: Level = level_scene.instantiate()
	levels.append(level)
	%Levels.add_child(level)
	G.level = level

	if is_instance_valid(level.level_camera):
		level.level_camera.make_current()


func _server_destroy_level(
	level: Level,
) -> void:
	Netcode.check_is_server()
	Netcode.check(
		levels.has(level),
		"level not in current list: %s" % level,
	)

	Netcode.print(
		"Destroying level: %s"
		% level.get_string(),
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	if G.level == level:
		G.level = null
	levels.erase(level)
	level.queue_free()


func on_level_added(level: Level) -> void:
	if Netcode.is_client:
		G.level = level
		levels.append(level)


func on_level_removed(level: Level) -> void:
	if Netcode.is_client:
		is_level_fully_loaded = false
		if G.level == level:
			G.level = null
		levels.erase(level)


## Validates and sanitizes player attributes for
## bunny configuration. Called by
## NetworkConnector when players declare their
## attributes.
# --- Active Session Polling ---
# Polls GET /session/active during a match to detect
# if another device started matchmaking for the same
# account. If the backend session is no longer
# "in_match", the client disconnects.


func _start_session_poll() -> void:
	# Only poll during remote server matches with
	# authenticated (non-anonymous) players who have
	# active session records.
	if not Netcode.should_connect_to_remote_server:
		return
	if Netcode.is_local_mode:
		return
	if G.auth_token_store == null:
		return
	if G.auth_token_store.is_anonymous:
		return
	if _PLATFORM_API_URL.is_empty():
		return

	if _session_poll_timer == null:
		_session_poll_timer = Timer.new()
		_session_poll_timer.name = (
			"SessionPollTimer")
		_session_poll_timer.process_mode = (
			Node.PROCESS_MODE_ALWAYS)
		_session_poll_timer.one_shot = false
		_session_poll_timer.timeout.connect(
			_poll_active_session)
		add_child(_session_poll_timer)

	if _session_poll_http == null:
		_session_poll_http = HTTPRequest.new()
		_session_poll_http.name = (
			"SessionPollHTTP")
		_session_poll_http.process_mode = (
			Node.PROCESS_MODE_ALWAYS)
		_session_poll_http.timeout = 10.0
		add_child(_session_poll_http)

	_session_poll_timer.start(
		_SESSION_POLL_INTERVAL_SEC)


func _stop_session_poll() -> void:
	if _session_poll_timer != null:
		_session_poll_timer.stop()


func _poll_active_session() -> void:
	if _session_poll_http == null:
		return
	# Skip if a request is already in flight.
	if (
		_session_poll_http
			.request_completed
			.is_connected(
				_on_session_poll_response)
	):
		return

	var url := (
		_PLATFORM_API_URL
		+ "/session/active")
	var headers: PackedStringArray = [
		"Content-Type: application/json",
	]
	if (
		G.auth_token_store != null
		and G.auth_token_store.is_token_valid()
	):
		headers.append(
			"Authorization: Bearer %s"
			% G.auth_token_store.jwt_token)

	_session_poll_http.request_completed.connect(
		_on_session_poll_response)
	var error := _session_poll_http.request(
		url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		(_session_poll_http.request_completed
			.disconnect(
				_on_session_poll_response))


func _on_session_poll_response(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	_session_poll_http.request_completed.disconnect(
		_on_session_poll_response)

	# Silently ignore errors. Only act on a positive
	# "session changed" response.
	if result != HTTPRequest.RESULT_SUCCESS:
		return
	if response_code != 200:
		return

	var parsed = JSON.parse_string(
		body.get_string_from_utf8())
	if parsed == null or not parsed is Dictionary:
		return

	var state = parsed.get("state")

	# Session is still in_match. All good.
	if state == "in_match":
		return

	# Session state changed (matchmaking, null,
	# etc.). Another device overrode this session.
	_stop_session_poll()
	_is_session_override_kick = true

	Netcode.print(
		"Session overridden by another device"
		+ " (state: %s)" % str(state),
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.KICKED_OTHER_SESSION"),
			ToastOverlay.Type.ERROR,
		)

	client_exit_match()


func _validate_player_attributes(
	attributes: Array,
	expected_count: int,
	peer_id: int,
) -> Array:
	var validated: Array = []

	for i in range(
		min(attributes.size(), expected_count)
	):
		var attr: Dictionary = (
			attributes[i].duplicate())

		# Validate/sanitize name_index.
		var name_idx: int = (
			attr.get("name_index", 0))
		if (name_idx < 0
				or name_idx
					>= DynamicAdjectiveConfig
						.NAMES.size()):
			attr["name_index"] = (
				randi()
				% DynamicAdjectiveConfig
					.NAMES.size())
			Netcode.warning(
				"Peer %d: Invalid name_index,"
				+" assigned random: %d" % [
					peer_id,
					attr["name_index"]],
				NetworkLogger
					.CATEGORY_CONNECTIONS,
			)

		# Validate/sanitize adj_list_id and
		# adj_index.
		var list_id: int = (
			attr.get("adj_list_id", 0))
		var adj_idx: int = (
			attr.get("adj_index", 0))
		if not DynamicAdjectiveConfig \
				.is_valid_adj_list_id(list_id):
			var is_soft: bool = (
				attr.get("is_soft", true))
			list_id = (
				DynamicAdjectiveConfig
					.AdjectiveListType.SOFT
				if is_soft
				else DynamicAdjectiveConfig
					.AdjectiveListType.HARD)
			attr["adj_list_id"] = list_id
			var adj_list: Array = (
				DynamicAdjectiveConfig
					.ADJ_LISTS_BY_ID[list_id])
			attr["adj_index"] = (
				randi() % adj_list.size())
			Netcode.warning(
				"Peer %d: Invalid adj_list_id,"
				+" assigned random" % peer_id,
				NetworkLogger
					.CATEGORY_CONNECTIONS,
			)
		elif not DynamicAdjectiveConfig \
				.is_valid_adj_index(
					list_id, adj_idx):
			var adj_list: Array = (
				DynamicAdjectiveConfig
					.ADJ_LISTS_BY_ID[list_id])
			attr["adj_index"] = (
				randi() % adj_list.size())
			Netcode.warning(
				"Peer %d: Invalid adj_index,"
				+" assigned random" % peer_id,
				NetworkLogger
					.CATEGORY_CONNECTIONS,
			)

		# Ensure required fields exist with
		# defaults. Validate body_type_index
		# bounds.
		var body_type_idx: int = (
			attr.get("body_type_index", 0))
		if (body_type_idx < 0
				or body_type_idx
					>= G.settings
						.body_types.size()):
			Netcode.warning(
				"Peer %d: body_type_index %d"
				+" out of range, assigned 0"
				% [peer_id, body_type_idx],
				NetworkLogger
					.CATEGORY_CONNECTIONS,
			)
			attr["body_type_index"] = 0

		# Validate costume_index bounds.
		var costume_idx: int = (
			attr.get("costume_index", 0))
		if (costume_idx < 0
				or costume_idx
					>= G.settings
						.costumes.size()):
			Netcode.warning(
				"Peer %d: costume_index %d"
				+" out of range, assigned 0"
				% [peer_id, costume_idx],
				NetworkLogger
					.CATEGORY_CONNECTIONS,
			)
			attr["costume_index"] = 0

		validated.append(attr)

	return validated
