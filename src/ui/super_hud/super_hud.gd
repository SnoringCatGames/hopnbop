class_name SuperHud
extends PanelContainer

func _enter_tree() -> void:
    G.super_hud = self

    if G.network.is_server:
        visible = false
        process_mode = Node.PROCESS_MODE_DISABLED
        return


func _ready() -> void:
    G.log.log_system_ready("SuperHud")

    if G.network.is_server:
        return

    # Initialize visibility based on current settings
    _sync_component_visibility()


func _sync_component_visibility() -> void:
    # Sync all component visibility with current settings.
    %DebugConsole.visible = G.settings.show_debug_console
    %PlayerStateList.visible = G.settings.show_debug_player_state
    %PerfTracker.visible = G.settings.show_perf_tracker


func toggle_debug_console() -> void:
    if G.network.is_server:
        return

    %DebugConsole.visible = not %DebugConsole.visible
    G.print(
        "Toggled DebugConsole: %s"
        % ("visible" if %DebugConsole.visible else "hidden"),
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func toggle_player_state_list() -> void:
    if G.network.is_server:
        return

    %PlayerStateList.visible = not %PlayerStateList.visible
    G.print(
        "Toggled PlayerStateList: %s"
        % ("visible" if %PlayerStateList.visible else "hidden"),
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )


func toggle_perf_tracker() -> void:
    if G.network.is_server:
        return

    %PerfTracker.visible = not %PerfTracker.visible
    G.print(
        "Toggled PerfTracker: %s"
        % ("visible" if %PerfTracker.visible else "hidden"),
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
    )
