class_name NetworkFrameDriver
extends Node
## Core frame-synchronous simulation engine for client-prediction rollback
## networking.
##
## NetworkFrameDriver is the heart of the networking system, managing
## deterministic frame-based simulation at a fixed FPS (independent of render
## framerate). It coordinates all networked entities through a three-phase
## processing cycle:
##
## 1. **_pre_network_process**: Restore state from rollback buffer for current
##    frame
## 2. **_network_process**: Execute game logic (movement, physics, input
##    handling)
## 3. **_post_network_process**: Pack and record new state to rollback buffer
##
## Key responsibilities:
## - Maintains server_frame_index and server_frame_time_usec for frame-aligned
##   simulation
## - Manages the rollback buffer
## - Detects state mismatches and triggers rollback reconciliation
## - Coordinates re-simulation of frames during rollback
## - Handles fast-forwarding when client falls behind server
## - Registers and manages all ReconcilableNetworkedState and
##   NetworkFrameProcessor nodes
##
## Networked entities must extend either ReconcilableNetworkedState or
## NetworkFrameProcessor to participate in this frame-synchronous cycle.
## - ReconcilableNetworkedState nodes support server-mismatch detection and
##   rollback
## - NetworkFrameProcessor nodes simply process each frame without rollback
##   support.
##
## Accessed via G.network.frame_driver singleton.
##
## Frame timing:
## - Target: 60 FPS (TARGET_NETWORK_TIME_STEP_SEC = 1/60 ≈ 0.01666 seconds)
## - Frames are identified by server_frame_index, which increments directly on
##   each physics tick for perfect synchronization with Godot's physics loop
## - Timestamps are calculated from frame indices, with periodic wall-clock
##   re-sync every 30 seconds to maintain accurate logging timestamps
## - Times are stored in microseconds for precision
##
## Rollback mechanism:
## - queue_rollback() schedules rollback to a specific frame (conflict detection)
## - _rollback_and_reprocess() restores state and re-simulates up to current
##   frame
## - Only one rollback occurs per _network_process, earliest frame takes priority

# FIXME: LEFT OFF HERE: Main list: ---------------------------------------------

# - Is there a potential problem from frame drift between the client and the server?

# - Test kills and bumps.
# - Adjust foot, head, and body shapes.

# - Lingering FIXMEs.

# TEST that when a high-speed kill happens, the bounce happens from where the initial collision contact should have been.

# TEST THIS
# - All FN keys
# - Player annotator

# UI fixes:
# - [Match countdown] Remaining Tasks:
#   - Configure Replication in MatchStateSynchronizer:
#   1. Open the MatchStateSynchronizer node in the scene tree
#   - Add these properties to replicate:
#   - state:match_start_time_usec (REPLICATION_MODE_ON_CHANGE)
#   - state:match_duration_usec (REPLICATION_MODE_ON_CHANGE)
#   - state:is_match_ended (REPLICATION_MODE_ON_CHANGE)
#   - Create countdown_timer.tscn
#   2. Create new scene with Label as root
#   - Attach CountdownTimer script
#   - Configure theme overrides (font size ~24, outline)
#   - Set unique_name_in_owner = true
#   - Save as countdown_timer.tscn
#   - Update hud.tscn
#   3. Open hud.tscn
#   - Navigate to MarginContainer/VBoxContainer/HBoxContainer/RightContent
#   - Add CountdownTimer scene as child
#   - Position and style as needed
# - Adjust scene files: lobby_level.tscn, player_list.tscn, player_display.tscn.
# - Lobby scene:
#   - Embed the game title logo within the level.
#   - Also embed some controls instruction.
#   - Also embed instructions to go down hole for starting match.
#   - Call MatchmakingClient.start_matchmaking() when any player jumps down a
#     rabbit hole on the right side of the level.
# - Hook-up / polish pause UI.
#   - Show a small panel in the center of the window with a lightly transparent screen.

# - Update some "debug mode" checks (like for enabling screenshots) to consider
#   whether we're running in preview mode in the editor.
#   - Add this as a getter in settings.
#   - Move some of the current G.network flag parsing and checks to settings.
#   - We should also override various other settings if we're not in the editor.
#     - Do this with getters on those properties.
#     - Probably need to check Engine.is_editor_hint though also in the getters.

