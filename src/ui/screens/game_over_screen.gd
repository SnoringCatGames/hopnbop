class_name GameOverScreen
extends Screen


func _enter_tree() -> void:
	super._enter_tree()
	G.game_over_screen = self


func on_open() -> void:
	super.on_open()

	# Display server message if present.
	if not G.local_session.latest_server_message.is_empty():
		%MessageLabel.text = G.local_session.latest_server_message
		%MessageLabel.visible = true
	else:
		%MessageLabel.visible = false

	%Button.grab_focus.call_deferred()


func _on_button_pressed() -> void:
	G.audio.play_click_sound()
	G.screens.client_open_screen(ScreensMain.ScreenType.LOBBY)
