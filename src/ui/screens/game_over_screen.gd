class_name GameOverScreen
extends Screen


func _enter_tree() -> void:
	super._enter_tree()
	G.game_over_screen = self


func on_open() -> void:
	super.on_open()

	# Display server message if present.
	if not G.client_session.latest_server_message.is_empty():
		%MessageLabel.text = G.client_session.latest_server_message
		%MessageLabel.visible = true
	else:
		%MessageLabel.visible = false

	# Wait a frame for the button to be fully ready, then grab focus.
	await get_tree().process_frame
	%Button.grab_focus()


func _on_button_pressed() -> void:
	G.audio.play_sound("click")
	G.screens.client_open_screen(ScreensMain.ScreenType.LOBBY)