# FIXME: GameLift
# - [Obsolete?] Proceed with the "AWS GameLift Deployment Guide"
#   - Add player authentication and profile management.
#   - Set up CloudWatch alarms for monitoring.
#   - Configure auto-scaling policies based on load.
# - Also ask AI to:
#   - Want to make sure we can easily test GameLift locally.
#   - Implement easy scripts for building and deploying and testing. Maybe can also add a hook for GitHub Actions when creating tags? Or ask for a better deployment with trigger solution
#   - Implement logic for handling logins to the various auth providers.
#   - Implement a database for recording some game data:
#     - player data (id, bunny name and adjective, first play time, last play time, total time played, total wins, total kills, total deaths, login info for whichever auth providers they've connected to, ...)
#     - a leaderboard
#   - Implement a way to make friends and to join matches with friends.

# - Tweak movement parameters

# - Have bunnies be flung in from off-screen from the left.
#   - Move the happen points over there, and give bunnies initial velocity.
#   - Remove some of the tiles near the top of the left wall for this. But make sure players can't jump that high.
#   - Disable player-player collision mask bit in the lobby.

# - Show a floating +/-N label over the PlayerDisplay when adjusting the score. With a tween. It should slowly rise up. It should fade out.

# FIXME: Rollback debug visualization and networking improvements:
#
# Prompt:
# Review my notes and to create a plan for implementing them.
# Please flag any aspects that seem like a mistake or that don't make sense.
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
#   - The local player is always the top row (regardless of peer_id) and
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
#   - While paused:
#     - The client then, only updates the debug UI 0.2 seconds after first
#       triggering pause, and whenever any new packed_state is received.
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
# - Use PixelLab for level art ideation?:
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
# - In the lobby, when spawning a player, briefly render over their head an indicator for which controls they're using.
#   - A simple drawing of rectangles in the shape of WASD, IJKL, or Arrows, or a controller shape.
# - Sounds (talk to Alden)
#   - Kill
#     - Splatter sound
#     - Confetti party popper sound for non-gore mode
#   - Jump sound
#   - Land sound
#   - Walk sound
#   - Bunny bump sound
#   - Menu click sound

# - Add support for dynamic level selection.
#   - The server should choose the level for a match.
#   - The client should be able to specific a three things: an inclusion list, an exclusion list, and a preferred level.
#   - The server should try to accommodate these, but should be able to override all of these, depending on the combined client preferences of the match.

# - Add support for a slide-transition effect that slides a black panel over the lobby screen before showing the loading screen.
#   - This panel slide will use a Tween.
#   - We'll need to trigger this from client_load_game.
#   - We'll need to then have a delay before despawning the lobby level.
#   - We'll need to then prevent player modifications (spawn, despawn, triggering anything in lobby) during this transition.
#   - We should also add another tween to every screen to transition it from transparent to opaque when it is opened.

# - Add alternate the camera modes.
#   - Support two modes: global camera vs player camera.
#   - This will be configured on the level.
#   - For global camera, dynamically instantiate, configure (according to
#     level bounds), attach, and activate a camera to the level.
#   - For player camera, add support for split screen.
#     - Add a TODO for this for now.

# - [Copilot] Go through each file and fix formatting inconsistencies.
#   - Make sure there are always two empty lines between functions and after the
#     class `extends` line.
#     - But make sure that if a file-level doc comment is present, it is on the
#       next line after the `extends` line
#   - Fix inconsistent line-break. Lines should break at 80 characters.
#   - Use tabs instead of spaces.
#   - Fix anything else that looks off.

# - Add support for web and mobile
#   - Plan through what all needs to change to support websockets
#   - Send client type to the matchmaking backend? Have it prefer the same device type, but be willing to match with others
#   - Mobile controls:
#     - Divide screen into three regions: left, middle, right
#     - Tap middle to jump
#     - Pressed left right I move
#     - Draw a semitransparent bar across the bottom to indicate the regions with an icon
#     - Have a setting to disable the bar

