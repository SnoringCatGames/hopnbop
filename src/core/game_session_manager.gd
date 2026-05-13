class_name GameSessionManager
extends Node
## Manages network session lifecycle for Hop 'n Bop.
##
## Coordinates session provider setup, connection flow, player ID assignment,
## and disconnect handling. Emits high-level events that game logic can respond
## to without directly handling network signals.

## Emitted when local player IDs are assigned by the server.
signal session_established(player_ids: Array[int])

## Emitted when all players are connected and validated (server only).
signal match_ready()

## Emitted when connection is lost.
signal connection_lost(reason_name: String, is_expected: bool)

## Emitted when server should reset for a new match (preview mode only).
signal server_should_reset()

## Emitted during matchmaking to report progress
## to the UI (client only).
signal matchmaking_progress(
	phase: String,
	elapsed_sec: float,
	estimated_total_sec: float,
)

## Emitted when the server must shut down soon
## (Spot reclamation or process termination).
signal server_shutdown_imminent(
	seconds_remaining: float)

## Emitted when matchmaking fails before a server
## connection is established (e.g., cancelled,
## HTTP error). The client should show a toast
## and return to the lobby.
signal matchmaking_failed(reason: String)

## Emitted when matchmaking times out and the
## client has enough local players to fall back
## to offline mode.
signal local_mode_fallback_requested()

var session_provider: SessionProvider

## The original session provider set up in _ready().
## Stored so it can be restored after local mode.
var _original_session_provider: SessionProvider


func _ready() -> void:
	# Must process while paused so HTTPRequest
	# and Timer children work during LOADING
	# screen (tree is paused on non-game screens).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_setup_session_provider()
	_connect_network_signals()


## Set up the appropriate session provider (Edgegap or Preview mode).
func _setup_session_provider() -> void:
	# Edgegap is the only production-server target. The
	# `PLATFORM=edgegap` env (set by Dockerfile.edgegap) is no
	# longer load-bearing — every production server is an
	# Edgegap container — but we keep it as a sanity log so a
	# misconfigured deploy is obvious.
	var is_production_server := (
		Netcode.is_server
		and not Netcode.is_preview
		and Netcode.should_connect_to_remote_server
	)
	if is_production_server and (
			OS.get_environment("PLATFORM") != "edgegap"):
		Netcode.log.warning(
			(
				"Production server detected without"
				+ " PLATFORM=edgegap env — proceeding with"
				+ " EdgegapServerProvider anyway"
			),
			NetworkLogger.CATEGORY_CONNECTIONS,
		)

	if is_production_server:
		session_provider = EdgegapServerProvider.new()
	elif (Netcode.should_connect_to_remote_server
			and Netcode.is_client):
		# Client: drive the Nakama matchmaker. The
		# Nakama runtime's MatchmakerMatched hook
		# allocates an Edgegap deployment and
		# notifies us with the connection info.
		session_provider = NakamaMatchmakerClient.new()
	else:
		# Preview mode or preview server with
		# remote connection: no validation.
		session_provider = PreviewSessionProvider.new(
			Netcode.log,
			{
				"server_ip":
					G.settings
						.local_preview_server_ip_address,
				"server_port":
					G.settings.server_port,
			}
		)

	session_provider.name = "SessionProvider"
	add_child(session_provider)
	_original_session_provider = session_provider

	# Set in NetworkConnector for validation.
	Netcode.connector.session_provider = session_provider

	# Connect to session provider signals.
	if Netcode.is_client:
		session_provider.session_ids_received.connect(
			_on_session_ids_received
		)
		session_provider.session_request_failed.connect(
			_on_session_request_failed
		)
		if session_provider.has_signal(
				"matchmaking_progress_updated"):
			(session_provider
				.matchmaking_progress_updated
				.connect(
					_on_matchmaking_progress))

	if Netcode.is_server:
		session_provider.all_players_connected.connect(
			_on_all_players_connected
		)
		if session_provider.has_signal(
				"shutdown_requested"):
			session_provider.shutdown_requested.connect(
				_on_shutdown_requested)


## Connect to NetworkConnector signals.
func _connect_network_signals() -> void:
	if Netcode.is_client:
		Netcode.connector.player_ids_assigned.connect(
			_on_player_ids_assigned
		)

	# Both client and server listen to disconnected signal.
	Netcode.connector.disconnected.connect(_on_disconnected)


