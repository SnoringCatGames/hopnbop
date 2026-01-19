class_name NetworkFrameDriver
extends Node

# FIXME: LEFT OFF HERE: Code review:

# Performance Improvements

# 24. Dictionary iteration in hot path

# _network_process iterates over _networked_state_nodes dictionary every frame:
# for node in _networked_state_nodes:
#     node._pre_network_process()

# Recommendation: Use Array instead of Dictionary for better cache locality:
# var _networked_state_nodes: Array[ReconcilableNetworkedState] = []

# 25. String formatting in logging

# Many log statements format strings even when logging is disabled:
# G.print(
#     "Client-prediction state mismatch: networked state: %s, local state: %s"
#     % [
#         get_string_for_packed_state(packed_state),
#         get_string_for_packed_state(buffer_state),
#     ],
#     ScaffolderLog.CATEGORY_NETWORK_SYNC,
# )

# Recommendation: Guard expensive operations:
# if G.log.should_log(ScaffolderLog.CATEGORY_NETWORK_SYNC):
#     G.print(
#         "Client-prediction state mismatch: networked state: %s, local state: %s"
#         % [get_string_for_packed_state(packed_state),
# get_string_for_packed_state(buffer_state)],
#         ScaffolderLog.CATEGORY_NETWORK_SYNC,
#     )

# 26. Backfill creates many temporary arrays

# func _backfill_to(target_index: int, fill_state: Variant) -> void:
#     while get_latest_index() < target_index:
#         var next_index := get_latest_index() + 1
#         set_at(next_index, fill_state.duplicate())  # Duplicate every iteration!

# Recommendation: Reuse array if possible, or batch allocate:
# var frames_to_fill := target_index - get_latest_index()
# var duplicates := []
# for i in frames_to_fill:
#     duplicates.append(fill_state.duplicate())
# for i in frames_to_fill:
#     set_at(get_latest_index() + 1, duplicates[i])

# Testing Recommendations

# Given the complexity of this system, I strongly recommend adding:

# 1. Unit tests for time conversion functions
# 2. Integration tests for:
# - Rollback with various frame gaps
# - Fast-forward scenarios
# - State mismatch detection with different threshold types
# - Jump event reconciliation
# 3. Stress tests for:
# - High packet loss scenarios
# - Frame skip/stutter scenarios
# - Many simultaneous rollbacks
# 4. Determinism verification: Run same inputs on client and server, verify states match

# ---
# Priority Summary

# Consider for Refactoring:
# - Issues #19-22: Design improvements

# Optimize When Profiling Shows Need:
# - Issues #23-26: Performance improvements

# ------------------------------------------------------------------------------

# FIXME: LEFT OFF HERE: ACTUALLY: Review and debug.
#
# - Get things compiling and try to hand-test a tad before asking the AI.
#   - Add if-statements, guarding on client/server, with a pass, everywhere, to
#     set breakpoints on easily as needed.
#   - Print statements.
#
# - /init, /plan, /review
#
# - Ask AI to analyze all networking logic (everything under the networking/ folder) and generate file-level doc comments for each class.
#
# - Also ask Opus to research recommended test frameworks for Godot, and to then design some integration tests for my networking systems, in particular the client prediction and rollback reconciliation systems
#
# - Ask the AI to write a detailed markdown document explaining the overall architecture, enumerating the networking systems, and describing in detail how they work together to implement client prediction, prediction error detection, and reconciliation with rollback and re-process. Include a section at the end steps to implement networking in a new game using this framework.
#
# - Ask for tips to hand-verify correctness of the overall system, and any particularly important aspects to test.
#
# - Possibly ask for help integrating with GameLift...

