class_name InputDeviceManager
extends Node
## Manages input device assignment to local players.
##
## Enables multiple players on a single client to have independent input
## sources by mapping device configurations to local player indices.
## Supports both gamepad device IDs and keyboard key bindings.

## Predefined keyboard binding presets for multiple keyboard players.
## Each preset maps action names to physical key codes.
const KEYBOARD_PARTITION_BINDINGS := [
	{
		"name": "WASD",
		"move_up": KEY_W,
		"move_down": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
	},
	{
		"name": "IJKL",
		"move_up": KEY_I,
		"move_down": KEY_K,
		"move_left": KEY_J,
		"move_right": KEY_L,
		"jump": KEY_SHIFT,
	},
	{
		"name": "ArrowKeys",
		"move_up": KEY_UP,
		"move_down": KEY_DOWN,
		"move_left": KEY_LEFT,
		"move_right": KEY_RIGHT,
		"jump": KEY_ENTER,
	},
	{
		"name": "NumPad",
		"move_up": KEY_KP_8,
		"move_down": KEY_KP_5,
		"move_left": KEY_KP_4,
		"move_right": KEY_KP_6,
		"jump": KEY_KP_0,
	},
]

## Maps local player index to device configuration.
## Dictionary<int, DeviceConfig>
var player_device_map := {}

## True while a text field (friend code, party code, chat) has grabbed
## the physical keyboard. While set, get_is_action_pressed reports no
## keyboard action as pressed, so typing can't leak into character
## control or side-panel navigation. Gamepad input is unaffected, so
## other local players keep playing. TextInputRow toggles this on
## focus in/out. Changes are noted in the H119 key trace.
var is_text_input_captured := false:
	set(value):
		if is_text_input_captured == value:
			return
		is_text_input_captured = value
		key_trace_note("text_capture=%s" % str(value))

## H119 key trace: a ring of recent movement-key events
## and move-action changes. PlayerActionSource dumps it
## when leftward movement stops during an A hold, so a
## playtest captures what the input layer saw.
const _KEY_TRACE_MAX := 160

## Physical keys the trace records.
const _TRACED_PHYSICAL_KEYS: Array[int] = [
	KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT,
]

var _key_trace: Array[String] = []

## Dictionary<int, bool>: whether the last recorded event
## for a traced key was a press (true) or a release (false).
var _last_key_is_press := {}

## How many traces have been dumped. Tests read this
## because the log itself does not print in test runs.
var key_trace_dump_count := 0

var _trace_dumped := false


## Records one movement-key event in the trace ring.
## Runs in _input so events a Control consumes (a
## focused LineEdit typing the key, say) still show.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	var physical := key_event.physical_keycode
	if physical == 0:
		physical = key_event.keycode
	if (key_event.keycode not in _TRACED_PHYSICAL_KEYS
			and physical not in _TRACED_PHYSICAL_KEYS):
		return
	handle_traced_key_event(
		key_event,
		Input.is_physical_key_pressed(physical),
	)


## Records one traced key event in the ring, and dumps
## the trace when an echo arrives for a key Input
## reports as up (the OS still repeats a key Godot
## believes is released). is_input_pressed is a
## parameter so tests can drive both halves.
func handle_traced_key_event(
		key_event: InputEventKey,
		is_input_pressed: bool,
) -> void:
	var physical := key_event.physical_keycode
	if physical == 0:
		physical = key_event.keycode
	key_trace_note(
		"key code=%d phys=%d pressed=%s echo=%s unicode=%d"
		% [
			key_event.keycode,
			key_event.physical_keycode,
			str(key_event.pressed),
			str(key_event.echo),
			key_event.unicode,
		]
	)
	_last_key_is_press[physical] = key_event.pressed
	if not key_event.pressed and not key_event.echo:
		# A real release ends the hold. The next
		# press may dump again.
		_trace_dumped = false
	if (key_event.pressed and key_event.echo
			and not is_input_pressed):
		dump_key_trace(
			"echo for key %d while Input reports it up"
			% physical,
		)


