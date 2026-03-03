class_name SCGSplashScreen
extends Screen

func _enter_tree() -> void:
	super._enter_tree()
	G.scg_splash_screen = self


func on_open() -> void:
	super.on_open()

	G.audio.play_sound("scg_splash")

	await get_tree().create_timer(
		G.settings.scg_splash_duration_sec,
	).timeout

	G.screens.client_open_screen(
		ScreensMain.ScreenType.LOBBY)
