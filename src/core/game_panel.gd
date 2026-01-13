class_name GamePanel
extends Node2D


# FIXME: LEFT OFF HERE: Debug game connections. -------------------------------
# - Commit message: Continue implementing network connections.
# - Make sure both clients can connect to the server and are spawned in the level.
# - Replace obsolete broken Player networked state with the start of the new thing.


# FIXME: [Rollback]: Buffer-state debug UI and rollback implementation:
#
# ### PART 1: Implement buffer-state history tracking
# - TODO: See notes doc.
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


var levels: Array[Level] = []

var match_state: MatchState:
    get: return %MatchStateSynchronizer.state
var match_state_synchronizer: MatchStateSynchronizer:
    get: return %MatchStateSynchronizer


func _enter_tree() -> void:
    G.game_panel = self
    G.local_session = LocalSession.new()


func _ready() -> void:
    G.log.log_system_ready("GamePanel")

    G.match_state = match_state

    for level_scene in G.settings.level_scenes:
        %LevelSpawner.add_spawnable_scene(level_scene.resource_path)

    if G.network.is_client:
        if G.network.is_connected_to_server:
            _client_on_server_connected()
        multiplayer.connected_to_server.connect(_client_on_server_connected)
        multiplayer.server_disconnected.connect(_client_on_server_disconnected)


func _client_on_server_connected() -> void:
    G.check_is_client("NetworkingMain._client_on_server_connected")
    G.check(G.local_session.is_game_loading,
        "GamePanel._client_on_server_connected: Game load is not expected")
    G.check(not G.local_session.is_game_active,
        "GamePanel._client_on_server_connected: Game is already active")

    G.local_session.is_game_loading = false
    G.local_session.is_game_active = true

    G.screens.client_open_screen(ScreensMain.ScreenType.GAME)


func _client_on_server_disconnected() -> void:
    G.check_is_client("NetworkingMain._client_on_server_disconnected")

    client_exit_game()


func client_load_game() -> void:
    G.check_is_client("NetworkingMain.client_load_game")
    G.check(not G.local_session.is_game_active,
        "GamePanel.client_load_game: Game is already active")
    G.check(not G.local_session.is_game_loading,
        "GamePanel.client_load_game: Game is already loading")
    G.check(not is_instance_valid(G.level),
        "GamePanel.client_load_game: Level is already set")

    G.local_session.clear()
    G.local_session.is_game_active = false
    G.local_session.is_game_loading = true

    G.screens.client_open_screen(ScreensMain.ScreenType.LOADING)

    G.network.client_connect_to_server()


func client_exit_game() -> void:
    G.check_is_client("NetworkingMain.client_exit_game")

    G.local_session.is_game_active = false
    G.local_session.is_game_loading = false

    G.network.client_disconnect()
    G.local_session.copy_match_state()
    G.local_session.clear()
    G.screens.client_open_screen(ScreensMain.ScreenType.GAME_OVER)
    for level in levels:
        levels.erase(level)
        level.queue_free()
    G.level = null


func server_start_game() -> void:
    G.check_is_server("NetworkingMain.server_start_game")
    G.check(not G.local_session.is_game_active,
        "GamePanel.server_start_game: Game is already active")
    G.check(not is_instance_valid(G.level),
        "GamePanel.server_start_game: Level is already set")

    G.local_session.is_game_active = true

    # TODO: Add in-game support for specifying which level to spawn on the server.

    _server_spawn_level(G.settings.default_level_scene)

    G.network.server_enable_connections()


func server_end_game() -> void:
    G.check_is_server("NetworkingMain.server_end_game")
    G.check(G.local_session.is_game_active,
        "GamePanel.server_end_game: Game is not active")
    G.check(is_instance_valid(G.level),
        "GamePanel.server_end_game: Level is not valid")

    G.local_session.is_game_active = false

    G.network.server_close_multiplayer_session()

    # TODO: Add support for tracking game stats in a separate backend database.

    _server_destroy_level(G.level)


func on_return_from_screen() -> void:
    G.check(G.local_session.is_game_active,
        "GamePanel.on_return_from_screen: Game is not active")
    G.check(not G.local_session.is_game_loading,
        "GamePanel.on_return_from_screen: Game is still loading")


func on_left_to_screen() -> void:
    pass


func _server_spawn_level(level_scene: PackedScene) -> void:
    G.check_is_server("NetworkingMain._server_spawn_level")
    G.check(G.settings.level_scenes.has(level_scene),
        "GamePanel._server_spawn_level: level_scene not registered in settings: %s" %
            level_scene)

    var level: Level = level_scene.instantiate()
    levels.push_back(level)
    %Levels.add_child(level)
    G.level = level


func _server_destroy_level(level: Level) -> void:
    G.check_is_server("NetworkingMain._server_destroy_level")
    G.check(levels.has(level),
        "GamePanel._server_destroy_level: level not in current list: %s" %
            level)

    if G.level == level:
        G.level = null
    levels.erase(level)
    level.queue_free()


func on_level_added(level: Level) -> void:
    if G.network.is_client:
        G.level = level
        levels.push_back(level)


func on_level_removed(level: Level) -> void:
    if G.network.is_client:
        if G.level == level:
            G.level = null
        levels.erase(level)
