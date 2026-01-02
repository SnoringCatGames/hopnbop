class_name GameOverScreen
extends PanelContainer


func _enter_tree() -> void:
	G.game_over_screen = self


func on_open() -> void:
	%Button.grab_focus.call_deferred()


func _on_button_pressed() -> void:
	G.main.play_click_sound()
	G.screens.open_screen(ScreensMain.ScreenType.GAME)
