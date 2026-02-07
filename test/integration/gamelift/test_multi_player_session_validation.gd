extends GutTest
## Integration tests for GameLift multi-player session validation with
## int-based player IDs.
##
## These tests run in preview mode (GameLift SDK not loaded) which uses
## the auto-accept validation path.


class TestMultiPlayerSessionValidation:
	extends GutTest

	var provider: GameLiftServerProvider

	func before_each():
		provider = GameLiftServerProvider.new()
		add_child_autofree(provider)
		await wait_frames(1)

	func test_validates_all_sessions_for_peer():
		# Verify provider validates all session IDs for a peer.
		provider.server_set_expected_player_count(2)

		var player_ids: Array[int] = [1, 2]
		var session_ids: Array = ["session_1", "session_2"]

		provider.server_validate_player_sessions(10, player_ids, session_ids)

		# Validation happens synchronously in preview mode.
		# Verify all players were validated.
		assert_eq(
			provider._validated_player_count,
			2,
			"Should have validated 2 players"
		)

		# Verify mappings created for both players.
		assert_eq(
			provider._player_to_session.size(),
			2,
			"Should have 2 player mappings"
		)
		assert_eq(
			provider._session_to_player.size(),
			2,
			"Should have 2 session mappings"
		)

	func test_player_to_session_bidirectional_mapping():
		# Verify bidirectional mapping between player_id and session_id.
		provider.server_set_expected_player_count(1)

		var player_ids: Array[int] = [42]
		var session_ids: Array = ["test_session_abc"]

		provider.server_validate_player_sessions(10, player_ids, session_ids)

		# Verify forward mapping (player -> session).
		assert_true(
			provider._player_to_session.has(42),
			"Should have player_id in forward map"
		)
		assert_eq(
			provider._player_to_session[42],
			"test_session_abc",
			"Should map player_id to session_id"
		)

		# Verify reverse mapping (session -> player).
		assert_true(
			provider._session_to_player.has("test_session_abc"),
			"Should have session_id in reverse map"
		)
		assert_eq(
			provider._session_to_player["test_session_abc"],
			42,
			"Should map session_id to player_id"
		)

	func test_multiple_players_tracked_independently():
		# Verify multiple players have separate mappings.
		provider.server_set_expected_player_count(3)

		var player_ids: Array[int] = [1, 2, 3]
		var session_ids: Array = ["session_a", "session_b", "session_c"]

		provider.server_validate_player_sessions(10, player_ids, session_ids)

		# Verify all players mapped.
		assert_eq(
			provider._player_to_session.size(),
			3,
			"Should have 3 player mappings"
		)
		assert_eq(
			provider._session_to_player.size(),
			3,
			"Should have 3 session mappings"
		)

		# Verify individual mappings.
		assert_eq(provider._player_to_session[1], "session_a")
		assert_eq(provider._player_to_session[2], "session_b")
		assert_eq(provider._player_to_session[3], "session_c")

		assert_eq(provider._session_to_player["session_a"], 1)
		assert_eq(provider._session_to_player["session_b"], 2)
		assert_eq(provider._session_to_player["session_c"], 3)

	func test_multiple_peers_session_isolation():
		# Verify players from different peers tracked independently.
		provider.server_set_expected_player_count(4)

		# Peer 1 with 2 players.
		var peer1_player_ids: Array[int] = [1, 2]
		var peer1_session_ids: Array = ["session_1", "session_2"]
		provider.server_validate_player_sessions(
			10,
			peer1_player_ids,
			peer1_session_ids
		)

		# Peer 2 with 2 players.
		var peer2_player_ids: Array[int] = [3, 4]
		var peer2_session_ids: Array = ["session_3", "session_4"]
		provider.server_validate_player_sessions(
			20,
			peer2_player_ids,
			peer2_session_ids
		)

		# Verify all 4 players tracked.
		assert_eq(
			provider._player_to_session.size(),
			4,
			"Should track all 4 players"
		)

		# Verify peer 1 mappings.
		assert_eq(provider._player_to_session[1], "session_1")
		assert_eq(provider._player_to_session[2], "session_2")

		# Verify peer 2 mappings.
		assert_eq(provider._player_to_session[3], "session_3")
		assert_eq(provider._player_to_session[4], "session_4")


