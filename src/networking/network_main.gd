class_name NetworkMain
extends Node
## Top-level controller and coordinator for all networking subsystems.

# FIXME: Review this type work-around.
const GameLiftManagerScript = preload("res://src/networking/gamelift_manager.gd")
##
## NetworkMain is the central orchestrator accessed via the G.network singleton.
## It manages and provides access to three core networking subsystems:
##
## - **time** (ServerTimeTracker): NTP-like clock synchronization between client
##   and server
## - **connector** (NetworkConnector): ENet peer management and connection
##   lifecycle
## - **frame_driver** (NetworkFrameDriver): Frame-synchronous simulation and
##   rollback coordination
##
## NetworkMain determines the local machine's role (server vs client) based on
## command-line arguments or headless mode and provides convenient accessors for
## common networking state:
##
## - is_server / is_client: Current machine's role
## - is_connected_to_server: Connection status (always true on server)
## - local_id: Local multiplayer peer ID
## - server_frame_index: Current server frame number
## - server_frame_time_usec: Frame-aligned server time
## - server_time_usec_not_frame_aligned: Raw estimated server time
##
## Testing with multiple instances in Godot editor:
## - In order to support local testing with preview mode in the Godot
##   editor, do the following:
##   - Open Debug > Customize Run Instances.
##   - Check "Enable Multiple Instances".
##   - Set the number of instances to 3.
##   - Check "Override Main Run Args" for each row.
##   - Change the "Launch Arguments" of each row to be one of the following:
##     --server, --client=1, --client=2.
##   - Also, include --preview as an arg in each row.

## Emitted when a PlayerInputFromClient node gains local multiplayer
## authority on this client. This occurs when the server spawns a player
## character for this client and the MultiplayerSynchronizer assigns
## authority. Use this signal to detect when the local player is ready.
@warning_ignore("unused_signal")
signal local_authority_added(input_from_client: PlayerInputFromClient)

## Emitted when a PlayerInputFromClient node loses local multiplayer
## authority on this client. This occurs when the player character is
## despawned or authority is transferred away from this client.
@warning_ignore("unused_signal")
signal local_authority_removed(input_from_client: PlayerInputFromClient)

var time := ServerTimeTracker.new()
var connector := NetworkConnector.new()
var frame_driver := NetworkFrameDriver.new()
var gamelift_manager # GameLiftManager (untyped to avoid parse order issues)

var is_preview := true
var is_headless := true
var is_server := true
var is_client: bool:
    get:
        return not is_server
var preview_client_number := 0

var is_connected_to_server: bool:
    get:
        return connector.is_connected_to_server

var local_id: int:
    get:
        return multiplayer.get_unique_id()

## If we bucket the current server_time_usec into discrete frames, this
## canonical time would be the exact midpoint between the previous and next
## frame.
var server_frame_time_usec: int:
    get:
        return frame_driver.server_frame_time_usec

## If we bucket the current server_time_usec into discrete frames, this
## would be index of the current frame.
var server_frame_index: int:
    get:
        return frame_driver.server_frame_index

var server_time_usec_not_frame_aligned: int:
    get:
        return time.get_server_time_usec()


func _enter_tree() -> void:
    time.name = "ServerTime"
    add_child(time)

    connector.name = "NetworkConnector"
    add_child(connector)

    frame_driver.name = "NetworkFrameDriver"
    add_child(frame_driver)

    gamelift_manager = GameLiftManagerScript.new()
    gamelift_manager.name = "GameLiftManager"
    add_child(gamelift_manager)

    is_headless = DisplayServer.get_name() == "headless"
    is_preview = OS.has_feature("editor")
    is_server = is_headless or G.args.has("server")
    preview_client_number = int(G.args.client) if G.args.has("client") else 0


func _ready() -> void:
    G.log.log_system_ready("NetworkMain")
