extends GutTest
## Integration tests for LobbyLevel player spawning.


class TestKeyboardPlayerSpawning:
	extends GutTest
	var lobby_level: LobbyLevel
	var root_node: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.client_session.
		G.client_session = ClientSession.new()

		# Mock G.match_state.
		G.match_state = GameMatchState.new()

		lobby_level = preload(
			"res://src/level/lobby_level.tscn"
		).instantiate()
		root_node.add_child(lobby_level)
		G.level = lobby_level

	func after_each():
		ArrayPool.clear_all_pools()
		G.level = null
		G.client_session = null
		G.match_state = null

	func test_spawn_keyboard_player_first():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)

		assert_eq(lobby_level.get_player_count(), 1)
		assert_not_null(lobby_level._pending_device_configs_by_index[0])
		assert_eq(
			lobby_level._pending_device_configs_by_index[0].type,
			DeviceConfig.DeviceType.KEYBOARD
		)

	func test_spawn_multiple_keyboard_players():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[1]
		)
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[2]
		)

		assert_eq(lobby_level.get_player_count(), 3)
		assert_not_null(lobby_level._pending_device_configs_by_index[0])
		assert_not_null(lobby_level._pending_device_configs_by_index[1])
		assert_not_null(lobby_level._pending_device_configs_by_index[2])

	func test_cannot_register_same_keyboard_twice():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)

		# Should still be 1 player (duplicate prevented by device name)
		assert_eq(lobby_level.get_player_count(), 1)

	func test_spawn_assigns_to_input_device_manager():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)

		assert_true(G.input_device_manager.has_device_for_player(0))

	func test_players_have_correct_lobby_ids():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[1]
		)

		assert_has(lobby_level.players_by_id, -1)
		assert_has(lobby_level.players_by_id, -2)


class TestGamepadPlayerSpawning:
	extends GutTest
	var lobby_level: LobbyLevel
	var root_node: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.client_session.
		G.client_session = ClientSession.new()

		# Mock G.match_state.
		G.match_state = GameMatchState.new()

		lobby_level = preload(
			"res://src/level/lobby_level.tscn"
		).instantiate()
		root_node.add_child(lobby_level)
		G.level = lobby_level

	func after_each():
		ArrayPool.clear_all_pools()
		G.level = null
		G.client_session = null
		G.match_state = null

	func test_spawn_gamepad_gets_first_slot():
		lobby_level._try_register_gamepad_player(0)

		assert_eq(lobby_level.get_player_count(), 1)
		assert_not_null(lobby_level._pending_device_configs_by_index[0])
		assert_eq(
			lobby_level._pending_device_configs_by_index[0].type,
			DeviceConfig.DeviceType.GAMEPAD
		)
		assert_eq(lobby_level._pending_device_configs_by_index[0].device_id, 0)

	func test_spawn_multiple_gamepads_in_sequence():
		lobby_level._try_register_gamepad_player(0)
		lobby_level._try_register_gamepad_player(1)

		assert_eq(lobby_level.get_player_count(), 2)
		assert_eq(lobby_level._pending_device_configs_by_index[0].device_id, 0)
		assert_eq(lobby_level._pending_device_configs_by_index[1].device_id, 1)

	func test_gamepad_duplication_prevented():
		# Test that same gamepad cannot spawn twice
		lobby_level._try_register_gamepad_player(0)
		lobby_level._try_register_gamepad_player(0)

		# Should be 1 player (duplicate prevented by device name)
		assert_eq(lobby_level.get_player_count(), 1)

	func test_despawn_gamepad_by_device_id():
		lobby_level._try_register_gamepad_player(0)
		assert_eq(lobby_level.get_player_count(), 1)

		lobby_level._try_deregister_gamepad_player(0)
		assert_eq(lobby_level.get_player_count(), 0)

	func test_gamepad_fills_next_sequential_slot():
		# Register keyboard player first (gets index 0)
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)

		# Gamepad should get index 1
		lobby_level._try_register_gamepad_player(0)

		assert_not_null(lobby_level._pending_device_configs_by_index[0])
		assert_not_null(lobby_level._pending_device_configs_by_index[1])
		assert_eq(
			lobby_level._pending_device_configs_by_index[0].type,
			DeviceConfig.DeviceType.KEYBOARD
		)
		assert_eq(
			lobby_level._pending_device_configs_by_index[1].type,
			DeviceConfig.DeviceType.GAMEPAD
		)


