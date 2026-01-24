extends GutTest
## Integration tests for ForwardedPlayerInputFromServer data flow.
##
## Tests the complete path: client input → server → forwarded to other clients.

const TestEnvironmentMock = preload("res://test/helpers/test_environment_mock.gd")


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()
	TestEnvironmentMock.cleanup_mock_level()


class TestInputForwardingEndToEnd:
	extends GutTest

	var root_node: Node
	var server_player: Player
	var server_state: CharacterStateFromServer
	var server_input: PlayerInputFromClient
	var server_forwarded: ForwardedPlayerInputFromServer


	func before_each():
		ArrayPool.clear_all_pools()

		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)

		# Setup mock level.
		TestEnvironmentMock.setup_mock_level(root_node)

		# Create server player with full 3-node setup.
		var setup = TestEnvironmentMock.setup_player_with_networking(
			root_node,
			"ServerPlayer",
		)
		server_player = setup.player
		server_state = setup.state_from_server
		server_input = setup.input_from_client
		server_forwarded = setup.forwarded_input

		# Initialize all nodes.
		server_state._ready()
		server_input._ready()
		server_forwarded._ready()

		# Initialize rollback buffers.
		if server_state._rollback_buffer == null:
			server_state._set_up_rollback_buffer()
		if server_input._rollback_buffer == null:
			server_input._set_up_rollback_buffer()
		if server_forwarded._rollback_buffer == null:
			server_forwarded._set_up_rollback_buffer()

		server_state._parse_property_names()
		server_input._parse_property_names()
		server_forwarded._parse_property_names()


	func after_each():
		ArrayPool.clear_all_pools()


	func test_remote_player_receives_forwarded_input():
		# Simulate remote client receiving ForwardedInput.
		# Mock: player is NOT locally controlled.
		server_player.input_from_client = null

		# Set forwarded input state.
		server_forwarded.actions = 0b1010

		# Create previous state.
		var previous_state := ArrayPool.acquire(2)
		previous_state[0] = 0b0001
		previous_state[1] = -1

		# Sync to scene state (remote player).
		server_forwarded._sync_to_scene_state(previous_state)

		# Remote player should see the actions.
		assert_eq(
			server_player.actions.bitmask,
			0b1010,
			"Remote player should receive forwarded actions",
		)
		assert_eq(
			server_player.actions.previous_bitmask,
			0b0001,
			"Remote player should receive previous actions",
		)

		ArrayPool.release(previous_state)


	func test_local_player_ignores_forwarded_input():
		# Simulate local player (has input authority).
		server_input.set_multiplayer_authority(1)

		# Set forwarded input state.
		server_forwarded.actions = 0b1111

		# Set local input state.
		server_player.actions.bitmask = 0b0001

		# Create previous state.
		var previous_state := ArrayPool.acquire(2)
		previous_state[0] = 0
		previous_state[1] = -1

		# Sync forwarded input to scene state.
		server_forwarded._sync_to_scene_state(previous_state)

		# Local player should NOT be modified by forwarded input.
		assert_eq(
			server_player.actions.bitmask,
			0b0001,
			"Local player should ignore forwarded input",
		)

		ArrayPool.release(previous_state)


class TestVisibilityFilterIntegration:
	extends GutTest

	var root_node: Node
	var forwarded_input: ForwardedPlayerInputFromServer


	func before_each():
		ArrayPool.clear_all_pools()

		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)

		# Setup mock level to prevent Player._enter_tree crashes
		TestEnvironmentMock.setup_mock_level(root_node)

		# Use setup_test_player to get a properly initialized player
		var player = TestEnvironmentMock.setup_test_player(root_node)

		forwarded_input = ForwardedPlayerInputFromServer.new()
		forwarded_input.name = "ForwardedInput"
		forwarded_input.root_path = NodePath(".")
		TestEnvironmentMock.init_replication_config(forwarded_input)
		forwarded_input.player = player
		player.add_child(forwarded_input)

		forwarded_input._ready()


	func after_each():
		ArrayPool.clear_all_pools()


	func test_visibility_filter_blocks_originating_client():
		# Set originating player ID.
		forwarded_input.multiplayer_id = 3

		# Visibility filter should block peer 3.
		assert_false(
			forwarded_input._visibility_filter(3),
			"Should block originating client (peer 3)",
		)


	func test_visibility_filter_allows_other_clients():
		# Set originating player ID.
		forwarded_input.multiplayer_id = 3

		# Other peers should be visible.
		assert_true(
			forwarded_input._visibility_filter(2),
			"Should allow peer 2",
		)
		assert_true(
			forwarded_input._visibility_filter(4),
			"Should allow peer 4",
		)
		assert_true(
			forwarded_input._visibility_filter(NetworkConnector.SERVER_ID),
			"Should allow server",
		)


