class_name NetworkingMain
extends Node
## Top-level controller logic for networking connectivity.
##
## Note: In order to support local testing with preview mode in the Godot
##   editor, do the following:
## - Open Debug > Customize Run Instances.
## - Check "Enable Multiple Instances".
## - Set the number of instances to 3.
## - Check "Override Main Run Args" for each row.
## - Change the "Launch Arguments" of each row to be one of the following:
##   --server, --client=1, --client=2.
## - Also, include --preview as an arg in each row.


const SERVER_ID := 1

var server_time_tracker := ServerTimeTracker.new()

var is_preview := true
var is_headless := true
var is_server := true
var is_client: bool:
    get: return not is_server
var preview_client_number := 0
var is_connected_to_server := false

var local_id: int:
    get: return multiplayer.get_unique_id()

var server_time_usec: int:
    get: return server_time_tracker.get_server_time_usec()


func _enter_tree() -> void:
    server_time_tracker.name = "ServerTime"
    add_child(server_time_tracker)

    is_headless = DisplayServer.get_name() == "headless"
    is_preview = G.args.has("preview")
    is_server = is_headless or G.args.has("server")
    preview_client_number = int(G.args.client) if G.args.has("client") else 0

    if is_client:
        _client_update_is_connected_to_server()
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _ready() -> void:
    G.log.log_system_ready("NetworkingMain")


func server_enable_connections() -> void:
    G.check_is_server("NetworkingMain.server_enable_connections")

    var peer = ENetMultiplayerPeer.new()
    peer.create_server(G.settings.server_port, G.settings.max_client_count)

    G.check(
        peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED,
        "Failed to start multiplayer server.")

    multiplayer.multiplayer_peer = peer

    G.print("Started multiplayer server.",
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)


func client_connect_to_server() -> void:
    G.check_is_client("NetworkingMain.client_connect_to_server")

    # TODO: Also support websocket or webrtc as needed.

    # FIXME: [GameLift]: Support connecting to the remote server.

    var peer = ENetMultiplayerPeer.new()
    peer.create_client(G.settings.server_ip_address, G.settings.server_port)

    if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
        G.log.alert_user("Failed to start multiplayer client.",
            ScaffolderLog.CATEGORY_CORE_SYSTEMS)
        G.game_panel.client_exit_game()
        return

    multiplayer.multiplayer_peer = peer

    G.print("Started multiplayer client.",
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)


func _on_peer_connected(multiplayer_id: int) -> void:
    if is_server:
        G.print("Client connected: %d" % multiplayer_id, 
            ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
    else:
        G.check(multiplayer_id == SERVER_ID)
        G.print("Connected to server: Local multiplayer_id=%s" % multiplayer_id,
            ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
        _client_update_is_connected_to_server()


func _on_peer_disconnected(multiplayer_id: int) -> void:
    if is_server:
        G.print("Client disconnected: %d" % multiplayer_id,
            ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
    else:
        G.check(multiplayer_id == SERVER_ID)
        G.print("Disconnect from server",
            ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
        _client_update_is_connected_to_server()


func _client_update_is_connected_to_server() -> void:
    if is_server:
        is_connected_to_server = true
    else:
        is_connected_to_server = false
        for peer_id in multiplayer.get_peers():
            if peer_id == SERVER_ID:
                is_connected_to_server = true
                break


func server_close_multiplayer_session() -> void:
    G.check_is_server("NetworkingMain.server_close_multiplayer_session")
    
    G.print("Ending network connections.",
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)
    
    multiplayer.multiplayer_peer.refuse_new_connections = true

    # FIXME: [GameLift]: End game: Look at GameLift example; disconnect players; disable joins
    for peer_id in multiplayer.get_peers():
        if peer_id != SERVER_ID:
            multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func client_disconnect() -> void:
    G.check_is_client("NetworkingMain.client_disconnect")
    
    G.print("Disconnecting from server",
        ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS)

    multiplayer.multiplayer_peer.disconnect_peer(SERVER_ID)

# FIXME: [GameLift]: Start level paused until all clients are connected.
