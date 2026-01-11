class_name LoadingScreen
extends Screen


func _enter_tree() -> void:
    super._enter_tree()
    G.loading_screen = self

    # FIXME: Open GAME screen once connected
    #G.screens.open_screen(ScreensMain.ScreenType.GAME)
