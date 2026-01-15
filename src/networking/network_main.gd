class_name NetworkMain
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


var time := ServerTimeTracker.new()
var connector := NetworkConnector.new()
var frame_driver := NetworkFrameDriver.new()

var is_preview := true
var is_headless := true
var is_server := true
var is_client: bool:
    get: return not is_server
var preview_client_number := 0

var is_connected_to_server: bool:
    get: return connector.is_connected_to_server

var local_id: int:
    get: return multiplayer.get_unique_id()

## If we bucket the current server_time_usec into discrete frames, this
## canonical time would be the exact midpoint between the previous and next
## frame.
var server_frame_time_usec: int:
    get: return frame_driver.server_frame_time_usec

## If we bucket the current server_time_usec into discrete frames, this
## would be index of the current frame.
var server_frame_index: int:
    get: return frame_driver.server_frame_index


var server_time_usec_not_frame_aligned: int:
    get: return time.get_server_time_usec()


func _enter_tree() -> void:
    time.name = "ServerTime"
    add_child(time)

    connector.name = "NetworkConnector"
    add_child(connector)

    frame_driver.name = "NetworkFrameDriver"
    add_child(frame_driver)

    is_headless = DisplayServer.get_name() == "headless"
    is_preview = G.args.has("preview")
    is_server = is_headless or G.args.has("server")
    preview_client_number = int(G.args.client) if G.args.has("client") else 0


func _ready() -> void:
    G.log.log_system_ready("NetworkMain")
