class_name GameOverScreen
extends Screen


func _enter_tree() -> void:
    super._enter_tree()
    G.game_over_screen = self


func on_open() -> void:
    %Button.grab_focus.call_deferred()


func _on_button_pressed() -> void:
    G.audio.play_click_sound()
    G.screens.open_screen(ScreensMain.ScreenType.GAME)
