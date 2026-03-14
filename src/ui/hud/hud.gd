class_name Hud
extends PanelContainer


@onready var player_list: PlayerList = %PlayerList
@onready var match_start_countdown: MatchStartCountdown = (
	$MatchStartCountdown)


func _enter_tree() -> void:
	G.hud = self


func _ready() -> void:
	G.log.log_system_ready("Hud")

	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	%PlayerOverheadLabels.set_up()

	# Wait for G.settings to be assigned.
	await get_tree().process_frame

	self.visible = G.settings.show_hud


func update_visibility() -> void:
	if Netcode.is_server:
		return

	visible = true

	match G.screens.current_screen:
		ScreensMain.ScreenType.GODOT_SPLASH, \
		ScreensMain.ScreenType.SCG_SPLASH, \
		ScreensMain.ScreenType.CONSENT, \
		ScreensMain.ScreenType.AUTH, \
		ScreensMain.ScreenType.LOADING, \
		ScreensMain.ScreenType.TERMS, \
		ScreensMain.ScreenType.PRIVACY, \
		ScreensMain.ScreenType.DATA_DELETION:
			visible = false
		ScreensMain.ScreenType.GAME_OVER, \
		ScreensMain.ScreenType.PAUSE:
			pass
		ScreensMain.ScreenType.LOBBY:
			pass
		ScreensMain.ScreenType.GAME:
			pass
		_:
			Netcode.ensure(false)


func start_match_countdown() -> void:
	if Netcode.is_server:
		return
	match_start_countdown.start_countdown()
