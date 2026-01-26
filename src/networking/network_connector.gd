class_name NetworkConnector
extends Node
## Manages ENet multiplayer peer connections between server and clients.
##
## NetworkConnector manages peer lifecycle (connection, disconnection) and
## provides connectivity status tracking. It is responsible for:
##
## - Creating and configuring server peers (server-side)
## - Creating and configuring client peers that connect to a server
##   (client-side)
## - Tracking connection status (is_connected_to_server)
## - Handling peer_connected and peer_disconnected signals
## - Managing graceful disconnection and session cleanup
##
## This class is accessed via the G.network.connector singleton and works in
## conjunction with NetworkMain, which coordinates all networking subsystems.
##
## Usage:
## - Server: Call server_enable_connections() to start accepting client
##   connections
## - Client: Call client_connect_to_server() to connect to a remote server
## - Both: Listen to peer_connected/peer_disconnected signals for connection
##   events
##
## Configuration is read from G.settings (server_port, server_ip_address,
## max_client_count).

## Signal emitted when a peer declares their player count.
## assigned_ids is an Array[int] of the player IDs assigned by the server.
signal peer_players_declared(
	peer_id: int,
	assigned_ids: Array[int]
)

## Tracks the reason for client disconnection.
enum DisconnectReason {
	UNKNOWN,
	CLIENT_INITIATED,
	SERVER_SHUTDOWN,
	CONNECTION_LOST,
}

const SERVER_ID := 1

## Transfer channel for pause/unpause RPCs. Using a dedicated channel ensures
## pause coordination messages are not blocked by other network traffic.
const RPC_CHANNEL_PAUSE := 1

var is_connected_to_server := false

## Last disconnect reason for displaying user-friendly messages.
var last_disconnect_reason := DisconnectReason.UNKNOWN

var server_ip_address := ""
var server_port := 0

# Server-only: Counter for assigning sequential player IDs.
var _next_player_id: int = 1

# Dictionary<int, int>
var _player_id_to_peer_id := {}
# Dictionary<int, int>
var _player_id_to_local_player_index := {}


func _enter_tree() -> void:
	if G.network.is_client:
		_client_update_is_connected_to_server()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _ready() -> void:
	G.log.log_system_ready("NetworkConnector")


