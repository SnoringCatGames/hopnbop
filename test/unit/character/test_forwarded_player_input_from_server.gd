@tool
extends GutTest
## Unit tests for ForwardedPlayerInputFromServer class.
##
## Tests the new server-authoritative input forwarding node that broadcasts
## player input to all clients except the originating player.

func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


## Mock player class for testing without full Character/Player dependencies.
## Note: Must extend Player to satisfy type requirements in
## ForwardedPlayerInputFromServer.
class MockPlayer extends Player:
	# Properties like actions and last_triggered_jump_frame_index are inherited
	# from Character.
	func _init():
		# Explicitly initialize inherited properties that have field initializers
		super._init()

	func _enter_tree() -> void:
		# Override to prevent Player's _enter_tree logic which requires G.level
		pass

	func _ready() -> void:
		# Override to prevent full Player initialization in tests which requires
		# state_from_server, collision_shape, movement_settings, etc.
		pass


class TestConfigurationAndInitialization:
	extends GutTest

	var root_node: Node
	var player_node: Node
	var forwarded_input: ForwardedPlayerInputFromServer


	func before_each():
		ArrayPool.clear_all_pools()

		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)

		# Create mock player node.
		player_node = Node.new()
		player_node.name = "Player"
		root_node.add_child(player_node)

		forwarded_input = ForwardedPlayerInputFromServer.new()
		forwarded_input.name = "ForwardedInput"
		forwarded_input.root_path = NodePath(".")
		forwarded_input.replication_config = SceneReplicationConfig.new()
		player_node.add_child(forwarded_input)


	func after_each():
		ArrayPool.clear_all_pools()


	func test_get_is_server_authoritative_returns_true():
		assert_true(
			forwarded_input._get_is_server_authoritative(),
			"ForwardedInput must be server-authoritative",
		)


	func test_synced_properties_match_expected():
		var props: Dictionary = \
		forwarded_input._synced_properties_and_rollback_diff_thresholds

		# Should have exactly 5 properties (actions + 4 interaction props).
		assert_eq(props.size(), 5, "Should have 5 synced properties")

		# Should have actions with threshold 0.
		assert_true(props.has("actions"), "Should sync actions")
		assert_eq(props["actions"], 0, "Actions threshold should be 0")

		# Should have interaction properties.
		assert_true(
			props.has("last_interaction_type"),
			"Should sync interaction type",
		)
		assert_true(
			props.has("last_interaction_frame_index"),
			"Should sync interaction frame index",
		)
		assert_true(
			props.has("last_interaction_position"),
			"Should sync interaction position",
		)
		assert_true(
			props.has("last_interaction_direction"),
			"Should sync interaction direction",
		)


	func test_get_default_values_returns_correct_array():
		var defaults: Array = forwarded_input._get_default_values()

		assert_eq(defaults.size(), 5, "Should have 5 default values")
		assert_eq(defaults[0], 0, "Default actions should be 0")
		assert_eq(
			defaults[1],
			PlayerInputNetworkState.ClientInteractionType.NONE,
			"Default interaction type should be NONE",
		)
		assert_eq(
			defaults[2],
			-1,
			"Default interaction timestamp should be -1",
		)
		assert_eq(
			defaults[3],
			Vector2.ZERO,
			"Default interaction position should be zero",
		)
		assert_eq(
			defaults[4],
			Vector2.ZERO,
			"Default interaction direction should be zero",
		)


class TestConfigurationWarnings:
	extends GutTest

	var root_node: Node
	var player_node: Player
	var state_from_server: CharacterStateFromServer
	var input_from_client: PlayerInputFromClient
	var forwarded_input: ForwardedPlayerInputFromServer


	func before_each():
		ArrayPool.clear_all_pools()

		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)


	func after_each():
		ArrayPool.clear_all_pools()


	func test_warning_when_player_not_set():
		# Create ForwardedInput without player export.
		player_node = MockPlayer.new()
		player_node.name = "Player"
		root_node.add_child(player_node)

		forwarded_input = ForwardedPlayerInputFromServer.new()
		forwarded_input.name = "ForwardedInput"
		forwarded_input.root_path = NodePath(".")
		forwarded_input.replication_config = SceneReplicationConfig.new()
		# Don't set player property.
		player_node.add_child(forwarded_input)

		forwarded_input._ready()

		var warnings := forwarded_input._get_configuration_warnings()

		assert_gt(warnings.size(), 0, "Should have warnings")
		var has_player_warning := false
		for warning in warnings:
			if "player is not set" in warning:
				has_player_warning = true
				break

		assert_true(
			has_player_warning,
			"Should warn when player is not set",
		)


	func test_warning_when_input_from_client_sibling_missing():
		# Create ForwardedInput without PlayerInputFromClient sibling.
		player_node = MockPlayer.new()
		player_node.name = "Player"
		root_node.add_child(player_node)

		forwarded_input = ForwardedPlayerInputFromServer.new()
		forwarded_input.name = "ForwardedInput"
		forwarded_input.root_path = NodePath(".")
		forwarded_input.replication_config = SceneReplicationConfig.new()
		forwarded_input.player = player_node
		player_node.add_child(forwarded_input)

		forwarded_input._ready()

		var warnings := forwarded_input._get_configuration_warnings()

		var has_sibling_warning := false
		for warning in warnings:
			if "requires a PlayerInputFromClient sibling" in warning:
				has_sibling_warning = true
				break

		assert_true(
			has_sibling_warning,
			"Should warn when PlayerInputFromClient sibling is missing",
		)


	func test_no_warnings_when_properly_configured():
		# Create full 3-node setup.
		player_node = MockPlayer.new()
		player_node.name = "Player"
		root_node.add_child(player_node)

		state_from_server = CharacterStateFromServer.new()
		state_from_server.name = "StateFromServer"
		state_from_server.root_path = NodePath(".")
		state_from_server.replication_config = SceneReplicationConfig.new()
		player_node.add_child(state_from_server)

		input_from_client = PlayerInputFromClient.new()
		input_from_client.name = "InputFromClient"
		input_from_client.root_path = NodePath(".")
		input_from_client.replication_config = SceneReplicationConfig.new()
		input_from_client.player = player_node
		player_node.add_child(input_from_client)

		forwarded_input = ForwardedPlayerInputFromServer.new()
		forwarded_input.name = "ForwardedInput"
		forwarded_input.root_path = NodePath(".")
		forwarded_input.replication_config = SceneReplicationConfig.new()
		forwarded_input.player = player_node
		player_node.add_child(forwarded_input)

		# Initialize all nodes.
		state_from_server._ready()
		input_from_client._ready()
		forwarded_input._ready()

		var warnings := forwarded_input._get_configuration_warnings()

		# Filter out base class warnings (like root_path, replication_config).
		var forwarded_specific_warnings := PackedStringArray()
		for warning in warnings:
			if ("player" in warning or "sibling" in warning or
					"properties" in warning):
				forwarded_specific_warnings.append(warning)

		assert_eq(
			forwarded_specific_warnings.size(),
			0,
			"Should have no ForwardedInput-specific warnings when properly configured",
		)


