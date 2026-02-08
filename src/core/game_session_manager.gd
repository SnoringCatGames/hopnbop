class_name GameSessionManager
extends Node
## Manages network session lifecycle for Jump 'n Thump.
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

var session_provider: SessionProvider


func _ready() -> void:
	_setup_session_provider()
	_connect_network_signals()


## Set up the appropriate session provider (GameLift or Preview mode).
func _setup_session_provider() -> void:
	if Netcode.should_connect_to_remote_server:
		# Production mode: use GameLift.
		if Netcode.is_server:
			session_provider = GameLiftServerProvider.new(
				{
					"anywhere_mode": G.settings.gamelift_anywhere_mode,
					"anywhere_websocket": G.settings.gamelift_anywhere_websocket,
					"anywhere_auth_token": G.settings.gamelift_anywhere_auth_token,
					"anywhere_fleet_id": G.settings.gamelift_anywhere_fleet_id,
					"anywhere_host_id": G.settings.gamelift_anywhere_host_id,
					"anywhere_process_id": G.settings.gamelift_anywhere_process_id,
					"server_port": Netcode.server_port
				}
			)
		else:
			session_provider = GameLiftClient.new(G.settings.backend_api_url)
	else:
		# Preview mode: no validation.
		session_provider = PreviewSessionProvider.new(
			Netcode.log,
			{
				"server_ip": G.settings.local_preview_server_ip_address,
				"server_port": G.settings.server_port
			}
		)

	session_provider.name = "SessionProvider"
	add_child(session_provider)

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

	if Netcode.is_server:
		session_provider.all_players_connected.connect(
			_on_all_players_connected
		)


## Connect to NetworkConnector signals.
func _connect_network_signals() -> void:
	if Netcode.is_client:
		Netcode.connector.player_ids_assigned.connect(
			_on_player_ids_assigned
		)

	# Both client and server listen to disconnected signal.
	Netcode.connector.disconnected.connect(_on_disconnected)


## CLIENT: Request session IDs from backend.
## level_prefs: Optional LevelPreferences for level selection hints.
func client_request_session(level_prefs: LevelPreferences = null) -> void:
	Netcode.check_is_client()

	var player_count := G.client_session.local_player_count
	var prefs_dict := {} if level_prefs == null else level_prefs.to_dict()

	G.print(
		"Requesting session for %d player(s)%s" % [
			player_count,
			" with level preferences" if not prefs_dict.is_empty() else ""
		],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	session_provider.client_request_session_ids(player_count, prefs_dict)


## Set expected player count for validation.
func server_set_expected_players(count: int) -> void:
	Netcode.check_is_server()

	if session_provider != null and session_provider.has_method(
		"server_set_expected_player_count"
	):
		session_provider.server_set_expected_player_count(count)


## Get the selected level ID for this game session.
## On server: returns level from game session properties.
## On client: returns level from matchmaking response.
func server_get_selected_level_id() -> StringName:
	if Netcode.is_server:
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
	selected_level_id: String = ""
) -> void:
	G.print(
		"Session IDs received, connecting to %s:%d%s" % [
			server_ip,
			server_port,
			", level: " + selected_level_id if not selected_level_id.is_empty() else ""
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
	Netcode.connector.client_connect_to_server(server_ip, server_port)


func _on_session_request_failed(error_message: String) -> void:
	G.error(
		"Session request failed: %s" % error_message,
		NetworkLogger.CATEGORY_CONNECTIONS
	)
	# Emit as unexpected connection loss.
	connection_lost.emit("Session request failed", false)


func _on_player_ids_assigned(assigned_ids: Array[int]) -> void:
	G.print(
		"Player IDs assigned: %s" % assigned_ids,
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Store in local session.
	G.client_session.local_player_ids = assigned_ids.duplicate()

	# Emit high-level event for game logic.
	session_established.emit(assigned_ids)


func _on_all_players_connected() -> void:
	G.print(
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
	G.print(
		"Disconnected from server: %s" % reason_name,
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Check if this was an expected disconnect (match ended normally).
	var is_expected := (
		reason == NetworkConnector.DisconnectReason.MATCH_FINISHED or
		G.match_state.is_match_ended
	)

	if is_expected:
		G.print(
			"Match ended, returning to lobby",
			NetworkLogger.CATEGORY_GAME_STATE
		)
	else:
		G.warning(
			"Unexpected disconnect: %s" % reason_name,
			NetworkLogger.CATEGORY_CONNECTIONS
		)

	# Emit high-level event for game logic.
	connection_lost.emit(reason_name, is_expected)


func _server_on_client_disconnected(peer_id: int, reason: int) -> void:
	var reason_name: String = NetworkConnector.DisconnectReason.keys()[reason]
	G.print(
		"Client %d disconnected: %s" % [peer_id, reason_name],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Check if all clients have disconnected.
	var remaining_peers := multiplayer.get_peers().size()
	G.print(
		"Remaining connected clients: %d" % remaining_peers,
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	if remaining_peers == 0:
		_server_on_all_clients_disconnected()


func _server_on_all_clients_disconnected() -> void:
	G.print(
		"All clients disconnected",
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	if Netcode.is_preview:
		# In preview mode, signal to reset for another match.
		G.print(
			"Preview mode: Signaling server reset",
			NetworkLogger.CATEGORY_CORE_SYSTEMS
		)
		server_should_reset.emit()
	else:
		# In production mode, exit the server application.
		G.print(
			"Production mode: Exiting server",
			NetworkLogger.CATEGORY_CORE_SYSTEMS
		)
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
