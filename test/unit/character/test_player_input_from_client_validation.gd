@tool
extends GutTest
## Unit tests for PlayerInputFromClient sibling validation and sync guards.
##
## Tests the validation logic that ensures ForwardedPlayerInputFromServer is
## present and has matching synced properties, and the authority guards that
## prevent sync conflicts.


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()
	TestEnvironmentMock.cleanup_mock_level()


class TestSiblingValidation:
	extends GutTest

	var root_node: Node
	var player: Player
	var input_from_client: PlayerInputFromClient


	func before_each():
		ArrayPool.clear_all_pools()

		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)

		# Setup mock level to prevent Player._enter_tree crashes
		TestEnvironmentMock.setup_mock_level(root_node)

		# Use the full player setup to ensure all required nodes are present
		var setup = TestEnvironmentMock.setup_player_with_networking(root_node)
		player = setup.player
		input_from_client = setup.input_from_client


	func after_each():
		ArrayPool.clear_all_pools()


class TestSyncGuard:
	extends GutTest

	var root_node: Node
	var player: Player
	var input_from_client: PlayerInputFromClient


	func before_each():
		ArrayPool.clear_all_pools()

		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)

		# Setup mock level to prevent Player._enter_tree crashes
		TestEnvironmentMock.setup_mock_level(root_node)

		# Use the full player setup to ensure all required nodes are present
		var setup = TestEnvironmentMock.setup_player_with_networking(root_node)
		player = setup.player
		input_from_client = setup.input_from_client


	func after_each():
		ArrayPool.clear_all_pools()


	func test_sync_to_scene_state_only_runs_for_authority():
		# Mock remote player (no authority).
		input_from_client.set_multiplayer_authority(2) # Different peer

		# Set actions.
		input_from_client.actions = 0b1111

		# Create previous state.
		var previous_state := ArrayPool.acquire(2)
		previous_state[0] = 0b0001
		previous_state[1] = -1

		# Sync to scene state.
		input_from_client._sync_to_scene_state(previous_state)

		# Player actions should NOT be modified (no authority).
		assert_eq(
			player.actions.bitmask,
			0,
			"Should not sync when not authority",
		)

		ArrayPool.release(previous_state)


	func test_sync_to_scene_state_runs_for_authority():
		# Mock local authority.
		input_from_client.set_multiplayer_authority(
			multiplayer.get_unique_id(),
		)

		# Set actions.
		input_from_client.actions = 0b0110

		# Create previous state.
		var previous_state := ArrayPool.acquire(2)
		previous_state[0] = 0b0010
		previous_state[1] = -1

		# Sync to scene state.
		input_from_client._sync_to_scene_state(previous_state)

		# Player actions should be updated.
		assert_eq(
			player.actions.bitmask,
			0b0110,
			"Should sync when has authority",
		)
		assert_eq(
			player.actions.previous_bitmask,
			0b0010,
			"Should update previous actions",
		)

		ArrayPool.release(previous_state)


	func test_sync_from_scene_state_reads_jump_frame_index_for_authority():
		# Mock local authority.
		input_from_client.set_multiplayer_authority(
			multiplayer.get_unique_id(),
		)

		# Set player's jump frame index.
		player.last_triggered_jump_frame_index = 100

		# Sync from scene state.
		input_from_client._sync_from_scene_state()

		# Input should have captured the jump interaction.
		assert_eq(
			input_from_client.last_interaction_type,
			PlayerInputNetworkState.ClientInteractionType.JUMP,
			"Should capture jump interaction type",
		)
		assert_eq(
			input_from_client.last_interaction_frame_index,
			100,
			"Should capture jump frame index",
		)
