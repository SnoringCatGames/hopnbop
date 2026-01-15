class_name NetworkConnector
extends Node


const SERVER_ID := 1

var is_connected_to_server := false


func _enter_tree() -> void:
    if G.network.is_client:
        _client_update_is_connected_to_server()
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _ready() -> void:
    G.log.log_system_ready("NetworkConnector")


func server_enable_connections() -> void:
    G.check_is_server("NetworkConnector.server_enable_connections")

    var peer = ENetMultiplayerPeer.new()
    peer.create_server(G.settings.server_port, G.settings.max_client_count)

    G.check(
        peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED,
        "Failed to start multiplayer server")

    multiplayer.multiplayer_peer = peer

    G.print("Started multiplayer server",
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)


func client_connect_to_server() -> void:
    G.check_is_client("NetworkConnector.client_connect_to_server")

    # TODO: Also support websocket or webrtc as needed.

    # FIXME: [GameLift]: Support connecting to the remote server.

    var peer = ENetMultiplayerPeer.new()
    peer.create_client(G.settings.server_ip_address, G.settings.server_port)

    if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
        G.log.alert_user("Failed to start multiplayer client",
            ScaffolderLog.CATEGORY_CORE_SYSTEMS)
        G.game_panel.client_exit_game()
        return

    multiplayer.multiplayer_peer = peer

    G.print("Started multiplayer client",
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)


func _on_peer_connected(multiplayer_id: int) -> void:
    if G.network.is_server:
        G.print("Client connected: %d" % multiplayer_id,
            ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

        # FIXME: [GameLift]: Start level paused until all clients are connected.
    else:
        G.check(multiplayer_id == SERVER_ID)
        G.print("Connected to server: Local multiplayer_id: %s" %
            G.network.local_id,
            ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
        _client_update_is_connected_to_server()


func _on_peer_disconnected(multiplayer_id: int) -> void:
    if G.network.is_server:
        G.print("Client disconnected: %d" % multiplayer_id,
            ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
    else:
        G.check(multiplayer_id == SERVER_ID)
        G.print("Disconnect from server",
            ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
        _client_update_is_connected_to_server()


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
    G.check_is_server("NetworkConnector.server_close_multiplayer_session")

    G.print("Ending network connections",
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

    multiplayer.multiplayer_peer.refuse_new_connections = true

    # FIXME: [GameLift]: End game: Look at GameLift example; disconnect players; disable joins
    for peer_id in multiplayer.get_peers():
        if peer_id != SERVER_ID:
            multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func client_disconnect() -> void:
    G.check_is_client("NetworkConnector.client_disconnect")

    G.print("Disconnecting from server",
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

    multiplayer.multiplayer_peer.disconnect_peer(SERVER_ID)