# FIXME: Rollback debug visualization and networking improvements:
#
# Prompt: Review my notes and to create a plan for implementing them. Please flag any aspects that seem like a mistake or that don't make sense.
#
# ### PART 0: Add benchmarking
# - Track how often rollbacks occur.
# - Track how many frames are involved with each rollback.
# - Track how long each rollback takes to process.
# - Display all of these benchmarks in the PerfTracker scene.
#
# ### PART 1: Add support for networked pause
# - Add a new flag: Settings.is_server_pause_enabled
# - First, the client sends an RPC to the server.
# - Then, the server flips a custom paused flag, and records the pause_time.
#   - Record this flag in match_state, and have it be synced On Change.
# - Then, have clients check when this flag changes and emit a local signal when
#   it does.
#   - When a pause occurs, on the client, revert any rollback buffer state from
#     after the pause frame.
#   - Also, revert frame-index tracking to the latest pause frame in other
#     places.
#   - Track the cumulative amount of time spent with the server paused. Use this
#     to subtract from server time whenever calculating frame index.
# - Also set get_tree().paused locally when the server is paused.
# - While paused:
#   - The server rejects any new client state stamped after pause_time.
#   - The server continues to replicate state at the same rate as before and
#     with the same on-changed conditions.
#   - However, that state _mostly_ shouldn't ever change.
#   - Instead, the server sends a special RPC whenever new client state has
#     been received and processed, which was stamped with a pre-pause time,
#     to indicate to clients that they can refresh the UI even though we're
#     paused.
#   - The client then, only updates the debug UI 0.2 seconds after first
#     triggering pause, and when this special server RPC is received.
#
# ### PART 2: Editor plugin buffer-state debug UI
# - Add two Settings flags:
#   - is_network_pause_debug_shortcut_enabled
#   - is_network_rollback_state_buffer_debug_ui_visible
#     - If true, this will be automatically shown when the network is paused.
# - Create a custom editor plugin for showing a custom tab panel in the bottom
#   dock of the editor.
# - This panel will show all recent network buffer state.
# - When the server is not paused, the panel will just show a pause button.
# - When the server is paused, the panel will show all current buffer state, all
#   in one place.
# - Also, add a hotkey (ESC) to quickly trigger a pause at runtime.
#
# - Buffer UI parts:
#   - It's all one big grid, with uniform cell sizes.
#   - Frame index on horizontal axis.
#   - List of players and their state along the vertical axis.
#   - Each player should be collapsible, and is collapsed by default.
#   - The local player is always the top row (regardless of multiplayer_id) and
#     is expanded by default.
#   - Each cell only renders a _DIFF_ from the previous cell!
#   - Also, each cell only renders a prefix of the state.
#   - However, each cell also includes a tooltip with complete details
#     (property name, unabridged labels, the diff, and the full current value).
#   - Each cell is also color-coded:
#     - Unchanged values show a "-" and are black.
#     - Changed values are blue.
#     - Missing networked state are grey.
#     - Cells representing values that triggered rollback are red.
#   - Also, color-code the frame index header cell for has-network-state (black),
#     no-network-state (grey), and triggered-rollback (red).
#
# ### PART 3: In-game buffer-state debug UI
# - Also, add a settings-toggleable in-game super-hud debug UI to render the
#   current buffer state when paused.
# - This UI should be interactable with the mouse!
# - This UI should prevent clicks from propagating to the underlying scene.
# - This UI should be semi-transparent, in order to still show the scene behind.
# - This UI should show the same content as the editor plugin version.
#
# ### PART 4: Buffer UI scrubbing
# - Add support for re-rendering the scene with the state from a given buffer
#   frame.
# - Add interaction support for picking and scrubbing through the buffer UI
#   (both the editor-plugin version and the in-game version).
#
# ### PART 5: Visualizing rollback reconciliation diff
# - Add a new settings flag: Settings.is_network_pause_on_rollback_enabled
# - Add a new hotkey (F12) for triggering auto-pause-on-rollback for the next
#   rollback.
#   - Don't auto-pause before the hotkey enables auto-pause, since there are
#     probably a lot of small rollbacks, and it would be too noisy.
# - Add support for automatically triggering a network pause from the client
#   when it triggers a rollback.
# - Whenever ((Settings.is_network_pause_debug_shortcut_enabled and
#   Settings.is_network_rollback_state_buffer_debug_ui_visible) or
#   Settings.is_network_pause_on_rollback_enabled), create a copy of all
#   pre-rollback rollback buffers whenever a rollback is triggered.
#   - This will get re-used for the rollback visual interpolation feature.
# - When pausing, auto scrub to the frame that orginated the rollback.
# - Now, in each tooltip, show info for both the pre- and post-rollback state.
# - Now, when scrubbing, show post-rollback scene state in the normal scene, and
#   render a duplicate version of the entire screen, overtop the first, as
#   semi-transparent, desaturated, and hue-shifted.
#
# ### PART 6: Visualizing server-side rollback
# - Add a new flag: Settings.is_visualizing_server_instead_of_client_rollbacks
# - When this is enabled, do most of the same pause logic, but don't show client
#   buffer state.
# - Instead, add a new RPC from the server that sends _all_ of the server's
#   pre-rollback buffer state, as well as the newly-received input state (this
#   should be sent any time the server is paused).
# - The client then replaces all of its local pre-rollback buffers with the
#   server's versions.
# - Show a label at the top of the panel that indicates whether we're seeing
#   local client state or remote server state.
# - Disable viewing the local client version of the buffer once the server
#   version has been viewed (since we'll have replaced pre-rollback buffers with
#   server state).
#
# ### PART 7: Rollback visual interpolation
# - Add support for visually interpolating from pre-rollback state to
#   post-rollback state.
#   - This should result in less snapping on the client.
# - Make sure each networked entity includes a special
#   RollbackVisualInterpolationOffset node.
#   - This should be assigned in an @export var.
#   - Make sure all visual state for the entity (sprites, animations, etc.) is
#     contained under this node.
#   - But all physics state (colliders, etc.) should be outside this node.
# - Use the duplicate pre-rollback buffer from the rollback-debug-ui feature.
# - Whenever a rollback occurs, we copy all prerollback state from the orginal
#   to the duplicate starting at the rollback origin frame and then for all
#   following frames.
#   - Note, we're now doing this regardless of which debug flags are enabled.
#   - However, for this interpolation, we only need to copy the frames at and
#     following the rollback.
#   - For the previous rollback debug visualization feature, we still need to
#     copy the entire buffer (but only when the appropriate debug flags are
#     enabled).
# - Then, we also record the last-rollback-start-time.
# - Then, in _physics_process, we adjust the RollbackVisualInterpolationOffset
#   position, according to current tween lerp logic from the rollback start time
#   to the current time and the interpolation duration.
#
# ### PART 8: Add hotkeys for toggling each of the various super-hud debug UI
# - F1 should toggle DebugConsole
# - F2 should toggle PlayerStateList
# - F3 should toggle PerfTracker
# - F4 should toggle the rollback buffer
#   - showing local state
#   - this should also toggle server pause
# - F5 should toggle the rollback buffer
#   - showing server state
#   - this should also toggle server pause
#   - we should be able to switch back-and-forth between the client and server
#     versions without unpausing
# - F12 should continue to trigger auto-pause-on-rollback for the next rollback
#   from PART 5.

