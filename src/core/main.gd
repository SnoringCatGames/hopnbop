class_name Main
extends Node2D


func _enter_tree() -> void:
	G.main = self
	G.log.set_log_filtering(
		G.settings.excluded_log_categories,
		G.settings.force_include_log_warnings,
	)

	randomize()

	Scaffolder.set_up()


func _ready() -> void:
	G.log.log_system_ready("Main")

	get_tree().paused = true

	await get_tree().process_frame

	_handle_preview_window_closing()

	_start_app()

	G.window_manager.update_window_mode()

	if Netcode.is_preview and Netcode.is_client:
		G.window_manager.position_client_window_in_preview_mode()


func _handle_preview_window_closing() -> void:
	if not Netcode.is_preview:
		return

	if (
		Netcode.preview_client_number > 1 and
		not G.settings.preview_run_multiple_clients
	):
		G.print(
			("Main._ready: Closing extra client process (--client=%s), " +
			"because G.settings.preview_run_multiple_clients is false") %
			Netcode.preview_client_number,
			NetworkLogger.CATEGORY_CORE_SYSTEMS,
		)
		close_app()
		return

	if (
		Netcode.is_server and
		G.settings.preview_connect_to_remote_server
	):
		G.print(
			("Main._ready: Closing local server process in preview mode, " +
			"because G.settings.preview_connect_to_remote_server is true"),
			NetworkLogger.CATEGORY_CORE_SYSTEMS,
		)
		close_app()
		return


func _start_app() -> void:
	if Netcode.is_server:
		get_tree().paused = false
		G.game_panel.server_start_game()
	else:
		if G.settings.start_in_game:
			_auto_start_game()
		elif G.settings.skip_splash:
			G.screens.client_open_screen(ScreensMain.ScreenType.LOBBY)
		else:
			G.screens.client_open_screen(ScreensMain.ScreenType.GODOT_SPLASH)


func _auto_start_game() -> void:
	# Auto-add one player with WASD keyboard bindings.
	var wasd_bindings := (
		InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
	)
	var device_config := DeviceConfig.new(
		DeviceConfig.DeviceType.KEYBOARD,
		DeviceConfig.KEYBOARD_DEVICE_ID,
		wasd_bindings
	)

	# Add to local session.
	var local_player_index := 0
	G.local_session.local_device_configs.append(device_config)
	G.input_device_manager.assign_device_to_player(
		local_player_index,
		device_config
	)

	# Generate player attributes.
	var attributes := (
		PlayerAttributeGenerator.generate_random_attributes()
	)
	G.local_session.local_player_attributes.append(attributes)

	G.game_panel.client_load_game()


func _notification(notification_type: int) -> void:
	match notification_type:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Handle the Android back button to navigate within the app instead of
			# quitting the app.
			if false:
				close_app()
			else:
				# TODO: Close the current screen/context.
				pass
		NOTIFICATION_WM_CLOSE_REQUEST:
			_disconnect_peers_in_preview_mode()
			close_app()
		_:
			pass


func close_app() -> void:
	if G.utils.were_screenshots_taken:
		Utils.open_screenshot_folder()
	G.print("Main.close_app", NetworkLogger.CATEGORY_CORE_SYSTEMS)

	# Explicitly disconnect to notify peers immediately in preview mode
	if Netcode.is_preview:
		if Netcode.is_client and Netcode.is_connected_to_server:
			Netcode.connector.client_disconnect()
		elif Netcode.is_server and multiplayer.get_peers().size() > 0:
			# Disconnect all clients to notify them immediately
			for peer_id in multiplayer.get_peers():
				multiplayer.multiplayer_peer.disconnect_peer(peer_id)

	get_tree().call_deferred("quit")


func update_window_title() -> void:
	## Delegates to WindowManager for title updates.
	G.window_manager.update_window_title()


func _disconnect_peers_in_preview_mode() -> void:
	# Explicitly disconnect to notify peers immediately in preview mode
	if not Netcode.is_preview:
		return

	if not is_instance_valid(multiplayer) or not is_instance_valid(multiplayer.multiplayer_peer):
		return

	if Netcode.is_client and Netcode.is_connected_to_server:
		Netcode.connector.client_disconnect()
	elif Netcode.is_server and multiplayer.get_peers().size() > 0:
		# Disconnect all clients to notify them immediately
		for peer_id in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
