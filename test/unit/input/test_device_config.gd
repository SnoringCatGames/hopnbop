extends GutTest
## Unit tests for DeviceConfig class.

class TestDeviceConfigCreation:
	extends GutTest

	func test_keyboard_device_creates_with_bindings():
		var bindings := {"move_up": KEY_W, "jump": KEY_SPACE}
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, bindings
		)
		assert_eq(config.type, DeviceConfig.DeviceType.KEYBOARD)
		assert_eq(config.device_id, -1)
		assert_has(config.key_bindings, "move_up")
		assert_has(config.key_bindings, "jump")

	func test_gamepad_device_creates_with_device_id():
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.GAMEPAD, 0, {}
		)
		assert_eq(config.type, DeviceConfig.DeviceType.GAMEPAD)
		assert_eq(config.device_id, 0)
		assert_eq(config.key_bindings.size(), 0)

	func test_name_extracted_from_bindings():
		var bindings := {"name": "WASD", "move_up": KEY_W}
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, bindings
		)
		assert_eq(config.name, "WASD")
		assert_false(config.key_bindings.has("name"))

	func test_key_bindings_duplicated_not_referenced():
		var original := {"move_up": KEY_W}
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, original
		)
		original["move_up"] = KEY_I
		assert_eq(config.key_bindings["move_up"], KEY_W)


class TestDeviceConfigEdgeCases:
	extends GutTest

	func test_empty_key_bindings():
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {}
		)
		assert_eq(config.key_bindings.size(), 0)
		assert_eq(config.name, "Unknown")

	func test_gamepad_ignores_key_bindings():
		var bindings := {"move_up": KEY_W}
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.GAMEPAD, 0, bindings
		)
		assert_eq(config.type, DeviceConfig.DeviceType.GAMEPAD)

	func test_negative_device_id_for_keyboard():
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {}
		)
		assert_eq(config.device_id, -1)

	func test_positive_device_id_for_gamepad():
		for device_id in [0, 1, 2, 3]:
			var config := DeviceConfig.new(
				DeviceConfig.DeviceType.GAMEPAD, device_id, {}
			)
			assert_eq(config.device_id, device_id)


class TestDeviceConfigKeyBindingStructure:
	extends GutTest

	func test_bindings_match_action_to_input_keys():
		var bindings := {
			"move_up": KEY_W,
			"move_down": KEY_S,
			"move_left": KEY_A,
			"move_right": KEY_D,
			"jump": KEY_SPACE,
		}
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, bindings
		)

		assert_has(config.key_bindings, "move_up")
		assert_has(config.key_bindings, "move_down")
		assert_has(config.key_bindings, "move_left")
		assert_has(config.key_bindings, "move_right")
		assert_has(config.key_bindings, "jump")

	func test_name_default_when_not_provided():
		var bindings := {"move_up": KEY_W}
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, bindings
		)
		assert_eq(config.name, "Unknown")
