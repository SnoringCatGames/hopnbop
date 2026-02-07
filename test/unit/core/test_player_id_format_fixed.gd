extends GutTest
## Unit tests for int-based player ID handling with server-assigned sequential IDs.


## Helper function to create default player attributes for testing.
static func _get_default_attributes() -> Dictionary:
	return {
		"bunny_name": "TestBunny",
		"adjective": "TestAdj",
		"is_soft": false,
		"body_type_index": 0,
		"costume_index": 0,
	}


class TestLobbyPlayerIds:
	extends GutTest

	func test_lobby_uses_negative_ids():
		var player_id_0 := LobbyLevel.get_local_player_id(0)
		var player_id_1 := LobbyLevel.get_local_player_id(1)
		var player_id_2 := LobbyLevel.get_local_player_id(2)

		assert_eq(player_id_0, -1)
		assert_eq(player_id_1, -2)
		assert_eq(player_id_2, -3)

	func test_lobby_ids_are_sequential_negative():
		for i in range(10):
			var player_id := LobbyLevel.get_local_player_id(i)
			assert_eq(player_id, - (i + 1))

	func test_lobby_ids_are_negative():
		for i in range(5):
			var player_id := LobbyLevel.get_local_player_id(i)
			assert_lt(player_id, 0, "Lobby player_id should be negative")

	func test_lobby_different_indices_different_ids():
		var player_id_0 := LobbyLevel.get_local_player_id(0)
		var player_id_1 := LobbyLevel.get_local_player_id(1)
		assert_ne(player_id_0, player_id_1)


class TestPlayerStateWithInts:
	extends GutTest

	static func _get_default_attributes() -> Dictionary:
		return {
			"bunny_name": "TestBunny",
			"adjective": "TestAdj",
			"is_soft": false,
			"body_type_index": 0,
			"costume_index": 0,
		}

	func test_player_match_state_stores_int_player_id():
		var player := PlayerState.new()
		player.set_up(42, 1234, 0, _get_default_attributes())

		assert_eq(player.player_id, 42)
		assert_typeof(player.player_id, TYPE_INT)

	func test_player_match_state_stores_explicit_peer_id():
		var player := PlayerState.new()
		player.set_up(42, 1234, 0, _get_default_attributes())

		assert_eq(player.peer_id, 1234)
		assert_typeof(player.peer_id, TYPE_INT)

	func test_player_match_state_stores_explicit_local_index():
		var player := PlayerState.new()
		player.set_up(42, 1234, 2, _get_default_attributes())

		assert_eq(player.local_player_index, 2)
		assert_typeof(player.local_player_index, TYPE_INT)

	func test_player_match_state_with_negative_lobby_id():
		var player := PlayerState.new()
		player.set_up(-1, 0, 0, _get_default_attributes())

		assert_eq(player.player_id, -1)
		assert_lt(player.player_id, 0)

	func test_player_match_state_multiple_players_same_peer():
		var players: Array[PlayerState] = []

		# Simulate server assigning IDs 1, 2, 3 to peer 1234
		for i in range(3):
			var player := PlayerState.new()
			player.set_up(i + 1, 1234, i, _get_default_attributes())
			players.append(player)

		assert_eq(players[0].player_id, 1)
		assert_eq(players[0].peer_id, 1234)
		assert_eq(players[0].local_player_index, 0)

		assert_eq(players[1].player_id, 2)
		assert_eq(players[1].peer_id, 1234)
		assert_eq(players[1].local_player_index, 1)

		assert_eq(players[2].player_id, 3)
		assert_eq(players[2].peer_id, 1234)
		assert_eq(players[2].local_player_index, 2)