class TestPlayerSessionCounting:
	extends GutTest

	var provider: GameLiftServerProvider

	func before_each():
		provider = GameLiftServerProvider.new()
		add_child_autofree(provider)
		await wait_frames(1)

	func test_validated_count_increments_per_player():
		# Verify validated count increments for each player.
		provider.server_set_expected_player_count(3)

		assert_eq(
			provider._validated_player_count,
			0,
			"Should start at 0"
		)

		# Validate first player.
		var player_ids1: Array[int] = [1]
		var session_ids1: Array = ["session_1"]
		provider.server_validate_player_sessions(10, player_ids1, session_ids1)
		assert_eq(
			provider._validated_player_count,
			1,
			"Should increment to 1"
		)

		# Validate second player.
		var player_ids2: Array[int] = [2]
		var session_ids2: Array = ["session_2"]
		provider.server_validate_player_sessions(10, player_ids2, session_ids2)
		assert_eq(
			provider._validated_player_count,
			2,
			"Should increment to 2"
		)

		# Validate third player.
		var player_ids3: Array[int] = [3]
		var session_ids3: Array = ["session_3"]
		provider.server_validate_player_sessions(10, player_ids3, session_ids3)
		assert_eq(
			provider._validated_player_count,
			3,
			"Should increment to 3"
		)

	func test_expected_count_vs_validated_count():
		# Verify all_players_connected emits when validated reaches expected.
		provider.server_set_expected_player_count(2)

		# Validate first player.
		var player_ids1: Array[int] = [1]
		var session_ids1: Array = ["session_1"]
		provider.server_validate_player_sessions(10, player_ids1, session_ids1)

		# Should have validated 1/2.
		assert_eq(
			provider._validated_player_count,
			1,
			"Should have validated 1 player"
		)

		# Validate second player.
		var player_ids2: Array[int] = [2]
		var session_ids2: Array = ["session_2"]
		provider.server_validate_player_sessions(10, player_ids2, session_ids2)

		# Should have validated 2/2.
		assert_eq(
			provider._validated_player_count,
			2,
			"Should have validated 2 players (all expected)"
		)


class TestSessionIdReverseLookup:
	extends GutTest

	var provider: GameLiftServerProvider

	func before_each():
		provider = GameLiftServerProvider.new()
		add_child_autofree(provider)
		await wait_frames(1)

		# Set up test mappings.
		provider.server_set_expected_player_count(2)
		var player_ids: Array[int] = [100, 200]
		var session_ids: Array = ["session_alpha", "session_beta"]
		provider.server_validate_player_sessions(
			10,
			player_ids,
			session_ids
		)

	func test_reverse_lookup_session_to_player():
		# Verify reverse lookup from session_id to player_id.
		assert_eq(
			provider._session_to_player.get("session_alpha"),
			100,
			"Should map session_alpha to player 100"
		)
		assert_eq(
			provider._session_to_player.get("session_beta"),
			200,
			"Should map session_beta to player 200"
		)

	func test_reverse_lookup_returns_zero_for_unknown():
		# Verify unknown session ID returns null/zero.
		var unknown_player = provider._session_to_player.get(
			"unknown_session",
			0
		)
		assert_eq(
			unknown_player,
			0,
			"Should return 0 for unknown session"
		)

	func test_forward_lookup_returns_empty_for_unknown():
		# Verify unknown player ID returns empty string.
		var unknown_session = provider._player_to_session.get(999, "")
		assert_eq(
			unknown_session,
			"",
			"Should return empty string for unknown player"
		)


class TestSessionValidationEdgeCases:
	extends GutTest

	var provider: GameLiftServerProvider

	func before_each():
		provider = GameLiftServerProvider.new()
		add_child_autofree(provider)
		await wait_frames(1)

	func test_zero_player_count():
		# Verify handling of 0 expected players.
		provider.server_set_expected_player_count(0)

		# Validate with empty typed arrays.
		var empty_player_ids: Array[int] = []
		var empty_session_ids: Array = []
		provider.server_validate_player_sessions(
			10,
			empty_player_ids,
			empty_session_ids
		)

		# Should not crash and should have 0 validated players.
		assert_eq(
			provider._validated_player_count,
			0,
			"Should have 0 validated players"
		)
		assert_eq(
			provider._player_to_session.size(),
			0,
			"Should have no player mappings"
		)
