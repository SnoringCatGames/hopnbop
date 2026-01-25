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

const SERVER_ID := 1

## Transfer channel for pause/unpause RPCs. Using a dedicated channel ensures
## pause coordination messages are not blocked by other network traffic.
const RPC_CHANNEL_PAUSE := 1

## Signal emitted when a peer declares their player count.
signal peer_players_declared(peer_id: int, session_ids: Array)

var is_connected_to_server := false

# Cached mapping, so we don't have to parse player_id strings repeatedly.
# Dictionary<StringName, int>
var _player_id_to_peer_id := {}

# Cached mapping, so we don't have to parse player_id strings repeatedly.
# Dictionary<StringName, int>
var _player_id_to_local_index := {}

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
	var result := peer.create_server(G.settings.server_port, G.settings.max_client_count)

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

	# TODO: Also support websocket or webrtc as needed.

	# FIXME: [GameLift]: Support connecting to the remote server.

	var peer = ENetMultiplayerPeer.new()
	var result := peer.create_client(G.settings.server_ip_address, G.settings.server_port)

	G.check(
		result == Error.OK,
		"Failed to start multiplayer client: error=%d" % result,
	)
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		G.log.alert_user("Failed to start multiplayer client: status=DISCONNECTED", ScaffolderLog.CATEGORY_CORE_SYSTEMS)
		G.game_panel.client_exit_game()
		return

	multiplayer.multiplayer_peer = peer

	G.print("Started multiplayer client", ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)


func _on_peer_connected(multiplayer_id: int) -> void:
	if G.network.is_server:
		G.print("Client connected: %d" % multiplayer_id, ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

		# FIXME: [GameLift]: Start level paused until all clients are connected.
	else:
		# Clients only care about connecting to the server
		if multiplayer_id != SERVER_ID:
			return

		G.print(
			"Connected to server: Local multiplayer_id: %s" %
				G.network.local_id,
			ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
		)
		_client_update_is_connected_to_server()
		G.main.update_window_title()

		# Declare player count to server.
		_client_send_player_declaration()


func _on_peer_disconnected(multiplayer_id: int) -> void:
	if G.network.is_server:
		G.print(
			"Client disconnected: %d" % multiplayer_id,
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
		if multiplayer_id != SERVER_ID:
			return

		G.print("Disconnect from server", ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
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
	# Send player count and session IDs to server.
	var player_count := G.local_session.local_player_count

	# FIXME: Populate this properly.
	var session_ids := []
	for i in range(player_count):
		session_ids.append(str("DEBUG_ID_%d" % i))

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

	G.print("Disconnecting from server", ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

	if multiplayer.multiplayer_peer.is_connected:
		multiplayer.multiplayer_peer.disconnect_peer(SERVER_ID)


## RPC called by client to declare how many players they have.
## This must be called before players are spawned on the server.
@rpc("any_peer", "call_remote", "reliable")
func _server_rpc_declare_players(session_ids: Array) -> void:
	G.check_is_client()

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

	# If GameLift is enabled, validate sessions before spawning players.
	if (
		G.settings.use_gamelift and
		is_instance_valid(G.network.game_lift_manager)
	):
		G.network.game_lift_manager.validate_player_sessions(
			peer_id,
			session_ids
		)

	# Emit signal for Level and MatchStateSynchronizer to handle spawning.
	peer_players_declared.emit(peer_id, session_ids)


static func get_player_id(p_peer_id: int, p_player_index: int) -> StringName:
	return "%d:%d" % [p_peer_id, p_player_index]


func get_peer_id_from_player_id(p_player_id: StringName) -> int:
	# Check the cache first.
	if _player_id_to_peer_id.has(p_player_id):
		return _player_id_to_peer_id[p_player_id]

	# Parse the string.
	var delimiter_index := p_player_id.find(":")
	if delimiter_index < 0:
		return 0
	var peer_id := int(p_player_id.substr(0, delimiter_index))

	# Cache it.
	_player_id_to_peer_id[p_player_id] = peer_id
	return peer_id


func get_local_index_from_player_id(p_player_id: StringName) -> int:
	# Check the cache first.
	if _player_id_to_local_index.has(p_player_id):
		return _player_id_to_local_index[p_player_id]

	# Parse the string.
	var delimiter_index := p_player_id.find(":")
	if delimiter_index < 0:
		return 0
	var local_player_index := int(p_player_id.substr(delimiter_index + 1))

	# Cache it.
	_player_id_to_local_index[p_player_id] = local_player_index
	return local_player_index
