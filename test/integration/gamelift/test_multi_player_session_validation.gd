extends GutTest
## Integration tests for GameLift multi-player session validation.


class TestMultiPlayerSessionValidation:
	extends GutTest

	func test_validates_all_sessions_for_peer():
		# Mock GameLiftManager.
		var manager := GameLiftManager.new()

		var peer_id := 1234
		var session_ids := ["session-1", "session-2"]

		# In preview mode, auto-accepts all sessions.
		manager.validate_player_sessions(peer_id, session_ids)

		# Verify internal state tracking.
		assert_eq(manager._validated_player_count, 2)
		assert_has(manager._player_to_session, "1234:0")
		assert_has(manager._player_to_session, "1234:1")

	func test_player_to_session_bidirectional_mapping():
		var manager := GameLiftManager.new()
		manager.validate_player_sessions(1, ["s1", "s2"])

		assert_eq(manager.get_session_id_for_player("1:0"), "s1")
		assert_eq(manager.get_player_id_for_session("s1"), "1:0")

	func test_multiple_players_tracked_independently():
		var manager := GameLiftManager.new()
		manager.validate_player_sessions(1, ["s1", "s2"])

		assert_eq(manager.get_session_id_for_player("1:0"), "s1")
		assert_eq(manager.get_session_id_for_player("1:1"), "s2")
		assert_ne(
			manager.get_session_id_for_player("1:0"),
			manager.get_session_id_for_player("1:1")
		)

	func test_multiple_peers_session_isolation():
		var manager := GameLiftManager.new()
		manager.validate_player_sessions(1, ["s1"])
		manager.validate_player_sessions(2, ["s2"])

		assert_eq(manager.get_session_id_for_player("1:0"), "s1")
		assert_eq(manager.get_session_id_for_player("2:0"), "s2")


class TestPlayerSessionCounting:
	extends GutTest

	func test_validated_count_increments_per_player():
		var manager := GameLiftManager.new()
		manager.set_expected_player_count(4)

		manager.validate_player_sessions(1, ["s1", "s2"])
		assert_eq(manager._validated_player_count, 2)

		manager.validate_player_sessions(2, ["s3", "s4"])
		assert_eq(manager._validated_player_count, 4)

	func test_expected_count_vs_validated_count():
		var manager := GameLiftManager.new()
		manager.set_expected_player_count(3)

		assert_eq(manager._validated_player_count, 0)
		manager.validate_player_sessions(1, ["s1", "s2"])
		assert_lt(manager._validated_player_count, 3)

		manager.validate_player_sessions(2, ["s3"])
		assert_eq(manager._validated_player_count, 3)


class TestSessionIdReverseLookup:
	extends GutTest

	func test_reverse_lookup_session_to_player():
		var manager := GameLiftManager.new()
		manager.validate_player_sessions(1234, ["s1", "s2", "s3"])

		assert_eq(manager.get_player_id_for_session("s1"), "1234:0")
		assert_eq(manager.get_player_id_for_session("s2"), "1234:1")
		assert_eq(manager.get_player_id_for_session("s3"), "1234:2")

	func test_reverse_lookup_returns_empty_for_unknown():
		var manager := GameLiftManager.new()
		var result := manager.get_player_id_for_session("unknown")
		assert_eq(result, "")

	func test_forward_lookup_returns_empty_for_unknown():
		var manager := GameLiftManager.new()
		var result := manager.get_session_id_for_player("9999:0")
		assert_eq(result, "")


class TestDeprecatedSinglePlayerAPI:
	extends GutTest

	func test_deprecated_get_session_for_peer():
		var manager := GameLiftManager.new()
		manager.validate_player_sessions(1234, ["s1", "s2"])

		# Should return first player's session (index 0).
		var result := manager.get_session_id_for_peer(1234)
		assert_eq(result, "s1")

	func test_deprecated_get_peer_for_session():
		var manager := GameLiftManager.new()
		manager.validate_player_sessions(1234, ["s1"])

		var result := manager.get_peer_id_for_session("s1")
		assert_eq(result, 1234)


class TestSessionValidationEdgeCases:
	extends GutTest

	func test_zero_player_count():
		var manager := GameLiftManager.new()
		# Edge case: 0 players (should not validate).
		manager.validate_player_sessions(1, [])

		assert_eq(manager._validated_player_count, 0)
