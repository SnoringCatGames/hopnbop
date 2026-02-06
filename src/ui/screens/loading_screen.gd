class_name LoadingScreen
extends Screen

func _enter_tree() -> void:
	super._enter_tree()
	G.loading_screen = self


func _process(_delta: float) -> void:
	update_status_message()


func on_open() -> void:
	super.on_open()
	G.check(G.client_session.is_game_loading, "LoadingScreen.on_open: Game is not loading")

	# Set initial message.
	update_status_message()


func update_status_message() -> void:
	if not is_instance_valid(%Label):
		return

	if Netcode.connector.is_connected_to_server:
		%Label.text = "Waiting for players..."
	else:
		%Label.text = "Connecting to server..."
