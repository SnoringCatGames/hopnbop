extends GutTest
## Unit tests for MatchState interaction deduplication.


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestInteractionDeduplication:
	extends GutTest

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func _make_state() -> MatchState:
		var state = MatchState.new()
		# Add test players.
		for pid in [1, 2]:
			var p = PlayerMatchState.new()
			p.player_id = pid
			state.players_by_id[pid] = p
		return state

	func test_first_interaction_is_recorded():
		var state = _make_state()
		var initial_kill_count = state.kills.size()

		state.server_add_kill(1, 2)

		assert_eq(
			state.kills.size(),
			initial_kill_count + 2,
			"Kill should be recorded"
		)

	func test_duplicate_kill_within_window_is_rejected():
		var state = _make_state()

		# First kill at frame 10.
		G.network.frame_driver.server_frame_index = 10
		state.server_add_kill(1, 2)
		var kills_after_first = state.kills.size()

		# Try duplicate within 4-frame window.
		G.network.frame_driver.server_frame_index = 12
		state.server_add_kill(1, 2)

		assert_eq(
			state.kills.size(),
			kills_after_first,
			"Duplicate kill within window should be rejected"
		)

	func test_duplicate_bump_within_window_is_rejected():
		var state = _make_state()

		# First bump at frame 20.
		G.network.frame_driver.server_frame_index = 20
		state.server_add_bump(1, 2)
		var bumps_after_first = state.bumps.size()

		# Try duplicate within 4-frame window.
		G.network.frame_driver.server_frame_index = 22
		state.server_add_bump(1, 2)

		assert_eq(
			state.bumps.size(),
			bumps_after_first,
			"Duplicate bump within window should be rejected"
		)

	func test_interaction_outside_window_is_allowed():
		var state = _make_state()

		# First kill at frame 10.
		G.network.frame_driver.server_frame_index = 10
		state.server_add_kill(1, 2)
		var kills_after_first = state.kills.size()

		# Second kill outside window (>4 frames).
		G.network.frame_driver.server_frame_index = 15
		state.server_add_kill(1, 2)

		assert_eq(
			state.kills.size(),
			kills_after_first + 2,
			"Kill outside window should be allowed"
		)

	func test_reversed_player_order_is_detected_as_duplicate():
		var state = _make_state()

		# First bump: player 1 and 2.
		G.network.frame_driver.server_frame_index = 30
		state.server_add_bump(1, 2)
		var bumps_after_first = state.bumps.size()

		# Try reversed order within window.
		G.network.frame_driver.server_frame_index = 32
		state.server_add_bump(2, 1)

		assert_eq(
			state.bumps.size(),
			bumps_after_first,
			"Reversed player order should be detected as duplicate"
		)

	func test_different_interaction_types_dont_conflict():
		var state = _make_state()

		# Kill at frame 40.
		G.network.frame_driver.server_frame_index = 40
		state.server_add_kill(1, 2)
		var kills_after = state.kills.size()

		# Bump at frame 42 (within window but different type).
		G.network.frame_driver.server_frame_index = 42
		state.server_add_bump(1, 2)

		assert_eq(
			state.kills.size(),
			kills_after,
			"Kill count should not change"
		)
		assert_gt(
			state.bumps.size(),
			0,
			"Bump should be recorded despite kill in window"
		)

	func test_interactions_at_different_frames_within_window():
		var state = _make_state()

		# First kill at frame 50.
		G.network.frame_driver.server_frame_index = 50
		state.server_add_kill(1, 2)
		var kills_count = state.kills.size()

		# Try kills at each frame in window.
		for offset in [1, 2, 3, 4]:
			G.network.frame_driver.server_frame_index = 50 + offset
			state.server_add_kill(1, 2)

		assert_eq(
			state.kills.size(),
			kills_count,
			"All duplicate attempts should be rejected"
		)

	func test_backward_frame_deduplication():
		var state = _make_state()

		# Kill at frame 60.
		G.network.frame_driver.server_frame_index = 60
		state.server_add_kill(1, 2)
		var kills_after_first = state.kills.size()

		# Try kill at earlier frame within window (rollback scenario).
		G.network.frame_driver.server_frame_index = 58
		state.server_add_kill(1, 2)

		assert_eq(
			state.kills.size(),
			kills_after_first,
			"Backward frame duplicate should be rejected"
		)


class TestRollbackBufferIntegration:
	extends GutTest

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_rollback_buffer_supports_arbitrary_frame_access():
		var state = MatchState.new()

		# Store interaction at frame 100.
		G.network.frame_driver.server_frame_index = 100
		var interaction = PlayerInteraction.new()
		interaction.player_1_id = 1
		interaction.player_2_id = 2
		interaction.type = PlayerInteraction.Type.KILL
		interaction.frame_index = 100

		var interactions = [interaction]
		state._recent_interactions.set_at(100, interactions)

		assert_true(
			state._recent_interactions.has_at(100),
			"Frame 100 should be accessible"
		)

		var retrieved = state._recent_interactions.get_at(100)
		assert_not_null(retrieved, "Should retrieve stored interactions")

	func test_rollback_buffer_allows_non_sequential_inserts():
		var state = MatchState.new()

		# Insert at frame 200 first.
		G.network.frame_driver.server_frame_index = 200
		state._recent_interactions.set_at(200, [])

		# Then insert at earlier frame 195 (rollback scenario).
		G.network.frame_driver.server_frame_index = 195
		state._recent_interactions.set_at(195, [])

		assert_true(
			state._recent_interactions.has_at(195),
			"Earlier frame should be accessible"
		)
		assert_true(
			state._recent_interactions.has_at(200),
			"Later frame should still be accessible"
		)

	func test_interactions_stored_at_correct_frames():
		var state = MatchState.new()
		for pid in [1, 2]:
			var p = PlayerMatchState.new()
			p.player_id = pid
			state.players_by_id[pid] = p

		# Record interaction at specific frame.
		G.network.frame_driver.server_frame_index = 300
		state.server_add_kill(1, 2)

		# Verify interaction was stored at correct frame.
		var stored = state._recent_interactions.get_at(300)
		assert_not_null(stored, "Interaction should be stored at frame 300")
		assert_gt(
			stored.size(),
			0,
			"Should have at least one interaction"
		)
		assert_eq(
			stored[0].frame_index,
			300,
			"Interaction frame_index should match"
		)
