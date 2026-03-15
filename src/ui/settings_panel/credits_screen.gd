class_name CreditsScreen
extends Screen
## Full-screen credits screen with centered text.
## Closes on any left/right/trigger input from any
## device, or on ESC/pause input. Also provides a
## visible close button at the bottom of the screen.


const _ACTIVATION_DELAY_SEC := 0.2

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat

var _return_screen_type := (
	ScreensMain.ScreenType.UNKNOWN)
var _navigator := ScreenFocusNavigator.new()
var _time_open := 0.0
var _is_dismissed := false


func _enter_tree() -> void:
	super._enter_tree()
	G.credits_screen = self


func _ready() -> void:
	%CloseRow.gui_input.connect(
		_on_close_row_gui_input)
	%CloseRow.focus_entered.connect(
		_update_close_row_style)
	%CloseRow.focus_exited.connect(
		_update_close_row_style)
	%Icon.custom_minimum_size = (
		%Icon.texture.get_size() * 2)


func set_return_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	_return_screen_type = screen_type


func on_open() -> void:
	_time_open = 0.0
	_is_dismissed = false
	var items: Array[Control] = [%CloseRow]
	_navigator.set_focusable_list(items)
	_navigator.prime()


func on_close() -> void:
	pass


func _process(delta: float) -> void:
	if not visible:
		return
	_time_open += delta
	if _time_open < _ACTIVATION_DELAY_SEC:
		# Still in delay. Pump navigator to
		# keep prev_* state fresh but ignore
		# output.
		_navigator.poll(delta)
		return

	if _navigator.poll(delta):
		_on_close_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (event.is_action_pressed(&"ui_cancel")
			or event.is_action_pressed(
				&"toggle_pause")
			or event.is_action_pressed(
				&"close_menu")):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	if _is_dismissed:
		return
	_is_dismissed = true
	G.screens.client_open_screen(
		_return_screen_type)


func _update_close_row_style() -> void:
	if %CloseRow.has_focus():
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
