extends GutTest
## Integration tests for multi-player declaration with server-assigned sequential IDs.

const DEFAULT_LEVEL_SCENE := preload("res://src/level/level_1.tscn")


## Helper function to create default player attributes for testing.
static func _get_default_attributes() -> Dictionary:
	return {
		"bunny_name": "TestBunny",
		"adjective": "TestAdj",
		"is_soft": false,
		"body_type_index": 0,
		"costume_index": 0,
	}


func before_each():
	ArrayPool.clear_all_pools()
	# Initialize network frame tracking.
	if not Netcode.frame_driver._is_frame_tracking_initialized:
		Netcode.frame_driver._initialize_frame_tracking()


func after_each():
	ArrayPool.clear_all_pools()


class TestMatchStateSynchronizerPlayerCreation:
	extends GutTest

	static func _get_default_attributes() -> Dictionary:
		return {
			"bunny_name": "TestBunny",
			"adjective": "TestAdj",
			"is_soft": false,
			"body_type_index": 0,
			"costume_index": 0,
		}

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_creates_player_match_states_for_assigned_ids():
		var synchronizer := MatchStateSynchronizer.new()
		var peer_id := 1234
		var assigned_ids: Array[int] = [1, 2]
		var attributes := [
			_get_default_attributes(),
			_get_default_attributes(),
		]

		# Simulate server assigning IDs 1 and 2 to this peer.
		synchronizer._server_on_peer_players_declared(
			peer_id,
			assigned_ids,
			attributes
		)

		# Verify 2 PlayerMatchState objects created with int keys.
		assert_eq(synchronizer.state.players_by_id.size(), 2)
		assert_has(synchronizer.state.players_by_id, 1)
		assert_has(synchronizer.state.players_by_id, 2)

	func test_player_ids_are_sequential_ints():
		var synchronizer := MatchStateSynchronizer.new()
		var assigned_ids: Array[int] = [1, 2, 3]
		var attributes := [
			_get_default_attributes(),
			_get_default_attributes(),
			_get_default_attributes(),
		]
		synchronizer._server_on_peer_players_declared(1, assigned_ids, attributes)

		var player_ids := synchronizer.state.players_by_id.keys()
		assert_has(player_ids, 1)
		assert_has(player_ids, 2)
		assert_has(player_ids, 3)

		# Verify they're ints, not strings.
		for player_id in player_ids:
			assert_typeof(player_id, TYPE_INT)

	func test_player_match_states_store_explicit_peer_id_and_local_index():
		var synchronizer := MatchStateSynchronizer.new()
		var peer_id := 5678
		var assigned_ids: Array[int] = [10, 11]
		var attributes := [
			_get_default_attributes(),
			_get_default_attributes(),
		]
		synchronizer._server_on_peer_players_declared(
			peer_id, assigned_ids, attributes)

		var player0: PlayerMatchState = synchronizer.state.players_by_id[10]
		var player1: PlayerMatchState = synchronizer.state.players_by_id[11]

		# Check player_ids are as assigned.
		assert_eq(player0.player_id, 10)
		assert_eq(player1.player_id, 11)

		# Check explicit peer_id and local_player_index.
		assert_eq(player0.peer_id, 5678)
		assert_eq(player1.peer_id, 5678)
		assert_eq(player0.local_player_index, 0)
		assert_eq(player1.local_player_index, 1)

	func test_multiple_peers_get_non_overlapping_ids():
		var synchronizer := MatchStateSynchronizer.new()

		# Peer 1 gets IDs [1, 2]
		synchronizer._server_on_peer_players_declared(1, [1, 2],
		[
			_get_default_attributes(),
			_get_default_attributes(),
		])

		# Peer 2 gets IDs [3]
		synchronizer._server_on_peer_players_declared(2, [3],
		[
			_get_default_attributes()
		])

		assert_eq(synchronizer.state.players_by_id.size(), 3)
		assert_has(synchronizer.state.players_by_id, 1)
		assert_has(synchronizer.state.players_by_id, 2)
		assert_has(synchronizer.state.players_by_id, 3)

		# Verify peer_ids are correct.
		assert_eq(synchronizer.state.players_by_id[1].peer_id, 1)
		assert_eq(synchronizer.state.players_by_id[2].peer_id, 1)
		assert_eq(synchronizer.state.players_by_id[3].peer_id, 2)


