class_name Hud
extends PanelContainer


func _enter_tree() -> void:
    G.hud = self

    if G.network.is_server:
        visible = false
        process_mode = Node.PROCESS_MODE_DISABLED
        return


func _ready() -> void:
    G.log.print("Hud._ready", ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION)

    if G.network.is_server:
        return

    # Wait for G.settings to be assigned.
    await get_tree().process_frame

    self.visible = G.settings.show_hud


func update_visibility() -> void:
    if G.network.is_server:
        return

    match G.screens.current_screen:
        ScreensMain.ScreenType.MAIN_MENU, \
        ScreensMain.ScreenType.LOADING, \
        ScreensMain.ScreenType.GAME_OVER, \
        ScreensMain.ScreenType.WIN, \
        ScreensMain.ScreenType.PAUSE:
            pass
        ScreensMain.ScreenType.GAME:
            pass
        _:
            G.utils.ensure(false)
