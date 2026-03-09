class_name ConfirmOverlay
extends CanvasLayer
## Modal confirmation dialog. Dynamically
## instantiated, added to the scene tree root,
## and queue_free'd on dismiss.
##
## Supports accept-only mode (no reject button)
## and device-specific or any-device input.


const _ACTIVATION_DELAY_SEC := 0.2

var _focus_style: StyleBoxTexture = preload(
	"res://src/ui/settings_panel/"
	+ "focus_border_stylebox.tres")
var _unfocused_style: StyleBoxFlat = preload(
	"res://src/ui/settings_panel/"
	+ "unfocused_stylebox.tres")

var _on_accept: Callable
var _on_reject: Callable
var _device_config: DeviceConfig
var _poller: AnyDeviceInputPoller
var _has_reject := false
var _focused_on_accept := true
var _time_open := 0.0
var _is_dismissed := false

# Device-specific input state.
var _prev_up := false
var _prev_down := false
var _prev_left := false
var _prev_right := false
var _prev_trigger := false


func open(
	message: String,
	accept_text: String,
	on_accept: Callable,
	reject_text: String = "",
	on_reject: Callable = Callable(),
	device_config: DeviceConfig = null,
) -> void:
	_on_accept = on_accept
	_on_reject = on_reject
	_device_config = device_config
	_has_reject = reject_text != ""

	%MessageLabel.text = message
	%AcceptLabel.text = accept_text

	if _has_reject:
		%RejectLabel.text = reject_text
		%RejectButton.visible = true
		_focused_on_accept = true
	else:
		%RejectButton.visible = false
		_focused_on_accept = true

	_update_focus()

	G.is_confirm_dialog_shown = true
	tree_exiting.connect(
		func() -> void:
			G.is_confirm_dialog_shown = false)

	# Set up input source.
	if _device_config == null:
		_poller = AnyDeviceInputPoller.new()
		_poller.prime()
	else:
		_prime_device_input()

	# Connect mouse clicks.
	%AcceptButton.gui_input.connect(
		_on_button_gui_input.bind(true))
	if _has_reject:
		%RejectButton.gui_input.connect(
			_on_button_gui_input.bind(false))

	# Connect mouse hover.
	%AcceptButton.mouse_entered.connect(
		func() -> void:
			_focused_on_accept = true
			_update_focus())
	if _has_reject:
		%RejectButton.mouse_entered.connect(
			func() -> void:
				_focused_on_accept = false
				_update_focus())


func _process(delta: float) -> void:
	_time_open += delta
	if _time_open < _ACTIVATION_DELAY_SEC:
		# Still in delay. Pump pollers to keep
		# prev_* state fresh but ignore output.
		if _poller != null:
			_poller.poll(delta)
		elif _device_config != null:
			_poll_device_input()
		return

	if _poller != null:
		_poller.poll(delta)
		if _has_reject:
			if _poller.up_just or _poller.down_just:
				_toggle_focus()
		if (_poller.left_just
				or _poller.right_just
				or _poller.trigger_just):
			_activate_focused()
	elif _device_config != null:
		var result := _poll_device_input()
		if _has_reject:
			if result.up_just or result.down_just:
				_toggle_focus()
		if (result.left_just
				or result.right_just
				or result.trigger_just):
			_activate_focused()


func _prime_device_input() -> void:
	if _device_config == null:
		return
	_prev_up = (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_up", _device_config))
	_prev_down = (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_down", _device_config))
	_prev_left = (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_left", _device_config))
	_prev_right = (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_right", _device_config))
	_prev_trigger = _is_trigger_pressed()


func _poll_device_input() -> Dictionary:
	var up := (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_up", _device_config))
	var down := (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_down", _device_config))
	var left := (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_left", _device_config))
	var right := (
		G.input_device_manager
			.get_is_action_pressed(
				&"move_right", _device_config))
	var trigger := _is_trigger_pressed()

	var up_just := up and not _prev_up
	var down_just := down and not _prev_down
	var left_just := left and not _prev_left
	var right_just := right and not _prev_right
	var trigger_just := trigger and not _prev_trigger

	_prev_up = up
	_prev_down = down
	_prev_left = left
	_prev_right = right
	_prev_trigger = trigger

	return {
		"up_just": up_just,
		"down_just": down_just,
		"left_just": left_just,
		"right_just": right_just,
		"trigger_just": trigger_just,
	}


func _is_trigger_pressed() -> bool:
	if (Input.is_physical_key_pressed(KEY_ENTER)
			or Input.is_physical_key_pressed(
				KEY_SPACE)):
		return true
	if (_device_config != null
			and _device_config.type
			== DeviceConfig.DeviceType.GAMEPAD):
		return Input.is_action_pressed(
			&"trigger_ui",
			_device_config.device_id)
	if _device_config == null:
		if Input.is_action_pressed(&"trigger_ui"):
			return true
	return false


func _toggle_focus() -> void:
	_focused_on_accept = not _focused_on_accept
	_update_focus()
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func _update_focus() -> void:
	if _focused_on_accept:
		%AcceptButton.add_theme_stylebox_override(
			"panel", _focus_style)
		if _has_reject:
			%RejectButton.add_theme_stylebox_override(
				"panel", _unfocused_style)
	else:
		%AcceptButton.add_theme_stylebox_override(
			"panel", _unfocused_style)
		if _has_reject:
			%RejectButton.add_theme_stylebox_override(
				"panel", _focus_style)


func _activate_focused() -> void:
	if _is_dismissed:
		return
	_is_dismissed = true
	if _focused_on_accept:
		if _on_accept.is_valid():
			_on_accept.call()
	else:
		if _on_reject.is_valid():
			_on_reject.call()
	queue_free()


func _on_button_gui_input(
	event: InputEvent,
	is_accept: bool,
) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if (mb.pressed
				and mb.button_index
				== MOUSE_BUTTON_LEFT):
			if _is_dismissed:
				return
			_is_dismissed = true
			if is_accept:
				if _on_accept.is_valid():
					_on_accept.call()
			else:
				if _on_reject.is_valid():
					_on_reject.call()
			queue_free()
