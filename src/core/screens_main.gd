class_name ScreensMain
extends PanelContainer


enum ScreenType {
    MAIN_MENU,
    LOADING,
    GAME_OVER,
    WIN,
    PAUSE,
    GAME,
}

var current_screen := ScreenType.MAIN_MENU


func _enter_tree() -> void:
    G.screens = self

    if G.network.is_server:
        visible = false
        process_mode = Node.PROCESS_MODE_DISABLED
        return


func _ready() -> void:
    G.log.log_system_ready("AudioMain")

    if G.network.is_server:
        for child in get_children():
            child.queue_free()
        return


func client_open_screen(screen_type: ScreenType) -> void:
    G.check_is_client("ScreensMain.client_open_screen")

    if screen_type == current_screen:
        # Already there!
        return

    var previous_screen_type := current_screen
    current_screen = screen_type

    G.print("Switching screens: %s => %s" % [
        ScreenType.keys()[previous_screen_type],
        ScreenType.keys()[screen_type],
    ], ScaffolderLog.CATEGORY_INTERACTION)

    get_tree().paused = screen_type != ScreenType.GAME

    G.main_menu_screen.visible = screen_type == ScreenType.MAIN_MENU
    G.loading_screen.visible = screen_type == ScreenType.LOADING
    G.game_over_screen.visible = screen_type == ScreenType.GAME_OVER
    G.win_screen.visible = screen_type == ScreenType.WIN
    G.pause_screen.visible = screen_type == ScreenType.PAUSE

    var ends_game := [
        ScreenType.MAIN_MENU,
        ScreenType.LOADING,
        ScreenType.GAME_OVER,
        ScreenType.WIN,
    ].has(screen_type)
    if ends_game and G.local_session.is_game_active:
        G.game_panel.client_exit_game()

    var plays_menu_theme := [
        ScreenType.MAIN_MENU,
        ScreenType.LOADING,
        ScreenType.GAME_OVER,
        ScreenType.WIN,
        ScreenType.PAUSE,
    ].has(screen_type)
    if plays_menu_theme:
        G.audio.fade_to_menu_theme()

    var plays_main_theme := [ScreenType.GAME].has(screen_type)
    if plays_main_theme:
        G.audio.fade_to_main_theme()

    if screen_type == ScreenType.GAME:
        G.game_panel.on_return_from_screen()
    else:
        var screen := get_screen_from_type(screen_type)
        screen.on_open()

    if previous_screen_type == ScreenType.GAME:
        G.game_panel.on_left_to_screen()
    else:
        var previous_screen := get_screen_from_type(previous_screen_type)
        previous_screen.on_close()

    G.hud.update_visibility()


func get_screen_from_type(screen_type: ScreenType) -> Screen:
    match screen_type:
        ScreenType.MAIN_MENU:
            return G.main_menu_screen
        ScreenType.LOADING:
            return G.loading_screen
        ScreenType.GAME_OVER:
            return G.game_over_screen
        ScreenType.WIN:
            return G.win_screen
        ScreenType.PAUSE:
            return G.pause_screen
        ScreenType.GAME:
            return null
        _:
            G.check(false, "ScreensMain.get_screen_from_type")
            return null
