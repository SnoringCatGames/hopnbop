@tool
extends GutTest
## Unit tests for ReconcilableState 3-node configuration validation.
##
## Tests the new validation logic that supports:
## - 1-node: NPC with only CharacterStateFromServer
## - 2-node: Player with CharacterStateFromServer + PlayerInputFromClient
## - 3-node: Player with CharacterStateFromServer + PlayerInputFromClient +
##           ForwardedPlayerInputFromServer

func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


## Test helper for server-authoritative state (like CharacterStateFromServer).
class TestServerAuthState extends ReconcilableState:
	var test_value := 0

	@warning_ignore("unused_private_class_variable") var _synced_properties_and_rollback_diff_thresholds := {
		"test_value": 0,
	}


	func _has_non_rollbackable_interactions() -> bool:
		return false  # Test class doesn't use interaction tracking.


	func _init() -> void:
		super._init()
		if replication_config == null:
			replication_config = SceneReplicationConfig.new()


	func _get_default_values() -> Array:
		return [0]


	func _get_is_server_authoritative() -> bool:
		return true


	func _sync_to_scene_state(_previous_state: Array) -> void:
		pass


	func _sync_from_scene_state() -> void:
		pass


## Test helper for client-authoritative state (like PlayerInputFromClient).
class TestClientAuthState extends ReconcilableState:
	var test_value := 0

	@warning_ignore("unused_private_class_variable") var _synced_properties_and_rollback_diff_thresholds := {
		"test_value": 0,
	}


	func _has_non_rollbackable_interactions() -> bool:
		return false  # Test class doesn't use interaction tracking.


	func _init() -> void:
		super._init()
		if replication_config == null:
			replication_config = SceneReplicationConfig.new()


	func _get_default_values() -> Array:
		return [0]


	func _get_is_server_authoritative() -> bool:
		return false


	func _sync_to_scene_state(_previous_state: Array) -> void:
		pass


	func _sync_from_scene_state() -> void:
		pass


## Test helper for forwarded input (server-authoritative, second server-auth node).
class TestForwardedState extends ReconcilableState:
	var test_value := 0

	@warning_ignore("unused_private_class_variable") var _synced_properties_and_rollback_diff_thresholds := {
		"test_value": 0,
	}


	func _has_non_rollbackable_interactions() -> bool:
		return false  # Test class doesn't use interaction tracking.


	func _init() -> void:
		super._init()
		if replication_config == null:
			replication_config = SceneReplicationConfig.new()


	func _get_default_values() -> Array:
		return [0]


	func _get_is_server_authoritative() -> bool:
		return true


	func _sync_to_scene_state(_previous_state: Array) -> void:
		pass


	func _sync_from_scene_state() -> void:
		pass


class TestThreeNodeValidationErrors:
	extends GutTest

	var root_node: Node


	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)


	func after_each():
		ArrayPool.clear_all_pools()


	func test_three_nodes_with_two_client_auth_shows_warning():
		# Create invalid setup: 2 client-auth + 1 server-auth.
		var client_state_1 = TestClientAuthState.new()
		client_state_1.name = "ClientState1"
		client_state_1.root_path = NodePath(".")
		root_node.add_child(client_state_1)

		var client_state_2 = TestClientAuthState.new()
		client_state_2.name = "ClientState2"
		client_state_2.root_path = NodePath(".")
		root_node.add_child(client_state_2)

		var server_state = TestServerAuthState.new()
		server_state.name = "ServerState"
		server_state.root_path = NodePath(".")
		root_node.add_child(server_state)

		# Initialize nodes.
		client_state_1._ready()
		client_state_2._ready()
		server_state._ready()

		# Should have configuration warning.
		assert_ne(
			client_state_1._partner_state_configuration_warning,
			"",
			"Should have warning for invalid 3-node setup",
		)
		assert_true(
			"exactly 1 client-authoritative" in \
			client_state_1._partner_state_configuration_warning,
			"Warning should mention client-authoritative requirement",
		)


	func test_three_nodes_with_three_server_auth_shows_warning():
		# Create invalid setup: 3 server-auth.
		var server_state_1 = TestServerAuthState.new()
		server_state_1.name = "ServerState1"
		server_state_1.root_path = NodePath(".")
		root_node.add_child(server_state_1)

		var server_state_2 = TestServerAuthState.new()
		server_state_2.name = "ServerState2"
		server_state_2.root_path = NodePath(".")
		root_node.add_child(server_state_2)

		var server_state_3 = TestServerAuthState.new()
		server_state_3.name = "ServerState3"
		server_state_3.root_path = NodePath(".")
		root_node.add_child(server_state_3)

		# Initialize nodes.
		server_state_1._ready()
		server_state_2._ready()
		server_state_3._ready()

		# Should have configuration warning.
		assert_ne(
			server_state_1._partner_state_configuration_warning,
			"",
			"Should have warning for 3 server-auth setup",
		)


	func test_four_nodes_shows_warning():
		# Create invalid setup: 4 nodes.
		var server_state = TestServerAuthState.new()
		server_state.name = "ServerState"
		server_state.root_path = NodePath(".")
		root_node.add_child(server_state)

		var client_state = TestClientAuthState.new()
		client_state.name = "ClientState"
		client_state.root_path = NodePath(".")
		root_node.add_child(client_state)

		var forwarded_state_1 = TestForwardedState.new()
		forwarded_state_1.name = "ForwardedState1"
		forwarded_state_1.root_path = NodePath(".")
		root_node.add_child(forwarded_state_1)

		var forwarded_state_2 = TestForwardedState.new()
		forwarded_state_2.name = "ForwardedState2"
		forwarded_state_2.root_path = NodePath(".")
		root_node.add_child(forwarded_state_2)

		# Initialize nodes.
		server_state._ready()
		client_state._ready()
		forwarded_state_1._ready()
		forwarded_state_2._ready()

		# Should have configuration warning about too many nodes.
		assert_ne(
			server_state._partner_state_configuration_warning,
			"",
			"Should have warning for 4 nodes",
		)
		assert_true(
			"no more than 3" in \
			server_state._partner_state_configuration_warning,
			"Warning should mention maximum of 3 nodes",
		)


class TestBackwardCompatibility:
	extends GutTest

	var root_node: Node


	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		root_node.name = "Root"
		add_child_autofree(root_node)


	func after_each():
		ArrayPool.clear_all_pools()


	func test_one_node_npc_still_valid():
		# NPC with only server-authoritative state.
		var server_state = TestServerAuthState.new()
		server_state.name = "ServerState"
		server_state.root_path = NodePath(".")
		root_node.add_child(server_state)

		server_state._ready()

		# Should have no siblings (NPC).
		assert_null(
			server_state.input_from_client,
			"NPC should have no input_from_client",
		)
		assert_null(
			server_state.forwarded_input_from_server,
			"NPC should have no forwarded_input_from_server",
		)

		# Should have no warnings.
		assert_eq(
			server_state._partner_state_configuration_warning,
			"",
			"NPC should have no configuration warnings",
		)
