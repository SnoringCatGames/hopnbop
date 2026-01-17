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


func _ready() -> void:
    G.log.log_system_ready("NetworkFrameDriver")

    if not Engine.is_editor_hint():
        G.process_sentinel.pre_physics_process.connect(_pre_physics_process)


func _pre_physics_process(_delta: float) -> void:
    _start_network_process()


## If we bucket server time into discrete frames, this would be the index of the
## frame corresponding to the given time.
func get_server_frame_index(p_server_time_usec: int) -> int:
    var time_sec := p_server_time_usec / 1000000.0
    return floori(fmod(time_sec, TARGET_NETWORK_TIME_STEP_SEC))


func _update_server_frame_time() -> void:
    var server_time_usec := G.network.server_time_usec_not_frame_aligned
    var frame_start_time_sec := \
        get_server_frame_index(server_time_usec) * TARGET_NETWORK_TIME_STEP_SEC
    server_frame_time_usec = floori(
        frame_start_time_sec + TARGET_NETWORK_TIME_STEP_SEC * 0.5)
    server_frame_index = get_server_frame_index(server_frame_time_usec)


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
    # - Only allow rolling back to the oldest frame + 1, so that we can
    #   populate various previous_foo fields.
    # - We should probably autopopulate the entire buffer with the default
    #   state, so it's always safe to look at the previous frame (unless we know
    #   we're at the oldest frame).
    _network_process()

    server_frame_time_usec = original_server_frame_time_usec
    server_frame_index = original_server_frame_index


## Simulate the current frame for all network-process-aware nodes.
func _network_process() -> void:
    # FIXME: LEFT OFF HERE: ACTUALLY, ACTUALLY, ACTUALLY: --------------------
    #
    # ****
    # - Need to conditionally resync scene state from buffer state before each call to _network_process.
    #   - If the buffer state is authoritative, we don't overwrite it, and we overwrite the scene state.
    #   - But we still may need to simulate and overwrite frames preceding that, in order to have state for other nodes to check during that frame.
    #
    # When iterating through _network_process, if for the given node, for the given frame:
    #
    # - client: is authoritative for actions:
    #   - if frame has authoritative state_from_server:
    #      - don't call network process
    #   - if frame doesn't have authoritative state_from_server:
    #     - call network process
    #   - if the actions buffer frame already has state recorder for this frame, don't change it. Else, record the current actions.
    #     - we may actually need to make sure to capture these actions separately from network process!
    #       - in case we somehow skipped network process for the CURRENT latest frame.
    #       - but we should decouple these anyway.
    #       - will add a separate record actions function, and call it separately (before?) network process.
    #       - that means the networked state class will need to have getters for both state from server and state from client (which is allowed to return null)
    #       - ???? Check: am I registering both state from server and state from client nodes for iterating in frame driver? Probably should only iterate over state from server...
    #
    # - client: not authoritative for actions:
    #   - if frame has authoritative state_from_server:
    #     - don't call _network_process
    #   - doesn't have authoritative state_from_server:
    #     - call _network_process
    #   - after possible _network_process, make sure action buffer frame is set or copy it over from the previous frame (label it predicted)
    #
    # - server:
    #   - for actions: make sure we either have state for the current frame, or copy over state from the previous.
    #   - for state from server: call network process every time on all nodes.
    pass

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