class TestRollbackIntegration:
	extends GutTest

	var root_node: Node
	var player: Player
	var forwarded_input: ForwardedPlayerInputFromServer


	func before_each():
		ArrayPool.clear_all_pools()

		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)

		# Setup mock level to prevent Player._enter_tree crashes
		TestEnvironmentMock.setup_mock_level(root_node)

		# Use setup_test_player to get a properly initialized player
		player = TestEnvironmentMock.setup_test_player(root_node)

		forwarded_input = ForwardedPlayerInputFromServer.new()
		forwarded_input.name = "ForwardedInput"
		forwarded_input.root_path = NodePath(".")
		TestEnvironmentMock.init_replication_config(forwarded_input)
		forwarded_input.player = player
		player.add_child(forwarded_input)

		forwarded_input._ready()

		# Initialize rollback buffer.
		if forwarded_input._rollback_buffer == null:
			forwarded_input._set_up_rollback_buffer()
		forwarded_input._parse_property_names()


	func after_each():
		ArrayPool.clear_all_pools()


	func test_forwarded_input_stores_state_in_rollback_buffer():
		# Use buffer's current latest + 1.
		var test_frame := forwarded_input._rollback_buffer.get_latest_index() + 1

		# Set forwarded input state.
		forwarded_input.actions = 0b1100
		forwarded_input.last_triggered_jump_time_usec = 5000000
		forwarded_input.frame_authority = \
		ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE

		# Record state.
		forwarded_input._sync_from_scene_state()
		var state := ArrayPool.acquire(3)
		state[0] = forwarded_input.actions
		state[1] = forwarded_input.last_triggered_jump_time_usec
		state[2] = forwarded_input.frame_authority

		forwarded_input._rollback_buffer.set_at(test_frame, state)

		# Verify stored.
		assert_true(
			forwarded_input._rollback_buffer.has_at(test_frame),
			"Should store state in rollback buffer",
		)

		var retrieved: Array = forwarded_input._rollback_buffer.get_at(test_frame)
		assert_eq(
			retrieved[0],
			0b1100,
			"Should store actions in buffer",
		)
		assert_eq(
			retrieved[1],
			5000000,
			"Should store jump timestamp in buffer",
		)


	func test_forwarded_input_restores_from_rollback_buffer():
		# Use buffer's current latest + 1.
		var test_frame := forwarded_input._rollback_buffer.get_latest_index() + 1

		# Store state in buffer.
		var state := ArrayPool.acquire(3)
		state[0] = 0b0111
		state[1] = 2500000
		state[2] = ReconcilableNetworkedState.FrameAuthority.PREDICTED

		forwarded_input._rollback_buffer.set_at(test_frame, state)

		# Restore from buffer.
		forwarded_input._unpack_buffer_state(test_frame)

		# Verify restored.
		assert_eq(
			forwarded_input.actions,
			0b0111,
			"Should restore actions from buffer",
		)
		assert_eq(
			forwarded_input.last_triggered_jump_time_usec,
			2500000,
			"Should restore jump timestamp from buffer",
		)
		assert_eq(
			forwarded_input.frame_authority,
			ReconcilableNetworkedState.FrameAuthority.PREDICTED,
			"Should restore frame authority from buffer",
		)


	func test_forwarded_input_mismatch_detection():
		# Simulate mismatch: predicted vs authoritative with different actions.
		var predicted_actions := 0b0001
		var authoritative_actions := 0b0010

		# Check for mismatch (threshold 0 = exact match required).
		var has_mismatch := \
		forwarded_input._check_do_values_mismatch(
			predicted_actions,
			authoritative_actions,
			0, # threshold
		)

		assert_true(
			has_mismatch,
			"Should detect mismatch with different actions (threshold 0)",
		)


	func test_forwarded_input_no_mismatch_when_matching():
		# Same actions, no mismatch.
		var actions := 0b0101

		var has_mismatch := \
		forwarded_input._check_do_values_mismatch(
			actions,
			actions,
			0,
		)

		assert_false(
			has_mismatch,
			"Should not detect mismatch with identical actions",
		)
