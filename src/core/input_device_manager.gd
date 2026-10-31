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
## focus in/out.
var is_text_input_captured := false

## H119 key trace: a ring of recent movement-key events
## and move-action changes. PlayerActionSource dumps it
## when leftward movement stops while A is still held,
## so a playtest captures what the input layer saw.
const _KEY_TRACE_MAX := 160

var _key_trace: Array[String] = []


## Records one movement-key event in the trace ring.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode not in [
		KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT
	] and key_event.physical_keycode not in [
		KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT
	]:
		return
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