class TestNetworkedLevelPlayerSpawning:
	extends GutTest
	var root_node: Node
	var networked_level: NetworkedLevel
	var mock_game_panel: Node

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Mock G.game_panel to avoid null reference errors.
		mock_game_panel = MockGamePanel.new()
		G.game_panel = mock_game_panel

		# Mock G.match_state.
		G.match_state = GameMatchState.new()

		# Create networked level.
		networked_level = DEFAULT_LEVEL_SCENE.instantiate()
		root_node.add_child(networked_level)
		G.level = networked_level

	func after_each():
		ArrayPool.clear_all_pools()
		G.game_panel = null
		G.match_state = null
		if is_instance_valid(mock_game_panel):
			mock_game_panel.queue_free()

	func test_builds_peer_to_player_ids_mapping():
		var peer_id := 1234
		var assigned_ids: Array[int] = [10, 11]
		networked_level._server_register_players_for_peer(peer_id, assigned_ids)

		assert_has(networked_level.peer_to_player_ids, 1234)
		var player_ids: Array = networked_level.peer_to_player_ids[1234]
		assert_eq(player_ids.size(), 2)
		assert_has(player_ids, 10)
		assert_has(player_ids, 11)


class TestPlayerIdFormatConsistency:
	extends GutTest

	static func _get_default_attributes() -> Dictionary:
		return {
			"bunny_name": "TestBunny",
			"adjective": "TestAdj",
			"is_soft": false,
			"body_type_index": 0,
			"costume_index": 0,
		}

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_match_state_and_networked_level_ids_match():
		var synchronizer := MatchStateSynchronizer.new()
		var root_node := Node.new()
		add_child_autofree(root_node)

		# Mock G.game_panel to avoid null reference errors.
		var mock_game_panel := MockGamePanel.new()
		G.game_panel = mock_game_panel

		# Mock G.match_state.
		G.match_state = GameMatchState.new()

		var networked_level := DEFAULT_LEVEL_SCENE.instantiate()
		root_node.add_child(networked_level)
		G.level = networked_level

		var peer_id := 1234
		var assigned_ids: Array[int] = [1, 2]
		var attributes := [
			_get_default_attributes(),
			_get_default_attributes(),
		]

		# Create players in both systems with same assigned IDs.
		synchronizer._server_on_peer_players_declared(
			peer_id, assigned_ids, attributes)
		networked_level._server_register_players_for_peer(peer_id, assigned_ids)

		# Verify IDs match (both use int keys now).
		var match_state_ids := synchronizer.state.players_by_id.keys()
		var level_ids: Array = networked_level.players_by_id.keys()

		for player_id in match_state_ids:
			assert_has(level_ids, player_id)
			assert_typeof(player_id, TYPE_INT)

		# Cleanup.
		G.game_panel = null
		G.match_state = null
		mock_game_panel.queue_free()


class TestServerIdAssignmentSimulation:
	extends GutTest

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_sequential_id_assignment():
		# Simulate NetworkConnector behavior.
		var next_player_id := 1

		# Client 1 declares 2 players.
		var client1_ids: Array[int] = []
		for i in range(2):
			client1_ids.append(next_player_id)
			next_player_id += 1

		# Client 2 declares 3 players.
		var client2_ids: Array[int] = []
		for i in range(3):
			client2_ids.append(next_player_id)
			next_player_id += 1

		# Verify sequential and non-overlapping.
		assert_eq(client1_ids, [1, 2])
		assert_eq(client2_ids, [3, 4, 5])

	func test_ids_never_reused():
		var next_player_id := 1
		var all_ids: Array[int] = []

		# Simulate 10 clients each with 2 players.
		for client_num in range(10):
			for player_num in range(2):
				all_ids.append(next_player_id)
				next_player_id += 1

		# Verify all unique.
		var unique_check := {}
		for id in all_ids:
			assert_false(
				unique_check.has(id),
				"ID %d was reused" % id
			)
			unique_check[id] = true

		# Verify sequential.
		for i in range(all_ids.size()):
			assert_eq(all_ids[i], i + 1)
