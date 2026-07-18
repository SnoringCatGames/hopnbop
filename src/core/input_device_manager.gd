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
