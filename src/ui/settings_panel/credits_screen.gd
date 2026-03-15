class_name CreditsScreen
extends Screen
## Full-screen credits screen with centered text.
## Closes on any left/right/trigger input from any
## device, or on ESC/pause input. Also provides a
## visible close button at the bottom of the screen.


const _ACTIVATION_DELAY_SEC := 0.2

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat

var _return_screen_type := ScreensMain.ScreenType.UNKNOWN
var _poller: AnyDeviceInputPoller
var _time_open := 0.0
var _is_dismissed := false
var _close_row_hovered := false


func _enter_tree() -> void:
	super._enter_tree()
	G.credits_screen = self


func _ready() -> void:
	%CloseRow.gui_input.connect(
		_on_close_row_gui_input)
	%CloseRow.mouse_entered.connect(
		_on_close_row_mouse_entered)
	%CloseRow.mouse_exited.connect(
		_on_close_row_mouse_exited)
	%Icon.custom_minimum_size = (
		%Icon.texture.get_size() * 2)


func set_return_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	_return_screen_type = screen_type


func on_open() -> void:
	_time_open = 0.0
	_is_dismissed = false
	_close_row_hovered = false
	_poller = AnyDeviceInputPoller.new()
	_poller.prime()
	_update_close_row_style()


func on_close() -> void:
	pass


func _process(delta: float) -> void:
	if not visible:
		return
	_time_open += delta
	if _time_open < _ACTIVATION_DELAY_SEC:
		# Still in delay. Pump poller to keep
		# prev_* state fresh but ignore output.
		_poller.poll(delta)
		return

	_poller.poll(delta)
	if (_poller.left_just
			or _poller.right_just
			or _poller.trigger_just):
		_on_close_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (event.is_action_pressed(&"ui_cancel")
			or event.is_action_pressed(&"toggle_pause")
			or event.is_action_pressed(&"close_menu")):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	if _is_dismissed:
		return
	_is_dismissed = true
	G.screens.client_open_screen(_return_screen_type)


func _update_close_row_style() -> void:
	if _close_row_hovered:
		%CloseRow.add_theme_stylebox_override(
			"panel", _focus_style)
	else:
		%CloseRow.add_theme_stylebox_override(
			"panel", _unfocused_style)


func _on_close_row_gui_input(
	event: InputEvent,
) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if (mb.pressed
				and mb.button_index
				== MOUSE_BUTTON_LEFT):
			_on_close_pressed()


func _on_close_row_mouse_entered() -> void:
	_close_row_hovered = true
	_update_close_row_style()


func _on_close_row_mouse_exited() -> void:
	_close_row_hovered = false
	_update_close_row_style()
