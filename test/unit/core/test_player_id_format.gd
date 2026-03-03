class_name TestPlayerIdFormat
extends GutTest
## Unit tests for int-based player ID handling with server-assigned sequential IDs.


## Shared helper for creating default player attributes.
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

	func test_player_match_state_stores_int_player_id():
		var player := PlayerState.new()
		player.set_up(42, 1234, 0, TestPlayerIdFormat._get_default_attributes())

		assert_eq(player.player_id, 42)
		assert_typeof(player.player_id, TYPE_INT)

	func test_player_match_state_stores_explicit_peer_id():
		var player := PlayerState.new()
		player.set_up(42, 1234, 0, TestPlayerIdFormat._get_default_attributes())

		assert_eq(player.peer_id, 1234)
		assert_typeof(player.peer_id, TYPE_INT)

	func test_player_match_state_stores_explicit_local_index():
		var player := PlayerState.new()
		player.set_up(42, 1234, 2, TestPlayerIdFormat._get_default_attributes())

		assert_eq(player.local_player_index, 2)
		assert_typeof(player.local_player_index, TYPE_INT)

	func test_player_match_state_with_negative_lobby_id():
		var player := PlayerState.new()
		player.set_up(-1, 0, 0, TestPlayerIdFormat._get_default_attributes())

		assert_eq(player.player_id, -1)
		assert_lt(player.player_id, 0)

	func test_player_match_state_multiple_players_same_peer():
		var players: Array[PlayerState] = []

		# Simulate server assigning IDs 1, 2, 3 to peer 1234
		for i in range(3):
			var player := PlayerState.new()
			player.set_up(i + 1, 1234, i, TestPlayerIdFormat._get_default_attributes())
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


class TestPlayerIdPacking:
	extends GutTest

	func test_packed_state_preserves_int_player_id():
		var player := PlayerState.new()
		player.set_up(42, 1234, 0, TestPlayerIdFormat._get_default_attributes())

		var packed := player.get_packed_state()
		var player_id_from_packed := PlayerState.get_player_id_from_packed_state(packed)

		assert_eq(player_id_from_packed, 42)
		assert_typeof(player_id_from_packed, TYPE_INT)

	func test_packed_state_preserves_peer_id_and_local_index():
		var player := PlayerState.new()
		player.set_up(42, 1234, 2, TestPlayerIdFormat._get_default_attributes())

		var packed := player.get_packed_state()

		var restored := PlayerState.new()
		restored.populate_from_packed_state(packed)

		assert_eq(restored.player_id, 42)
		assert_eq(restored.peer_id, 1234)
		assert_eq(restored.local_player_index, 2)

	func test_packed_state_with_negative_lobby_id():
		var player := PlayerState.new()
		player.set_up(-1, 0, 0, TestPlayerIdFormat._get_default_attributes())

		var packed := player.get_packed_state()
		var player_id_from_packed := PlayerState.get_player_id_from_packed_state(packed)

		assert_eq(player_id_from_packed, -1)


class TestPlayerIdEdgeCases:
	extends GutTest

	func test_zero_player_id():
		var player := PlayerState.new()
		assert_eq(player.player_id, 0, "Default player_id should be 0")

	func test_very_large_positive_player_id():
		var player := PlayerState.new()
		var large_id := 2147483647 # Max int32
		player.set_up(large_id, 1, 0, TestPlayerIdFormat._get_default_attributes())

		assert_eq(player.player_id, large_id)

	func test_negative_lobby_id_range():
		# Test large range of lobby player indices.
		for i in range(100):
			var player_id := LobbyLevel.get_local_player_id(i)
			assert_lt(player_id, 0, "Lobby IDs must be negative")
			assert_eq(player_id, - (i + 1))

class TestMatchStateKillsAndBumpsArrays:
	extends GutTest

	func test_kills_uses_packed_int32_array():
		var match_state := GameMatchState.new()

		# Server records kill: player 1 killed player 2
		match_state.kills = PackedInt32Array([1, 2])

		assert_typeof(match_state.kills, TYPE_PACKED_INT32_ARRAY)
		assert_eq(match_state.kills.size(), 2)
		assert_eq(match_state.kills[0], 1)
		assert_eq(match_state.kills[1], 2)

	func test_bumps_uses_packed_int32_array():
		var match_state := GameMatchState.new()

		# Server records bump: player 3 bumped player 4
		match_state.bumps = PackedInt32Array([3, 4])

		assert_typeof(match_state.bumps, TYPE_PACKED_INT32_ARRAY)
		assert_eq(match_state.bumps.size(), 2)
		assert_eq(match_state.bumps[0], 3)
		assert_eq(match_state.bumps[1], 4)

	func test_multiple_kills_sequential():
		var match_state := GameMatchState.new()

		# Multiple kills: 1->2, 3->4, 5->6
		match_state.kills = PackedInt32Array([1, 2, 3, 4, 5, 6])

		assert_eq(match_state.kills.size(), 6)
		# First kill
		assert_eq(match_state.kills[0], 1)
		assert_eq(match_state.kills[1], 2)
		# Second kill
		assert_eq(match_state.kills[2], 3)
		assert_eq(match_state.kills[3], 4)
		# Third kill
		assert_eq(match_state.kills[4], 5)
		assert_eq(match_state.kills[5], 6)

	func test_kills_with_negative_lobby_ids():
		var match_state := GameMatchState.new()

		# Lobby player -1 kills lobby player -2
		match_state.kills = PackedInt32Array([-1, -2])

		assert_eq(match_state.kills[0], -1)
		assert_eq(match_state.kills[1], -2)
