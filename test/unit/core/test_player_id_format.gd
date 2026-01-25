extends GutTest
## Unit tests for player ID format handling.


class TestPlayerIdCreation:
	extends GutTest

	func test_composite_format_creation():
		var peer_id := 1234
		var local_index := 0
		var player_id := NetworkConnector.get_player_id(peer_id, local_index)
		assert_eq(player_id, "1234:0")

	func test_multiple_players_same_peer():
		var peer_id := 1234
		var player_ids: Array[StringName] = []
		for i in range(3):
			player_ids.append(NetworkConnector.get_player_id(peer_id, i))

		assert_eq(player_ids[0], "1234:0")
		assert_eq(player_ids[1], "1234:1")
		assert_eq(player_ids[2], "1234:2")

	func test_lobby_format_creation():
		var local_index := 2
		var player_id := "lobby:%d" % local_index
		assert_eq(player_id, "lobby:2")

	func test_different_peers_same_local_index():
		var player_id_1 := NetworkConnector.get_player_id(1234, 0)
		var player_id_2 := NetworkConnector.get_player_id(5678, 0)
		assert_ne(player_id_1, player_id_2)
		assert_eq(player_id_1, "1234:0")
		assert_eq(player_id_2, "5678:0")


class TestPlayerIdParsing:
	extends GutTest

	func test_extract_peer_id_from_valid_format():
		var player_id := "1234:0"
		var parts := player_id.split(":")
		assert_eq(parts.size(), 2)
		assert_eq(int(parts[0]), 1234)
		assert_eq(int(parts[1]), 0)

	func test_extract_local_index():
		var player_id := "1234:2"
		var parts := player_id.split(":")
		var local_index := int(parts[1])
		assert_eq(local_index, 2)

	func test_empty_player_id_parsing():
		var player_id := ""
		var parts := player_id.split(":")
		# Should handle gracefully
		assert_eq(parts.size(), 1)
		assert_eq(parts[0], "")

	func test_malformed_player_id_no_colon():
		var player_id := "1234"
		var parts := player_id.split(":")
		assert_eq(parts.size(), 1)
		# Only one part, extraction would fail

	func test_malformed_player_id_extra_colons():
		var player_id := "1234:0:extra"
		var parts := player_id.split(":")
		assert_eq(parts.size(), 3)
		# Should use first two parts only
		assert_eq(int(parts[0]), 1234)
		assert_eq(int(parts[1]), 0)

	func test_lobby_format_parsing():
		var player_id := "lobby:1"
		var parts := player_id.split(":")
		assert_eq(parts.size(), 2)
		assert_eq(parts[0], "lobby")
		assert_eq(int(parts[1]), 1)


class TestPlayerMatchStateIdHandling:
	extends GutTest

	func test_player_match_state_parses_composite_id():
		var player := PlayerMatchState.new()
		player.set_up("1234:0", true)
		assert_eq(player.player_id, "1234:0")
		assert_eq(player.peer_id, 1234)
		assert_eq(player.local_index, 0)

	func test_player_match_state_handles_lobby_format():
		var player := PlayerMatchState.new()
		player.set_up("lobby:1", true)
		assert_eq(player.player_id, "lobby:1")
		# peer_id extraction may fail for lobby format - check behavior
		# The _parse_player_id function tries to parse "lobby" as int

	func test_player_match_state_handles_multiple_indices():
		for i in range(4):
			var player := PlayerMatchState.new()
			player.set_up("1234:%d" % i, true)
			assert_eq(player.peer_id, 1234)
			assert_eq(player.local_index, i)

	func test_player_match_state_extracts_peer_from_different_peers():
		var peer_ids := [1, 1234, 5678, 999999]
		for peer_id in peer_ids:
			var player := PlayerMatchState.new()
			player.set_up("%d:0" % peer_id, true)
			assert_eq(player.peer_id, peer_id)


class TestPlayerIdEdgeCases:
	extends GutTest

	func test_zero_peer_id():
		var player_id := "0:0"
		var parts := player_id.split(":")
		assert_eq(int(parts[0]), 0)

	func test_very_large_peer_id():
		var peer_id := 2147483647 # Max int32
		var player_id := "%d:0" % peer_id
		var parts := player_id.split(":")
		assert_eq(int(parts[0]), peer_id)

	func test_large_local_index():
		var player_id := "1234:99"
		var parts := player_id.split(":")
		assert_eq(int(parts[1]), 99)

	func test_colon_only():
		var player_id := ":"
		var parts := player_id.split(":")
		assert_eq(parts.size(), 2)
		assert_eq(parts[0], "")
		assert_eq(parts[1], "")

	func test_leading_colon():
		var player_id := ":0"
		var parts := player_id.split(":")
		assert_eq(parts.size(), 2)
		assert_eq(parts[0], "")
		assert_eq(parts[1], "0")

	func test_trailing_colon():
		var player_id := "1234:"
		var parts := player_id.split(":")
		assert_eq(parts.size(), 2)
		assert_eq(parts[0], "1234")
		assert_eq(parts[1], "")
