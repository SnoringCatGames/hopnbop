class_name ScreensMain
extends PanelContainer

enum ScreenType {
	UNKNOWN,
	GODOT_SPLASH,
	SCG_SPLASH,
	CONSENT,
	AUTH,
	LOADING,
	GAME_OVER,
	PAUSE,
	LOBBY,
	GAME,
	TERMS,
	PRIVACY,
	DATA_DELETION,
	LEADERBOARD,
	MY_STATS,
	CREDITS,
	LANGUAGE,
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

	Netcode.print(
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
		[ScreenType.LOADING, ScreenType.LOBBY],
		[ScreenType.GAME, ScreenType.GAME_OVER],
		[ScreenType.GAME, ScreenType.LOBBY],
		[ScreenType.GAME_OVER, ScreenType.LOBBY],
		[ScreenType.GAME_OVER, ScreenType.LOADING],
		[ScreenType.UNKNOWN, ScreenType.LOBBY],
		[ScreenType.UNKNOWN, ScreenType.GAME],
		[ScreenType.SCG_SPLASH, ScreenType.CONSENT],
		[ScreenType.SCG_SPLASH, ScreenType.AUTH],
		[ScreenType.SCG_SPLASH, ScreenType.LOBBY],
		[ScreenType.SCG_SPLASH, ScreenType.GAME],
		[ScreenType.CONSENT, ScreenType.AUTH],
		[ScreenType.CONSENT, ScreenType.LOBBY],
		[ScreenType.AUTH, ScreenType.LOBBY],
	]
	for pair in transition_pairs:
		if from_screen == pair[0] and to_screen == pair[1]:
			return true
	return false


func _perform_screen_switch(
	previous_screen_type: ScreenType,
	screen_type: ScreenType
) -> void:
	G.web_debug_watchdog.breadcrumb(  # FIXME(end-of-match-debug)
		"screens_main._perform_screen_switch.start",
		{
			"from": ScreenType.keys()[previous_screen_type],
			"to": ScreenType.keys()[screen_type],
		})
	current_screen = screen_type

	Netcode.print(
		"Switching screens: %s => %s" %
		[
			ScreenType.keys()[previous_screen_type],
			ScreenType.keys()[screen_type],
		],
		NetworkLogger.CATEGORY_USER_INTERACTION,
	)

	get_tree().paused = (
		screen_type not in [ScreenType.GAME, ScreenType.LOBBY])
	G.is_ui_interaction_mode_enabled = (
		screen_type not in [ScreenType.GAME, ScreenType.LOBBY])

	# CRITICAL FIX: Ensure ScreensMain is visible before showing any screen.
	if not Netcode.is_server:
		visible = true

	G.loading_screen.visible = screen_type == ScreenType.LOADING
	G.game_over_screen.visible = screen_type == ScreenType.GAME_OVER
	G.pause_screen.visible = screen_type == ScreenType.PAUSE
	G.godot_splash_screen.visible = screen_type == ScreenType.GODOT_SPLASH
	G.scg_splash_screen.visible = screen_type == ScreenType.SCG_SPLASH
	if is_instance_valid(G.consent_screen):
		G.consent_screen.visible = (
			screen_type == ScreenType.CONSENT)
	if is_instance_valid(G.auth_screen):
		G.auth_screen.visible = (
			screen_type == ScreenType.AUTH)
	if is_instance_valid(G.terms_screen):
		G.terms_screen.visible = (
			screen_type == ScreenType.TERMS)
	if is_instance_valid(G.privacy_screen):
		G.privacy_screen.visible = (
			screen_type == ScreenType.PRIVACY)
	if is_instance_valid(G.data_deletion_screen):
		G.data_deletion_screen.visible = (
			screen_type == ScreenType.DATA_DELETION)
	if is_instance_valid(G.leaderboard_screen):
		G.leaderboard_screen.visible = (
			screen_type == ScreenType.LEADERBOARD)
	if is_instance_valid(G.my_stats_screen):
		G.my_stats_screen.visible = (
			screen_type == ScreenType.MY_STATS)
	if is_instance_valid(G.credits_screen):
		G.credits_screen.visible = (
			screen_type == ScreenType.CREDITS)
	if is_instance_valid(G.language_screen):
		G.language_screen.visible = (
			screen_type == ScreenType.LANGUAGE)

	var ends_game := (
		[
			ScreenType.GODOT_SPLASH,
			ScreenType.SCG_SPLASH,
			ScreenType.CONSENT,
			ScreenType.AUTH,
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

	if screen_type == ScreenType.GAME:
		# Fade out the menu theme immediately. The main
		# theme starts after the match-start countdown
		# (triggered by GamePanel).
		G.audio.fade_out_menu_theme()

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
	G.web_debug_watchdog.breadcrumb("screens_main._perform_screen_switch.end")  # FIXME(end-of-match-debug)


func get_screen_from_type(
	screen_type: ScreenType,
) -> PlatformScreen:
	# Returns PlatformScreen (the common ancestor) so the
	# function can surface both Screen subclasses (loading,
	# game_over, my_stats, etc.) and PlatformAuthScreen /
	# PlatformConsentScreen subclasses, which are sibling
	# branches under PlatformScreen.
	var screen: PlatformScreen = null
	match screen_type:
		ScreenType.GODOT_SPLASH:
			screen = G.godot_splash_screen
		ScreenType.SCG_SPLASH:
			screen = G.scg_splash_screen
		ScreenType.CONSENT:
			screen = G.consent_screen
		ScreenType.AUTH:
			screen = G.auth_screen
		ScreenType.LOADING:
			screen = G.loading_screen
		ScreenType.GAME_OVER:
			screen = G.game_over_screen
		ScreenType.PAUSE:
			screen = G.pause_screen
		ScreenType.TERMS:
			screen = G.terms_screen
		ScreenType.PRIVACY:
			screen = G.privacy_screen
		ScreenType.DATA_DELETION:
			screen = G.data_deletion_screen
		ScreenType.LEADERBOARD:
			screen = G.leaderboard_screen
		ScreenType.MY_STATS:
			screen = G.my_stats_screen
		ScreenType.CREDITS:
			screen = G.credits_screen
		ScreenType.LANGUAGE:
			screen = G.language_screen
		ScreenType.LOBBY, ScreenType.GAME:
			screen = null
		_:
			Netcode.fatal("ScreensMain.get_screen_from_type")
	return screen
