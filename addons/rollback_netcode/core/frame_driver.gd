class_name FrameDriver
extends Node
## Core frame-synchronous simulation engine for client-prediction rollback
## networking.
##
## FrameDriver is the heart of the networking system, managing deterministic
## frame-based simulation at a fixed FPS (independent of render framerate). It
## coordinates all networked entities through a three-phase processing cycle:
##
## 1. **_pre_network_process**: Restore state from rollback buffer for current
##    frame
## 2. **_network_process**: Execute game logic (movement, physics, input
##    handling)
## 3. **_post_network_process**: Pack and record new state to rollback buffer
##
## Key responsibilities:
## - Maintains server_frame_index as the primary synchronization primitive
## - Manages the rollback buffer
## - Detects state mismatches and triggers rollback reconciliation
## - Coordinates re-simulation of frames during rollback
## - Handles fast-forwarding when client falls behind server
## - Registers and manages all ReconcilableState and FrameProcessor nodes
##
## Networked entities must extend either ReconcilableState or FrameProcessor to
## participate in this frame-synchronous cycle.
## - ReconcilableState nodes support server-mismatch detection and rollback
## - FrameProcessor nodes simply process each frame without rollback support
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
## - queue_rollback() schedules rollback to a specific frame (conflict
##   detection).
## - _rollback_and_reprocess() restores state and re-simulates up to current
##   frame.
## - Only one rollback occurs per _network_process, earliest frame takes
##   priority.

# FIXME: LEFT OFF HERE: Main list: ---------------------------------------------

# I hit a crash.
# "Trying to assign value of type 'Nil' to a variable of type 'Array'."
# res://src/scaffolder/character/character_state_from_server.gd:1009
# res://src/scaffolder/character/character_state_from_server.gd:973
# ...

# - "Easter eggs"!
#   - Release by easter.
#   - Also, secrets in every level, and stuff you can actually collect and unlock...

# - Polish gore/flower sprites.
# - Polish gore amounts.
# - Test gore.

# - Sudden death.

# - Make score popup bigger, and to the right of to score.
# - Score popup, more tweens, position away, fade, embiggen more, rotate back and forth

# - Fix kills.

# - TEST that when a high-speed kill happens, the bounce happens from where the
#   initial collision contact should have been.
#   -!!!!!!!!!!!!!!! I think this still happens

# - Ask AI if it's expected for there to be so many predicted instead of
#   authoritative values. Shouldn't values in the past become authoritative as
#   those packets around from the server?

# Water:
# - Reverse gravity
# - Still use move and slide
# - But also force a min y
# - Define a float depth constant to define how far to sink into the surface
# - Have water tiles use full collision square shape
# - Detect intersection, and use the to trigger water float physics
# - Need to make a good splash effect animation!
# - Make a different splash animation for exiting the water
# - Allow jumping up from the water only when you're at the surface
# - Don't allow diving without jumping

# - Add notes to implement: water, spring, ice, flies, jetpack, and other cheats


# - Test kills and bumps.

# - Polish movement. It still seems like we get jitter and stuck
#   player-inputs-on-server-side too often.

# - Review /rollback_netcode/examples/.
# - Look at how some old Scaffolder utilities are used, like ScaffolderTime. Should we simplify and replace them with built-in logic that we _don't_ have the consumer app worry about?

# - Lingering FIXMEs.


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

# Check on how the GitHub Actions current daily actions setup is working.

# Make a new GitHub action for deploying releases.
# - First, I should start using a dev branch for normal work, and merge into main whenever it's release-ready.
# - It should takie master branch and deploy it to itch and aws gamelift
# - It should also deploy to Godot Asset library.
# - It should also create zip files for the build and record them in the repo.
# - AND can it bump my versions for me?? Can it accept a text box for version? Can I tell it all the spots to update the version? Then I could put versions back in the READMEs...

# - Have bunnies be flung in from off-screen from the left.
#   - Move the happen points over there, and give bunnies initial velocity.
#   - Remove some of the tiles near the top of the left wall for this. But make sure players can't jump that high.
#   - Disable player-player collision mask bit in the lobby.

