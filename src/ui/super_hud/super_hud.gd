class_name SuperHud
extends PanelContainer


func _enter_tree() -> void:
	G.super_hud = self


func _ready() -> void:
	G.log.log_system_ready("SuperHud")

	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	# Wait for G.settings to be assigned.
	await get_tree().process_frame

	# Respect master HUD toggle.
	self.visible = G.settings.show_hud

	# Initialize component visibility based on current settings.
	_sync_component_visibility()


func _sync_component_visibility() -> void:
	# Sync all component visibility with current settings.
	%DebugConsole.visible = G.settings.show_debug_console
	%PlayerStateList.visible = G.settings.show_debug_player_state
	%PerfTrackerPanel.visible = G.settings.show_perf_tracker
	%NetworkSimulationPanel.visible = (
		G.settings.show_network_simulation
	)


func toggle_debug_console() -> void:
	if Netcode.is_server:
		return

	%DebugConsole.visible = not %DebugConsole.visible
	Netcode.print(
		"Toggled DebugConsole: %s" %
		("visible" if %DebugConsole.visible else "hidden"),
		NetworkLogger.CATEGORY_INTERACTION,
	)


func toggle_player_state_list() -> void:
	if Netcode.is_server:
		return

	%PlayerStateList.visible = G.settings.show_debug_player_state
	Netcode.print(
		"PlayerStateList: %s" %
		("visible" if %PlayerStateList.visible else "hidden"),
		NetworkLogger.CATEGORY_INTERACTION,
	)


func toggle_perf_tracker() -> void:
	if Netcode.is_server:
		return

	%PerfTrackerPanel.visible = not %PerfTrackerPanel.visible
	Netcode.print(
		"Toggled PerfTracker: %s" %
		("visible" if %PerfTrackerPanel.visible else "hidden"),
		NetworkLogger.CATEGORY_INTERACTION,
	)


func toggle_network_simulation() -> void:
	if Netcode.is_server:
		return

	%NetworkSimulationPanel.visible = (
		not %NetworkSimulationPanel.visible
	)
	Netcode.print(
		"Toggled NetworkSimulation: %s" %
		(
			"visible"
			if %NetworkSimulationPanel.visible
			else "hidden"
		),
		NetworkLogger.CATEGORY_INTERACTION,
	)
