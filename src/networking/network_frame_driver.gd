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

# Dictionary<ReconcilableNetworkedState, bool>
var _networked_state_nodes := {}

# Dictionary<NetworkFrameProcessor, bool>
var _network_frame_processor_nodes := {}

var _queued_rollback_frame_index := 0

var rollback_buffer_size: int:
    get: return ceili(
        G.settings.rollback_buffer_duration_sec *
        TARGET_NETWORK_FPS)

var oldest_rollbackable_frame_index: int:
    get:
        # For a rollback, we must be able to consider both the target frame as
        # well as the previous frame, so we can't rollback to the oldest
        # recorded frame.
        return max(G.network.server_frame_index - rollback_buffer_size + 2, 1)


func _ready() -> void:
    G.log.log_system_ready("NetworkFrameDriver")

    if not Engine.is_editor_hint():
        G.process_sentinel.pre_physics_process.connect(_pre_physics_process)


func _pre_physics_process(_delta: float) -> void:
    _start_network_process()


## If we bucket server time into discrete frames, this would be the index of the
## frame corresponding to the given time.
func get_frame_index_from_time(p_time_usec: int) -> int:
    var time_sec := p_time_usec / 1000000.0
    return floori(fmod(time_sec, TARGET_NETWORK_TIME_STEP_SEC))


func get_time_from_frame_index(p_frame_index: int) -> int:
    return floori(p_frame_index * TARGET_NETWORK_TIME_STEP_SEC + \
        TARGET_NETWORK_TIME_STEP_SEC * 0.5)


func _update_server_frame_time() -> void:
    var server_time_usec := G.network.server_time_usec_not_frame_aligned
    var frame_start_time_sec := \
        get_frame_index_from_time(server_time_usec) * \
        TARGET_NETWORK_TIME_STEP_SEC

    var next_server_frame_time_usec := floori(
        frame_start_time_sec + TARGET_NETWORK_TIME_STEP_SEC * 0.5)
    var next_server_frame_index := \
        get_frame_index_from_time(server_frame_time_usec)

    # If our tracking of server time has skewed enough that we're skipping a
    # frame, then we need to fast-forward the system.
    if next_server_frame_index > server_frame_index + 1:
        G.warning("Fast-forwarding due to _physics_process frame skew")
        fast_forward(next_server_frame_index)

    server_frame_time_usec = next_server_frame_time_usec
    server_frame_index = next_server_frame_index


func add_networked_state(node: ReconcilableNetworkedState) -> void:
    G.ensure(not _networked_state_nodes.has(node))
    _networked_state_nodes[node] = true


func remove_networked_state(node: ReconcilableNetworkedState) -> void:
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
## - At most one rollback will occur per _network_process loop, and the earliest
##   server_frame_index will be used.
## - The given frame index marks where the state mismatch occured that is
##   triggering this rollback.
## - The first processed frame of the rollback will be the frame _after_ the
##   mismatch.
##   - We already know that the local simulation at the mismatch resulting in
##     the wrong state, so we don't re-simulate that frame.
# FIXME: LEFT OFF HERE: ACTUALLY:
# - Call this.
# - This frame
func queue_rollback(p_conflicting_frame_index: int) -> bool:
    # FIXME: LEFT OFF HERE: Check if this check should happen earlier.
    # Rollback simulation would start on the next frame after the mismatch.
    var target_rollback_frame := p_conflicting_frame_index + 1
    if target_rollback_frame < oldest_rollbackable_frame_index:
        # TODO: We'll probably want to remove this log.
        G.log.warn(
            "Requested rollback to frame %d, but oldest rollbackable frame is %d",
            target_rollback_frame,
            oldest_rollbackable_frame_index)
        return false

    if _queued_rollback_frame_index == 0:
        _queued_rollback_frame_index = target_rollback_frame
    else:
        _queued_rollback_frame_index = mini(
            _queued_rollback_frame_index, target_rollback_frame)

    return true


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


func _start_rollback() -> void:
    var original_server_frame_index := server_frame_index
    var original_server_frame_time_usec := server_frame_time_usec

    server_frame_index = _queued_rollback_frame_index
    server_frame_time_usec = floori(
        server_frame_index * TARGET_NETWORK_TIME_STEP_SEC)

    # FIMXE: [Rollback] Start the rollback.
    # - First, reset all registered nodes in _networked_state_nodes to
    #   _queued_rollback_frame_index.
    #   - Add doc comments that this may need to also set indirect derived
    #     state.
    # - Then, traverse _all_ nodes starting at _queued_rollback_frame_index + 1.
    # - Then, repeat for each index
    # - Only allow rolling back to the oldest frame + 1, so that we can
    #   populate various previous_foo fields.
    # - We should probably autopopulate the entire buffer with the default
    #   state, so it's always safe to look at the previous frame (unless we know
    #   we're at the oldest frame).
    _network_process()

    server_frame_index = original_server_frame_index
    server_frame_time_usec = original_server_frame_time_usec


## Simulate the current frame for all network-process-aware nodes.
func _network_process() -> void:
    # Sync other scene state from the current network state.
    for node in _networked_state_nodes:
        node._pre_network_process()

    # Let all network-process-aware nodes handle the frame.
    for node in _networked_state_nodes:
        node._network_process()
    for node in _network_frame_processor_nodes:
        node._network_process()

    # Sync the current network state from other scene state.
    for node in _networked_state_nodes:
        node._post_network_process()


func fast_forward(new_frame_index: int) -> void:
    # FIXME: LEFT OFF HERE: ACTUALLY, ACTUALLY, ACTUALLY, ACTUALLY: Fast forward
    pass


# FIXME: LEFT OFF HERE: ACTUALLY, ACTUALLY, ACTUALLY, ACTUALLY: ------------
# - After finishing hooking up all the parts, walk through each bit and
#   double-check if we're setting and getting "latest" state from the buffer
#   at the correct times (before and after the simulation).
