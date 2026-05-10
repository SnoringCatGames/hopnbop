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

	# Server-side: the snoringcat-platform runtime sets
	# TRANSPORT_TYPE in the Edgegap deploy env to indicate the
	# transport for this allocation (enet for native-only
	# matches, webrtc when any web player is in the lobby).
	# Client-side this env var is unset, so this is a no-op
	# there.
	_apply_transport_from_env()

	randomize()

	Scaffolder.set_up()


func _apply_transport_from_env() -> void:
	var raw: String = OS.get_environment("TRANSPORT_TYPE")
	if not raw.is_empty():
		match raw.to_lower():
			"enet":
				Netcode.settings.transport_type = (
					NetworkSettings.TransportType.ENET)
			"webrtc":
				Netcode.settings.transport_type = (
					NetworkSettings.TransportType.WEBRTC)
			"websocket":
				Netcode.settings.transport_type = (
					NetworkSettings.TransportType.WEBSOCKET)
			_:
				push_warning(
					"Unknown TRANSPORT_TYPE env value: %s"
					% raw)
	# Optional override for the signaling port. Edgegap declares
	# 4434/TCP for signaling separate from 4433/UDP for game
	# data; the runtime injects SIGNALING_PORT=4434 when
	# allocating a webrtc-mode container.
	var signaling_raw: String = OS.get_environment(
		"SIGNALING_PORT")
	if not signaling_raw.is_empty():
		var parsed := int(signaling_raw)
		if parsed > 0:
			Netcode.settings.signaling_port = parsed

	# Edgegap injects the external host port for each declared
	# container port as ARBITRIUM_PORT_<NAME>_EXTERNAL (port
	# NAME, not container port number). The signaling server
	# uses this for ICE candidate rewriting — port-preserving
	# NAT inside the container means STUN reflects the
	# container port, not the external port the client dials.
	# Reading it directly from env keeps rollback_netcode
	# platform-agnostic; the addon just reads
	# Netcode.settings.host_udp_port.
	var udp_external: String = OS.get_environment(
		"ARBITRIUM_PORT_GAME_EXTERNAL")
	if not udp_external.is_empty():
		var udp_port := int(udp_external)
		if udp_port > 0:
			Netcode.settings.host_udp_port = udp_port


func _ready() -> void:
	G.log.log_system_ready("Main")

	get_tree().paused = true

	await get_tree().process_frame

	# _handle_preview_window_closing() may call close_app()
	# (deferred quit). When it does we must skip _start_app —
	# otherwise the level spawn / ENet bind / register_server
	# all run for one frame before quit fires, which is what
	# was making the local-server preview window briefly
	# appear in remote-matchmaking mode.
	if _handle_preview_window_closing():
		return

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



## Returns true if this preview process should shut down
## immediately (close_app() has been called and the caller
## must NOT continue with _start_app()). Returns false for
## any other case. Calling close_app() from _ready() alone
## isn't enough — quit is deferred to end-of-frame, so
## _start_app would still run and partially boot a server
## that's about to die.
func _handle_preview_window_closing() -> bool:
	if not Netcode.is_preview:
		return false

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
		return true

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
		return true

	if (
		Netcode.is_server
		and G.settings
			.preview_connect_to_remote_server
		and not G.settings
			.generate_level_thumbnails
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
		return true

	return false


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
	_server_game_version: String,
) -> void:
	if not is_compatible:
		_show_update_required_dialog()
		return

	# On web, check for a stale build by fetching
	# version.json from the same origin. This works
	# independently of the backend, so web-only
	# deploys also trigger a refresh.
	if OS.has_feature("web"):
		_check_web_build_version()
		return

	_continue_client_startup()


func _check_web_build_version() -> void:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(
		_on_web_version_check_completed.bind(http),
		CONNECT_ONE_SHOT,
	)
	# Fetch version.json from the same origin with a
	# cache-busting query param to bypass CDN cache.
	var base_url: String = JavaScriptBridge.eval(
		"window.location.origin")
	var url := (
		"%s/version.json?_t=%d"
		% [base_url, Time.get_ticks_msec()])
	var error := http.request(
		url,
		PackedStringArray(),
		HTTPClient.METHOD_GET,
	)
	if error != OK:
		http.queue_free()
		_continue_client_startup()


func _on_web_version_check_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
) -> void:
	http.queue_free()

	if (
		result != HTTPRequest.RESULT_SUCCESS
		or response_code != 200
	):
		_continue_client_startup()
		return

	var parsed = JSON.parse_string(
		body.get_string_from_utf8())
	if parsed == null or not parsed is Dictionary:
		_continue_client_startup()
		return

	var web_game_version: String = parsed.get(
		"game_version", "")
	if (
		web_game_version != ""
		and not _is_web_game_version_current(
			web_game_version)
	):
		_web_hard_refresh(web_game_version)
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
		close_app,
	)


func _is_web_game_version_current(
	server_game_version: String,
) -> bool:
	var client_game_version: String = (
		ProjectSettings.get_setting(
			"application/config/version", ""))
	if client_game_version == server_game_version:
		return true

	# Check for the loop-breaker query param. If we
	# already refreshed once for this version, do not
	# refresh again to avoid an infinite reload loop.
	var url: String = (
		JavaScriptBridge.eval("window.location.href"))
	var expected_param := (
		"v_refreshed=" + server_game_version)
	if expected_param in url:
		return true

	return false


func _web_hard_refresh(
	server_game_version: String,
) -> void:
	# Append the server version as a query param
	# (loop breaker), then navigate to the new URL.
	# Changing the URL forces the browser to re-fetch
	# the page. If the browser still serves a stale
	# build after this, the loop breaker param
	# prevents another refresh.
	var safe_version := (
		server_game_version.replace("'", "\\'"))
	JavaScriptBridge.eval("""
		(function() {
			var url = new URL(window.location.href);
			url.searchParams.set(
				'v_refreshed', '%s');
			window.location.replace(url.toString());
		})();
	""" % safe_version)


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
			# Android back button. We don't have an in-app
			# navigation stack to pop yet; treat as quit until
			# screen-stack handling exists.
			close_app()
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

	# Release the backend session lock so the
	# player can re-queue on next launch.
	if (
		Netcode.is_client
		and Netcode.should_connect_to_remote_server
		and is_instance_valid(G.game_panel)
		and is_instance_valid(
			G.game_panel.session_manager)
		and is_instance_valid(
			G.game_panel.session_manager
				.session_provider)
		and G.game_panel.session_manager
			.session_provider
			.has_method("clear_session")
	):
		(G.game_panel.session_manager
			.session_provider.clear_session())

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

	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.close()")
	else:
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