# - Fix code style inconsistencies across the codebase.
#   - Use tabs, not spaces.
#   - When wrapping expressions across multiple lines, place operators at the start of the next line rather than the end of the previous.
#   - Wrap lines at 80 characters.
#   - Prefer using parens to wrap lines rather than backslashes.
#   - Use periods at the ends of comments.
#   - Prefer `not` instead of `!` (although, do use `!=` when appropriate).
#   - Follow the Godot style guide: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html
#   - Use multiple sub-agents to parallelize this work.

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
# - Add a screen shake for each kill?
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
#   - Add countdown tick sounds.
#     - Match-start: Arpeggio: Do mi so do!
#     - Match-end: Write a simple song, beat-aligned to seconds, 10 seconds long.
# - Make sleeping bunny animations for while the countdown is going.
#   - Make sure to override process_mode on PlayerAnimators, so they will move when paused.

# UI fixes:
# - Adjust scene files: lobby_level.tscn, player_list.tscn, player_display.tscn.
# - Lobby scene:
#   - Embed the game title logo within the level.
#   - Also embed some controls instruction.
#   - Also embed instructions to go down hole for starting match.
#   - Call MatchmakingClient.start_matchmaking() when any player jumps down a
#     rabbit hole on the right side of the level.
# - Hook-up / polish pause UI.
#   - Show a small panel in the center of the window with a lightly transparent screen.
# - Revise game-over UI.
#   - Also a panel overlay over the still-visible level area.
#   - Only show this game-over panel while in the lobby.
#   - Have this panel persist, and not take up too much space.
#   - Let players move while the panel is open.
#   - So, completely not a "screen" or part of the transition system at all
#     anymore.

# - Add alternate camera modes.
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

# Animated tiles
# - Research how to implement animated tiles.
# - Have Tile set point to a scene for each animated tile.
# - ALSO, plan a way to sync occlusion and background animated tiles, so rustling one will also trigger the other.
# - Probably implement this by subclassing the TileMap. Then have a property to indicate its partner TileMap, and assert it's set.
# - Then, need to figure out collisions for an offset area for these rustle tiles.
# - Then...

# ### TODO: After everything else:
# - Survey the codebase for where we use string literals. Should any of these be StringName literals instead?
# - Survey all RPCs. Decide whether we should introduce new RPC channels and assign them as appropriate. Reference them as consts on NetworkConnector.
# - Review tests.
# - Review these notes: https://docs.google.com/document/d/1qJcNUrE1y8UllVVCojp-IN3zCwml8VK7kjYhp1uJhV4
# - Review the example app.
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
# - Search for and replace/remove anthropic and claude.

# Record this somewhere. These are the places to update when bumping a new version.
# Version Management Locations
# 1. Rollback Netcode Plugin
# - project settings
# - addons/rollback_netcode/core/network_Netcode.gd:50 - const VERSION := "1.0.0" (single source of truth)
# - addons/rollback_netcode/plugin.cfg:6 - version="1.0.0" (Asset Library metadata)
# - addons/rollback_netcode/examples/simple_game/project.godot - Example project
# 2. GameLift Session Manager Plugin
# - project settings
# - backend/template.yaml
# - addons/gamelift_session_manager/plugin.cfg:6 - version="1.0.0"
# 3. GameLift GDExtension
# - No real version used.
# - gamelift-gdextension/README.md - Build version references (lines 325-329)
# 4. Jump 'n Thump Game
# project.godot:14 - config/version="0.1.0" (main game version)

# ### Devlog post:
# - AI helped a lot
# - AI sucked at:
#   - Fixing the GitHub Actions CI workflows.
#     - Probably ~60 iterations.
#

## Emitted when pause state changes (for UI updates).
signal pause_state_changed(is_paused: bool, initiator_peer_id: int)

## Emitted when a pause is requested (for validation/accounting).
signal pause_requested(peer_id: int)

## Emitted when an unpause is requested.
signal unpause_requested(peer_id: int)

## Emitted when match start countdown begins (for game-specific UI).
## countdown_end_frame is the frame index when countdown ends.
signal match_start_countdown_started(countdown_end_frame: int)

## Emitted when match start countdown ends and gameplay begins.
signal match_start_countdown_ended

## This determines the period we use between frames that we record in rollback
## buffers.
##
## Network state will presumably be slower than this in practice. When that
## occurs, we fill-in empty frames by extrapolating from the most-recent filled
## frame.

# Network tick rate properties derived from Netcode.settings.
var target_network_fps: float:
	get:
		return Netcode.settings.target_network_fps if Netcode.settings else 60.0

var target_network_time_step_sec: float:
	get:
		return 1.0 / target_network_fps

