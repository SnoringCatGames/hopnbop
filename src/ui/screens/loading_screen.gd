class_name LoadingScreen
extends Screen

func _enter_tree() -> void:
	super._enter_tree()
	G.loading_screen = self


func _process(_delta: float) -> void:
	update_status_message()


func on_open() -> void:
	super.on_open()

	# If game is no longer loading (disconnect during transition), skip setup.
	# The screen system will immediately transition to GAME_OVER.
	if not G.client_session.is_game_loading:
		Netcode.print(
			"LoadingScreen opened but game is no longer loading " + \
			"(disconnect during transition)",
			NetworkLogger.CATEGORY_GAME_STATE
		)
		return

	# Set initial message.
	update_status_message()


# Override the parent method, so we can force the hud theme.
func _set_default_styling() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	#theme = G.settings.default_theme
	add_theme_stylebox_override("panel", G.settings.screen_style_box)


func update_status_message() -> void:
	if not is_instance_valid(%Label):
		return

	if Netcode.connector.is_connected_to_server:
		%Label.text = "Waiting for players..."
	else:
		%Label.text = "Connecting to server..."
