class_name NetworkFrameDriver
extends Node


# FIXME: LEFT OFF HERE: ACTUALLY: Review logic.
#
# - After finishing hooking up all the parts, walk through each bit and
#   double-check if we're setting and getting "latest" state from the buffer
#   at the correct times (before and after the simulation).
#
# - Ask AI to analyze all networking logic (everything under the networking/ folder) and generate file-level doc comments for each class.
#
# - Ask AI to do a thorough code review:
#
# I need to you to perform a thorough code review of all of my networking logic (everything under the networking/ folder), as well as how it integrates with character/player logic.
# - Give special focus on the client prediction and rollback reconciliation systems.
# - Please pay careful attention to possible sequencing problems, edge cases, and off-by-one errors.
# - Also offer any feedback on potential design improvements or performance improvements.
#
# - Also ask Opus to research recommended test frameworks for Godot, and to then design some integration tests for my networking systems, in particular the client prediction and rollback reconciliation systems
#
# - Ask for tips to hand-verify correctness of the overall system, and any particularly important aspects to test.
#
# - Possibly ask for help integrating with GameLift...
#


# FIXME: [Rollback debug visualization]: Notes:
#
# ### PART 1: Hand test
# - Add if-statements, guarding on client/server, with a pass, everywhere, to
#   set breakpoints on easily as needed.
# - Print statements.
#
# ### PART 2: Buffer-state debug UI
# - Add two settings flags:
#   - is_network_pause_debug_shortcut_enabled
#   - is_network_rollback_state_buffer_debug_ui_visible
#     - If true, this will be automatically shown when the network is paused.
# - Create a custom editor plugin for showing a custom tab panel in the bottom
#   dock of the editor.
# - This panel will show all recent network buffer state.
# - THIS WILL REQUIRE ADDING SUPPORT FOR PAUSING THE SERVER (so we can actually
#   inspect the state):
#   - First, the client sends an RPC to the server.
#   - Then, the server flips a custom paused flag, and records the pause_time.
#   - While paused:
#     - The server rejects any new client state stamped after pause_time.
#     - The server continues to replicate state at the same rate as before and
#       with the same on-changed conditions.
#     - However, that state _mostly_ shouldn't ever change.
#     - Instead, the server sends a special RPC whenever new client state has
#       been received and processed, which was stamped with a pre-pause time,
#       to indicated to clients that they can refresh the UI even though we're
#       paused.
#     - The client then, only updates the debug UI 0.5 seconds after first
#       triggering pause, and when this special server RPC is received.
# - When the server is not paused, the panel will just show a pause button.
# - When the server is paused, the panel will show all current buffer state, all
#   in one place.
# - Also, add a hotkey to quickly trigger a pause at runtime.
# - Also, add a settings-toggleable in-game super-hud debug UI to render the
#   current buffer state when paused.
# - This UI should be interactable with the mouse!
# - This UI should prevent clicks from propagating to the underlying scene.
# - This UI should be semi-transparent, in order to still show the scene behind.
# #### Buffer UI parts:
# - It's all one big grid, with uniform cell sizes.
# - Frame index on horizontal axis.
# - List of players and their state along the vertical axis.
# - Each player should be collapsible, and is collapsed by default.
# - The local player is always the top row (regardless of multiplayer_id) and is
#   expanded by default.
# - Each cell only renders a _DIFF_ from the previous cell!
# - Also, each cell only renders a prefix of the state.
# - However, each cell also includes a tooltip with complete details
#   (property name, unabridged labels, the diff, and the full current value).
# - Each cell is also color-coded:
#   - Unchanged values show a "-" and are black.
#   - Changed values are blue.
#   - Missing networked state are grey.
#   - Cells representing values that triggered rollback are red.
# - Also, color-code the frame index header cell for has-network-state (black),
#   no-network-state (grey), and triggered-rollback (red).
#
# ### PART 3: Buffer UI scrubbing
# - Add support for re-rendering the scene with the state from a given buffer
#   frame.
# - Add interaction support for picking and scrubbing through the buffer.
#
# ### PART 4: Rollback reconciliation
# - Add benchmarking:
#   - Track how often rollbacks occur.
#   - Track how many frames are involved with each rollback.
#   - Track how long each rollback takes to process.
# - Implement a check (on both the client and the server) to only trigger
#   rollback if any property's state diff is greater than a configured
#   threshold.
#   - This threshold will need to be configured separately for each property.
#   - TODO: Think about how to configure this...
# - TODO: See notes doc.
#
# ### PART 5: Visualizing rollback reconciliation diff
# - Add a new settings flag: Settings.is_network_pause_on_rollback_enabled
# - Add a new hotkey for triggering auto-pause-on-rollback for the next rollback.
#   - Don't auto-pause before the hotkey enables auto-pause, since there are
#     probably a lot of small rollbacks, and it would be too noisy.
# - OR, should I instead (or also) add a setting to indicate
#   only-auto-pause-on-rollback-when-rollback-is-processing-more-than-x-frames?
# - Add support for automatically triggering a network pause from the client
#   when it triggers a rollback.
# - Whenever both Settings.is_network_pause_debug_shortcut_enabled and
#   Settings.is_network_rollback_state_buffer_debug_ui_visible are
#   enabled, we'll create a copy of all rollback buffers whenever a rollback is
#   triggered.
#   - ACTUALLY, we should just trigger refreshing this duplicate buffer state
#     for all rollbacks, regardless.
#   - This will get re-used for the rollback visual interpolation feature.
#   post-rollback state.
# - When pausing, auto scrub to the frame that orginated the rollback.
# - Now, in each tooltip, show info for both the pre- and post-rollback state.
# - Now, when scrubbing, show post-rollback scene state in the normal scene, and
#   render a duplicate version of the entire screen, overtop the first, as
#   semi-transparent, desaturated, and hue-shifted.
#
# ### PART 5: Visualizing server-side rollback
# - Add a new flag: Settings.is_visualizing_server_instead_of_client_rollbacks
# - When this is enabled, do most of the same pause logic, but don't show client
#   buffer state.
# - Instead, add a new RPC from the server that sends _all_ of the server's
#   pre-rollback buffer state, as well as the newly-received input state.
# - The client then replaces all of its local pre-rollback buffers with the
#   server's versions.
# - The client then...TODO
#
# ### PART 6: Rollback visual interpolation
# - Add support for visually interpolating from pre-rollback state to
#   post-rollback state.
#   - This should result in less snapping on the client.
# - Make sure each networked entity includes a special
#   RollbackVisualInterpolationOffset node.
#   - This should be assigned in an @export var.
#   - Make sure all visual state for the entity (sprites, animations, etc.) and
#     contained under this node.
#   - But all physics state (colliders, etc.) should be outside this node.
# - Maintain a duplicate networked-state rollback buffer for each buffer.
#   - We can actually just re-use the duplicate buffer from the
#     rollback-debug-ui feature.
# - This second buffer will always represent prerollback state.
# - This duplicate buffer must always be the same size as the original.
# - Whenever a rollback occurs, we copy all prerollback state from the orginal
#   to the duplicate
#   starting at the rollback origin frame and then for all following frames.
# - Then, we also record the last-rollback-start-time.
# - Then, in _physics_process, we adjust the RollbackVisualInterpolationOffset
#   position, according to current tween lerp logic from the rollback start time
#   to the current time and the interpolation duration.


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
        # - When processing a frame, we must be able to consider both the target
        #   frame as well as the previous frame, so we can't rollback to the
        #   oldest recorded frame.
        # - Also, some buffers could already contain networked state for the
        #   next frame, so those buffers have one fewer past frames.
        return max(G.network.server_frame_index - rollback_buffer_size + 3, 1)