var target_network_time_step_usec: int:
	get:
		return floori(1_000_000 / target_network_fps)

## Current frame index. Incremented directly on each physics tick in
## _pre_physics_process(). Drives all frame-synchronous simulation and rollback.
## This is the single source of truth for frame progression and network
## synchronization.
var server_frame_index := 0

## Tracks whether frame tracking has been initialized. Initialization is
## deferred until the first physics tick, preventing fast-forward at startup.
var _is_frame_tracking_initialized := false

## Timestamp when server_frame_index was last manually reset (for new matches).
## Used to suppress frame sync warnings during the expected synchronization period.
var _frame_reset_time_usec := 0

## Grace period in seconds after frame reset to suppress sync warnings.
const FRAME_SYNC_GRACE_PERIOD_SEC := 3.0

## Returns true if we're within the grace period after a frame reset.
## During this time, frame sync warnings are suppressed as they're expected.
var is_in_sync_grace_period: bool:
	get:
		if _frame_reset_time_usec == 0:
			return false
		var elapsed_usec := Time.get_ticks_usec() - _frame_reset_time_usec
		return elapsed_usec < (FRAME_SYNC_GRACE_PERIOD_SEC * 1_000_000)

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

## Optional validator for pause requests (server-only). When set, called
## with (peer_id: int) before executing a client-initiated pause. Must
## return Dictionary with:
## - "allowed": bool (false to reject the pause request)
## - "pauses_used": int (cumulative pause count for the initiator)
var server_pause_validator: Callable = Callable()

## Tracks last pause request time for rate limiting (microseconds).
var _last_pause_request_time_usec := 0

## Peer ID of the client that initiated the current pause.
var _pause_initiator_peer_id: int = 0

## Number of pauses used by the initiator at the time of pause.
var _pause_initiator_pauses_used: int = 0

## Time when the current pause will automatically unpause (microseconds).
## This is replicated to clients for countdown display.
var _pause_auto_unpause_time_usec: int = 0

## SceneTreeTimer for auto-unpause (server-only).
var _pause_auto_unpause_timer: SceneTreeTimer = null

## Frame index when match start countdown ends. States before this frame are
## discarded. Set automatically when match starts.
var match_start_countdown_end_frame_index := -1

## Tracks if the initial match start countdown has been triggered.
## Used to distinguish first unpause (match start) from subsequent unpauses.
var _has_match_start_countdown_started := false

## Tracks if the initial match start countdown has completed.
var _has_match_start_countdown_ended := false

## Returns true if match start countdown is currently active.
var is_match_start_countdown_active: bool:
	get:
		return (
			match_start_countdown_end_frame_index >= 0 and
			server_frame_index < match_start_countdown_end_frame_index
		)

## Interval for periodic wall-clock re-sync to maintain accurate timestamps for
## logging. Re-sync is handled automatically via SceneTree timers.
const WALL_CLOCK_RESYNC_INTERVAL_SEC := 30.0

var _networked_state_nodes: Array[ReconcilableState] = []

var _frame_processor_nodes: Array[FrameProcessor] = []

var _queued_rollback_frame_index := 0
var _queued_rollback_cause: String = ""

## True during rollback re-simulation. Used to suppress re-sending
## of client input that was already transmitted during forward sim.
var is_resimulating := false

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
		return ceili(Netcode.settings.rollback_buffer_duration_sec *
			target_network_fps)

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
	Netcode.log.print("FrameDriver ready", NetworkLogger.CATEGORY_SYSTEM_INITIALIZATION)

	if not Engine.is_editor_hint():
		# Connect to ProcessSentinel for deterministic frame ordering.
		# ProcessSentinel places helper nodes at scene tree root with extreme
		# priority values to ensure this runs before all other physics processing.
		Netcode.process_sentinel.pre_physics_process.connect(_pre_physics_process)

		# Start paused - server will unpause when ready (e.g., after all players
		# connect).
		if is_inside_tree():
			get_tree().paused = true

		# In preview mode (local multi-instance testing), track client
		# connections and unpause when all expected clients have connected.
		if Netcode.is_preview and Netcode.is_server:
			multiplayer.peer_connected.connect(_on_preview_peer_connected)
			# Check if clients are already connected.
			_check_preview_clients_connected()


