class_name DeviceConfig
extends RefCounted
## Configuration for a single input device.
##
## Used by InputDeviceManager to assign input devices to local players.
## Supports both gamepad device IDs and keyboard key bindings.

## Device type enumeration.
enum DeviceType {
	KEYBOARD,
	GAMEPAD,
}

const KEYBOARD_DEVICE_ID := -1

## Type of device (KEYBOARD or GAMEPAD).
var type: DeviceType

var name: StringName

## Device identifier.
## For KEYBOARD: -1 (keyboards don't have device IDs).
## For GAMEPAD: 0-based device index from Input API.
var device_id: int

## Key bindings for keyboard players.
## Dictionary mapping action names to physical key codes.
## Only used when type == KEYBOARD.
## Example: {"move_left": KEY_A, "move_right": KEY_D, "jump": KEY_SPACE}
var key_bindings: Dictionary


func _init(
		p_type: DeviceType,
		p_device_id: int,
		p_key_bindings: Dictionary = {}) -> void:
	type = p_type
	device_id = p_device_id
	name = p_key_bindings.get("name", "Unknown")
	if p_type == DeviceType.GAMEPAD:
		name = get_controller_device_name(device_id)
	key_bindings = p_key_bindings.duplicate()
	key_bindings.erase("name")


static func get_controller_device_name(p_device_id: int) -> StringName:
	return "GamePad_%d" % p_device_id
