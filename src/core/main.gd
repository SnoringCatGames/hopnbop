class_name Main
extends Node2D


@export var settings: Settings


func _enter_tree() -> void:
    G.main = self
    G.settings = settings
    G.log.set_log_filtering(
        G.settings.excluded_log_categories,
        G.settings.force_include_log_warnings)

    randomize()

    get_tree().paused = true

    Scaffolder.set_up()


func _ready() -> void:
    G.log.print("Main._ready", ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION)

    await get_tree().process_frame

    # TODO: Open first screen/level based on manifest settings.

    if G.settings.full_screen and not G.network.is_server:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

    start_app()


func start_app() -> void:
    if G.network.is_server:
        get_tree().paused = false
        G.game_panel.server_start_game()
    else:
        var screen_type := ScreensMain.ScreenType.LOADING if G.settings.start_in_game else ScreensMain.ScreenType.MAIN_MENU
        G.screens.open_screen(screen_type)


func _notification(notification_type: int) -> void:
    match notification_type:
        NOTIFICATION_WM_GO_BACK_REQUEST:
            # Handle the Android back button to navigate within the app instead of
            # quitting the app.
            if false:
                close_app()
            else:
                # TODO: Close the current screen/context.
                pass
        NOTIFICATION_WM_CLOSE_REQUEST:
            close_app()
        NOTIFICATION_WM_WINDOW_FOCUS_OUT:
            if G.settings.pauses_on_focus_out:
                pause()
        _:
            pass


func _unhandled_input(event: InputEvent) -> void:
    if G.settings.dev_mode:
        if event is InputEventKey:
            match event.physical_keycode:
                KEY_P:
                    if G.settings.is_screenshot_hotkey_enabled:
                        G.utils.take_screenshot()
                KEY_O:
                    if is_instance_valid(G.hud):
                        G.hud.visible = not G.hud.visible
                        G.log.print(
                            "Toggled HUD visibility: %s" %
                            ("visible" if G.hud.visible else "hidden"),
                            ScaffolderLog.CATEGORY_CORE_SYSTEMS)
                KEY_ESCAPE:
                    if G.settings.pauses_on_focus_out:
                        pause()
                _:
                    pass


func pause() -> void:
    if G.network.is_client:
        if G.screens.current_screen == ScreensMain.ScreenType.GAME:
            G.screens.open_screen(ScreensMain.ScreenType.PAUSE)
    else:
        # TODO: Add optional networked support for pausing a game?
        pass


func close_app() -> void:
    if G.utils.were_screenshots_taken:
        G.utils.open_screenshot_folder()
    G.log.print("Shell.close_app", ScaffolderLog.CATEGORY_CORE_SYSTEMS)
    get_tree().call_deferred("quit")
