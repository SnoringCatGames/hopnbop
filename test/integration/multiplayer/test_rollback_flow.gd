extends GutTest
## Integration tests for rollback buffer flow with frame simulation.
##
## These tests simulate the interaction between RollbackBuffer, ArrayPool,
## and frame-based state management as it would occur during networked
## gameplay with rollback reconciliation.


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestFrameSimulation:
	extends GutTest

	var buffer: RollbackBuffer
	var frame_index: int

	func before_each():
		ArrayPool.clear_all_pools()
		frame_index = 0
		var default_state := [0.0, 0.0, 0.0, 0] # x, y, velocity, authority
		buffer = RollbackBuffer.new(90, frame_index, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_simulates_multiple_frames_without_rollback():
		# Simulate 30 frames of movement with constant velocity.
		var velocity := 10.0
		var delta := 1.0 / 60.0 # 60 FPS

		for i in range(30):
			var state := ArrayPool.acquire(4)
			state[0] = i * velocity * delta # x position
			state[1] = 0.0 # y position
			state[2] = velocity
			state[3] = ReconcilableState.FrameAuthority.PREDICTED

			buffer.set_at(frame_index, state)
			frame_index += 1

		# Verify final state.
		var final_state: Array = buffer.get_at(29)
		assert_not_null(final_state)
		assert_almost_eq(final_state[0], 29 * velocity * delta, 0.1)

	func test_backfills_missing_frames_during_packet_loss():
		# Simulate a scenario where frames 11-16 are missing due to packet
		# loss.
		# First, advance buffer to frame 9 by appending states.
		for i in range(9):
			var state := ArrayPool.acquire(4)
			state[0] = 0.0
			state[1] = 0.0
			state[2] = 0.0
			state[3] = ReconcilableState.FrameAuthority.PREDICTED
			buffer.append(state)

		# Now append a specific state at frame 10.
		var state_10 := ArrayPool.acquire(4)
		state_10[0] = 90.0
		state_10[1] = 50.0
		state_10[2] = 10.0
		state_10[3] = ReconcilableState.FrameAuthority.AUTHORITATIVE
		buffer.append(state_10)

		# Jump to frame 17 (skipping 11-16).
		buffer.backfill_to_with_last_state(17)

		# Verify that frames 11-16 were backfilled with frame 10's state.
		for i in range(11, 17):
			var state: Array = buffer.get_at(i)
			assert_not_null(state, "Frame %d should be backfilled" % i)
			assert_eq(state[0], 90.0, "Backfilled position should match")
			assert_eq(
				state[3],
				ReconcilableState.FrameAuthority.PREDICTED,
                "Backfilled state should be PREDICTED"
			)


class TestRollbackReconciliation:
	extends GutTest

	var buffer: RollbackBuffer
	var frame_index: int

	func before_each():
		ArrayPool.clear_all_pools()
		frame_index = 0
		var default_state := [0.0, 0.0, 0.0, 0]
		buffer = RollbackBuffer.new(90, frame_index, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_detects_mismatch_and_triggers_rollback():
		# Simulate client prediction for frames 0-10.
		for i in range(11):
			var state := ArrayPool.acquire(4)
			state[0] = i * 5.0 # Client predicted position
			state[1] = 0.0
			state[2] = 5.0
			state[3] = ReconcilableState.FrameAuthority.PREDICTED
			buffer.set_at(i, state)

		# Server sends authoritative correction for frame 5 with different
		# position.
		var server_state := ArrayPool.acquire(4)
		server_state[0] = 30.0 # Server says position is different
		server_state[1] = 0.0
		server_state[2] = 5.0
		server_state[3] = ReconcilableState.FrameAuthority.AUTHORITATIVE

		var client_state_5: Array = buffer.get_at(5)
		var has_mismatch := absf(
			client_state_5[0] - server_state[0]
		) > 1.0

		assert_true(has_mismatch, "Should detect position mismatch")

		# Apply server correction.
		buffer.set_at(5, server_state)

		# Verify correction was applied.
		var corrected_state: Array = buffer.get_at(5)
		assert_eq(corrected_state[0], 30.0)
		assert_eq(
			corrected_state[3],
			ReconcilableState.FrameAuthority.AUTHORITATIVE
		)

	func test_re_simulates_frames_after_rollback_point():
		# Client predicts frames 0-10.
		for i in range(11):
			var state := ArrayPool.acquire(4)
			state[0] = i * 10.0
			state[1] = 0.0
			state[2] = 10.0
			state[3] = ReconcilableState.FrameAuthority.PREDICTED
			buffer.set_at(i, state)

		# Record predicted position at frame 10.
		var predicted_pos_10: float = buffer.get_at(10)[0]

		# Server corrects frame 5 with slightly different velocity.
		var server_state_5 := ArrayPool.acquire(4)
		server_state_5[0] = 50.0
		server_state_5[1] = 0.0
		server_state_5[2] = 8.0 # Different velocity
		server_state_5[3] = \
			ReconcilableState.FrameAuthority.AUTHORITATIVE
		buffer.set_at(5, server_state_5)

		# Re-simulate frames 6-10 with corrected velocity.
		var delta := 1.0 / 60.0
		for i in range(6, 11):
			var prev_state: Array = buffer.get_at(i - 1)
			var new_state := ArrayPool.acquire(4)
			new_state[0] = prev_state[0] + prev_state[2] * delta
			new_state[1] = 0.0
			new_state[2] = prev_state[2]
			new_state[3] = ReconcilableState.FrameAuthority.PREDICTED
			buffer.set_at(i, new_state)

		# Verify that frame 10 position has changed.
		var corrected_pos_10: float = buffer.get_at(10)[0]
		assert_ne(
			predicted_pos_10,
			corrected_pos_10,
            "Re-simulation should change future frames"
		)


class TestBufferWraparound:
	extends GutTest

	var buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [0.0, 0.0, 0]
		# Small buffer to test wraparound quickly.
		buffer = RollbackBuffer.new(10, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_maintains_correct_state_after_wraparound():
		# Push enough frames to wrap around multiple times.
		for i in range(50):
			var state := ArrayPool.acquire(3)
			state[0] = float(i)
			state[1] = float(i * 2)
			state[2] = ReconcilableState.FrameAuthority.PREDICTED
			buffer.append(state)

		# Only the last 10 frames should be accessible.
		# After 50 appends starting from frame 0, we're at frame 50.
		# So frames 41-50 are accessible (last 10 frames).
		assert_true(buffer.has_at(41))
		assert_true(buffer.has_at(50))
		assert_false(buffer.has_at(40))

		# Verify state values are correct.
		# Frame 45 was created by the 45th append (i=44 in the loop)
		var state_45: Array = buffer.get_at(45)
		assert_eq(state_45[0], 44.0)
		assert_eq(state_45[1], 88.0)

	func test_can_apply_server_correction_to_old_frame():
		# Simulate many frames.
		for i in range(30):
			var state := ArrayPool.acquire(3)
			state[0] = float(i)
			state[1] = 0.0
			state[2] = ReconcilableState.FrameAuthority.PREDICTED
			buffer.append(state)

		# Server sends correction for frame 25 (still within buffer).
		assert_true(buffer.has_at(25))

		var server_state := ArrayPool.acquire(3)
		server_state[0] = 999.0
		server_state[1] = 888.0
		server_state[2] = \
			ReconcilableState.FrameAuthority.AUTHORITATIVE
		buffer.set_at(25, server_state)

		# Verify correction was applied.
		var corrected: Array = buffer.get_at(25)
		assert_eq(corrected[0], 999.0)
		assert_eq(corrected[1], 888.0)


class TestArrayPoolEfficiency:
	extends GutTest

	var buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [0.0, 0.0, 0, 0, 0]
		buffer = RollbackBuffer.new(30, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_reuses_arrays_during_frame_updates():
		# Fill buffer with initial states.
		for i in range(30):
			var state := ArrayPool.acquire(5)
			state[0] = float(i)
			buffer.append(state)

		var stats_before := ArrayPool.get_pool_stats()

		# Update existing frames (should reuse arrays).
		for i in range(30):
			var state := ArrayPool.acquire(5)
			state[0] = float(i * 10)
			buffer.set_at(i, state)

		var stats_after := ArrayPool.get_pool_stats()

		# The pool should have received arrays back from set_at reuse logic.
		assert_gte(
			stats_after.get("total_pooled", 0),
			stats_before.get("total_pooled", 0),
            "Arrays should be reused, not recreated"
		)

	func test_releases_arrays_when_overwriting_old_frames():
		# Fill buffer beyond capacity.
		for i in range(60):
			var state := ArrayPool.acquire(5)
			state[0] = float(i)
			buffer.append(state)

		var stats := ArrayPool.get_pool_stats()

		# Arrays from overwritten frames should be in the pool.
		assert_gt(
			stats.get("total_pooled", 0),
			0,
            "Overwritten frames should release arrays to pool"
		)


class TestLargeGapBackfill:
	extends GutTest

	var buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [100.0, 200.0, 0]
		buffer = RollbackBuffer.new(90, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_reinitializes_buffer_for_very_large_gap():
		# Set a state at frame 0.
		var state_0 := ArrayPool.acquire(3)
		state_0[0] = 999.0
		state_0[1] = 888.0
		state_0[2] = ReconcilableState.FrameAuthority.AUTHORITATIVE
		buffer.set_at(0, state_0)

		# Jump way ahead (beyond buffer capacity).
		buffer.backfill_to_with_last_state(500)

		# Verify buffer was reinitialized at new frame.
		assert_eq(buffer.get_latest_index(), 500)

		# State should be based on frame 0.
		var state_500: Array = buffer.get_at(500)
		assert_eq(state_500[0], 999.0)
		assert_eq(state_500[1], 888.0)
		# But should be marked as PREDICTED.
		assert_eq(
			state_500[2],
			ReconcilableState.FrameAuthority.PREDICTED
		)

	func test_handles_negative_indices_correctly():
		# Access index -1 (previous frame for frame 0).
		var state_minus_1: Array = buffer.get_at(-1)
		assert_not_null(state_minus_1)
		assert_eq(state_minus_1[0], 100.0)
		assert_eq(state_minus_1[1], 200.0)

		# Access index -2.
		var state_minus_2: Array = buffer.get_at(-2)
		assert_not_null(state_minus_2)
		assert_eq(state_minus_2[0], 100.0)
		assert_eq(state_minus_2[1], 200.0)

		# Index -3 should not be accessible.
		assert_null(buffer.get_at(-3))
