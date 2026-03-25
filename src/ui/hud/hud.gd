class_name Hud
extends PanelContainer


const _ASPECT_RATIO_THRESHOLD := 2.0
const _SIDE_PANEL_CAMERA_OFFSET_PX := 96.0


@onready var player_list: PlayerList = %PlayerList
@onready var _player_list_vertical: PlayerList = (
	%PlayerListVertical)
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

	get_tree().root.size_changed.connect(
		_on_window_resized)
	_apply_layout()


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
		ScreensMain.ScreenType.PAUSE, \
		ScreensMain.ScreenType.LEADERBOARD, \
		ScreensMain.ScreenType.MY_STATS, \
		ScreensMain.ScreenType.CREDITS, \
		ScreensMain.ScreenType.LANGUAGE:
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


func _on_window_resized() -> void:
	_apply_layout()


func _apply_layout() -> void:
	var window_size := DisplayServer.window_get_size()
	var aspect_ratio := (
		float(window_size.x) / float(window_size.y))
	var use_vertical := aspect_ratio >= _ASPECT_RATIO_THRESHOLD

	player_list.visible = not use_vertical
	_player_list_vertical.visible = use_vertical

	var offset_px: float = (
		_SIDE_PANEL_CAMERA_OFFSET_PX
		if use_vertical
		else 0.0)
	G.pixel_viewport_manager.set_side_panel_offset(
		offset_px)
