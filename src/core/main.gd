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

	if (
		G.network.preview_client_number > 1 and
		not G.settings.preview_run_multiple_clients
	):
		G.print(
			("Main._ready: Closing extra client process (--client=%s), " +
			"because G.settings.preview_run_multiple_clients is false") %
			G.network.preview_client_number,
		)
		close_app()

	_start_app()

	_update_window_mode()

	if (G.network.is_preview and
		G.network.is_client and
		G.settings.preview_run_multiple_clients
	):
		_position_client_window_in_preview_mode()


func _update_window_mode() -> void:
	if (
		G.settings.auto_minimize_server_window and
		G.network.is_server and
		G.network.is_preview
	):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	elif G.settings.full_screen and not G.network.is_server:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _start_app() -> void:
	if G.network.is_server:
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
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if (G.settings.pauses_on_focus_out and
					G.settings.is_server_pause_enabled):
				G.network.frame_driver.client_request_pause()
		_:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if G.settings.dev_mode:
		if event is InputEventKey:
			match event.physical_keycode:
				KEY_P:
					if G.settings.is_screenshot_hotkey_enabled:
						G.utils.take_screenshot()
				KEY_O:
					if is_instance_valid(G.hud):
						G.hud.visible = not G.hud.visible
						G.print(
							"Toggled HUD visibility: %s" %
							("visible" if G.hud.visible else "hidden"),
							ScaffolderLog.CATEGORY_CORE_SYSTEMS,
						)
				KEY_ESCAPE:
					if G.settings.is_server_pause_enabled:
						G.network.frame_driver.client_request_pause()
				KEY_F1:
					if is_instance_valid(G.super_hud):
						G.super_hud.toggle_debug_console()
				KEY_F2:
					if is_instance_valid(G.super_hud):
						G.super_hud.toggle_player_state_list()
				KEY_F3:
					if is_instance_valid(G.super_hud):
						G.super_hud.toggle_perf_tracker()
				_:
					pass

	if (
		event.is_action_pressed("toggle_pause") and
		G.settings.is_server_pause_enabled
	):
		G.network.frame_driver.client_request_toggle_pause()
		get_viewport().set_input_as_handled()


func close_app() -> void:
	if G.utils.were_screenshots_taken:
		Utils.open_screenshot_folder()
	G.print("Main.close_app", ScaffolderLog.CATEGORY_CORE_SYSTEMS)

	# Explicitly disconnect to notify peers immediately in preview mode
	if G.network.is_preview:
		if G.network.is_client and G.network.is_connected_to_server:
			G.network.connector.client_disconnect()
		elif G.network.is_server and multiplayer.get_peers().size() > 0:
			# Disconnect all clients to notify them immediately
			for peer_id in multiplayer.get_peers():
				multiplayer.multiplayer_peer.disconnect_peer(peer_id)

	get_tree().call_deferred("quit")


func update_window_title() -> void:
	if not G.network.is_preview:
		return

	var app_name = ProjectSettings.get_setting("application/config/name")
	var device_prefix: String
	if G.network.is_server:
		device_prefix = "SERVER"
	else:
		device_prefix = "CLIENT %s" % G.network.local_peer_id

	DisplayServer.window_set_title("[%s] %s (DEBUG)" % [device_prefix, app_name])


func _position_client_window_in_preview_mode() -> void:
	# Get usable screen area (excluding taskbar and other system UI).
	var usable_rect := DisplayServer.screen_get_usable_rect()
	@warning_ignore("integer_division")
	var half_width := usable_rect.size.x / 2

	# Account for window title bar height.
	const TITLE_BAR_HEIGHT := 48
	var window_height := usable_rect.size.y - TITLE_BAR_HEIGHT

	# Resize window to half the usable screen width.
	DisplayServer.window_set_size(Vector2i(half_width, window_height))

	# Position based on local_peer_id.
	var position_x := usable_rect.position.x
	if G.network.preview_client_number != 1:
		position_x += half_width
	var position_y := usable_rect.position.y + TITLE_BAR_HEIGHT
	DisplayServer.window_set_position(Vector2i(position_x, position_y))


func _disconnect_peers_in_preview_mode() -> void:
	# Explicitly disconnect to notify peers immediately in preview mode
	if not G.network.is_preview:
		return

	if not is_instance_valid(multiplayer) or not is_instance_valid(multiplayer.multiplayer_peer):
		return

	if G.network.is_client and G.network.is_connected_to_server:
		G.network.connector.client_disconnect()
	elif G.network.is_server and multiplayer.get_peers().size() > 0:
		# Disconnect all clients to notify them immediately
		for peer_id in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