## CLIENT: Request session IDs from backend.
## session_prefs: Optional SessionPreferences
## for matchmaking hints.
## extra_props: Optional dict merged into the
## flattened prefs dict after to_dict(). Used by
## the party flow to inject party_id /
## matchmaker_properties without having to extend
## SessionPreferences for every consumer.
func client_request_session(
	session_prefs: SessionPreferences = null,
	extra_props: Dictionary = {},
) -> void:
	Netcode.check_is_client()

	# Refresh auth token if needed before matchmaking.
	if (
		Platform.token_store != null
		and Platform.token_store.needs_refresh()
	):
		# Notify loading screen that authentication
		# is in progress.
		matchmaking_progress.emit(
			"authenticating", 0.0, -1.0)
		Netcode.print(
			"Refreshing auth token before"
			+ " matchmaking",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		G.auth_client.refresh_token()
		await G.auth_client.auth_completed
		if not Platform.token_store.is_token_valid():
			Netcode.error(
				"Auth token refresh failed,"
				+ " cannot matchmake",
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
			connection_lost.emit(
				"Auth token expired", false
			)
			return

	var player_count := (
		G.client_session.local_player_count)
	var prefs_dict := (
		{}
		if session_prefs == null
		else session_prefs.to_dict())
	for key in extra_props:
		prefs_dict[key] = extra_props[key]

	Netcode.print(
		"Requesting session for"
		+ " %d player(s)%s" % [
			player_count,
			" with session preferences"
			if not prefs_dict.is_empty()
			else ""],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	session_provider.client_request_session_ids(
		player_count, prefs_dict)


## Initialize local-only offline mode. Sets up
## OfflineMultiplayerPeer, swaps to
## LocalOnlySessionProvider, and connects late
## server-side signals.
func start_local_mode() -> void:
	Netcode.is_local_mode = true

	Netcode.print(
		"Starting local mode",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Set up offline multiplayer peer (peer
	# ID 1 = SERVER_ID).
	var offline_peer := (
		OfflineMultiplayerPeer.new())
	multiplayer.multiplayer_peer = offline_peer

	# Swap session provider to local-only.
	# Keep the original alive for restore later.
	var local_provider := (
		LocalOnlySessionProvider.new())
	local_provider.name = (
		"LocalOnlySessionProvider")
	add_child(local_provider)
	session_provider = local_provider
	Netcode.connector.session_provider = (
		local_provider)

	# Connect late server-side signals on
	# this manager.
	(session_provider.all_players_connected
		.connect(_on_all_players_connected))


## Tear down local mode and restore the
## original session provider.
func cleanup_local_mode() -> void:
	# Free the local-only provider.
	if (is_instance_valid(session_provider)
			and session_provider
				is LocalOnlySessionProvider):
		session_provider.queue_free()

	# Restore original provider.
	session_provider = _original_session_provider
	Netcode.connector.session_provider = (
		_original_session_provider)

	# Reset connector state from local mode.
	Netcode.connector.reset_local_mode()

	# Reset multiplayer peer.
	multiplayer.multiplayer_peer = null

	Netcode.print(
		"Local mode cleaned up",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)


## Set expected player count for validation.
func server_set_expected_players(count: int) -> void:
	Netcode.check(
		Netcode.runs_server_logic,
		"Expected server or local mode",
	)

	if session_provider != null and session_provider.has_method(
		"server_set_expected_player_count"
	):
		session_provider.server_set_expected_player_count(count)


## Get the selected level ID for this game session.
## On server: returns level from game session properties.
## On client: returns level from matchmaking response.
func server_get_selected_level_id() -> StringName:
	if Netcode.runs_server_logic:
		if session_provider != null and session_provider.has_method(
			"server_get_selected_level_id"
		):
			return session_provider.server_get_selected_level_id()
	else:
		# Client gets level from stored session response.
		return G.client_session.selected_level_id
	return ""


# --- Signal Handlers ---


func _on_session_ids_received(
	session_ids: Array,
	server_ip: String,
	server_port: int,
	selected_level_id: String,
	signaling_url: String,
) -> void:
	Netcode.print(
		"Session IDs received, connecting to %s:%d%s%s" % [
			server_ip,
			server_port,
			", level: " + selected_level_id if not selected_level_id.is_empty() else "",
			", signaling_url=" + signaling_url if not signaling_url.is_empty() else "",
		],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Store session IDs in local session.
	G.client_session.client_session_ids.clear()
	for session_id in session_ids:
		G.client_session.client_session_ids.append(str(session_id))

	# Store selected level ID (client may use this for UI/preview).
	G.client_session.selected_level_id = StringName(selected_level_id)

	# Connect to server.
	Netcode.connector.client_connect_to_server(
		server_ip, server_port, signaling_url)


func _on_session_request_failed(error_message: String) -> void:
	Netcode.print(
		"Session request failed: %s" % error_message,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Version mismatch is a terminal error. Show a
	# blocking dialog with no way to proceed.
	if error_message.begins_with("Version mismatch"):
		var dialog: ConfirmOverlay = (
			G.settings.confirm_overlay_scene
				.instantiate())
		G.confirm_layer.add_child(dialog)
		dialog.open(
			error_message,
			"Close Game",
			func() -> void:
				get_tree().quit(),
		)
		return

	# Fall back to local mode on timeout with
	# enough local players.
	var is_timeout := error_message.begins_with(
		"Matchmaking timed out")
	if (is_timeout
			and G.client_session.local_player_count
				>= 2):
		local_mode_fallback_requested.emit()
		return

	# No server connection was established, so this
	# is not a connection loss. Signal matchmaking
	# failure so the client returns to the lobby.
	matchmaking_failed.emit(error_message)


func _on_player_ids_assigned(assigned_ids: Array[int]) -> void:
	Netcode.print(
		"Player IDs assigned: %s" % str(assigned_ids),
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Store in local session.
	G.client_session.local_player_ids = assigned_ids.duplicate()

	# Populate profile image URLs for local players
	# from auth store so they are available in the
	# lobby before the server broadcasts them.
	if not Platform.token_store.profile_image_url.is_empty():
		for pid in assigned_ids:
			G.client_session.profile_image_urls[pid] = (
				Platform.token_store.profile_image_url)

	# Emit high-level event for game logic.
	session_established.emit(assigned_ids)


func _on_all_players_connected() -> void:
	Netcode.print(
		"All players connected and validated",
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Emit high-level event for game logic.
	match_ready.emit()


func _on_disconnected(peer_id: int, reason: int) -> void:
	if Netcode.is_client:
		_client_on_server_disconnected(reason)
	elif Netcode.is_server:
		_server_on_client_disconnected(peer_id, reason)


func _client_on_server_disconnected(reason: int) -> void:
	var reason_name: String = NetworkConnector.DisconnectReason.keys()[reason]
	Netcode.print(
		"Disconnected from server: %s" % reason_name,
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Check if this was an expected disconnect (match ended normally).
	var is_expected := (
		reason == NetworkConnector
			.DisconnectReason.MATCH_FINISHED
		or G.match_state.is_match_ended
	)

	if is_expected:
		Netcode.print(
			"Match ended, returning to lobby",
			NetworkLogger.CATEGORY_GAME_STATE
		)
	else:
		Netcode.warning(
			"Unexpected disconnect: %s" % reason_name,
			NetworkLogger.CATEGORY_CONNECTIONS
		)

	# Emit high-level event for game logic.
	connection_lost.emit(reason_name, is_expected)


func _server_on_client_disconnected(peer_id: int, reason: int) -> void:
	var reason_name: String = NetworkConnector.DisconnectReason.keys()[reason]
	Netcode.print(
		"Client %d disconnected: %s" % [peer_id, reason_name],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Check if all clients have disconnected.
	var remaining_peers := multiplayer.get_peers().size()
	Netcode.print(
		"Remaining connected clients: %d" % remaining_peers,
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	if remaining_peers == 0:
		_server_on_all_clients_disconnected()
	elif _should_abort_pre_match(remaining_peers):
		_server_abort_not_enough_players()


func _server_on_all_clients_disconnected() -> void:
	Netcode.print(
		"All clients disconnected",
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	if Netcode.is_preview:
		# In preview mode, signal to reset for another match.
		Netcode.print(
			"Preview mode: Signaling server reset",
			NetworkLogger.CATEGORY_CORE_SYSTEMS
		)
		server_should_reset.emit()
	else:
		# In production mode, exit the server application.
		Netcode.print(
			"Production mode: Exiting server",
			NetworkLogger.CATEGORY_CORE_SYSTEMS
		)
		# Wait long enough for the match_end RPC's HTTP request
		# (10s timeout in match_result_reporter.gd) to complete
		# before tearing down the scene tree. Without this, the
		# in-flight HTTPRequest is freed mid-flight, the runtime
		# never sees match_end, never calls Edgegap's Stop
		# endpoint, and the deployment leaks until the 24h
		# max_duration cap. Observed empirically: 1s was not
		# enough on a remote container with TLS handshake.
		await get_tree().create_timer(12.0).timeout
		get_tree().quit()


## Returns true if a pre-match abort is warranted.
## Conditions: match timer has not started, game
## session is active, fewer than 2 clients remain,
## and not in preview mode (where single-client
## testing is valid).
func _should_abort_pre_match(
	remaining_peers: int,
) -> bool:
	if Netcode.is_preview:
		return false
	if Netcode.is_local_mode:
		return false
	if remaining_peers >= 2:
		return false
	# Only abort before the match timer starts.
	if G.match_state.is_match_active:
		return false
	if G.match_state.is_match_ended:
		return false
	if not G.client_session.is_game_active:
		return false
	return true


## Notifies remaining clients and closes the
## session because a peer dropped before the
## match started. Clients see the
## TOAST.NOT_ENOUGH_PLAYERS message.
func _server_abort_not_enough_players() -> void:
	Netcode.print(
		"Aborting: not enough players"
		+ " to start match",
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	# SERVER_SHUTDOWN reason triggers the
	# NOT_ENOUGH_PLAYERS toast on clients.
	Netcode.connector.server_notify_shutdown()
	# Short delay so the notification RPC is
	# delivered before the connection closes.
	await get_tree().create_timer(0.5).timeout
	(Netcode.connector
		.server_close_multiplayer_session())


func _on_matchmaking_progress(
	phase: String,
	elapsed_sec: float,
	estimated_total_sec: float,
) -> void:
	matchmaking_progress.emit(
		phase, elapsed_sec, estimated_total_sec)


func _on_shutdown_requested(
	seconds_remaining: float,
) -> void:
	Netcode.print(
		"Shutdown requested,"
		+ " %.0f seconds remaining"
		% seconds_remaining,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	server_shutdown_imminent.emit(
		seconds_remaining)


