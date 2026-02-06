class_name ScreensMain
extends PanelContainer

enum ScreenType {
	UNKNOWN,
	GODOT_SPLASH,
	SCG_SPLASH,
	LOADING,
	GAME_OVER,
	PAUSE,
	LOBBY,
	GAME,
}

var current_screen := ScreenType.UNKNOWN


func _enter_tree() -> void:
	G.screens = self

	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	# Explicitly set visible on clients.
	visible = true


func _ready() -> void:
	G.log.log_system_ready("ScreensMain")

	if Netcode.is_server:
		for child in get_children():
			child.queue_free()
		return

	G.print(
		"ScreensMain._ready() - visible=%s" % visible,
		NetworkLogger.CATEGORY_GAME_STATE
	)


func client_open_screen(screen_type: ScreenType) -> void:
	Netcode.check_is_client()

	if screen_type == current_screen:
		# Already there!
		return

	var previous_screen_type := current_screen
	var should_transition := _should_play_transition(
		previous_screen_type,
		screen_type
	)

	if should_transition and G.screen_transition:
		# Capture current screen, switch, then fade out the capture.
		G.screen_transition.transition_wipe(
			G.settings.screen_transition_duration,
			ScreenTransition.DEFAULT_PATTERN,
			ScreenTransition.DEFAULT_TILE_STYLE,
			func(): _perform_screen_switch(previous_screen_type, screen_type),
		)
	else:
		_perform_screen_switch(previous_screen_type, screen_type)


func _should_play_transition(
	from_screen: ScreenType,
	to_screen: ScreenType
) -> bool:
	# Play transitions for major screen changes involving lobby/match.
	var transition_pairs := [
		[ScreenType.LOBBY, ScreenType.LOADING],
		[ScreenType.LOADING, ScreenType.GAME],
		[ScreenType.GAME, ScreenType.GAME_OVER],
		[ScreenType.GAME_OVER, ScreenType.LOBBY],
		[ScreenType.UNKNOWN, ScreenType.LOBBY],
		[ScreenType.UNKNOWN, ScreenType.GAME],
		[ScreenType.SCG_SPLASH, ScreenType.LOBBY],
		[ScreenType.SCG_SPLASH, ScreenType.GAME],
	]
	for pair in transition_pairs:
		if from_screen == pair[0] and to_screen == pair[1]:
			return true
	return false


func _perform_screen_switch(
	previous_screen_type: ScreenType,
	screen_type: ScreenType
) -> void:
	current_screen = screen_type

	G.print(
		"Switching screens: %s => %s" %
		[
			ScreenType.keys()[previous_screen_type],
			ScreenType.keys()[screen_type],
		],
		NetworkLogger.CATEGORY_INTERACTION,
	)

	get_tree().paused = screen_type not in [ScreenType.GAME, ScreenType.LOBBY]

	# CRITICAL FIX: Ensure ScreensMain is visible before showing any screen.
	if not Netcode.is_server:
		visible = true

	G.loading_screen.visible = screen_type == ScreenType.LOADING
	G.game_over_screen.visible = screen_type == ScreenType.GAME_OVER
	G.pause_screen.visible = screen_type == ScreenType.PAUSE
	G.godot_splash_screen.visible = screen_type == ScreenType.GODOT_SPLASH
	G.scg_splash_screen.visible = screen_type == ScreenType.SCG_SPLASH

	if screen_type == ScreenType.LOADING:
		G.print(
			"Set LoadingScreen visible=true, actual=%s, ScreensMain.visible=%s, CanvasLayer.visible=%s" % [
				G.loading_screen.visible,
				visible,
				get_parent().visible if get_parent() else "no_parent"
			],
			NetworkLogger.CATEGORY_GAME_STATE
		)

	var ends_game := (
		[
			ScreenType.GODOT_SPLASH,
			ScreenType.SCG_SPLASH,
			ScreenType.GAME_OVER,
			ScreenType.LOBBY,
		].has(screen_type)
	)
	if ends_game and G.client_session.is_game_active:
		G.game_panel.client_exit_match()

	var plays_menu_theme := (
		[
			ScreenType.LOADING,
			ScreenType.GAME_OVER,
			ScreenType.PAUSE,
			ScreenType.LOBBY,
		].has(screen_type)
	)
	if plays_menu_theme:
		G.audio.fade_to_menu_theme()

	var plays_main_theme := [ScreenType.GAME].has(screen_type)
	if plays_main_theme:
		G.audio.fade_to_main_theme()

	if screen_type == ScreenType.GAME:
		G.game_panel.on_return_to_game_from_screen(previous_screen_type)
	elif screen_type == ScreenType.LOBBY:
		G.game_panel.on_return_to_lobby_from_screen(previous_screen_type)
	else:
		var screen := get_screen_from_type(screen_type)
		screen.on_open()

	if previous_screen_type == ScreenType.GAME:
		G.game_panel.on_left_game_to_screen(screen_type)
	elif previous_screen_type == ScreenType.LOBBY:
		G.game_panel.on_left_lobby_to_screen(screen_type)
	elif previous_screen_type != ScreenType.UNKNOWN:
		var previous_screen := get_screen_from_type(previous_screen_type)
		previous_screen.on_close()

	G.hud.update_visibility()


func get_screen_from_type(screen_type: ScreenType) -> Screen:
	match screen_type:
		ScreenType.GODOT_SPLASH:
			return G.godot_splash_screen
		ScreenType.SCG_SPLASH:
			return G.scg_splash_screen
		ScreenType.LOADING:
			return G.loading_screen
		ScreenType.GAME_OVER:
			return G.game_over_screen
		ScreenType.PAUSE:
			return G.pause_screen
		ScreenType.LOBBY:
			return null
		ScreenType.GAME:
			return null
		_:
			G.fatal("ScreensMain.get_screen_from_type")
			return null
