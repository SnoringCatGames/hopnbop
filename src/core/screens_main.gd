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
    G.log.print("AudioMain._ready", ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION)

    if G.network.is_server:
        for child in get_children():
            child.queue_free()
        return


func open_screen(screen_type: ScreenType) -> void:
    if G.network.is_server:
        G.log.warning("ScreensMain.open_screen: is_server")
        return

    current_screen = screen_type

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
    if ends_game:
        G.game_panel.exit_game()

    var loads_game := screen_type == ScreenType.LOADING
    if loads_game:
        G.game_panel.client_load_game()

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

    match screen_type:
        ScreenType.MAIN_MENU:
            G.main_menu_screen.on_open()
        ScreenType.LOADING:
            G.loading_screen.on_open()
        ScreenType.GAME_OVER:
            G.game_over_screen.on_open()
        ScreenType.WIN:
            G.win_screen.on_open()
        ScreenType.PAUSE:
            G.pause_screen.on_open()
        ScreenType.GAME:
            G.game_panel.on_return_from_screen()

    G.hud.update_visibility()