class TestPlayerDespawning:
	extends GutTest
	var lobby_level: LobbyLevel
	var root_node: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.client_session.
		G.client_session = ClientSession.new()

		# Mock G.match_state.
		G.match_state = GameMatchState.new()

		lobby_level = preload(
			"res://src/level/lobby_level.tscn"
		).instantiate()
		root_node.add_child(lobby_level)
		G.level = lobby_level

	func after_each():
		ArrayPool.clear_all_pools()
		G.level = null
		G.client_session = null
		G.match_state = null

	func test_deregister_player_by_device_name():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[1]
		)
		assert_eq(lobby_level.get_player_count(), 1)

		lobby_level._deregister_player("IJKL")
		assert_eq(lobby_level.get_player_count(), 0)

	func test_despawn_clears_input_device_manager():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		assert_true(G.input_device_manager.has_device_for_player(0))

		lobby_level._deregister_player("WASD")
		assert_false(G.input_device_manager.has_device_for_player(0))

	func test_despawn_nonexistent_player_safe():
		lobby_level._deregister_player("NonExistent")
		# Should not crash
		assert_eq(lobby_level.get_player_count(), 0)

	func test_despawn_removes_from_players_by_id():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		assert_has(lobby_level.players_by_id, -1)

		lobby_level._deregister_player("WASD")
		assert_false(lobby_level.players_by_id.has(-1))


class TestMatchStartTransition:
	extends GutTest
	var lobby_level: LobbyLevel
	var root_node: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.client_session.
		G.client_session = ClientSession.new()

		# Mock G.match_state.
		G.match_state = GameMatchState.new()

		lobby_level = preload(
			"res://src/level/lobby_level.tscn"
		).instantiate()
		root_node.add_child(lobby_level)
		G.level = lobby_level

	func after_each():
		ArrayPool.clear_all_pools()
		G.level = null
		G.client_session = null
		G.match_state = null

	func test_can_start_match_with_players():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		assert_true(lobby_level.can_start_match())

	func test_cannot_start_match_without_players():
		assert_false(lobby_level.can_start_match())

	func test_pending_configs_contain_all_active():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[2]
		)

		var active := lobby_level._pending_device_configs_by_index
		assert_eq(active.size(), 2)
		assert_eq(active[0].type, DeviceConfig.DeviceType.KEYBOARD)
		assert_eq(active[1].type, DeviceConfig.DeviceType.KEYBOARD)


class TestLobbyLevelPlayerPositioning:
	extends GutTest
	var lobby_level: LobbyLevel
	var root_node: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.client_session.
		G.client_session = ClientSession.new()

		# Mock G.match_state.
		G.match_state = GameMatchState.new()

		lobby_level = preload(
			"res://src/level/lobby_level.tscn"
		).instantiate()
		root_node.add_child(lobby_level)
		G.level = lobby_level

	func after_each():
		ArrayPool.clear_all_pools()
		G.level = null
		G.client_session = null
		G.match_state = null

	func test_players_spawn_at_spawn_point():
		lobby_level._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)

		var player0: Player = lobby_level.players_by_id[-1]

		# Lobby uses random spawn point selection.
		# With a single spawn point, the player spawns
		# at that point's position. Allow small
		# tolerance for physics resolution.
		var spawn_points := (
			lobby_level._get_spawn_points())
		assert_eq(
			spawn_points.size(),
			1,
			"Lobby has one spawn point",
		)
		assert_almost_eq(
			player0.global_position,
			spawn_points[0].spawn_position,
			Vector2(2, 2),
			"Player spawns near the spawn point",
		)