## Dumps the trace ring once per hold. The dump uses
## the default log category, which default settings do
## not filter out, so a playtest on stock settings
## captures it (PlayerActions is filtered by default).
func dump_key_trace(reason: String) -> bool:
	if _trace_dumped:
		return false
	_trace_dumped = true
	key_trace_dump_count += 1
	Netcode.print(
		"H119TRACE %s\n%s" % [
			reason,
			"\n".join(get_key_trace()),
		],
		NetworkLogger.CATEGORY_DEFAULT,
	)
	return true


## True when the last recorded event for the key was
## a press, so no key-up has been seen for it.
func get_last_key_is_press(physical: int) -> bool:
	return bool(_last_key_is_press.get(physical, false))


## The dump reason when move_left just went false
## while the last A event is still a press: the
## release had no key-up event behind it. Returns an
## empty string when this frame is not that case.
func get_move_left_release_reason(
		ml_pressed: bool,
		ml_was: bool,
) -> String:
	if (ml_was and not ml_pressed
			and get_last_key_is_press(KEY_A)):
		return (
			"move_left released with no A key-up"
			+ " (last A event is a press)")
	return ""


## Appends one timestamped line to the trace ring.
func key_trace_note(text: String) -> void:
	_key_trace.append(
		"%d %s" % [Time.get_ticks_msec(), text])
	if _key_trace.size() > _KEY_TRACE_MAX:
		_key_trace.remove_at(0)


## The trace ring, oldest first.
func get_key_trace() -> Array[String]:
	return _key_trace.duplicate()


func _ready() -> void:
	G.log.log_system_ready("InputDeviceManager")


## App and window focus changes go in the ring: a
## focus loss can clear the pressed keys with no key
## event, which is one way a hold can end early.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			key_trace_note("app_focus_out")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			key_trace_note("app_focus_in")
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			key_trace_note("window_focus_out")
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			key_trace_note("window_focus_in")


## Assigns a device configuration to a local player index.
func assign_device_to_player(
		local_player_index: int,
		device_config: DeviceConfig) -> void:
	player_device_map[local_player_index] = device_config
	Netcode.print("Assigned device to player %d: type=%s, device_id=%d" %
		[local_player_index, device_config.name, device_config.device_id],
		NetworkLogger.CATEGORY_PLAYER_ACTIONS)


func unassign_device_from_player(local_player_index: int) -> void:
	player_device_map.erase(local_player_index)


## Gets the device configuration for a local player.
func get_device_for_player(local_player_index: int) -> DeviceConfig:
	return player_device_map.get(local_player_index)


## Checks if a device is assigned to a local player.
func has_device_for_player(local_player_index: int) -> bool:
	return player_device_map.has(local_player_index)


## Gets the input state for an action using device-specific polling.
func get_is_action_pressed(action: StringName, device_config: DeviceConfig) -> bool:
	match device_config.type:
		DeviceConfig.DeviceType.KEYBOARD:
			# While a text field has captured the keyboard, it owns
			# every physical key: suppress keyboard actions so typing
			# a code or chat message can't also move a character or
			# navigate a panel. Gamepad players (branch below) keep
			# control.
			if is_text_input_captured:
				return false
			# Use physical key code from bindings.
			if device_config.key_bindings.has(action):
				var key_code: int = device_config.key_bindings[action]
				return Input.is_physical_key_pressed(key_code)
		DeviceConfig.DeviceType.GAMEPAD:
			# Use Godot's device-specific input polling.
			# NOTE: This requires action names to be defined in InputMap.
			return Input.is_action_pressed(action, device_config.device_id)
		_:
			Netcode.fatal()
	return false


## Clears all device assignments.
func clear_all_assignments() -> void:
	player_device_map.clear()