# ### TODO: After everything else:
# - Survey the codebase for where we use string literals. Should any of these be StringName literals instead?
# - Survey all RPCs. Decide whether we should introduce new RPC channels and assign them as appropriate. Reference them as consts on NetworkConnector.
# - Review tests.
# - Review these notes: https://docs.google.com/document/d/1qJcNUrE1y8UllVVCojp-IN3zCwml8VK7kjYhp1uJhV4
# - Review NETWORKING_ARCHITECTURE.md.
# - Review these notes: https://trello.com/c/i8peodBL
# - Organize Settings.
#   - Analyze all properties in Settings, and how they are used.
#   - Re-group, re-order, re-name, and possibly consolidate properties in whichever way makes the most sense.
# - Use is_instance_valid instead of null comparisons.
# - Survey usage of G.check, G.ensure, G.error, G.fatal, and G.alert.
#   - Check if there are places that I should be more gracefully showing the
#     player a message, and/or redirecting back to the lobby, possibly with
#     reset game state.
# - AI: Scan through all logs, and consider whether we should add any additional
#   categories, and re-group logs int whichever categories make the most sense.
# - AI: I am considering creating a re-usable GDExtension that I can publish on
#   the Godot Asset Library for anyone to use for common featurse when
#   integrating with AWS GameLift.
#   - Does this make sense? Is there any logic within the current C++
#     GDExtension directory that is specific to this local game? Or are there
#     any additional features that it would make sense to add?
# - AI: I want to publish a plugin on the Godot Asset Library that provides
#   support for client prediction and rollback networking. Please create a plan
#   for implementing this plugin based on the current networking architecture in
#   this project. The plugin should be easy to integrate into new Godot
#   projects, and should include documentation and example scenes. In
#   particular, analyze this codebase, and identify which systems need to be
#   decoupled in order to separate-out the game-agnostic networking logic
#   (connection, replication, prediction, rollback, driver, time-tracking,
#   important not-game-specific local-session and match-state logic, etc). In
#   particular, I think some of the current "local-session" vs "match-state" vs
#   other state tracked in networking systems might be best to consolidate in a
#   separate location.
#
# ### Devlog post:
# - AI helped a lot
# - AI sucked at:
#   - Fixing the GitHub Actions CI workflows.
#     - Probably ~60 iterations.
#

## This determines the period we use between frames that we record in rollback
## buffers.
##
## Network state will presumably be slower than this in practice. When that
## occurs, we fill-in empty frames by extrapolating from the most-recent filled
## frame.
const TARGET_NETWORK_FPS = ScaffolderTime.PHYSICS_FPS
const TARGET_NETWORK_TIME_STEP_SEC := 1.0 / TARGET_NETWORK_FPS
const TARGET_NETWORK_TIME_STEP_USEC := floori(1_000_000 / TARGET_NETWORK_FPS)

## Frame-aligned server time (microseconds). Calculated from server_frame_index
## via get_time_usec_from_frame_index(), which returns the midpoint timestamp
## of the current frame. Periodically re-synced to wall-clock time for accurate
## logging.
var server_frame_time_usec := 0

## Current frame index. Incremented directly on each physics tick in
## _pre_physics_process(). Drives all frame-synchronous simulation and rollback.
## This is the single source of truth for frame progression.
var server_frame_index := 0

## Tracks whether frame tracking has been initialized. Initialization is
## deferred until the first physics tick after ServerTimeTracker is ready,
## preventing fast-forward at startup.
var _is_frame_tracking_initialized := false

## Pauses frame simulation. Starts paused by default - server unpauses when
## ready (e.g., after all players connect in GameLift). When paused,
## _pre_physics_process returns early without incrementing server_frame_index
## or running network processing.
var _is_paused := true

## Frame index when pause started. Used to calculate cumulative pause duration,
## filter incoming states during pause, and revert frame tracking after pause.
var _pause_start_frame_index := 0

## Total frames paused across all pause periods. This is subtracted from
## time-based frame calculations to maintain continuous frame progression
## without gaps.
var _cumulative_paused_frames := 0

## History of pause periods for debugging/logging.
## Array of { start_frame: int, end_frame: int, duration_frames: int }
var _pause_history: Array[Dictionary] = []

## Tracks last pause request time for rate limiting (microseconds).
var _last_pause_request_time_usec := 0

## Peer ID of the client that initiated the current pause.
var _pause_initiator_peer_id: int = 0

## Number of pauses used by the initiator at the time of pause.
var _pause_initiator_pauses_used: int = 0

## Time when the current pause will automatically unpause (microseconds).
## This is replicated to clients for countdown display.
var _pause_auto_unpause_time_usec: int = 0

## Timeout ID for auto-unpause timer (server-only).
var _pause_auto_unpause_timeout_id: int = 0

## Interval for periodic wall-clock re-sync to maintain accurate timestamps for
## logging. Re-sync is handled automatically via G.time.set_interval().
const WALL_CLOCK_RESYNC_INTERVAL_SEC := 30.0