func client_reset() -> void:
	# Reset frame index for new match to sync with server's reset.
	server_frame_index = 0
	# Start grace period to suppress expected frame sync warnings.
	_frame_reset_time_usec = Time.get_ticks_usec()
	# Start paused so client waits for server's unpause signal
	# before transitioning from LOADING to GAME screen.
	_is_paused = true
	# Reset match start countdown state from previous match.
	match_start_countdown_end_frame_index = -1
	_has_match_start_countdown_started = false
	_has_match_start_countdown_ended = false


## Handles peer connections in preview mode to auto-unpause when ready.
func _on_preview_peer_connected(_peer_id: int) -> void:
	_check_preview_clients_connected()


## Checks if all expected clients are connected in preview mode.
func _check_preview_clients_connected() -> void:
	if not Netcode.is_preview or not Netcode.is_server:
		return

	var connected_count := multiplayer.get_peers().size()
	var expected_count := Netcode.settings.preview_client_count

	Netcode.log.print(
		"Preview mode: %d/%d clients connected" % [connected_count, expected_count],
		NetworkLogger.CATEGORY_NETWORK_SYNC
	)

	if connected_count >= expected_count:
		Netcode.log.print(
			"All expected clients connected; Unpausing game",
			NetworkLogger.CATEGORY_NETWORK_SYNC
		)
		# Disconnect signal to avoid re-checking.
		if multiplayer.peer_connected.is_connected(_on_preview_peer_connected):
			multiplayer.peer_connected.disconnect(_on_preview_peer_connected)
		server_set_is_paused(false)


## Re-enable preview mode auto-unpause for a new match.
##
## Call this when starting a new match in preview mode to reconnect the
## peer_connected signal and re-enable auto-unpause logic.
func server_reset_preview_mode_unpause() -> void:
	if not Netcode.is_preview or not Netcode.is_server:
		return

	Netcode.log.print(
		"Resetting preview mode auto-unpause for new match",
		NetworkLogger.CATEGORY_NETWORK_SYNC
	)

	# Reconnect the signal if not already connected.
	if not multiplayer.peer_connected.is_connected(_on_preview_peer_connected):
		multiplayer.peer_connected.connect(_on_preview_peer_connected)

	# Check if clients are already connected.
	_check_preview_clients_connected()


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
	if is_paused:
		client_request_unpause()
	else:
		client_request_pause()


## Request pause from client. Only works if Netcode.settings.is_server_pause_enabled.
func client_request_pause() -> void:
	Netcode.check_is_client()
	_server_rpc_client_request_pause.rpc_id(NetworkConnector.SERVER_ID)


## Request unpause from client. Only works if Netcode.settings.is_server_pause_enabled.
func client_request_unpause() -> void:
	Netcode.check_is_client()
	_server_rpc_request_unpause.rpc_id(NetworkConnector.SERVER_ID)

## Client requests server to pause.