# FIXME: After polishing networking from above:
# - Implement player kills.
#   - In this game players kill each other by jumping on each other's heads.
#   - In order to detect when one player jumps onto another's head, use the following strategy (or let me know if there is some other industry standard way to implement this that wolud be better!):
#     - Add an additional pair of Area2D nodes to Bunny.tscn.
#     - Have the collision shape be a long thin rectangle for both of these.
#     - Have one area line up with the bottom of the main collision shape and the other line up with the top.
#     - Listen for area-entered and exited events for both of these shapes, and use those listeners to track a list of currently-overlapping bunnies.
#     - Then add logic to also detect when two bunny's collide with eachother with their main collision geometry (possibly handle this by checking current collisions after move_and_slide?).
#     - When two bunnies collide:
#       - Check their relative velocity.
#       - If they are getting closer together vertically, and they are in the list of currently overlapping head/foot areas, then trigger the kill.
#   - Only detect kills on the server. Then send an RPC from the server to all clients for a kill. Include killer, killee, position, and time in the RPC args.
#   - Also for a kill, update game_panel.match_state.
#   - Then handle destroying the killed player and respawning them after a short 1 second delay.
#     - Check for any logic that depends of there being a local player node present, and update it to handle when the player is yet to respawn.
#   - For any bunny-bunny collision that doesn't result in a kill, call this a "bump".
#     - Also track bumps in match_state.
#     - But don't send an RPC for bumps.
#   - Also implement bouncing for the killer when a kill occurs:
#     - The killer should bounce upward a bit, while maintaining horizontal velocity.
# - Use PixelLab for art creation:
#   - https://www.pixellab.ai/
#   - Bunny
#     - Create some mocks for a simple 16x16 bunny.
#     - [Choose one.]
#     - Create a animation spritesheet for this bunny. I need eight frames for a "walk" animation (this is probably more of a hop, since it's a bunny). I need four frames for a jump-rise animation, and four frames for a jump-fall animation. I need eight frames for an idle animation.
#   - Explosion
#     - I need to create animation frames for a gratuitously gorey bunny-explosion splatter effect.
#     - I need to create an alternate bunny-explosion effect for when gore is disabled. This effect should spray flowers and maybe rainbows.
# - Hook-up animations:
#   - Spritesheets are [here].
#   - bunny_animator.tscn and bunny.tscn are [here].
#   - Hook-up the rest, walk, jump-rise, and jump-fall animations.
#   - Hook-up the bunny-explosion gore effect when a bunny is killed.
# - Gore setting:
#   - Add a toggle button on the main menu, pause menu, and game over menu to switch gore on and off.
#   - Record this setting in Settings.
#   - Update the bunny-death animation to check this setting. For non-gore mode, use the flower explosion animation.
#   - Persist a copy of Settings to local user space.
#   - Then, have the gore setting persist to this space when changed; add functions on Settings for triggering save and load, and trigger save from menus when toggling gore.
#   - Have gore default to off.
# - Add a match-selection "level" scene.
#   - Load into this initially when opening the "game" screen.
#   - Update the game/networking systems to support running the game in "local" (non-networked) mode.
#   - Use this local mode for this match-selection level.
#   - Add a special platform on the right side of the level. When the player lands on this platform, trigger load into the main level (and connection with the remote server).
# - Add support for using controllers as input.
# - Add support for multiple players on a single client.
#   - Support the following controls: WASD, IJKL, arrow keys, controllers.
#   - Remove "space" as an input for the "jump" action.
#   - Instead, have just_pressed of "move_up" trigger "jump".
# - In the match-selection level support local players joining or leaving.
#   - By default, have 0 local players.
#   - Show a big message at the top of the screen, indicating to press up to join and down to leave.
#     - It should also indicate the available controls (WASD, IJKL, arrow keys, controllers).
#   - Add logic to spawn and destroy local players when up and down are pressed.
#   - Add logic to map input source (WASD, IJKL, arrow keys, controllers) to player.
#   - Update PlayerActionSource to only handle the specific input source
#     associated with its corresponding player.
#   - Update game connection logic to handle the new dynamic list of players
#     from a client.
#     - Instead of the server just automatically spawning a player for each
#       newly-connected client, the server should wait until the client sends an
#       RPC with its local-player count.
#     - We now need to also introduce a concept of player_id.
#     - When the server receives the RPC from the client indicating its number
#       of local players, the server will generate player_ids for each of the
#       new players, as well as the player name and adjective state that we were
#       previously generating. The player_id now also gets replicated with
#       PlayerMatchState.
#     - The client then detects when a new player_id is represented in match
#       state or on a Player node, picks an input source to map to this
#       player_id, and records that.
#     - Maintain a mapping from multiplayer_id to player_id.
#     - Replace most preexisting references to multiplayer id with this new
#       player_id, as appropriate.
# - Add support for accumulating gore (or flower) particles from bunny
#   explosions.
#   - Whenever an explosion happens, spawn a handful of custom particles that explode outward.
#   - These should be a custom scene, rather than using Godot's built-in particle logic.
#   - A particle should extend RigidBody2D.
#   - Each particle should use a circle for its collision geometry.
#   - We should have a set of 8 different particle definitions for gore and a set of 8 for flowers.
#   - Each particle definition has a different sprite and a different collision radius.
#   - Each particle is assigned a random definition.
#   - Each particle is assigned a random direction and a random speed (within a min-max range).
#   - Actually, define two separate types of particles: fast and slow:
#    - There should be four definitions for either type (still with a duplicate set for gore vs non-gore mode).
#    - The fast particles should have a lot more speed when initially spawned, and should bounce more.
#   - When the particle comes to rest (displacement for a frame is less than some threshold like 0.05), destroy the node, and record the particle's type and position in separate arrays.
#   - Create a shader that accepts these arrays of particle types and positions, and renders them.
#   - Alternatively, let me know if there is a better way to efficently render tens of thousands of particles like this!
#
# - Sounds
#   - Kill
#     - Splatter sound
#     - Confetti party popper sound for non-gore mode
#   - Jump sound
#   - Land sound
#   - Walk sound
#   - Bunny bump sound
#   - Menu click sound

