extends GutTest
## Integration tests for multi-player declaration protocol.


func before_each():
	ArrayPool.clear_all_pools()
	# Initialize network systems.
	if not G.network.time.is_time_initialized:
		G.network.time._start_time_offset_usec = 0


func after_each():
	ArrayPool.clear_all_pools()


class TestMatchStateSynchronizerPlayerCreation:
	extends GutTest

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_creates_player_match_states_for_declared_count():
		var synchronizer := MatchStateSynchronizer.new()
		var peer_id := 1234
		var session_ids := ["1", "2"]

		# Simulate peer_players_declared signal.
		synchronizer._server_on_peer_players_declared(peer_id, session_ids)

		# Verify 2 PlayerMatchState objects created.
		assert_eq(synchronizer.state.players.size(), 2)
		assert_has(synchronizer.state.players, "1234:0")
		assert_has(synchronizer.state.players, "1234:1")

	func test_player_ids_have_correct_format():
		var synchronizer := MatchStateSynchronizer.new()
		var session_ids := ["1", "2", "3"]
		synchronizer._server_on_peer_players_declared(1, session_ids)

		var player_ids := synchronizer.state.players.keys()
		assert_has(player_ids, "1:0")
		assert_has(player_ids, "1:1")
		assert_has(player_ids, "1:2")

	func test_player_match_states_have_correct_peer_id():
		var synchronizer := MatchStateSynchronizer.new()
		var peer_id := 5678
		var session_ids := ["1", "2"]
		synchronizer._server_on_peer_players_declared(peer_id, session_ids)

		var player0: PlayerMatchState = synchronizer.state.players["5678:0"]
		var player1: PlayerMatchState = synchronizer.state.players["5678:1"]

		assert_eq(player0.peer_id, 5678)
		assert_eq(player1.peer_id, 5678)
		assert_eq(player0.local_player_index, 0)
		assert_eq(player1.local_player_index, 1)

	func test_multiple_peers_create_separate_players():
		var synchronizer := MatchStateSynchronizer.new()
		synchronizer._server_on_peer_players_declared(1, ["1", "2"])
		synchronizer._server_on_peer_players_declared(2, ["3"])

		assert_eq(synchronizer.state.players.size(), 3)
		assert_has(synchronizer.state.players, "1:0")
		assert_has(synchronizer.state.players, "1:1")
		assert_has(synchronizer.state.players, "2:0")


class TestNetworkedLevelPlayerSpawning:
	extends GutTest
	var root_node: Node
	var networked_level: NetworkedLevel

	func before_each():
		ArrayPool.clear_all_pools()
		root_node = Node.new()
		add_child_autofree(root_node)

		# Create networked level.
		networked_level = preload(
			"res://src/level/default_level.tscn"
		).instantiate()
		root_node.add_child(networked_level)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_spawns_n_players_for_peer():
		var peer_id := 1234
		var player_count := 3

		networked_level._server_register_players_for_peer(peer_id, player_count)

		assert_eq(networked_level.players.size(), 3)
		assert_has(networked_level.players_by_id, "1234:0")
		assert_has(networked_level.players_by_id, "1234:1")
		assert_has(networked_level.players_by_id, "1234:2")

	func test_builds_peer_to_player_ids_mapping():
		var peer_id := 1234
		networked_level._server_register_players_for_peer(peer_id, 2)

		assert_has(networked_level.peer_to_player_ids, 1234)
		var player_ids: Array = networked_level.peer_to_player_ids[1234]
		assert_eq(player_ids.size(), 2)
		assert_has(player_ids, "1234:0")
		assert_has(player_ids, "1234:1")

	func test_removes_all_players_on_peer_disconnect():
		var peer_id := 1234
		networked_level._server_register_players_for_peer(peer_id, 2)
		assert_eq(networked_level.players.size(), 2)

		networked_level._server_deregister_players_for_peer(peer_id)

		assert_eq(networked_level.players.size(), 0)
		assert_false(networked_level.peer_to_player_ids.has(peer_id))

	func test_multiple_peers_tracked_independently():
		networked_level._server_register_players_for_peer(1, 2)
		networked_level._server_register_players_for_peer(2, 3)

		assert_eq(networked_level.players.size(), 5)
		assert_eq(networked_level.peer_to_player_ids[1].size(), 2)
		assert_eq(networked_level.peer_to_player_ids[2].size(), 3)

	func test_disconnect_one_peer_preserves_others():
		networked_level._server_register_players_for_peer(1, 2)
		networked_level._server_register_players_for_peer(2, 1)

		networked_level._server_deregister_players_for_peer(1)

		assert_eq(networked_level.players.size(), 1)
		assert_has(networked_level.players_by_id, "2:0")
		assert_false(networked_level.players_by_id.has("1:0"))


class TestPlayerIdFormatConsistency:
	extends GutTest

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_match_state_and_networked_level_ids_match():
		var synchronizer := MatchStateSynchronizer.new()
		var root_node := Node.new()
		add_child_autofree(root_node)
		var networked_level := preload(
			"res://src/level/default_level.tscn"
		).instantiate()
		root_node.add_child(networked_level)

		var peer_id := 1234
		var session_ids := ["1", "2"]

		# Create players in both systems.
		synchronizer._server_on_peer_players_declared(peer_id, session_ids)
		networked_level._server_register_players_for_peer(peer_id, session_ids)

		# Verify IDs match.
		var match_state_ids := synchronizer.state.players.keys()
		var level_ids: Array = networked_level.players_by_id.keys()

		for player_id in match_state_ids:
			assert_has(level_ids, player_id)