@rpc("any_peer", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _server_rpc_client_request_pause() -> void:
	Netcode.check_is_server()

	var peer_id := multiplayer.get_remote_sender_id()

	if not Netcode.settings.is_server_pause_enabled:
		Netcode.log.print(
			"Client %d requested pause, but server pause is disabled" % peer_id,
						NetworkLogger.CATEGORY_NETWORK_SYNC
		)
		return

	# Block pause requests during match start countdown.
	if is_match_start_countdown_active:
		Netcode.log.print(
			"Client %d requested pause during match start countdown - rejected" % peer_id,
			NetworkLogger.CATEGORY_NETWORK_SYNC
		)
		return

	# Rate limit pause requests.
	var current_time := Time.get_ticks_usec()
	var cooldown_usec := int(Netcode.settings.pause_request_cooldown_sec * 1_000_000)
	if current_time - _last_pause_request_time_usec < cooldown_usec:
		return

	# Validate with game-level logic (pause limits, match state, etc.).
	var pauses_used := 0
	if server_pause_validator.is_valid():
		var result: Dictionary = server_pause_validator.call(peer_id)
		if not result.get("allowed", true):
			Netcode.log.print(
				"Client %d pause rejected by game validator" %
				peer_id,
				NetworkLogger.CATEGORY_NETWORK_SYNC
			)
			return
		pauses_used = result.get("pauses_used", 0)

	pause_requested.emit(peer_id)

	_last_pause_request_time_usec = current_time
	_server_execute_pause(peer_id, pauses_used)


## Client requests server to unpause.
@rpc("any_peer", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _server_rpc_request_unpause() -> void:
	Netcode.check_is_server()

	var peer_id := multiplayer.get_remote_sender_id()

	if not Netcode.settings.is_server_pause_enabled:
		Netcode.log.print(
			"Client %d requested unpause, but server pause is disabled" % peer_id,
			NetworkLogger.CATEGORY_NETWORK_SYNC
		)
		return

	# Check if requesting peer is the pause initiator.
	if peer_id != _pause_initiator_peer_id:
		Netcode.log.print(
			"Client %d requested unpause, but only initiator (peer %d) can unpause" % [
				peer_id,
				_pause_initiator_peer_id,
			],
			NetworkLogger.CATEGORY_NETWORK_SYNC
		)
		return

	# Rate limit pause requests.
	var current_time := Time.get_ticks_usec()
	var cooldown_usec := int(Netcode.settings.pause_request_cooldown_sec * 1_000_000)
	if current_time - _last_pause_request_time_usec < cooldown_usec:
		return

	_last_pause_request_time_usec = current_time

	# Emit signal for game to handle
	unpause_requested.emit(peer_id)

	_server_execute_unpause()

## Server notifies all clients of pause.


@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _client_rpc_notify_pause(
	server_pause_frame: int,
	pause_initiator_peer_id: int,
	pause_initiator_pauses_used: int,
) -> void:
	Netcode.check_is_client()

	_client_execute_pause_at_server_frame(
		server_pause_frame,
		pause_initiator_peer_id,
		pause_initiator_pauses_used,
	)

## Server notifies all clients of unpause.


@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _client_rpc_notify_unpause(
		server_unpause_frame: int,
		server_cumulative_paused_frames: int,
) -> void:
	Netcode.check_is_client()

	_client_execute_unpause_at_server_frame(
		server_unpause_frame,
		server_cumulative_paused_frames,
	)


## Server notifies clients to start match start countdown.
## Clients pause locally and unpause when countdown ends.
@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _client_rpc_start_match_start_countdown(countdown_frames: int) -> void:
	Netcode.check_is_client()

	match_start_countdown_end_frame_index = countdown_frames
	_has_match_start_countdown_started = true
	_is_paused = false

	Netcode.log.print(
		"Starting match start countdown (%d frames)" % countdown_frames,
		NetworkLogger.CATEGORY_GAME_STATE
	)

	# Emit pause_state_changed to trigger screen transition (LOADING -> GAME).
	# This must happen before pausing tree so UI transitions work.
	pause_state_changed.emit(false, 0)

	# Pause client tree during match start countdown (characters won't move).
	# Will be unpaused when countdown ends in _pre_physics_process.
	if is_inside_tree():
		get_tree().paused = true

	# Emit signal for game-specific UI (e.g., show match start countdown display).
	match_start_countdown_started.emit(countdown_frames)


## Server notifies all clients of impending graceful shutdown.
## Called before disconnecting clients during Spot instance termination.
@rpc("authority", "call_remote", "reliable", NetworkConnector.RPC_CHANNEL_PAUSE)
func _client_rpc_notify_shutdown(shutdown_message: String) -> void:
	Netcode.check_is_client()

	Netcode.log.print(
		"Server shutdown notification: %s" % shutdown_message,
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Store reason in connector for disconnect handling.
	Netcode.connector.last_disconnect_reason = NetworkConnector.DisconnectReason.SERVER_SHUTDOWN


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
		int(Netcode.settings.max_pause_duration_sec * 1_000_000)
	)

	# Schedule auto-unpause using timer system (server-only).
	if Netcode.is_server:
		_pause_auto_unpause_timer = get_tree().create_timer(Netcode.settings.max_pause_duration_sec)
		_pause_auto_unpause_timer.timeout.connect(func():
			Netcode.log.print("Auto-unpausing after timeout", NetworkLogger.CATEGORY_NETWORK_SYNC)
			_server_execute_unpause()
		)

	# Clean up buffer frames after pause started.
	_cleanup_buffer_after_pause()

	# Clear queued rollback - it's based on invalid post-pause state.
	_queued_rollback_frame_index = 0
	_queued_rollback_cause = ""

	# Notify clients (if server and in tree for RPC).
	if Netcode.is_server and is_inside_tree():
		_client_rpc_notify_pause.rpc(
			server_frame_index,
			_pause_initiator_peer_id,
			_pause_initiator_pauses_used,
		)

	# Pause Godot scene tree.
	if is_inside_tree():
		get_tree().paused = true

	# Emit signal for UI updates
	pause_state_changed.emit(true, initiator_peer_id)

	Netcode.log.print(
		"Server paused at frame %d by peer %d" % [server_frame_index, initiator_peer_id],
		NetworkLogger.CATEGORY_NETWORK_SYNC
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

	# Unpause the scene tree (paused in _ready).
	if is_inside_tree():
		get_tree().paused = false

	# Cancel auto-unpause timeout (server-only).
	# SceneTreeTimer cannot be canceled once started, so we just clear the
	# reference.
	if Netcode.is_server and _pause_auto_unpause_timer != null:
		_pause_auto_unpause_timer = null

	# Reset pause state variables.
	_pause_initiator_peer_id = 0
	_pause_initiator_pauses_used = 0
	_pause_auto_unpause_time_usec = 0

	# Check if this is the initial match start and countdown is enabled.
	var is_starting_match_start_countdown := (
		Netcode.is_server and
		not _has_match_start_countdown_started and
		Netcode.settings.match_start_countdown_sec > 0
	)

	if is_starting_match_start_countdown:
		_has_match_start_countdown_started = true

		# Calculate match start countdown end frame.
		var countdown_frames := int(
			Netcode.settings.match_start_countdown_sec * target_network_fps
		)
		match_start_countdown_end_frame_index = countdown_frames

		Netcode.log.print(
			"Starting match start countdown (%d frames)" % countdown_frames,
			NetworkLogger.CATEGORY_GAME_STATE
		)

		# Notify clients to start match start countdown (they pause locally).
		if is_inside_tree():
			_client_rpc_start_match_start_countdown.rpc(countdown_frames)

		# Emit signal for game-specific UI.
		match_start_countdown_started.emit(countdown_frames)
	else:
		# Normal unpause - notify clients.
		if Netcode.is_server and is_inside_tree():
			_client_rpc_notify_unpause.rpc(
				server_frame_index,
				_cumulative_paused_frames,
			)

	# Unpause Godot scene tree.
	if is_inside_tree():
		get_tree().paused = false

	# Emit signal for UI updates
	pause_state_changed.emit(false, 0)

	Netcode.log.print(
		"Server unpaused at frame %d (paused for %d frames, cumulative: %d)" %
		[server_frame_index, pause_duration_frames, _cumulative_paused_frames],
		NetworkLogger.CATEGORY_NETWORK_SYNC
	)


## Execute pause on client at server-specified frame (client-side).
func _client_execute_pause_at_server_frame(
		server_pause_frame: int,
		pause_initiator_peer_id: int,
		pause_initiator_pauses_used: int,
) -> void:
	if _is_paused:
		return

	_is_paused = true
	_pause_initiator_peer_id = pause_initiator_peer_id
	_pause_initiator_pauses_used = pause_initiator_pauses_used

	# Calculate auto-unpause time for countdown display.
	_pause_auto_unpause_time_usec = (
		Time.get_ticks_usec() +
		int(Netcode.settings.max_pause_duration_sec * 1_000_000)
	)

	# Align with server's pause frame.
	server_frame_index = server_pause_frame
	_pause_start_frame_index = server_pause_frame

	# Clean up buffer frames after pause started.
	_cleanup_buffer_after_pause()

	# Clear queued rollback.
	_queued_rollback_frame_index = 0
	_queued_rollback_cause = ""

	# Pause Godot scene tree.
	if is_inside_tree():
		get_tree().paused = true

	# Emit signal for game to handle screen transitions
	pause_state_changed.emit(true, pause_initiator_peer_id)

	Netcode.log.print(
		"Client synchronized pause at frame %d" % server_frame_index,
		NetworkLogger.CATEGORY_NETWORK_SYNC
	)


## Execute unpause on client at server-specified frame (client-side).
func _client_execute_unpause_at_server_frame(
		server_unpause_frame: int,
		server_cumulative_paused_frames: int,
) -> void:
	if not _is_paused:
		return

	# Adopt server's pause accounting.
	_cumulative_paused_frames = server_cumulative_paused_frames

	var previous_frame := server_frame_index

	# Align frame index with server.
	server_frame_index = server_unpause_frame

	_is_paused = false
	_pause_start_frame_index = 0

	# Reset pause state variables.
	_pause_initiator_peer_id = 0
	_pause_initiator_pauses_used = 0
	_pause_auto_unpause_time_usec = 0

	# Unpause Godot scene tree.
	if is_inside_tree():
		get_tree().paused = false

	# Emit signal for game to handle screen transitions
	pause_state_changed.emit(false, 0)

	Netcode.log.print(
		"Client synchronized unpause: frame %d->%d (paused: %d, init=%s)" % [
			previous_frame,
			server_frame_index,
			_cumulative_paused_frames,
			_is_frame_tracking_initialized,
		],
		NetworkLogger.CATEGORY_NETWORK_SYNC
	)


## Clean up rollback buffer state after pause.
func _cleanup_buffer_after_pause() -> void:
	for node in _networked_state_nodes:
		if is_instance_valid(node):
			node._cleanup_buffer_after_pause(_pause_start_frame_index)


## Reinitialize rollback buffers after a hard frame reset.
##
## When the frame index jumps backward (e.g., from 1439 to 1429), the buffers
## contain stale predicted data at the new frame indices. This method
## reinitializes buffers to default values at the new frame, preventing stale
## data from corrupting the simulation.
func reinitialize_buffers_for_hard_reset(new_frame_index: int) -> void:
	for node in _networked_state_nodes:
		if is_instance_valid(node):
			node._reinitialize_buffer_for_hard_reset(new_frame_index)


func _pre_physics_process(_delta: float) -> void:
	# Slow frame simulation: artificially delay physics ticks to
	# simulate a machine struggling to keep up.
	if (
		Netcode.condition_simulator != null
		and Netcode.condition_simulator.is_enabled
		and Netcode.condition_simulator.get_frame_delay_ms() > 0
	):
		OS.delay_msec(
			Netcode.condition_simulator.get_frame_delay_ms()
		)

	if _is_paused:
		# Still advance frame index in local mode so frame-based
		# logic (boost cooldown, coyote time, jump throttle) works
		# correctly even though networking is paused.
		if not G.is_networked_level_active:
			if not _is_frame_tracking_initialized:
				_initialize_frame_tracking()
			else:
				server_frame_index += 1
		return

	if not _is_frame_tracking_initialized:
		_initialize_frame_tracking()
		return

	# Increment frame index directly on each physics tick.
	server_frame_index += 1

	# During match start countdown, process only buffer synchronization without game logic.
	# This keeps rollback buffers in sync while preventing character movement.
	# Clients stay paused; animations still run (PROCESS_MODE_ALWAYS).
	if is_match_start_countdown_active:
		_run_network_process(true)
		return

	# Handle match start countdown end: log, unpause client tree, emit signal.
	if match_start_countdown_end_frame_index >= 0 and not _has_match_start_countdown_ended:
		Netcode.log.print(
			"Match start countdown ended at frame %d, match starting" % server_frame_index,
			NetworkLogger.CATEGORY_GAME_STATE
		)
		_has_match_start_countdown_ended = true

		# Unpause client tree (was paused when match start countdown started).
		if Netcode.is_client and is_inside_tree():
			get_tree().paused = false

		match_start_countdown_ended.emit()

	_run_network_process()


func _initialize_frame_tracking() -> void:
	# Frame tracking can start immediately since we use frame-based sync.
	_is_frame_tracking_initialized = true

	# Initialize to frame 0
	# The first physics tick will increment this to 1
	var previous_frame_index := server_frame_index
	server_frame_index = 0

	# Note: Clients track their own frame indices locally starting from 0.
	# Periodic frame index broadcasts from the server prevent drift.
	Netcode.log.print(
		"Frame tracking initialized at frame 0 (was %d)" % previous_frame_index,
		NetworkLogger.CATEGORY_NETWORK_SYNC
	)


## Registers a ReconcilableState node for frame-synchronous processing.
func add_networked_state(node: ReconcilableState) -> void:
	Netcode.log.ensure(not _networked_state_nodes.has(node), "Node already registered")
	_networked_state_nodes.append(node)


func remove_networked_state(node: ReconcilableState) -> void:
	var index := _networked_state_nodes.find(node)
	Netcode.log.ensure(index >= 0, "Node not found in registered nodes")
	_networked_state_nodes.remove_at(index)


func add_frame_processor(node: FrameProcessor) -> void:
	Netcode.log.ensure(not _frame_processor_nodes.has(node), "Node already registered")
	_frame_processor_nodes.append(node)


func remove_frame_processor(node: FrameProcessor) -> void:
	var index := _frame_processor_nodes.find(node)
	Netcode.log.ensure(index >= 0, "Node not found in registered nodes")
	_frame_processor_nodes.remove_at(index)


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
func queue_rollback(
	p_conflicting_frame_index: int,
	p_cause: String = "",
) -> bool:
	var target_rollback_frame := p_conflicting_frame_index + 1
	if is_frame_too_old_to_consider(p_conflicting_frame_index):
		Netcode.log.warning(
			("Rollback rejected: frame %d is too old " +
			"(oldest rollbackable: %d)") %
			[target_rollback_frame, oldest_rollbackable_frame_index],
			NetworkLogger.CATEGORY_NETWORK_SYNC
		)
		return false

	# Rollback simulation would start on the next frame after the mismatch.
	if _queued_rollback_frame_index == 0:
		_queued_rollback_frame_index = target_rollback_frame
		_queued_rollback_cause = p_cause
	else:
		if target_rollback_frame < _queued_rollback_frame_index:
			_queued_rollback_cause = p_cause
		_queued_rollback_frame_index = mini(
			_queued_rollback_frame_index,
			target_rollback_frame,
		)

	return true


## For most nodes in the scene, _network_process should happen before
## _physics_process.
func _run_network_process(only_buffers := false) -> void:
	if _queued_rollback_frame_index > 0:
		_rollback_and_reprocess()
		_queued_rollback_frame_index = 0
		_queued_rollback_cause = ""

	if only_buffers:
		_network_process_buffers_only()
	else:
		_network_process()


func _rollback_and_reprocess() -> void:
	var cause_str := (
		" cause=%s" % _queued_rollback_cause
		if _queued_rollback_cause != ""
		else ""
	)
	if Netcode.log.is_verbose:
		Netcode.log.verbose(
			"Starting rollback from frame %d to frame %d%s" %
			[server_frame_index,
			_queued_rollback_frame_index, cause_str],
			NetworkLogger.CATEGORY_NETWORK_SYNC
		)

	var rollback_start_time_usec := Time.get_ticks_usec()

	var original_server_frame_index := server_frame_index

	server_frame_index = _queued_rollback_frame_index

	# Re-simulate all frames between the mismatch and current frame (exclusive).
	# The loop processes frames [rollback_frame, original_frame), but not the
	# original frame itself. The current frame will be re-simulated afterward in
	# the normal _run_network_process flow.
	is_resimulating = true
	var frame_count := 0
	while server_frame_index < original_server_frame_index:
		_network_process()
		server_frame_index += 1
		frame_count += 1
	is_resimulating = false

	server_frame_index = original_server_frame_index

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
	for node in _frame_processor_nodes:
		node._network_process()

	# Sync the current network state from other scene state.
	for node in _networked_state_nodes:
		node._post_network_process()


## Process only buffer synchronization without game logic (for match start countdown).
## This keeps rollback buffers in sync between server and clients during match start countdown
## without actually simulating game logic.
func _network_process_buffers_only() -> void:
	# Remove invalid nodes (iterate backwards to avoid issues when removing).
	for i in range(_networked_state_nodes.size() - 1, -1, -1):
		var node := _networked_state_nodes[i]
		if not is_instance_valid(node):
			_networked_state_nodes.remove_at(i)

	# Sync state from buffers to scene (but game logic won't run, so positions don't change).
	for node in _networked_state_nodes:
		node._pre_network_process()

	# SKIP _network_process() - no game logic during match start countdown.

	# Sync state back to buffers and send to network.
	for node in _networked_state_nodes:
		node._post_network_process()


func fast_forward(new_frame_index: int) -> void:
	var fastforward_start_time_usec := Time.get_ticks_usec()
	var frame_count := 0

	while server_frame_index < new_frame_index:
		server_frame_index += 1
		_network_process()
		frame_count += 1

	# Track fast-forward metrics
	last_fastforward_frame_count = frame_count
	last_fastforward_duration_usec = Time.get_ticks_usec() - fastforward_start_time_usec
	total_fastforwards += 1


## Backfill all rollback buffers after match start countdown ends.
## During match start countdown, network processing was skipped, so buffers weren't updated.
## This fills frames from spawn to current frame with the last known state.
func _backfill_all_buffers_after_match_start_countdown() -> void:
	for node in _networked_state_nodes:
		node.backfill_buffer_to_current_frame()
