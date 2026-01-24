class_name GodotSplashScreen
extends Screen

func _enter_tree() -> void:
	super._enter_tree()
	G.godot_splash_screen = self


func on_open() -> void:
	super.on_open()

	await get_tree().create_timer(G.settings.godot_splash_duration_sec).time

	G.screens.client_open_screen(ScreensMain.ScreenType.SCG_SPLASH)
