class_name NetworkingMain
extends Node
## Top-level controller logic for networking connectivity.
##
## Note: In order to support local testing with preview mode in the Godot
##   editor, do the following:
## - Open Debug > Custom Run Instances.
## - Check "Enable Multiple Instances".
## - Set the number of instances to 3.
## - Check "Override Main Run Args" for each row.
## - Change the "Launch Arguments" of each row to be one of the following:
##   --server, --client=1, --client=2.


const SERVER_ID := 1

var server_time_tracker := ServerTimeTracker.new()

var is_preview := true
var is_headless := true
var is_server := true
var is_client: bool:
    get: return not is_server
var preview_client_number := 0
var is_connected_to_server := false

var server_time_usec: int:
    get: return server_time_tracker.get_server_time_usec()


func _enter_tree() -> void:
    server_time_tracker.name = "ServerTime"
    add_child(server_time_tracker)

    is_headless = DisplayServer.get_name() == "headless"
    is_preview = G.args.has("preview")
    is_server = is_headless or G.args.has("server")
    preview_client_number = int(G.args.client) if G.args.has("client") else 0

    _update_is_connected_to_server()
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_connected(_multiplayer_id: int) -> void:
    if is_server:
        pass
    else:
        _update_is_connected_to_server()


func _on_peer_disconnected(_multiplayer_id: int) -> void:
    if is_server:
        pass
    else:
        _update_is_connected_to_server()


func _ready() -> void:
    G.log.print("NetworkingMain._ready", ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION)

    # FIXME: Also support websocket or webrtc as needed.

    var peer = ENetMultiplayerPeer.new()
    if is_server:
        peer.create_server(G.settings.server_port, G.settings.max_client_count)
    else:
        peer.create_client(G.settings.server_ip_address, G.settings.server_port)
    if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
        var message := "Failed to start multiplayer server."
        if is_preview:
            G.log.alert_user(message, ScaffolderLog.CATEGORY_CORE_SYSTEMS)
        else:
            G.log.error(message, ScaffolderLog.CATEGORY_CORE_SYSTEMS)
    multiplayer.multiplayer_peer = peer


func _update_is_connected_to_server() -> void:
    if is_server:
        is_connected_to_server = true
    else:
        is_connected_to_server = false
        for peer_id in multiplayer.peers:
            if peer_id == SERVER_ID:
                is_connected_to_server = true
                break




# FIXME:
# - Start level paused until all clients are connected?
# -
