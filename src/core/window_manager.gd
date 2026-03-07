class_name WindowManager
extends Node
## Manages window positioning, sizing, and display modes.
##
## Handles preview mode window layouts, fullscreen toggling, and window title
## updates. Automatically assigned as a child of Global singleton.


func _ready() -> void:
	# Update the title after waiting for state to initialize.
	await get_tree().process_frame
	_update_window_title()


func update_window_mode() -> void:
	## Sets window mode based on settings
	## and network role.
	if (
		G.settings.auto_minimize_server_window
		and Netcode.is_server
		and Netcode.is_preview
	):
		DisplayServer.window_set_mode(
			DisplayServer
				.WINDOW_MODE_MINIMIZED)
	elif not Netcode.is_server:
		if G.settings.full_screen:
			DisplayServer.window_set_mode(
				DisplayServer
					.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(
				DisplayServer
					.WINDOW_MODE_WINDOWED)


func _update_window_title() -> void:
	## Updates window title with server/client designation in preview mode.
	if not Netcode.is_preview:
		return

	var app_name = ProjectSettings.get_setting("application/config/name")
	var device_prefix: String
	if Netcode.is_server:
		device_prefix = "SERVER"
	else:
		device_prefix = "CLIENT %s" % Netcode.preview_client_number

	DisplayServer.window_set_title(
		"[%s] %s (DEBUG)" % [device_prefix, app_name]
	)


func position_window_in_preview_mode() -> void:
	## Positions window in preview mode based on server/client role.
	if not Netcode.is_preview:
		return

	if Netcode.is_server:
		position_server_window_in_preview_mode()
	elif Netcode.is_client:
		position_client_window_in_preview_mode()


func position_server_window_in_preview_mode() -> void:
	## Positions server window in preview mode layout.
	if not Netcode.is_preview or not Netcode.is_server:
		return

	# If auto-minimize is enabled, don't position the server window.
	if G.settings.auto_minimize_server_window:
		return

	# Account for window title bar height.
	const TITLE_BAR_HEIGHT := 48

	var screen_count := DisplayServer.get_screen_count()
	# Default to current screen (which windows start on).
	var target_screen := DisplayServer.window_get_current_screen()

	# Check if we should move to another monitor.
	if G.settings.move_preview_windows_to_other_display and screen_count > 1:
		# Move server window to screen 0 (secondary monitor).
		target_screen = 0

	# Get usable screen area for the target screen.
	var usable_rect := DisplayServer.screen_get_usable_rect(target_screen)

	@warning_ignore("integer_division")
	var third_width := usable_rect.size.x / 3

	if G.settings.preview_run_multiple_clients:
		# With 2 clients: Server takes top portion (3/8), Client 2 bottom
		# (5/8).
		# Account for both server and client 2 title bars.
		var available_height := usable_rect.size.y - (2 * TITLE_BAR_HEIGHT)
		@warning_ignore("integer_division")
		var server_height := (available_height * 3) / 8

		DisplayServer.window_set_size(Vector2i(third_width, server_height))
		DisplayServer.window_set_position(
			Vector2i(
				usable_rect.position.x,
				usable_rect.position.y + TITLE_BAR_HEIGHT
			)
		)
	else:
		# With 1 client: Server takes left half.
		var window_height := usable_rect.size.y - TITLE_BAR_HEIGHT

		DisplayServer.window_set_size(Vector2i(third_width, window_height))
		DisplayServer.window_set_position(
			Vector2i(
				usable_rect.position.x,
				usable_rect.position.y + TITLE_BAR_HEIGHT
			)
		)


## Returns true if this process should close
## because thumbnail generation is active and
## this is a client.
func should_close_for_thumbnail_generation(
) -> bool:
	return (
		Netcode.is_preview
		and Netcode.is_client
		and G.settings.generate_level_thumbnails
	)


## Iterates through every registered level,
## spawning each in sequence, configuring the
## viewport for 1:1 pixel rendering, and saving
## a screenshot named after the level id.
func generate_all_thumbnails() -> void:
	var count := G.level_registry.get_level_count()
	Netcode.print(
		"Generating thumbnails for %d levels"
		% count,
		NetworkLogger.CATEGORY_CORE_SYSTEMS,
	)

	for i in count:
		var info := (
			G.level_registry.get_level_by_index(i))
		if info == null or info.scene == null:
			continue
		await _generate_thumbnail_for_level(info)

	Netcode.print(
		"All thumbnail snapshots complete",
		NetworkLogger.CATEGORY_CORE_SYSTEMS,
	)


func _generate_thumbnail_for_level(
	info: LevelInfo,
) -> void:
	# Clean up previous level.
	if is_instance_valid(G.level):
		G.level.queue_free()
		G.level = null
		await get_tree().process_frame

	# Spawn the level scene.
	var level: Level = info.scene.instantiate()
	(G.game_panel.get_node("Levels")
		.add_child(level))
	G.level = level

	var camera := level.level_camera
	if not is_instance_valid(camera):
		Netcode.print(
			"Skipping %s: no camera" % info.id,
			NetworkLogger.CATEGORY_CORE_SYSTEMS,
		)
		return

	# Read the scene-configured camera zoom before
	# the next process frame, where PVM would
	# override it in thumbnail snapshot mode.
	var camera_zoom := camera.zoom

	# Wait a frame for camera initialization.
	await get_tree().process_frame
	var base_res := Vector2(
		ProjectSettings.get_setting(
			"display/window/size/viewport_width",
			1152),
		ProjectSettings.get_setting(
			"display/window/size/viewport_height",
			648),
	)
	var visible_size := Vector2i(
		roundi(base_res.x / camera_zoom.x),
		roundi(base_res.y / camera_zoom.y),
	)

	Netcode.print(
		"Thumbnail [%d/%d] %s (%dx%d px)" % [
			G.level_registry
				.get_all_level_ids()
				.find(info.id) + 1,
			G.level_registry.get_level_count(),
			info.id,
			visible_size.x,
			visible_size.y],
		NetworkLogger.CATEGORY_CORE_SYSTEMS,
	)

	# Size and center the server window.
	DisplayServer.window_set_size(visible_size)
	var screen := (
		DisplayServer
			.window_get_current_screen())
	var usable_rect := (
		DisplayServer
			.screen_get_usable_rect(screen))
	@warning_ignore("integer_division")
	var pos_x := (
		usable_rect.position.x
		+ (usable_rect.size.x - visible_size.x)
		/ 2
	)
	@warning_ignore("integer_division")
	var pos_y := (
		usable_rect.position.y
		+ (usable_rect.size.y - visible_size.y)
		/ 2
	)
	DisplayServer.window_set_position(
		Vector2i(pos_x, pos_y))

	# Override PVM base resolution so the
	# viewport, integer scale, and zoom scale
	# all resolve to 1:1.
	if is_instance_valid(
		G.pixel_viewport_manager
	):
		(G.pixel_viewport_manager
			.configure_thumbnail_snapshot(
				visible_size))

	# Wait for the viewport to render.
	await get_tree().create_timer(0.5).timeout

	_take_thumbnail_screenshot(info.id)


func _take_thumbnail_screenshot(
	level_id: StringName,
) -> void:
	## Captures the game SubViewport directly and
	## saves it as a PNG screenshot named after the
	## level id. Also copies to the project asset
	## folder for use as level thumbnails.
	if (
		not is_instance_valid(
			G.pixel_viewport_manager)
		or not is_instance_valid(
			G.pixel_viewport_manager.sub_viewport)
	):
		return

	var result := (
		DirAccess.make_dir_recursive_absolute(
			"user://screenshots"))
	if result != OK:
		return

	var image := (
		G.pixel_viewport_manager.sub_viewport
			.get_texture().get_image())
	var path := (
		"user://screenshots/%s.png"
		% level_id)
	var status := image.save_png(path)
	if status != OK:
		Netcode.print(
			"Failed to save thumbnail: "
			+ path,
			NetworkLogger.CATEGORY_CORE_SYSTEMS,
		)
		return

	Netcode.print(
		"Took thumbnail screenshot: "
		+ path,
		NetworkLogger.CATEGORY_CORE_SYSTEMS,
	)
	G.utils.were_screenshots_taken = true

	# Copy to project asset folder so level
	# thumbnails stay up-to-date.
	_copy_thumbnail_to_assets(image, level_id)


func _copy_thumbnail_to_assets(
	image: Image,
	level_id: StringName,
) -> void:
	var asset_dir := (
		"res://assets/images/level_thumbnails")
	var dir_result := (
		DirAccess.make_dir_recursive_absolute(
			asset_dir))
	if dir_result != OK:
		Netcode.print(
			"Failed to create asset dir: "
			+ asset_dir,
			NetworkLogger.CATEGORY_CORE_SYSTEMS,
		)
		return

	var asset_path := (
		"%s/%s.png" % [asset_dir, level_id])
	var status := image.save_png(asset_path)
	if status != OK:
		Netcode.print(
			"Failed to copy thumbnail to: "
			+ asset_path,
			NetworkLogger.CATEGORY_CORE_SYSTEMS,
		)
	else:
		Netcode.print(
			"Copied thumbnail to: "
			+ asset_path,
			NetworkLogger.CATEGORY_CORE_SYSTEMS,
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

	# Check if server window is visible (not auto-minimized).
	var server_visible := not G.settings.auto_minimize_server_window

	if not G.settings.preview_run_multiple_clients:
		# Single client layout.
		if server_visible:
			# Client takes right half, server takes left half.
			@warning_ignore("integer_division")
			var third_width := usable_rect.size.x / 3
			var two_third_width := usable_rect.size.x - third_width
			var window_height := usable_rect.size.y - TITLE_BAR_HEIGHT

			DisplayServer.window_set_size(Vector2i(two_third_width, window_height))
			DisplayServer.window_set_position(
				Vector2i(
					usable_rect.position.x + third_width,
					usable_rect.position.y + TITLE_BAR_HEIGHT
				)
			)
		else:
			# No server visible: center window at half monitor size.
			@warning_ignore("integer_division")
			var window_width := usable_rect.size.x / 2
			@warning_ignore("integer_division")
			var window_height := usable_rect.size.y / 2

			# Set size.
			DisplayServer.window_set_size(
				Vector2i(window_width, window_height)
			)

			# Center the window.
			@warning_ignore("integer_division")
			var position_x := usable_rect.position.x + (
				(usable_rect.size.x - window_width) / 2
			)
			@warning_ignore("integer_division")
			var position_y := usable_rect.position.y + (
				(usable_rect.size.y - window_height) / 2
			)
			DisplayServer.window_set_position(
				Vector2i(position_x, position_y)
			)
	else:
		# Multiple clients layout.
		@warning_ignore("integer_division")
		var third_width := usable_rect.size.x / 3
		var two_third_width := usable_rect.size.x - third_width

		if server_visible:
			# Client 1 takes right half, Client 2 takes bottom-left quadrant.
			if Netcode.preview_client_number == 1:
				# Client 1: entire right half.
				var window_height := usable_rect.size.y - TITLE_BAR_HEIGHT

				DisplayServer.window_set_size(
					Vector2i(two_third_width, window_height)
				)
				DisplayServer.window_set_position(
					Vector2i(
						usable_rect.position.x + third_width,
						usable_rect.position.y + TITLE_BAR_HEIGHT
					)
				)
			else:
				# Client 2: bottom-left portion (5/8 of vertical space).
				# Account for both server and client 2 title bars.
				var available_height := (
					usable_rect.size.y - (2 * TITLE_BAR_HEIGHT)
				)
				@warning_ignore("integer_division")
				var server_height := (available_height * 3) / 8
				@warning_ignore("integer_division")
				var client2_height := (available_height * 5) / 8

				DisplayServer.window_set_size(
					Vector2i(third_width, client2_height)
				)
				DisplayServer.window_set_position(
					Vector2i(
						usable_rect.position.x,
						usable_rect.position.y
						+ TITLE_BAR_HEIGHT
						+ server_height
						+ TITLE_BAR_HEIGHT
					)
				)
		else:
			# No server visible: split screen between clients.
			var window_height := usable_rect.size.y - TITLE_BAR_HEIGHT

			# Calculate position on target screen.
			var position_x := usable_rect.position.x
			if Netcode.preview_client_number != 1:
				position_x += third_width
			var position_y := usable_rect.position.y + TITLE_BAR_HEIGHT
			var width := (
				two_third_width
				if Netcode.preview_client_number != 1
				else third_width
			)

			# Set size and position.
			DisplayServer.window_set_size(Vector2i(width, window_height))
			DisplayServer.window_set_position(
				Vector2i(position_x, position_y)
			)
