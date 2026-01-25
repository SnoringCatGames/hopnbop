extends GutTest
## Integration tests for full lobby-to-networked flow with int-based player IDs.

const LOBBY_LEVEL_SCENE := preload("res://src/level/lobby_level.tscn")
const MockLevel := preload("res://test/helpers/mock_level.gd")


class TestFullPlayerFlow:
	extends GutTest
	var lobby: LobbyLevel
	var root_node: Node
	var mock_level: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.level to avoid null reference errors.
		mock_level = MockLevel.new()
		G.level = mock_level

		lobby = LOBBY_LEVEL_SCENE.instantiate()
		root_node.add_child(lobby)

	func after_each():
		ArrayPool.clear_all_pools()
		G.level = null
		if is_instance_valid(mock_level):
			mock_level.queue_free()

	func test_lobby_device_configs_persist_to_local_session():
		# Spawn players.
		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		lobby._try_register_gamepad_player(0)

		# Verify lobby has correct player count and configs.
		assert_eq(lobby.get_player_count(), 2)
		assert_eq(lobby._pending_device_configs_by_index.size(), 2)

		# Verify device types in lobby configs.
		assert_eq(
			lobby._pending_device_configs_by_index[0].type,
			DeviceConfig.DeviceType.KEYBOARD
		)
		assert_eq(
			lobby._pending_device_configs_by_index[1].type,
			DeviceConfig.DeviceType.GAMEPAD
		)

	func test_device_config_array_ordering_preserved():
		# Spawn players in order (join order determines index).
		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[2]
		)

		# All active configs should be sequential.
		assert_eq(lobby._pending_device_configs_by_index.size(), 2)

		# First player should use WASD bindings
		assert_eq(
			lobby._pending_device_configs_by_index[0].key_bindings["move_up"],
			KEY_W
		)

		# Second player should use Arrow bindings
		assert_eq(
			lobby._pending_device_configs_by_index[1].key_bindings["move_up"],
			KEY_UP
		)

	func test_player_count_consistency():
		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		lobby._try_register_gamepad_player(0)
		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[2]
		)

		var active_count := lobby.get_player_count()
		var active_configs := lobby._pending_device_configs_by_index

		assert_eq(active_count, 3)
		assert_eq(active_configs.size(), 3)


class TestDeviceConfigThreading:
	extends GutTest
	var lobby: LobbyLevel
	var root_node: Node
	var mock_level: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.level to avoid null reference errors.
		mock_level = MockLevel.new()
		G.level = mock_level

		lobby = LOBBY_LEVEL_SCENE.instantiate()
		root_node.add_child(lobby)

	func after_each():
		ArrayPool.clear_all_pools()
		G.level = null
		if is_instance_valid(mock_level):
			mock_level.queue_free()

	func test_device_configs_contain_correct_bindings():

		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)

		var configs := lobby._pending_device_configs_by_index
		assert_eq(configs.size(), 1)

		var config: DeviceConfig = configs[0]
		assert_has(config.key_bindings, "move_up")
		assert_eq(config.key_bindings["move_up"], KEY_W)

	func test_gamepad_device_id_preserved():
		lobby._try_register_gamepad_player(3) # Device ID 3

		var configs := lobby._pending_device_configs_by_index
		var config: DeviceConfig = configs[0]

		assert_eq(config.type, DeviceConfig.DeviceType.GAMEPAD)
		assert_eq(config.device_id, 3)


class TestLocalSessionCleaning:
	extends GutTest
	var lobby: LobbyLevel
	var root_node: Node
	var mock_level: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.level to avoid null reference errors.
		mock_level = MockLevel.new()
		G.level = mock_level

		lobby = LOBBY_LEVEL_SCENE.instantiate()
		root_node.add_child(lobby)

	func after_each():
		ArrayPool.clear_all_pools()
		G.level = null
		if is_instance_valid(mock_level):
			mock_level.queue_free()

	func test_lobby_tracks_player_count():
		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)

		assert_eq(lobby.get_player_count(), 1)

		# Verify configs array matches player count
		assert_eq(lobby._pending_device_configs_by_index.size(), 1)

	func test_device_configs_ready_for_session():
		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)

		# Verify configs can be duplicated for session transfer
		var configs_copy := lobby._pending_device_configs_by_index.duplicate()
		assert_eq(configs_copy.size(), 1)
		assert_eq(configs_copy[0].type, DeviceConfig.DeviceType.KEYBOARD)


class TestLobbyPlayerIsolation:
	extends GutTest
	var lobby: LobbyLevel
	var root_node: Node
	var mock_level: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.level to avoid null reference errors.
		mock_level = MockLevel.new()
		G.level = mock_level

		lobby = LOBBY_LEVEL_SCENE.instantiate()
		root_node.add_child(lobby)

	func after_each():
		ArrayPool.clear_all_pools()
		G.level = null
		if is_instance_valid(mock_level):
			mock_level.queue_free()

	func test_lobby_players_use_negative_ids():
		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[0]
		)
		lobby._try_register_keyboard_player(
			InputDeviceManager.KEYBOARD_PARTITION_BINDINGS[2]
		)

		# Lobby players use negative IDs: -1, -2, -3, etc.
		var player0: Player = lobby.players_by_id[-1]
		var player1: Player = lobby.players_by_id[-2]

		assert_not_null(player0)
		assert_not_null(player1)
		assert_eq(player0.player_id, -1)
		assert_eq(player1.player_id, -2)
