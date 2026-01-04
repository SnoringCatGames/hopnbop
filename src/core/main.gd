class_name Main
extends Node2D


@export var settings: Settings


var is_paused := true:
    get:
        return is_paused
    set(value):
        is_paused = value


func _enter_tree() -> void:
    G.main = self
    G.settings = settings


func _ready() -> void:
    print("main._ready")

    randomize()

    get_tree().paused = true

    await get_tree().process_frame

    # TODO: Open first screen/level based on manifest settings.

    if G.settings.full_screen:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

    start_game()


func start_game() -> void:
    var screen_type := ScreensMain.ScreenType.GAME if G.settings.start_in_game else ScreensMain.ScreenType.MAIN_MENU
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
                is_paused = true
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
                        print(
                            "Toggled HUD visibility: %s" %
                            ("visible" if G.hud.visible else "hidden"))
                KEY_ESCAPE:
                    if G.settings.pauses_on_focus_out:
                        is_paused = true
                _:
                    pass


func close_app() -> void:
    if G.utils.were_screenshots_taken:
        G.utils.open_screenshot_folder()
    print("Shell.close_app")
    get_tree().call_deferred("quit")
