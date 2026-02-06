class_name WindowManager
extends Node
## Manages window positioning, sizing, and display modes.
##
## Handles preview mode window layouts, fullscreen toggling, and window title
## updates. Automatically assigned as a child of Global singleton.


func update_window_mode() -> void:
	## Sets window mode based on settings and network role.
	if (
		G.settings.auto_minimize_server_window and
		Netcode.is_server and
		Netcode.is_preview
	):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	elif G.settings.full_screen and not Netcode.is_server:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func update_window_title() -> void:
	## Updates window title with server/client designation in preview mode.
	if not Netcode.is_preview:
		return

	var app_name = ProjectSettings.get_setting("application/config/name")
	var device_prefix: String
	if Netcode.is_server:
		device_prefix = "SERVER"
	else:
		device_prefix = "CLIENT %s" % Netcode.local_peer_id

	DisplayServer.window_set_title(
		"[%s] %s (DEBUG)" % [device_prefix, app_name]
	)


func position_client_window_in_preview_mode() -> void:
	## Positions client windows in split-screen or centered layout.
	if not Netcode.is_preview or not Netcode.is_client:
		return

	# Account for window title bar height.
	const TITLE_BAR_HEIGHT := 48

	var screen_count := DisplayServer.get_screen_count()
	# Default to current screen (which windows start on).
	var target_screen := DisplayServer.window_get_current_screen()

	# Check if we should move to another monitor.
	if G.settings.move_preview_windows_to_other_display and screen_count > 1:
		# Move client window(s) to screen 0 (secondary monitor).
		target_screen = 0

	# Get usable screen area for the target screen.
	var usable_rect := DisplayServer.screen_get_usable_rect(target_screen)

	if not G.settings.preview_run_multiple_clients:
		# Single client: center window at half monitor size.
		@warning_ignore("integer_division")
		var window_width := usable_rect.size.x / 2
		@warning_ignore("integer_division")
		var window_height := usable_rect.size.y / 2

		# Set size.
		DisplayServer.window_set_size(Vector2i(window_width, window_height))

		# Center the window.
		@warning_ignore("integer_division")
		var position_x := usable_rect.position.x + (
			(usable_rect.size.x - window_width) / 2
		)
		@warning_ignore("integer_division")
		var position_y := usable_rect.position.y + (
			(usable_rect.size.y - window_height) / 2
		)
		DisplayServer.window_set_position(Vector2i(position_x, position_y))

	else:
		# Use split-screen layout (on either primary or other monitor).
		@warning_ignore("integer_division")
		var half_width := usable_rect.size.x / 2
		var window_height := usable_rect.size.y - TITLE_BAR_HEIGHT

		# Calculate position on target screen.
		var position_x := usable_rect.position.x
		if Netcode.preview_client_number != 1:
			position_x += half_width
		var position_y := usable_rect.position.y + TITLE_BAR_HEIGHT

		# Set size and position.
		DisplayServer.window_set_size(Vector2i(half_width, window_height))
		DisplayServer.window_set_position(Vector2i(position_x, position_y))
