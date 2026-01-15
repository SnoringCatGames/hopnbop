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
    G.log.log_system_ready("Main")

    await get_tree().process_frame

    if G.network.preview_client_number > 1 and not G.settings.run_multiple_clients:
        G.print("Main._ready: Closing extra client process (--client=%s), because G.settings.run_multiple_clients is false." % G.network.preview_client_number)
        close_app()

    if G.settings.full_screen and not G.network.is_server:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

    _start_app()


func _start_app() -> void:
    if G.network.is_server:
        get_tree().paused = false
        G.game_panel.server_start_game()
    else:
        if G.settings.start_in_game:
            G.game_panel.client_load_game()
        else:
            G.screens.client_open_screen(ScreensMain.ScreenType.MAIN_MENU)


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
                _client_local_pause()
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
                        G.print(
                            "Toggled HUD visibility: %s" %
                            ("visible" if G.hud.visible else "hidden"),
                            ScaffolderLog.CATEGORY_CORE_SYSTEMS)
                KEY_ESCAPE:
                    if G.settings.pauses_on_focus_out:
                        _client_local_pause()
                _:
                    pass


func _client_local_pause() -> void:
    if G.network.is_server:
        return

    if G.screens.current_screen == ScreensMain.ScreenType.GAME:
        G.screens.client_open_screen(ScreensMain.ScreenType.PAUSE)


func close_app() -> void:
    if G.utils.were_screenshots_taken:
        G.utils.open_screenshot_folder()
    G.print("Main.close_app", ScaffolderLog.CATEGORY_CORE_SYSTEMS)
    get_tree().call_deferred("quit")
