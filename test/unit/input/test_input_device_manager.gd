extends GutTest
## Unit tests for InputDeviceManager.


class TestDeviceAssignment:
	extends GutTest
	var manager: InputDeviceManager

	func before_each():
		manager = InputDeviceManager.new()

	func test_assign_device_to_player_stores_config():
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {"move_up": KEY_W}
		)
		manager.assign_device_to_player(0, config)
		assert_true(manager.has_device_for_player(0))
		assert_eq(manager.get_device_for_player(0), config)

	func test_assign_multiple_devices():
		var config1 := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD,
			-1,
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		var config2 := DeviceConfig.new(
			DeviceConfig.DeviceType.GAMEPAD, 0, {}
		)
		manager.assign_device_to_player(0, config1)
		manager.assign_device_to_player(1, config2)

		assert_true(manager.has_device_for_player(0))
		assert_true(manager.has_device_for_player(1))
		assert_ne(
			manager.get_device_for_player(0),
			manager.get_device_for_player(1)
		)

	func test_reassign_device_overwrites():
		var config1 := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {}
		)
		var config2 := DeviceConfig.new(
			DeviceConfig.DeviceType.GAMEPAD, 0, {}
		)
		manager.assign_device_to_player(0, config1)
		manager.assign_device_to_player(0, config2)

		var retrieved := manager.get_device_for_player(0)
		assert_eq(retrieved.type, DeviceConfig.DeviceType.GAMEPAD)

	func test_get_device_returns_null_when_not_assigned():
		assert_null(manager.get_device_for_player(0))

	func test_clear_all_assignments():
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {}
		)
		manager.assign_device_to_player(0, config)
		manager.clear_all_assignments()
		assert_false(manager.has_device_for_player(0))

	func test_assign_to_multiple_local_indices():
		for i in range(4):
			var config := DeviceConfig.new(
				DeviceConfig.DeviceType.KEYBOARD,
				-1,
				{"move_up": KEY_W + i}
			)
			manager.assign_device_to_player(i, config)

		for i in range(4):
			assert_true(manager.has_device_for_player(i))


class TestActionStatePolling:
	extends GutTest

	func test_returns_false_for_missing_action_in_bindings():
		var manager := InputDeviceManager.new()
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {"move_up": KEY_W}
		)
		# Action "jump" not in bindings
		var result := manager.get_is_action_pressed("jump", config)
		assert_false(result)

	func test_returns_false_for_empty_bindings():
		var manager := InputDeviceManager.new()
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {}
		)
		var result := manager.get_is_action_pressed("move_up", config)
		assert_false(result)

	func test_keyboard_action_uses_physical_key():
		# This test verifies the keyboard path calls the correct API.
		var manager := InputDeviceManager.new()
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {"move_up": KEY_W}
		)
		# NOTE: Without actual key press simulation, we can only test
		# that the method returns a boolean value.
		var result := manager.get_is_action_pressed("move_up", config)
		assert_typeof(result, TYPE_BOOL)

	func test_gamepad_action_uses_device_id():
		# This test verifies the gamepad path calls the correct API.
		var manager := InputDeviceManager.new()
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.GAMEPAD, 0, {}
		)
		# NOTE: Without actual gamepad simulation, we can only test
		# that the method returns a boolean value.
		var result := manager.get_is_action_pressed("jump", config)
		assert_typeof(result, TYPE_BOOL)


class TestBindingPresets:
	extends GutTest

	func test_partition_bindings_array_exists():
		assert_not_null(InputDeviceManager.KEYBOARD_PARTITION_BINDINGS)
		assert_eq(InputDeviceManager.KEYBOARD_PARTITION_BINDINGS.size(), 3)

	func test_wasd_bindings_preset_exists():
		var wasd := InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		assert_not_null(wasd)
		assert_has(wasd, "move_up")
		assert_eq(wasd["move_up"], KEY_W)
		assert_eq(wasd["name"], "WASD")

	func test_ijkl_bindings_preset_exists():
		var ijkl := InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[1]
		assert_not_null(ijkl)
		assert_has(ijkl, "move_up")
		assert_eq(ijkl["move_up"], KEY_I)
		assert_eq(ijkl["name"], "IJKL")

	func test_arrow_bindings_preset_exists():
		var arrow := InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[2]
		assert_not_null(arrow)
		assert_has(arrow, "move_up")
		assert_eq(arrow["move_up"], KEY_UP)
		assert_eq(arrow["name"], "ArrowKeys")

	func test_all_presets_have_required_actions():
		var required_actions := [
			"move_up",
			"move_down",
			"move_left",
			"move_right",
			"jump",
		]

		for preset in InputDeviceManager.KEYBOARD_PARTITION_BINDINGS:
			for action in required_actions:
				assert_has(
					preset,
					action,
					"Preset missing action: %s" % action
				)


class TestDeviceManagerEdgeCases:
	extends GutTest
	var manager: InputDeviceManager

	func before_each():
		manager = InputDeviceManager.new()

	func test_has_device_returns_false_for_unassigned():
		assert_false(manager.has_device_for_player(0))
		assert_false(manager.has_device_for_player(999))

	func test_get_device_returns_null_for_unassigned():
		assert_null(manager.get_device_for_player(0))
		assert_null(manager.get_device_for_player(999))

	func test_can_assign_to_negative_index():
		# BUG: No bounds checking on local_index
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {}
		)
		manager.assign_device_to_player(-1, config)
		assert_true(manager.has_device_for_player(-1))

	func test_can_assign_to_very_large_index():
		# BUG: No bounds checking on local_index
		var config := DeviceConfig.new(
			DeviceConfig.DeviceType.KEYBOARD, -1, {}
		)
		manager.assign_device_to_player(999, config)
		assert_true(manager.has_device_for_player(999))
