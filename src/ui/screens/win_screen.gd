class_name WinScreen
extends Screen


func _enter_tree() -> void:
    super._enter_tree()
    G.win_screen = self


func on_open() -> void:
    super.on_open()
    %Button.grab_focus.call_deferred()


func _on_button_pressed() -> void:
    G.audio.play_click_sound()
    G.screens.client_open_screen(ScreensMain.ScreenType.MAIN_MENU)