var _networked_state_nodes: Array[ReconcilableNetworkedState] = []

var _network_frame_processor_nodes: Array[NetworkFrameProcessor] = []

var _queued_rollback_frame_index := 0

## Rollback tracking metrics (for performance monitoring)
var last_rollback_frame_count := 0
var last_rollback_duration_usec := 0
var total_rollbacks := 0

## Fast-forward tracking metrics (for performance monitoring)
var last_fastforward_frame_count := 0
var last_fastforward_duration_usec := 0
var total_fastforwards := 0

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
		return max(server_frame_index - rollback_buffer_size + 3, 1)

## Whether frame simulation is currently paused.
var is_paused: bool:
	get:
		return _is_paused

## Frame index when pause started. Returns 0 if not currently paused.
var pause_start_frame: int:
	get:
		return _pause_start_frame_index if _is_paused else 0


func _ready() -> void:
	G.log.log_system_ready("NetworkFrameDriver")

	if not Engine.is_editor_hint():
		G.process_sentinel.pre_physics_process.connect(_pre_physics_process)

		# Start paused - server will unpause when ready (e.g., after all players
		# connect in GameLift).
		if is_inside_tree():
			get_tree().paused = true

		# In preview mode (local multi-instance testing), track client
		# connections and unpause when all expected clients have connected.
		if G.network.is_preview and G.network.is_server:
			multiplayer.peer_connected.connect(_on_preview_peer_connected)
			# Check if clients are already connected.
			_check_preview_clients_connected()


## Handles peer connections in preview mode to auto-unpause when ready.
func _on_preview_peer_connected(_peer_id: int) -> void:
	_check_preview_clients_connected()


## Checks if all expected clients are connected in preview mode.
func _check_preview_clients_connected() -> void:
	if not G.network.is_preview or not G.network.is_server:
		return

	var connected_count := multiplayer.get_peers().size()
	var expected_count := G.settings.preview_client_count

	G.print(
		"Preview mode: %d/%d clients connected" % [
			connected_count,
			expected_count
		],
		ScaffolderLog.CATEGORY_NETWORK_SYNC,
	)

	if connected_count >= expected_count:
		G.print(
			"All expected clients connected; Unpausing game",
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
		)
		# Disconnect signal to avoid re-checking.
		if multiplayer.peer_connected.is_connected(_on_preview_peer_connected):
			multiplayer.peer_connected.disconnect(_on_preview_peer_connected)
		server_set_is_paused(false)


## Pause or unpause frame simulation.
##
## When paused, frame processing stops completely - server_frame_index does not
## increment and no network processing occurs. This is used by GameLift to wait
## for all players to connect before starting the game.
##
## @param paused: true to pause, false to unpause.
func server_set_is_paused(paused: bool) -> void:
	if paused:
		_server_execute_pause()
	else:
		_server_execute_unpause()


func client_request_toggle_pause() -> void:
	if G.network.frame_driver.is_paused:
		G.network.frame_driver.client_request_unpause()
	else:
		G.network.frame_driver.client_request_pause()


## Request pause from client. Only works if Settings.is_server_pause_enabled.
func client_request_pause() -> void:
	G.check_is_client()
	_server_rpc_client_request_pause.rpc_id(NetworkConnector.SERVER_ID)


## Request unpause from client. Only works if Settings.is_server_pause_enabled.
func client_request_unpause() -> void:
	G.check_is_client()
	_server_rpc_request_unpause.rpc_id(NetworkConnector.SERVER_ID)

## Client requests server to pause.