func server_enable_connections() -> void:
	G.check_is_server()

	var peer = ENetMultiplayerPeer.new()
	var result := peer.create_server(server_port, G.settings.max_client_count)

	G.check(
		result == Error.OK,
		"Failed to start multiplayer server: error=%d" % result,
	)
	G.check(
		peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED,
		"Failed to start multiplayer server: status=DISCONNECTED",
	)

	multiplayer.multiplayer_peer = peer

	G.print("Started multiplayer server", ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

	G.main.update_window_title()


func client_connect_to_server() -> void:
	G.check_is_client()

	# Reset disconnect reason for new connection attempt.
	last_disconnect_reason = DisconnectReason.UNKNOWN

	# TODO: Also support websocket or webrtc as needed.

	var peer = ENetMultiplayerPeer.new()
	var result := peer.create_client(server_ip_address, server_port)

	G.check(
		result == Error.OK,
		"Failed to start multiplayer client: error=%d" % result,
	)
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		G.log.alert_user(
			"Failed to start multiplayer client: status=DISCONNECTED",
			ScaffolderLog.CATEGORY_CORE_SYSTEMS
		)
		G.game_panel.client_exit_game()
		return

	multiplayer.multiplayer_peer = peer

	G.print("Started multiplayer client", ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)


func _on_peer_connected(peer_id: int) -> void:
	if G.network.is_server:
		G.print("Client connected: %d" % peer_id, ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

		# FIXME: [GameLift]: Start level paused until all clients are connected.
	else:
		# Clients only care about connecting to the server
		if peer_id != SERVER_ID:
			return

		G.print(
			"Connected to server: Local peer_id: %s" %
				G.network.local_peer_id,
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
		)
		_client_update_is_connected_to_server()
		G.main.update_window_title()

		# Declare player count to server.
		_client_send_player_declaration()


func _on_peer_disconnected(peer_id: int) -> void:
	if G.network.is_server:
		G.print(
			"Client disconnected: %d" % peer_id,
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
		)

		# In preview mode, close the server when all clients have disconnected
		if G.network.is_preview and multiplayer.get_peers().size() == 0:
			G.print(
				"All clients disconnected in preview mode, closing server",
				ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
			)
			G.main.close_app()
	else:
		# Clients only care about disconnecting from the server
		if peer_id != SERVER_ID:
			return

		# Set reason if not already set by shutdown notification
		if last_disconnect_reason == DisconnectReason.UNKNOWN:
			last_disconnect_reason = DisconnectReason.CONNECTION_LOST

		G.print("Disconnect from server",
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
		_client_update_is_connected_to_server()
		G.main.update_window_title()

		# In preview mode, close the client when the server disconnects
		if G.network.is_preview:
			G.print(
				"Server disconnected in preview mode, closing client",
				ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
			)
			G.main.close_app()


func _client_send_player_declaration() -> void:
	G.check(G.local_session.has_valid_session_ids(),
		"Client has no session IDs.",
	)

	# Send player count and session IDs to server.
	var player_count := G.local_session.local_player_count

	# Use stored session IDs from backend matchmaking.
	var session_ids := G.local_session.local_session_ids

	G.check(player_count == session_ids.size(),
		"Player count %d does not match session IDs size %d." %
			[player_count, session_ids.size()],
	)

	G.print(
		"Declaring %d player(s) to server" % player_count,
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
	)

	# Call RPC to declare players.
	_server_rpc_declare_players.rpc_id(SERVER_ID, session_ids)


func _client_update_is_connected_to_server() -> void:
	if G.network.is_server:
		is_connected_to_server = true
	else:
		is_connected_to_server = false
		for peer_id in multiplayer.get_peers():
			if peer_id == SERVER_ID:
				is_connected_to_server = true
				break


func server_close_multiplayer_session() -> void:
	G.check_is_server()

	G.print("Ending network connections", ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

	multiplayer.multiplayer_peer.refuse_new_connections = true

	# FIXME: [GameLift]: End game: Look at GameLift example; disconnect players; disable joins
	for peer_id in multiplayer.get_peers():
		if peer_id != SERVER_ID:
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func client_disconnect() -> void:
	G.check_is_client()

	# Mark as client-initiated disconnect
	last_disconnect_reason = DisconnectReason.CLIENT_INITIATED

	G.print("Disconnecting from server",
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

	if multiplayer.multiplayer_peer.is_connected:
		multiplayer.multiplayer_peer.disconnect_peer(SERVER_ID)


## RPC called by client to declare how many players they have.
## This must be called before players are spawned on the server.
@rpc("any_peer", "call_remote", "reliable")
func _server_rpc_declare_players(session_ids: Array) -> void:
	G.check_is_server()

	var peer_id := multiplayer.get_remote_sender_id()
	var player_count := session_ids.size()

	# Validate player count.
	if player_count < 1 or player_count > G.settings.local_player_max:
		G.warning(
			"Invalid player count from peer %d: %d (min=1, max=%d)" % [
				peer_id,
				player_count,
				G.settings.local_player_max,
			],
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
		)
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	G.print(
		"Peer %d declared %d player(s)" % [peer_id, player_count],
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
	)

	# Assign sequential player IDs.
	var assigned_ids: Array[int] = []
	for local_player_index in range(player_count):
		assigned_ids.append(_next_player_id)
		_player_id_to_peer_id[_next_player_id] = peer_id
		_player_id_to_local_player_index[_next_player_id] = local_player_index
		_next_player_id += 1

	# Send assigned IDs back to client.
	_client_rpc_receive_player_ids.rpc_id(peer_id, assigned_ids)

	G.print(
		"Assigned IDs %s to peer %d" % [assigned_ids, peer_id],
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
	)

	# If GameLift is enabled, validate sessions before spawning players.
	if (
		G.network.should_connect_to_remote_server and
		is_instance_valid(G.network.game_lift_manager)
	):
		G.network.game_lift_manager.validate_player_sessions(
			peer_id,
			assigned_ids,
			session_ids
		)

	# Emit signal for Level and MatchStateSynchronizer to handle spawning.
	peer_players_declared.emit(peer_id, assigned_ids)


## RPC called by server to send assigned player IDs to the client.
@rpc("authority", "call_remote", "reliable")
func _client_rpc_receive_player_ids(assigned_ids: Array[int]) -> void:
	G.check_is_client()

	# Record local player IDs and indices.
	for local_player_index in range(assigned_ids.size()):
		var player_id := assigned_ids[local_player_index]
		_player_id_to_peer_id[player_id] = G.network.local_peer_id
		_player_id_to_local_player_index[player_id] = local_player_index

	G.local_session.local_player_ids = assigned_ids

	G.print(
		"Received assigned player IDs: %s" % [assigned_ids],
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
	)


func client_on_player_state_connected(
		p_player_id: int,
		p_peer_id: int,
		p_local_index: int) -> void:
	_player_id_to_peer_id[p_player_id] = p_peer_id
	_player_id_to_local_player_index[p_player_id] = p_local_index


## Gets the peer_id associated with a given player_id.
## Returns -1 if the player_id is not found (e.g., lobby player).
func get_peer_id_from_player_id(p_player_id: int) -> int:
	if _player_id_to_peer_id.has(p_player_id):
		return _player_id_to_peer_id[p_player_id]
	return 0


## Gets the local_player_index associated with a given player_id.
## Returns -1 if the player_id is not found (e.g., lobby player).
func get_local_player_index_from_player_id(p_player_id: int) -> int:
	if _player_id_to_local_player_index.has(p_player_id):
		return _player_id_to_local_player_index[p_player_id]
	return -1
