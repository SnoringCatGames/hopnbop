@tool
extends GutTest
## Unit tests for CharacterStateFromServer input forwarding logic.
##
## Tests the _network_process() method that copies input data from
## PlayerInputFromClient to ForwardedPlayerInputFromServer.

const TestEnvironmentMock = preload("res://test/helpers/test_environment_mock.gd")


func before_each():
	ArrayPool.clear_all_pools()
	# Initialize network time for rollback buffer setup
	if not G.network.time.is_time_initialized:
		G.network.time._start_time_offset_usec = 0


func after_each():
	ArrayPool.clear_all_pools()
	TestEnvironmentMock.cleanup_mock_level()


class TestForwardingLogic:
	extends GutTest

	var root_node: Node
	var player: Player
	var state_from_server: CharacterStateFromServer
	var input_from_client: PlayerInputFromClient
	var forwarded_input: ForwardedPlayerInputFromServer


	func before_each():
		ArrayPool.clear_all_pools()
		# Initialize network time for rollback buffer setup
		if not G.network.time.is_time_initialized:
			G.network.time._start_time_offset_usec = 0

		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)

		# Setup mock level.
		TestEnvironmentMock.setup_mock_level(root_node)

		# Create full 3-node setup using helper.
		var setup = TestEnvironmentMock.setup_player_with_networking(root_node)
		player = setup.player
		state_from_server = setup.state_from_server
		input_from_client = setup.input_from_client
		forwarded_input = setup.forwarded_input

		# Nodes are already initialized when added to tree in
		# setup_player_with_networking, no need to call _ready() again.


	func after_each():
		ArrayPool.clear_all_pools()


	func test_caches_forwarded_input_on_ready():
		# _ready() was called in before_each, check if cached.
		assert_not_null(
			state_from_server.forwarded_input_from_server,
			"Should cache forwarded_input_from_server reference",
		)
		assert_eq(
			state_from_server.forwarded_input_from_server,
			forwarded_input,
			"Should reference the correct ForwardedInput node",
		)