@rpc("any_peer", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _server_rpc_client_request_pause() -> void:
	G.check_is_server()

	var peer_id := multiplayer.get_remote_sender_id()

	if not G.settings.is_server_pause_enabled:
		G.print(
			"Client %d requested pause, but server pause is disabled" % peer_id,
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
		)
		return

	# Rate limit pause requests.
	var current_time := Time.get_ticks_usec()
	var cooldown_usec := int(G.settings.pause_request_cooldown_sec * 1_000_000)
	if current_time - _last_pause_request_time_usec < cooldown_usec:
		return

	# Check pause limit for this peer.
	var pauses_used: int = G.game_panel.match_state.pauses_used_by_peer.get(peer_id, 0)
	if pauses_used >= G.settings.max_pauses_per_client:
		G.print(
			"Client %d requested pause, but has exhausted pause limit (%d/%d)" % [
				peer_id,
				pauses_used,
				G.settings.max_pauses_per_client,
			],
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
		)
		return

	# Increment pause count for this peer.
	G.game_panel.match_state.pauses_used_by_peer[peer_id] = pauses_used + 1

	_last_pause_request_time_usec = current_time
	_server_execute_pause(peer_id, pauses_used + 1)


## Client requests server to unpause.
@rpc("any_peer", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _server_rpc_request_unpause() -> void:
	G.check_is_server()

	var peer_id := multiplayer.get_remote_sender_id()

	if not G.settings.is_server_pause_enabled:
		G.print(
			"Client %d requested unpause, but server pause is disabled" % peer_id,
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
		)
		return

	# Check if requesting peer is the pause initiator.
	if peer_id != _pause_initiator_peer_id:
		G.print(
			"Client %d requested unpause, but only initiator (peer %d) can unpause" % [
				peer_id,
				_pause_initiator_peer_id,
			],
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
		)
		return

	# Rate limit pause requests.
	var current_time := Time.get_ticks_usec()
	var cooldown_usec := int(G.settings.pause_request_cooldown_sec * 1_000_000)
	if current_time - _last_pause_request_time_usec < cooldown_usec:
		return

	_last_pause_request_time_usec = current_time
	_server_execute_unpause()

## Server notifies all clients of pause.


@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _client_rpc_notify_pause(
	server_pause_frame: int,
	server_pause_time_usec: int,
	pause_initiator_peer_id: int,
	pause_initiator_pauses_used: int,
	pause_auto_unpause_time_usec: int,
) -> void:
	G.check_is_client()

	_client_execute_pause_at_server_frame(
		server_pause_frame,
		server_pause_time_usec,
		pause_initiator_peer_id,
		pause_initiator_pauses_used,
		pause_auto_unpause_time_usec,
	)

## Server notifies all clients of unpause.


@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _client_rpc_notify_unpause(
		server_unpause_frame: int,
		server_unpause_time_usec: int,
		server_cumulative_paused_frames: int,
) -> void:
	G.check_is_client()

	_client_execute_unpause_at_server_frame(
		server_unpause_frame,
		server_unpause_time_usec,
		server_cumulative_paused_frames,
	)


## Server notifies all clients of impending graceful shutdown.
## Called before disconnecting clients during Spot instance termination.
@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _client_rpc_notify_shutdown(shutdown_message: String) -> void:
	G.check_is_client()

	G.print(
		"Server shutdown notification: %s" % shutdown_message,
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS,
	)

	# Store reason in connector for disconnect handling.
	G.network.connector.last_disconnect_reason = \
		NetworkConnector.DisconnectReason.SERVER_SHUTDOWN

	# Store message in LocalSession for game over screen display.
	G.local_session.latest_server_message = shutdown_message


## Internal method to execute pause on server or client.
##
## @param initiator_peer_id: Peer ID that initiated the pause (0 for system pause).
## @param pauses_used: Number of pauses used by initiator after this pause.
func _server_execute_pause(
	initiator_peer_id: int = 0,
	pauses_used: int = 0
) -> void:
	if _is_paused:
		return

	_is_paused = true
	_pause_start_frame_index = server_frame_index
	_pause_initiator_peer_id = initiator_peer_id
	_pause_initiator_pauses_used = pauses_used

	# Calculate auto-unpause time for replication to clients (for countdown).
	_pause_auto_unpause_time_usec = (
		Time.get_ticks_usec() +
		int(G.settings.max_pause_duration_sec * 1_000_000)
	)

	# Schedule auto-unpause using timer system (server-only).
	if G.network.is_server:
		_pause_auto_unpause_timeout_id = G.time.set_timeout(
			func():
				G.print(
					"Auto-unpausing after timeout",
					ScaffolderLog.CATEGORY_NETWORK_SYNC,
				)
				_server_execute_unpause(),
			G.settings.max_pause_duration_sec,
		)

	# Clean up buffer frames after pause started.
	_cleanup_buffer_after_pause()

	# Clear queued rollback - it's based on invalid post-pause state.
	_queued_rollback_frame_index = 0

	# Notify clients (if server and in tree for RPC).
	if G.network.is_server and is_inside_tree():
		_client_rpc_notify_pause.rpc(
			server_frame_index,
			server_frame_time_usec,
			_pause_initiator_peer_id,
			_pause_initiator_pauses_used,
			_pause_auto_unpause_time_usec,
		)

	# Pause Godot scene tree.
	if is_inside_tree():
		get_tree().paused = true

	# Pause time tracking.
	G.network.time.pause()

	G.print(
		"Server paused at frame %d by peer %d" % [
			server_frame_index,
			initiator_peer_id,
		],
		ScaffolderLog.CATEGORY_NETWORK_SYNC,
	)


## Internal method to execute unpause on server or client.
func _server_execute_unpause() -> void:
	if not _is_paused:
		return

	var pause_duration_frames := server_frame_index - _pause_start_frame_index
	_cumulative_paused_frames += pause_duration_frames

	# Record pause history.
	_pause_history.append(
		{
			"start_frame": _pause_start_frame_index,
			"end_frame": server_frame_index,
			"duration_frames": pause_duration_frames,
		},
	)

	_is_paused = false

	# Cancel auto-unpause timeout (server-only).
	if G.network.is_server and _pause_auto_unpause_timeout_id != 0:
		G.time.clear_timeout(_pause_auto_unpause_timeout_id)
		_pause_auto_unpause_timeout_id = 0

	# Reset pause state variables.
	_pause_initiator_peer_id = 0
	_pause_initiator_pauses_used = 0
	_pause_auto_unpause_time_usec = 0

	# Notify clients (if server and in tree for RPC).
	if G.network.is_server and is_inside_tree():
		_client_rpc_notify_unpause.rpc(
			server_frame_index,
			server_frame_time_usec,
			_cumulative_paused_frames,
		)

	# Unpause Godot scene tree.
	if is_inside_tree():
		get_tree().paused = false

	# Unpause time tracking.
	G.network.time.unpause()

	G.print(
		"Server unpaused at frame %d (paused for %d frames, cumulative: %d)" %
		[server_frame_index, pause_duration_frames, _cumulative_paused_frames],
		ScaffolderLog.CATEGORY_NETWORK_SYNC,
	)


## Execute pause on client at server-specified frame (client-side).
func _client_execute_pause_at_server_frame(
		server_pause_frame: int,
		server_pause_time_usec: int,
		pause_initiator_peer_id: int,
		pause_initiator_pauses_used: int,
		pause_auto_unpause_time_usec: int,
) -> void:
	if _is_paused:
		return

	_is_paused = true
	_pause_initiator_peer_id = pause_initiator_peer_id
	_pause_initiator_pauses_used = pause_initiator_pauses_used
	_pause_auto_unpause_time_usec = pause_auto_unpause_time_usec

	# Align with server's pause frame.
	server_frame_index = server_pause_frame
	server_frame_time_usec = server_pause_time_usec
	_pause_start_frame_index = server_pause_frame

	# Clean up buffer frames after pause started.
	_cleanup_buffer_after_pause()

	# Clear queued rollback.
	_queued_rollback_frame_index = 0

	# Pause Godot scene tree.
	if is_inside_tree():
		get_tree().paused = true

	# Pause time tracking.
	G.network.time.pause()

	# Auto-open pause screen for all clients.
	if is_instance_valid(G.screens):
		if G.screens.current_screen == ScreensMain.ScreenType.GAME:
			G.screens.client_open_screen(ScreensMain.ScreenType.PAUSE)

	G.print(
		"Client synchronized pause at frame %d" % server_frame_index,
		ScaffolderLog.CATEGORY_NETWORK_SYNC,
	)


## Execute unpause on client at server-specified frame (client-side).
func _client_execute_unpause_at_server_frame(
		server_unpause_frame: int,
		server_unpause_time_usec: int,
		server_cumulative_paused_frames: int,
) -> void:
	if not _is_paused:
		return

	# Adopt server's pause accounting.
	_cumulative_paused_frames = server_cumulative_paused_frames

	var previous_frame := server_frame_index

	# Align frame index with server.
	server_frame_index = server_unpause_frame
	server_frame_time_usec = server_unpause_time_usec

	_is_paused = false
	_pause_start_frame_index = 0

	# Reset pause state variables.
	_pause_initiator_peer_id = 0
	_pause_initiator_pauses_used = 0
	_pause_auto_unpause_time_usec = 0

	# Unpause Godot scene tree.
	if is_inside_tree():
		get_tree().paused = false

	# Unpause time tracking.
	G.network.time.unpause()

	# Auto-close pause screen and return to game.
	# Also transition from loading screen to game when server starts.
	if is_instance_valid(G.screens):
		if G.screens.current_screen == ScreensMain.ScreenType.PAUSE:
			G.screens.client_open_screen(ScreensMain.ScreenType.GAME)
		elif G.screens.current_screen == ScreensMain.ScreenType.LOADING:
			# Transition from loading to game when server unpauses.
			G.screens.client_open_screen(ScreensMain.ScreenType.GAME)

	G.print(
		"Client synchronized unpause: frame %d->%d (paused: %d, init=%s)" % [
			previous_frame,
			server_frame_index,
			_cumulative_paused_frames,
			_is_frame_tracking_initialized,
		],
		ScaffolderLog.CATEGORY_NETWORK_SYNC,
	)


## Clean up rollback buffer state after pause.
func _cleanup_buffer_after_pause() -> void:
	for node in _networked_state_nodes:
		if is_instance_valid(node):
			node._cleanup_buffer_after_pause(_pause_start_frame_index)


func _pre_physics_process(_delta: float) -> void:
	if _is_paused:
		return

	if not _is_frame_tracking_initialized:
		_initialize_frame_tracking()
		return

	# Increment frame index directly on each physics tick
	server_frame_index += 1

	_run_network_process()


func _initialize_frame_tracking() -> void:
	# Wait for ServerTimeTracker to be ready before starting frame tracking
	if not G.network.time.is_time_initialized:
		return

	_is_frame_tracking_initialized = true

	# Initialize to frame 0
	# The first physics tick will increment this to 1
	var previous_frame_index := server_frame_index
	server_frame_index = 0
	server_frame_time_usec = get_time_usec_from_frame_index(0)

	# Set up periodic wall-clock re-sync using ScaffolderTime's interval system
	G.time.set_interval(
		_resync_frame_time_to_wall_clock,
		WALL_CLOCK_RESYNC_INTERVAL_SEC,
		[],
		TimeType.APP_CLOCK,
	)

	# Note: Clients sync to server's clock via NTP offset, but track their own
	# frame indices locally starting from 0
	G.print(
		"Frame tracking initialized at frame 0 (was %d)" % previous_frame_index,
		ScaffolderLog.CATEGORY_NETWORK_SYNC,
	)


## If we bucket server time into discrete frames, this would be the index of the
## frame corresponding to the given time. Accounts for cumulative pause time to
## maintain continuous frame indices without gaps.
func get_frame_index_from_time_usec(p_time_usec: int) -> int:
	@warning_ignore("integer_division")
	var raw_frame := p_time_usec / TARGET_NETWORK_TIME_STEP_USEC
	return raw_frame - _cumulative_paused_frames


## Convert frame index to time. Accounts for cumulative pause time by adding
## paused frames back to the time calculation.
func get_time_usec_from_frame_index(p_frame_index: int) -> int:
	var adjusted_frame := p_frame_index + _cumulative_paused_frames
	return floori(
		adjusted_frame * TARGET_NETWORK_TIME_STEP_USEC +
		TARGET_NETWORK_TIME_STEP_USEC * 0.5,
	)


func _update_server_frame_time() -> void:
	# Update frame timestamp based on current frame index
	# Periodic wall-clock re-sync is handled by G.time.set_interval
	server_frame_time_usec = get_time_usec_from_frame_index(server_frame_index)


func _resync_frame_time_to_wall_clock() -> void:
	var actual_server_time_usec := G.network.server_time_usec_not_frame_aligned
	var frame_based_time_usec := get_time_usec_from_frame_index(server_frame_index)
	var drift_usec := actual_server_time_usec - frame_based_time_usec

	# Warn if drift exceeds 1 second (indicates potential timing issues)
	if absf(drift_usec) > 1_000_000:
		@warning_ignore("integer_division")
		G.warning(
			"Large timestamp drift detected: %d ms at frame %d" %
			[drift_usec / 1000, server_frame_index],
			ScaffolderLog.CATEGORY_NETWORK_SYNC,
		)

	# Sync frame time to wall-clock to maintain accurate timestamps for logging
	server_frame_time_usec = actual_server_time_usec

	@warning_ignore("integer_division")
	G.print(
		"Re-synced frame timestamp to wall-clock (drift: %d ms)" %
		[drift_usec / 1000],
		ScaffolderLog.CATEGORY_NETWORK_SYNC,
	)


# FIXME: REMOVE: Is this actually a potential problem?
func _log_frame_drift() -> void:
	# Calculate what frame we SHOULD be at based on server time
	var estimated_server_time := G.network.time.get_server_time_usec()
	var expected_frame := get_frame_index_from_time_usec(estimated_server_time)
	var frame_drift := server_frame_index - expected_frame

	@warning_ignore("integer_division")
	var time_drift_ms := frame_drift * TARGET_NETWORK_TIME_STEP_USEC / 1000

	G.print(
		"Frame drift: local=%d expected=%d diff=%d (%d ms)" % [
			server_frame_index,
			expected_frame,
			frame_drift,
			time_drift_ms,
		],
		ScaffolderLog.CATEGORY_NETWORK_SYNC,
	)


func add_networked_state(node: ReconcilableNetworkedState) -> void:
	G.ensure(not _networked_state_nodes.has(node))
	_networked_state_nodes.append(node)


func remove_networked_state(node: ReconcilableNetworkedState) -> void:
	var index := _networked_state_nodes.find(node)
	G.ensure(index >= 0)
	_networked_state_nodes.remove_at(index)


func add_network_frame_processor(node: NetworkFrameProcessor) -> void:
	G.ensure(not _network_frame_processor_nodes.has(node))
	_network_frame_processor_nodes.append(node)


func remove_network_frame_processor(node: NetworkFrameProcessor) -> void:
	var index := _network_frame_processor_nodes.find(node)
	G.ensure(index >= 0)
	_network_frame_processor_nodes.remove_at(index)


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
			("Requested rollback to frame %d, " +
			"but oldest rollbackable frame is %d") %
			[target_rollback_frame, oldest_rollbackable_frame_index],
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
	# Don't process frames on clients until they have received the server's
	# start time offset and can calculate valid frame indices.
	if not G.network.time.is_time_initialized:
		return

	_update_server_frame_time()

	if _queued_rollback_frame_index > 0:
		_rollback_and_reprocess()
		_queued_rollback_frame_index = 0

	_network_process()


func _rollback_and_reprocess() -> void:
	G.verbose(
		"Starting rollback from frame %d to frame %d" %
		[server_frame_index, _queued_rollback_frame_index],
		ScaffolderLog.CATEGORY_NETWORK_SYNC,
	)

	var rollback_start_time_usec := Time.get_ticks_usec()

	var original_server_frame_index := server_frame_index
	var original_server_frame_time_usec := server_frame_time_usec

	server_frame_index = _queued_rollback_frame_index
	server_frame_time_usec = floori(
		server_frame_index * TARGET_NETWORK_TIME_STEP_USEC +
		TARGET_NETWORK_TIME_STEP_USEC * 0.5,
	)

	# Re-simulate all frames between the mismatch and current frame (exclusive).
	# The loop processes frames [rollback_frame, original_frame), but not the
	# original frame itself. The current frame will be re-simulated afterward in
	# the normal _run_network_process flow.
	var frame_count := 0
	while server_frame_index < original_server_frame_index:
		_network_process()
		server_frame_time_usec += TARGET_NETWORK_TIME_STEP_USEC
		server_frame_index += 1
		frame_count += 1

	server_frame_index = original_server_frame_index
	server_frame_time_usec = original_server_frame_time_usec

	# Track rollback metrics
	last_rollback_frame_count = frame_count
	last_rollback_duration_usec = Time.get_ticks_usec() - rollback_start_time_usec
	total_rollbacks += 1


## Simulate the current frame for all network-process-aware nodes.
func _network_process() -> void:
	# Remove invalid nodes (iterate backwards to avoid issues when removing).
	for i in range(_networked_state_nodes.size() - 1, -1, -1):
		var node := _networked_state_nodes[i]
		# TODO: This should not be possible, so try to figure out the underlying
		#       problem.
		if not is_instance_valid(node):
			_networked_state_nodes.remove_at(i)

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
	var fastforward_start_time_usec := Time.get_ticks_usec()
	var frame_count := 0

	while server_frame_index < new_frame_index:
		server_frame_time_usec += TARGET_NETWORK_TIME_STEP_USEC
		server_frame_index += 1
		_network_process()
		frame_count += 1

	# Track fast-forward metrics
	last_fastforward_frame_count = frame_count
	last_fastforward_duration_usec = Time.get_ticks_usec() - fastforward_start_time_usec
	total_fastforwards += 1