func _ready() -> void:
    G.log.log_system_ready("NetworkFrameDriver")

    if not Engine.is_editor_hint():
        G.process_sentinel.pre_physics_process.connect(_pre_physics_process)


func _pre_physics_process(_delta: float) -> void:
    _run_network_process()


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
        G.warning("Fast-forwarding due to _physics_process frame skew",
            ScaffolderLog.CATEGORY_NETWORK_SYNC)
        fast_forward(next_server_frame_index - 1)

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


func is_frame_too_old_to_consider(p_frame_index: int) -> bool:
    var target_rollback_frame := p_frame_index + 1
    return target_rollback_frame < oldest_rollbackable_frame_index


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
func queue_rollback(p_conflicting_frame_index: int) -> bool:
    var target_rollback_frame := p_conflicting_frame_index + 1
    if is_frame_too_old_to_consider(p_conflicting_frame_index):
        G.fatal("Requested rollback to frame %d, but oldest rollbackable frame is %d" %
            [target_rollback_frame, oldest_rollbackable_frame_index])
        return false

    # Rollback simulation would start on the next frame after the mismatch.
    if _queued_rollback_frame_index == 0:
        _queued_rollback_frame_index = target_rollback_frame
    else:
        _queued_rollback_frame_index = mini(
            _queued_rollback_frame_index, target_rollback_frame)

    return true


## For most nodes in the scene, _network_process should happen before
## _physics_process.
func _run_network_process() -> void:
    _update_server_frame_time()

    if _queued_rollback_frame_index > 0:
        _rollback_and_reprocess()
        _queued_rollback_frame_index = 0

    _network_process()


func _rollback_and_reprocess() -> void:
    G.print("Starting rollback", ScaffolderLog.CATEGORY_NETWORK_SYNC)

    var original_server_frame_index := server_frame_index
    var original_server_frame_time_usec := server_frame_time_usec

    server_frame_index = _queued_rollback_frame_index
    server_frame_time_usec = floori(
        server_frame_index * TARGET_NETWORK_TIME_STEP_SEC)

    while server_frame_index < original_server_frame_index:
        _network_process()
        server_frame_index += 1

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
    while server_frame_index < new_frame_index:
        server_frame_time_usec += floori(TARGET_NETWORK_TIME_STEP_SEC * 1000000)
        server_frame_index += 1
        _network_process()
