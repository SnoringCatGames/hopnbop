class_name NetworkFrameDriver
extends Node


## This determines the period we use between frames that we record in rollback
## buffers.
##
## Network state will presumably be slower than this in practice. When that
## occurs, we fill-in empty frames by extrapolating from the most-recent filled
## frame.
const TARGET_NETWORK_FPS = ScaffolderTime.PHYSICS_FPS
const TARGET_NETWORK_TIME_STEP_SEC := 1.0 / TARGET_NETWORK_FPS

## If we bucket the current server_time_usec into discrete frames, this
## canonical time would be the exact midpoint between the previous and next
## frame.
var server_frame_time_usec := 0

## If we bucket the current server_time_usec into discrete frames, this
## would be index of the current frame.
var server_frame_index := 0

# Dictionary<NetworkedState, bool>
var _networked_state_nodes := {}

# Dictionary<NetworkFrameProcessor, bool>
var _network_frame_processor_nodes := {}

var _queued_rollback_frame_index := 0


func _ready() -> void:
    G.log.log_system_ready("NetworkFrameDriver")

    if not Engine.is_editor_hint():
        G.process_sentinel.connect("pre_physics_process", _pre_physics_process)


func _pre_physics_process(_delta: float) -> void:
    _start_network_process()


## If we bucket server time into discrete frames, this would be the index of the
## frame corresponding to the given time.
func get_server_frame_index(p_server_time_usec: int) -> int:
    var time_sec := p_server_time_usec / 1000000.0
    return floori(fmod(time_sec, TARGET_NETWORK_TIME_STEP_SEC))


func _update_server_frame_time() -> void:
    var server_time_usec := G.network.time.get_server_time_usec()
    var frame_start_time_sec := \
        get_server_frame_index(server_time_usec) * TARGET_NETWORK_TIME_STEP_SEC
    server_frame_time_usec = floori(
        frame_start_time_sec + TARGET_NETWORK_TIME_STEP_SEC * 0.5)
    server_frame_index = get_server_frame_index(server_frame_time_usec)


func add_networked_state(node: NetworkedState) -> void:
    G.ensure(not _networked_state_nodes.has(node))
    _networked_state_nodes[node] = true


func remove_networked_state(node: NetworkedState) -> void:
    G.ensure(_networked_state_nodes.has(node))
    _networked_state_nodes.erase(node)


func add_network_frame_processor(node: NetworkFrameProcessor) -> void:
    G.ensure(not _network_frame_processor_nodes.has(node))
    _network_frame_processor_nodes[node] = true


func remove_network_frame_processor(node: NetworkFrameProcessor) -> void:
    G.ensure(_network_frame_processor_nodes.has(node))
    _network_frame_processor_nodes.erase(node)


## This will trigger a rollback to occur on the next _network_process.
##
## At most one rollback will occur per _network_process loop, and the earliest
## server_frame_index will be used.
# FIXME: [Rollback] Call this.
func queue_rollback(p_server_frame_index: int) -> void:
    if _queued_rollback_frame_index == 0:
        _queued_rollback_frame_index = p_server_frame_index
    else:
        _queued_rollback_frame_index = mini(
            _queued_rollback_frame_index, p_server_frame_index)


## For most nodes in the scene, _network_process should happen before
## _physics_process.
func _start_network_process() -> void:
    _update_server_frame_time()

    if _queued_rollback_frame_index > 0:
        _start_rollback()
        _queued_rollback_frame_index = 0
    else:
        # Just handle this next frame normally, no rollback needed.
        _network_process()

    # After simulating this frame, or extrapolating frames due to rollback, pack
    # the latest state for syncing across the network.
    for node in _networked_state_nodes:
        node.pack_state()


func _start_rollback() -> void:
    var original_server_frame_time_usec := server_frame_time_usec
    var original_server_frame_index := server_frame_index

    # FIMXE: [Rollback] Start the rollback.
    # - First, reset all registered nodes in _networked_state_nodes to
    #   _queued_rollback_frame_index.
    #   - Add doc comments that this may need to also set indirect derived
    #     state.
    # - Then, traverse _all_ nodes starting at _queued_rollback_frame_index + 1.
    # - Then, repeat for each index
    _network_process()

    server_frame_time_usec = original_server_frame_time_usec
    server_frame_index = original_server_frame_index


## Simulate the current frame for all network-process-aware nodes.
func _network_process() -> void:
    # Let all network-process-aware nodes handle the frame.
    for node in _networked_state_nodes:
        node._network_process()
    for node in _network_frame_processor_nodes:
        node._network_process()

    # Record the current rollback frame state.
    for node in _networked_state_nodes:
        node.record_rollback_frame()
