class_name InputHandler
extends Node
## Handles all runtime keyboard shortcuts and debug toggles.
##
## Processes input actions configured in project.godot and updates G.settings
## and UI visibility accordingly. Automatically assigned as a child of Global
## singleton.


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_annotations"):
		G.settings.draw_annotations = not G.settings.draw_annotations
		G.print(
			"Debug annotations: %s" % (
				"ON" if G.settings.draw_annotations else "OFF"
			)
		)
	elif event.is_action_pressed("toggle_hud"):
		G.settings.show_hud = not G.settings.show_hud
		G.print("HUD: %s" % ("ON" if G.settings.show_hud else "OFF"))
		if is_instance_valid(G.hud):
			G.hud.visible = G.settings.show_hud
		if is_instance_valid(G.super_hud):
			G.super_hud.visible = G.settings.show_hud
	elif event.is_action_pressed("toggle_music"):
		G.settings.mute_music = not G.settings.mute_music
		G.print("Music: %s" % ("OFF" if G.settings.mute_music else "ON"))
		if is_instance_valid(G.audio):
			G.audio.apply_music_mute()
	elif event.is_action_pressed("take_screenshot"):
		if Netcode.is_preview:
			G.utils.take_screenshot()
	elif event.is_action_pressed("toggle_perf_tracker"):
		G.settings.show_perf_tracker = not G.settings.show_perf_tracker
		G.print(
			"PerfPanel: %s" % (
				"ON" if G.settings.show_perf_tracker else "OFF"
			)
		)
		if is_instance_valid(G.super_hud):
			G.super_hud.toggle_perf_tracker()
	elif event.is_action_pressed("toggle_debug_console"):
		G.settings.show_debug_console = not G.settings.show_debug_console
		G.print(
			"DebugConsole: %s" % (
				"ON" if G.settings.show_debug_console else "OFF"
			)
		)
		if is_instance_valid(G.super_hud):
			G.super_hud.toggle_debug_console()
	elif event.is_action_pressed("toggle_debug_player_state"):
		G.settings.show_debug_player_state = (
			not G.settings.show_debug_player_state
		)
		G.print(
			"DebugPlayerState: %s" % (
				"ON" if G.settings.show_debug_player_state else "OFF"
			)
		)
		if is_instance_valid(G.super_hud):
			G.super_hud.toggle_player_state_list()
	elif event.is_action_pressed("toggle_pause"):
		G.print(
			"Requesting server %s" % (
				"UNPAUSE" if Netcode.frame_driver.is_paused else "PAUSE"
			)
		)
		if G.settings.is_server_pause_enabled:
			Netcode.frame_driver.client_request_toggle_pause()
			get_viewport().set_input_as_handled()
