class_name SidePanelManager
extends CanvasLayer
## Container that manages a stack of SidePanelPage
## instances with slide animations. Owns the
## background overlay and handles cascading close.


signal closed

const _SLIDE_IN_DURATION := 0.2
const _SLIDE_OUT_DURATION := 0.1

@export var _settings_page_scene: PackedScene

var _player: Player
var _device_config: DeviceConfig
var _panel_stack: Array[SidePanelPage] = []
var _is_closing := false


func open(player: Player) -> void:
	G.log.print("[SidePanelManager] Opened")
	_player = player
	_resolve_device_config()

	# Push the initial settings page.
	var page: SettingsPage = (
		_settings_page_scene.instantiate())
	push_page(page)

	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func push_page(page: SidePanelPage) -> void:
	# Disable input on current top page.
	if not _panel_stack.is_empty():
		_panel_stack.back().is_input_active = false

	page.setup(self, _player, _device_config)
	_panel_stack.append(page)
	%PanelStack.add_child(page)
	# Size the page to fill the PanelStack. The
	# page root is not anchor-managed so
	# position.x can be tweened for sliding.
	page.size = %PanelStack.size
	page.build_ui()
	page.rebuild_row_list()
	page._set_focus(0)
	page.prime_input_state()
	_animate_slide_in(page)


func pop_page() -> void:
	if _is_closing:
		return
	if _panel_stack.size() <= 1:
		# Last page. Close everything.
		close_all()
		return

	var top_page: SidePanelPage = (
		_panel_stack.pop_back())
	top_page.is_input_active = false
	_animate_slide_out(
		top_page,
		func() -> void:
			top_page.queue_free(),
	)

	# Re-enable input on the new top page.
	if not _panel_stack.is_empty():
		var new_top: SidePanelPage = _panel_stack.back()
		new_top.is_input_active = true
		# Prime input state to avoid phantom
		# "just pressed" from keys held during
		# the sub-panel.
		new_top.prime_input_state()

	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func close_all() -> void:
	if _is_closing:
		return
	_is_closing = true
	G.log.print("[SidePanelManager] Closed")

	# Save level preferences if the level pref
	# page exists in the stack.
	for page in _panel_stack:
		if page is LevelPrefPage:
			page.save_level_preferences()
			break
	G.local_settings.save_settings()

	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")

	G.is_settings_ui_shown = false
	G.settings_ui_player = null
	closed.emit()
	queue_free()


func get_device_config() -> DeviceConfig:
	return _device_config


func _resolve_device_config() -> void:
	# In lobby, player_id = -(lobby_id + 1).
	var lobby_id: int = (
		-((_player.player_id) + 1))
	_device_config = (
		G.input_device_manager
			.get_device_for_player(lobby_id))


func _animate_slide_in(
	page: SidePanelPage,
) -> void:
	# Start off-screen to the right.
	var width: float = %PanelStack.size.x
	page.position.x = width
	var tween := create_tween()
	tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		page, "position:x",
		0.0, _SLIDE_IN_DURATION,
	).set_ease(
		Tween.EASE_OUT,
	).set_trans(
		Tween.TRANS_CUBIC,
	)


func _animate_slide_out(
	page: SidePanelPage,
	on_complete: Callable,
) -> void:
	var width: float = %PanelStack.size.x
	var tween := create_tween()
	tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		page, "position:x",
		width, _SLIDE_OUT_DURATION,
	).set_ease(
		Tween.EASE_IN,
	).set_trans(
		Tween.TRANS_CUBIC,
	)
	tween.tween_callback(on_complete)


func _unhandled_input(event: InputEvent) -> void:
	if _is_closing:
		return
	if event.is_action_pressed(&"toggle_pause"):
		close_all()
		get_viewport().set_input_as_handled()
