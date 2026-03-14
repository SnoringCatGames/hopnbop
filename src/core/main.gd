class_name Main
extends Node2D


func _enter_tree() -> void:
	G.main = self
	G.side_panel_layer = %SidePanelLayer
	G.confirm_layer = %ConfirmLayer
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

	var is_generating_thumbnails := (
		Netcode.is_preview
		and Netcode.is_server
		and G.settings.generate_level_thumbnails
	)

	if is_generating_thumbnails:
		get_tree().paused = false
		await (G.window_manager
			.generate_all_thumbnails())
		close_app()
		return

	_start_app()

	G.window_manager.update_window_mode()
	(G.window_manager
		.position_window_in_preview_mode())



func _handle_preview_window_closing() -> void:
	if not Netcode.is_preview:
		return

	# In thumbnail generation mode, close all
	# client windows. Only the server stays.
	if (G.window_manager
			.should_close_for_thumbnail_generation()):
		Netcode.print(
			"Main._ready: Closing client"
			+ " process for thumbnail"
			+ " generation mode",
			NetworkLogger
				.CATEGORY_CORE_SYSTEMS,
		)
		close_app()
		return

	if (
		Netcode.preview_client_number > 1
		and not G.settings
			.preview_run_multiple_clients
	):
		Netcode.print(
			("Main._ready: Closing extra client"
			+ " process (--client=%s), because"
			+ " preview_run_multiple_clients"
			+ " is false") %
			Netcode.preview_client_number,
			NetworkLogger.CATEGORY_CORE_SYSTEMS,
		)
		close_app()
		return

	if (
		Netcode.is_server
		and G.settings
			.preview_connect_to_remote_server
	):
		Netcode.print(
			("Main._ready: Closing local server"
			+ " process in preview mode,"
			+ " because"
			+ " preview_connect_to_remote_server"
			+ " is true"),
			NetworkLogger.CATEGORY_CORE_SYSTEMS,
		)
		close_app()
		return


func _start_app() -> void:
	if Netcode.is_server:
		get_tree().paused = false
		G.game_panel.server_start_match()
	else:
		# Check protocol version against the backend
		# before proceeding. Skip in preview and local
		# mode where there is no remote backend.
		if Netcode.should_connect_to_remote_server:
			_check_protocol_version()
		else:
			_continue_client_startup()


func _check_protocol_version() -> void:
	G.backend_api_client.version_checked.connect(
		_on_version_checked,
		CONNECT_ONE_SHOT,
	)
	G.backend_api_client.check_version()


func _on_version_checked(
	is_compatible: bool,
	_server_protocol_version: int,
) -> void:
	if not is_compatible:
		_show_update_required_dialog()
		return
	_continue_client_startup()


func _show_update_required_dialog() -> void:
	var dialog: ConfirmOverlay = (
		G.settings.confirm_overlay_scene
			.instantiate())
	G.confirm_layer.add_child(dialog)
	get_tree().paused = false
	dialog.open(
		tr("VERSION.UPDATE_REQUIRED"),
		tr("VERSION.CLOSE_GAME"),
		func() -> void:
			get_tree().quit(),
	)


func _continue_client_startup() -> void:
	if (G.settings.start_in_game
			and G.settings.is_preview_mode):
		# We see issues in preview mode on
		# resource-constrained machines where the
		# server process may not send or receive
		# messages correctly when all startup
		# processing happens at once across each
		# process.
		var auto_start_delay := randf() * 0.5 + 0.5
		await (get_tree()
			.create_timer(auto_start_delay)
			.timeout)

		_auto_start_game()
	elif (G.settings.skip_splash
			and G.settings.is_preview_mode):
		if G.settings.skip_auth:
			G.screens.client_open_screen(
				ScreensMain.ScreenType.LOBBY)
		else:
			G.screens.client_open_screen(
				ScreensMain.ScreenType.CONSENT)
	else:
		G.screens.client_open_screen(
			ScreensMain.ScreenType.GODOT_SPLASH)


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
	G.client_session.local_device_configs.append(device_config)
	G.input_device_manager.assign_device_to_player(
		local_player_index,
		device_config
	)

	# Generate player attributes.
	var attributes := (
		PlayerAttributeGenerator.generate_random_attributes()
	)
	G.client_session.local_player_attributes.append(attributes)

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
	# Force-close settings panel so unsaved
	# preferences are written to disk.
	for child in G.side_panel_layer.get_children():
		if child is SidePanelManager:
			child.close_all()
			break

	if G.utils.were_screenshots_taken:
		Utils.open_screenshot_folder()
	Netcode.print("Main.close_app", NetworkLogger.CATEGORY_CORE_SYSTEMS)

	# Explicitly disconnect to notify peers
	# immediately in preview mode.
	if Netcode.is_preview:
		if (Netcode.is_client
				and Netcode.is_connected_to_server):
			Netcode.connector.client_disconnect()
		elif (Netcode.is_server
				and multiplayer.get_peers()
					.size() > 0):
			# Disconnect all clients to notify
			# them immediately.
			for peer_id in multiplayer.get_peers():
				multiplayer.multiplayer_peer.disconnect_peer(peer_id)

	get_tree().call_deferred("quit")


func _disconnect_peers_in_preview_mode() -> void:
	# Explicitly disconnect to notify peers
	# immediately in preview mode.
	if not Netcode.is_preview:
		return

	if (not is_instance_valid(multiplayer)
			or not is_instance_valid(
				multiplayer.multiplayer_peer)):
		return

	if (Netcode.is_client
			and Netcode.is_connected_to_server):
		Netcode.connector.client_disconnect()
	elif (Netcode.is_server
			and multiplayer.get_peers()
				.size() > 0):
		# Disconnect all clients to notify them
		# immediately.
		for peer_id in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