class TestStateSynchronization:
	extends GutTest

	var root_node: Node
	var player: MockPlayer
	var forwarded_input: ForwardedPlayerInputFromServer


	func before_each():
		ArrayPool.clear_all_pools()

		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)

		player = MockPlayer.new()
		player.name = "Player"
		root_node.add_child(player)

		forwarded_input = ForwardedPlayerInputFromServer.new()
		forwarded_input.name = "ForwardedInput"
		forwarded_input.root_path = NodePath(".")
		forwarded_input.replication_config = SceneReplicationConfig.new()
		forwarded_input.player = player
		player.add_child(forwarded_input)

		forwarded_input._ready()
		# Initialize rollback buffer.
		if forwarded_input._rollback_buffer == null:
			forwarded_input._set_up_rollback_buffer()
		forwarded_input._parse_property_names()


	func after_each():
		ArrayPool.clear_all_pools()


	func test_sync_to_scene_state_skips_locally_controlled_player():
		# Mock locally-controlled player.
		var input_from_client = PlayerInputFromClient.new()
		input_from_client.name = "InputFromClient"
		input_from_client.root_path = NodePath(".")
		input_from_client.replication_config = SceneReplicationConfig.new()
		input_from_client.player = player
		player.add_child(input_from_client)
		player.input_from_client = input_from_client

		# Set multiplayer authority to simulate local control.
		input_from_client.set_multiplayer_authority(1)

		# Set forwarded input actions.
		forwarded_input.actions = 0b0011

		# Create previous state.
		var previous_state := ArrayPool.acquire(2)
		previous_state[0] = 0b0001 # previous actions
		previous_state[1] = -1 # previous jump timestamp

		# Sync to scene state.
		forwarded_input._sync_to_scene_state(previous_state)

		# Player actions should NOT be modified (locally-controlled player).
		assert_eq(
			player.actions.bitmask,
			0,
			"Should not modify locally-controlled player actions",
		)

		ArrayPool.release(previous_state)


	func test_sync_to_scene_state_updates_remote_player_actions():
		# Mock remote player (no local authority).
		player.input_from_client = null

		# Set forwarded input actions.
		forwarded_input.actions = 0b0011

		# Create previous state.
		var previous_state := ArrayPool.acquire(2)
		previous_state[0] = 0b0001 # previous actions
		previous_state[1] = -1 # previous jump timestamp

		# Sync to scene state.
		forwarded_input._sync_to_scene_state(previous_state)

		# Player actions should be updated.
		assert_eq(
			player.actions.bitmask,
			0b0011,
			"Should update remote player actions",
		)
		assert_eq(
			player.actions.previous_bitmask,
			0b0001,
			"Should update previous actions",
		)

		ArrayPool.release(previous_state)


	func test_sync_to_scene_state_updates_jump_frame_index():
		# Mock remote player.
		player.input_from_client = null

		# Set jump interaction at frame 60.
		forwarded_input.last_interaction_type = PlayerInputNetworkState.ClientInteractionType.JUMP
		forwarded_input.last_interaction_frame_index = 60

		# Create previous state.
		var previous_state := ArrayPool.acquire(2)
		previous_state[0] = 0
		previous_state[1] = -1

		# Sync to scene state.
		forwarded_input._sync_to_scene_state(previous_state)

		# Player should have jump frame index = 60.
		assert_eq(
			player.last_triggered_jump_frame_index,
			60,
			"Should update jump frame index",
		)

		ArrayPool.release(previous_state)


	func test_sync_from_scene_state_does_nothing():
		# Set player actions.
		player.actions.bitmask = 0b1111

		# Sync from scene state.
		forwarded_input._sync_from_scene_state()

		# Forwarded input actions should remain 0 (server-authoritative).
		assert_eq(
			forwarded_input.actions,
			0,
			"Should not read from scene (server-authoritative)",
		)


	func test_network_process_is_empty():
		# Should not crash when called.
		forwarded_input._network_process()

		# Assert that the method completed successfully without crashing.
		assert_true(
			true,
			"_network_process() should complete without crashing",
		)
