class_name InputHandler
extends Node
## Handles all runtime keyboard shortcuts and debug toggles.
##
## Processes input actions configured in project.godot and updates G.settings
## and UI visibility accordingly. Automatically assigned as a child of Global
## singleton.


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_annotations"):
		if not Netcode.is_debug:
			return
		G.settings.draw_annotations = not G.settings.draw_annotations
		Netcode.print(
			"Debug annotations: %s" % (
				"ON" if G.settings.draw_annotations else "OFF"
			)
		)
	elif event.is_action_pressed("toggle_hud"):
		# Check if any HUD/debug element is currently on.
		var any_on = (
			G.settings.show_hud
			or G.settings.draw_annotations
			or G.settings.show_debug_console
			or G.settings.show_debug_player_state
			or G.settings.show_perf_tracker
			or G.settings.show_player_overhead_labels
			or G.settings.show_player_outlines
		)

		# If anything is on, turn everything off.
		# If everything is off, turn everything on.
		var new_state = not any_on

		G.settings.show_hud = new_state
		G.settings.show_player_overhead_labels = new_state
		G.settings.show_player_outlines = new_state

		# Preview-only settings: only enable when in preview mode.
		var is_debug_and_new_state = new_state and Netcode.is_debug
		G.settings.draw_annotations = is_debug_and_new_state
		G.settings.show_debug_console = is_debug_and_new_state
		G.settings.show_debug_player_state = is_debug_and_new_state
		G.settings.show_perf_tracker = is_debug_and_new_state
		# Network simulation panel is not included in the "all on"
		# toggle — it must be opened explicitly via F7.
		G.settings.show_network_simulation = false

		Netcode.print(
			"All HUD/Debug: %s" % ("ON" if new_state else "OFF")
		)

		# Update UI components.
		if is_instance_valid(G.hud):
			G.hud.visible = new_state
		if is_instance_valid(G.super_hud) and Netcode.is_debug:
			G.super_hud.visible = is_debug_and_new_state
			G.super_hud.toggle_perf_tracker()
			G.super_hud.toggle_debug_console()
			G.super_hud.toggle_player_state_list()
		if is_instance_valid(G.player_overhead_labels):
			G.player_overhead_labels.visible = new_state
		if is_instance_valid(G.player_annotations):
			G.player_annotations.visible = new_state
		_update_player_outlines()
	elif event.is_action_pressed("toggle_music"):
		G.settings.mute_music = not G.settings.mute_music
		Netcode.print("Music: %s" % ("OFF" if G.settings.mute_music else "ON"))
		if is_instance_valid(G.audio):
			G.audio.apply_music_mute()
	elif event.is_action_pressed("take_screenshot"):
		if Netcode.is_debug:
			G.utils.take_screenshot()
	elif event.is_action_pressed("toggle_perf_tracker"):
		if not Netcode.is_debug:
			return
		G.settings.show_perf_tracker = not G.settings.show_perf_tracker
		Netcode.print(
			"PerfPanel: %s" % (
				"ON" if G.settings.show_perf_tracker else "OFF"
			)
		)
		if is_instance_valid(G.super_hud):
			G.super_hud.toggle_perf_tracker()
	elif event.is_action_pressed("toggle_debug_console"):
		if not Netcode.is_debug:
			return
		G.settings.show_debug_console = not G.settings.show_debug_console
		Netcode.print(
			"DebugConsole: %s" % (
				"ON" if G.settings.show_debug_console else "OFF"
			)
		)
		if is_instance_valid(G.super_hud):
			G.super_hud.toggle_debug_console()
	elif event.is_action_pressed("toggle_debug_player_state"):
		if not Netcode.is_debug:
			return
		G.settings.show_debug_player_state = (
			not G.settings.show_debug_player_state
		)
		Netcode.print(
			"DebugPlayerState: %s" % (
				"ON" if G.settings.show_debug_player_state else "OFF"
			)
		)
		if is_instance_valid(G.super_hud):
			G.super_hud.toggle_player_state_list()
	elif event.is_action_pressed("toggle_network_simulation"):
		if not Netcode.is_debug:
			return
		G.settings.show_network_simulation = (
			not G.settings.show_network_simulation
		)
		Netcode.print(
			"NetworkSimulation: %s" % (
				"ON"
				if G.settings.show_network_simulation
				else "OFF"
			)
		)
		if is_instance_valid(G.super_hud):
			G.super_hud.toggle_network_simulation()
	elif event.is_action_pressed("toggle_pause"):
		Netcode.print(
			"Requesting server %s" % (
				"UNPAUSE" if Netcode.frame_driver.is_paused else "PAUSE"
			)
		)
		if G.settings.is_server_pause_enabled:
			Netcode.frame_driver.client_request_toggle_pause()
			get_viewport().set_input_as_handled()


func _update_player_outlines() -> void:
	if not is_instance_valid(G.level):
		return
	for player in G.level.players_by_id.values():
		if is_instance_valid(player) and player.has_method("update_outline"):
			player.update_outline()
