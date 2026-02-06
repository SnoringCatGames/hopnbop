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


func _ready() -> void:
	G.log.log_system_ready("AudioMain")

	if Netcode.is_server:
		for child in get_children():
			child.queue_free()
		return


func client_open_screen(screen_type: ScreenType) -> void:
	Netcode.check_is_client()

	if screen_type == current_screen:
		# Already there!
		return

	var previous_screen_type := current_screen
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

	G.loading_screen.visible = screen_type == ScreenType.LOADING
	G.game_over_screen.visible = screen_type == ScreenType.GAME_OVER
	G.pause_screen.visible = screen_type == ScreenType.PAUSE
	G.godot_splash_screen.visible = screen_type == ScreenType.GODOT_SPLASH
	G.scg_splash_screen.visible = screen_type == ScreenType.SCG_SPLASH

	var ends_game := (
		[
			ScreenType.GODOT_SPLASH,
			ScreenType.SCG_SPLASH,
			ScreenType.LOADING,
			ScreenType.GAME_OVER,
			ScreenType.LOBBY,
		].has(screen_type)
	)
	if ends_game and G.local_session.is_game_active:
		G.game_panel.client_exit_game()

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