## This determines the period we use between frames that we record in rollback
## buffers.
##
## Network state will presumably be slower than this in practice. When that
## occurs, we fill-in empty frames by extrapolating from the most-recent filled
## frame.
const TARGET_NETWORK_FPS = ScaffolderTime.PHYSICS_FPS
const TARGET_NETWORK_TIME_STEP_SEC := 1.0 / TARGET_NETWORK_FPS
const TARGET_NETWORK_TIME_STEP_USEC := floori(1_000_000 / TARGET_NETWORK_FPS)

## If we bucket the current server_time_usec into discrete frames, this
## canonical time would be the exact midpoint between the previous and next
## frame.
var server_frame_time_usec := 0

## If we bucket the current server_time_usec into discrete frames, this
## would be index of the current frame.
var server_frame_index := 0

# Dictionary<ReconcilableNetworkedState, bool>
var _networked_state_nodes := { }

# Dictionary<NetworkFrameProcessor, bool>
var _network_frame_processor_nodes := { }

var _queued_rollback_frame_index := 0

var rollback_buffer_size: int:
    get:
        return ceili(
            G.settings.rollback_buffer_duration_sec * TARGET_NETWORK_FPS,
        )

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


func _pre_physics_process(delta: float) -> void:
    if delta / NetworkFrameDriver.TARGET_NETWORK_TIME_STEP_SEC > 1.5:
        G.warning(
            "Physics frame skip detected: delta=%fs"
            % [delta],
            ScaffolderLog.CATEGORY_NETWORK_SYNC,
        )
    _run_network_process()


