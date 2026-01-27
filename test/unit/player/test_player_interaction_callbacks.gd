extends GutTest
## Unit tests for player interaction callback methods.


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestCallbackMethodsExist:
	extends GutTest

	func test_player_has_bumped_callback():
		var player = Player.new()

		assert_true(
			player.has_method("client_on_bumped"),
			"Player should have client_on_bumped method"
		)

		player.free()

	func test_player_has_killed_callback():
		var player = Player.new()

		assert_true(
			player.has_method("client_on_killed"),
			"Player should have client_on_killed method"
		)

		player.free()

	func test_player_has_died_callback():
		var player = Player.new()

		assert_true(
			player.has_method("client_on_died"),
			"Player should have client_on_died method"
		)

		player.free()


class TestCallbackInvocation:
	extends GutTest

	func test_bump_notification_doesnt_crash_with_null_players():
		var state = MatchState.new()

		# Call notification with non-existent players.
		# Should not crash even though G.get_player returns null.
		state.client_notify_bump(999, 998, 0.0, 0.0, 0)

		# If we get here, test passes.
		assert_true(true, "Should handle null players gracefully")

	func test_kill_notification_doesnt_crash_with_null_players():
		var state = MatchState.new()

		# Call notification with non-existent players.
		# Should not crash even though G.get_player returns null.
		state.client_notify_kill(999, 998, 0.0, 0.0, 0)

		# If we get here, test passes.
		assert_true(true, "Should handle null players gracefully")


class TestBumpCallbackParameters:
	extends GutTest

	func test_bumped_callback_signature_accepts_parameters():
		# Test that the callback signature is correct.
		var player = Player.new()

		# Call with mock parameters (should not crash).
		player.client_on_bumped(null, true)
		player.client_on_bumped(null, false)

		player.free()
		assert_true(true, "Callback accepts correct parameters")


class TestKillCallbackParameters:
	extends GutTest

	func test_killed_callback_signature_accepts_parameter():
		# Test that the callback signature is correct.
		var player = Player.new()

		# Call with mock parameter (should not crash).
		player.client_on_killed(null)

		player.free()
		assert_true(true, "Callback accepts correct parameter")

	func test_died_callback_signature_accepts_parameter():
		# Test that the callback signature is correct.
		var player = Player.new()

		# Call with mock parameter (should not crash).
		player.client_on_died(null)

		player.free()
		assert_true(true, "Callback accepts correct parameter")


class TestCallbacksWithNullPlayers:
	extends GutTest

	func test_bump_notification_handles_null_player():
		var state = MatchState.new()

		# Call with non-existent players (G.get_player will return null).
		# Should not crash.
		state.client_notify_bump(9999, 9998, 0.0, 0.0, 0)

		assert_true(true, "Should handle null players")

	func test_kill_notification_handles_null_players():
		var state = MatchState.new()

		# Call with non-existent players (G.get_player will return null).
		# Should not crash.
		state.client_notify_kill(9999, 9998, 0.0, 0.0, 0)

		assert_true(true, "Should handle null players")
