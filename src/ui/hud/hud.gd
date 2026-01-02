class_name Hud
extends PanelContainer


func _enter_tree() -> void:
	G.hud = self


func _ready() -> void:
	# Wait for G.settings to be assigned.
	await get_tree().process_frame

	self.visible = G.settings.show_hud


func update_visibility() -> void:
	match G.screens.current_screen:
		ScreensMain.ScreenType.MAIN_MENU, \
		ScreensMain.ScreenType.GAME_OVER, \
		ScreensMain.ScreenType.WIN, \
		ScreensMain.ScreenType.PAUSE:
			pass
		ScreensMain.ScreenType.GAME:
			pass
		_:
			G.utils.ensure(false)