## If we bucket server time into discrete frames, this would be the index of the
## frame corresponding to the given time.
func get_frame_index_from_time_usec(p_time_usec: int) -> int:
    return floori(p_time_usec / TARGET_NETWORK_TIME_STEP_USEC)


func get_time_usec_from_frame_index(p_frame_index: int) -> int:
    return floori(
        p_frame_index * TARGET_NETWORK_TIME_STEP_USEC +
        TARGET_NETWORK_TIME_STEP_USEC * 0.5,
    )


func _update_server_frame_time() -> void:
    var server_time_usec := G.network.server_time_usec_not_frame_aligned
    var frame_start_time_usec := floori(
        get_frame_index_from_time_usec(server_time_usec) *
        TARGET_NETWORK_TIME_STEP_USEC,
    )

    var next_server_frame_time_usec := floori(
        frame_start_time_usec + TARGET_NETWORK_TIME_STEP_USEC * 0.5,
    )
    var next_server_frame_index := get_frame_index_from_time_usec(
        next_server_frame_time_usec,
    )

    if not G.ensure(
        next_server_frame_index >= server_frame_index - 1,
        "Server frame index went backwards: %d -> %d"
        % [server_frame_index, next_server_frame_index],
    ):
        return

    # If our tracking of server time has skewed enough that we're skipping a
    # frame, then we need to fast-forward the system.
    if next_server_frame_index > server_frame_index + 1:
        G.warning(
            "Fast-forwarding due to _physics_process frame skew",
            ScaffolderLog.CATEGORY_NETWORK_SYNC,
        )
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
        G.fatal(
            "Requested rollback to frame %d, " +
            "but oldest rollbackable frame is %d"
            % [target_rollback_frame, oldest_rollbackable_frame_index],
        )
        return false

    # Rollback simulation would start on the next frame after the mismatch.
    if _queued_rollback_frame_index == 0:
        _queued_rollback_frame_index = target_rollback_frame
    else:
        _queued_rollback_frame_index = mini(
            _queued_rollback_frame_index,
            target_rollback_frame,
        )

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
        server_frame_index * TARGET_NETWORK_TIME_STEP_USEC,
    )

    # Re-simulate all frames between the mismatch and current frame (exclusive).
    # The loop processes frames [rollback_frame, original_frame), but not the
    # original frame itself. The current frame will be re-simulated afterward in
    # the normal _run_network_process flow.
    while server_frame_index < original_server_frame_index:
        _network_process()
        server_frame_index += 1

    server_frame_index = original_server_frame_index
    server_frame_time_usec = original_server_frame_time_usec


## Simulate the current frame for all network-process-aware nodes.
func _network_process() -> void:
    for node in _networked_state_nodes.keys():
        # TODO: This should not be possible, so try to figure out the underlying
        #       problem.
        if not is_instance_valid(node):
            # We're iterating over a copy of the keys, so it's safe to erase.
            _networked_state_nodes.erase(node)

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
        server_frame_time_usec += TARGET_NETWORK_TIME_STEP_USEC
        server_frame_index += 1
        _network_process()
