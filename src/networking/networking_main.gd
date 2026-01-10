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

var server_time := ServerTimeTracker.new()

var is_server := true
var preview_client_number := 0


func _enter_tree() -> void:
    server_time.name = "ServerTime"
    add_child(server_time)


func _ready() -> void:
    # FIXME
    pass
    #multiplayer.has_multiplayer_peer()
    #multiplayer.is_server()

    is_server = DisplayServer.get_name() == "headless" or G.args.has("server")
    preview_client_number = G.args.client if G.args.has("client") else 0

    # FIXME
    var peer = ENetMultiplayerPeer.new()
    if is_server:
        peer.create_server(G.settings.remote_server_port, G.settings.max_client_count)
    else:
        peer.create_client(G.settings.remote_server_ip_address, G.settings.remote_server_port)
    multiplayer.multiplayer_peer = peer


# FIXME:
# - Start level paused until all clients are connected.
# -
