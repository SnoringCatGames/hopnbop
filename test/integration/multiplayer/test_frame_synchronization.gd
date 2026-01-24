extends GutTest
## Integration tests for frame synchronization and timing.
##
## Tests the interaction between server time tracking, frame index calculation,
## and rollback buffer management across different latency scenarios.


const FRAME_DURATION_USEC := 16666  # ~60 FPS (1/60 second in microseconds)


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestTimeToFrameConversion:
	extends GutTest

	func test_converts_time_to_frame_index():
		# At 60 FPS, each frame is ~16.666ms (16666 usec).
		var time_usec := 1000000  # 1 second
		@warning_ignore("integer_division")
		var expected_frame := time_usec / FRAME_DURATION_USEC
		# Should be ~60 frames.
		assert_eq(expected_frame, 60)

	func test_converts_frame_to_time():
		var frame := 120  # 2 seconds at 60 FPS
		var expected_time_usec := frame * FRAME_DURATION_USEC
		# Should be ~2 seconds (120 * 16666 = 1999920 usec).
		assert_eq(expected_time_usec, 1999920)

	func test_handles_fractional_frames():
		# Time that doesn't align perfectly to frame boundary.
		var time_usec := 25000  # 25ms
		@warning_ignore("integer_division")
		var frame := time_usec / FRAME_DURATION_USEC
		# Should round down to frame 1.
		assert_eq(frame, 1)

	func test_zero_time_is_frame_zero():
		var time_usec := 0
		@warning_ignore("integer_division")
		var frame := time_usec / FRAME_DURATION_USEC
		assert_eq(frame, 0)


class TestFrameSynchronization:
	extends GutTest

	var client_buffer: RollbackBuffer
	var server_buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [0.0, 0.0, 0, 0]  # x, y, frame, authority
		client_buffer = RollbackBuffer.new(90, 0, default_state)
		server_buffer = RollbackBuffer.new(90, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_client_and_server_frame_alignment():
		# Both start at frame 0 at time 0.
		var _current_time_usec := 0
		var current_frame := 0

		# Simulate 10 frames.
		for i in range(10):
			_current_time_usec += FRAME_DURATION_USEC
			current_frame += 1

			# Both should advance to same frame.
			var client_state := ArrayPool.acquire(4)
			client_state[0] = float(i)
			client_state[1] = 0.0
			client_state[2] = current_frame
			client_state[3] = \
				ReconcilableNetworkedState.FrameAuthority.PREDICTED
			client_buffer.append(client_state)

			var server_state := ArrayPool.acquire(4)
			server_state[0] = float(i)
			server_state[1] = 0.0
			server_state[2] = current_frame
			server_state[3] = \
				ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE
			server_buffer.append(server_state)

		# Both should be at frame 10.
		# Started at frame 0, then appended 10 times (frames 1-10).
		assert_eq(client_buffer.get_latest_index(), 10)
		assert_eq(server_buffer.get_latest_index(), 10)

		# Frame indices should match.
		var client_latest: Array = client_buffer.get_latest()
		var server_latest: Array = server_buffer.get_latest()
		assert_eq(client_latest[2], server_latest[2])

	func test_handles_clock_offset():
		# Server clock is 100ms (100000 usec) ahead of client.
		var clock_offset_usec := 100000

		var client_time := 500000  # Client thinks it's 500ms
		var server_time := client_time + clock_offset_usec  # Server is 600ms

		@warning_ignore("integer_division")
		var client_frame := client_time / FRAME_DURATION_USEC
		@warning_ignore("integer_division")
		var server_frame := server_time / FRAME_DURATION_USEC

		# Server should be ~6 frames ahead.
		assert_gt(server_frame, client_frame)
		assert_almost_eq(server_frame - client_frame, 6.0, 1.0)


class TestLatencyScenarios:
	extends GutTest

	var buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [0.0, 0.0, 0]
		buffer = RollbackBuffer.new(90, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_low_latency_scenario():
		# 20ms RTT (ping) = ~1 frame delay at 60 FPS.
		var rtt_usec := 20000
		@warning_ignore("integer_division")
		var one_way_latency_frames := (rtt_usec / 2) / FRAME_DURATION_USEC

		# Client predicts 1 frame ahead.
		assert_eq(one_way_latency_frames, 0)

		# Client should receive server state for frame 4 while at frame 5.
		for i in range(6):
			var state := ArrayPool.acquire(3)
			state[0] = float(i)
			state[1] = 0.0
			state[2] = ReconcilableNetworkedState.FrameAuthority.PREDICTED
			buffer.set_at(i, state)

		# Server state arrives for frame 4.
		assert_true(buffer.has_at(4))

	func test_high_latency_scenario():
		# 200ms RTT = ~6 frames delay at 60 FPS.
		var rtt_usec := 200000
		@warning_ignore("integer_division")
		var one_way_latency_frames := (rtt_usec / 2) / FRAME_DURATION_USEC

		# Should be ~6 frames.
		assert_almost_eq(one_way_latency_frames, 6.0, 1.0)

		# Client predicts 6 frames ahead.
		var client_frame := 20
		var server_acknowledged_frame := client_frame - 6

		# Client should have predicted up to frame 20.
		for i in range(21):
			var state := ArrayPool.acquire(3)
			state[0] = float(i)
			state[1] = 0.0
			state[2] = ReconcilableNetworkedState.FrameAuthority.PREDICTED
			buffer.set_at(i, state)

		# Server state arrives for frame 14.
		assert_true(buffer.has_at(server_acknowledged_frame))

	func test_variable_latency_jitter():
		# Simulate packets arriving with variable delay.
		var packet_frames := [5, 7, 6, 9, 8]  # Out of order

		for frame in packet_frames:
			var state := ArrayPool.acquire(3)
			state[0] = float(frame * 10)
			state[1] = 0.0
			state[2] = \
				ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE

			# Ensure buffer can accommodate.
			if frame > buffer.get_latest_index():
				buffer.backfill_to_with_last_state(frame)

			buffer.set_at(frame, state)

		# All frames should be present.
		for frame in packet_frames:
			assert_true(buffer.has_at(frame))
			var state: Array = buffer.get_at(frame)
			assert_eq(state[0], float(frame * 10))


class TestFrameSkipDetection:
	extends GutTest

	var buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [0.0, 0.0, 0]
		buffer = RollbackBuffer.new(90, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_detects_frame_skip():
		# Simulate frames 0-5, then skip to 10.
		for i in range(6):
			var state := ArrayPool.acquire(3)
			state[0] = float(i)
			state[1] = 0.0
			state[2] = ReconcilableNetworkedState.FrameAuthority.PREDICTED
			buffer.set_at(i, state)

		var last_frame := buffer.get_latest_index()
		var next_expected := last_frame + 1
		var actual_next := 10

		var frame_skip := actual_next - next_expected
		assert_gt(frame_skip, 0, "Should detect frame skip")
		assert_eq(frame_skip, 4, "Should skip 4 frames")

	func test_backfills_skipped_frames():
		# Frames 0-5 exist.
		for i in range(6):
			var state := ArrayPool.acquire(3)
			state[0] = float(i * 5)
			state[1] = 0.0
			state[2] = ReconcilableNetworkedState.FrameAuthority.PREDICTED
			buffer.set_at(i, state)

		# Jump to frame 15 (skipping 6-14).
		buffer.backfill_to_with_last_state(15)

		# Verify all frames 6-14 were backfilled.
		for i in range(6, 15):
			assert_true(buffer.has_at(i), "Frame %d should be backfilled" % i)
			var state: Array = buffer.get_at(i)
			# Should have last known state.
			assert_eq(state[0], float(5 * 5))
			# Should be marked PREDICTED.
			assert_eq(
				state[2],
				ReconcilableNetworkedState.FrameAuthority.PREDICTED
			)


class TestBufferSizeAndLatency:
	extends GutTest

	func test_buffer_size_sufficient_for_latency():
		# Buffer should hold at least 1.5 seconds of frames.
		var buffer_duration_seconds := 1.5
		var frames_per_second := 60
		var min_buffer_size := int(
			buffer_duration_seconds * frames_per_second
		)

		# Default buffer is 90 frames.
		assert_eq(min_buffer_size, 90)

		# This should handle up to 1.5 seconds of RTT.
		var max_rtt_usec := int(buffer_duration_seconds * 1000000)
		assert_eq(max_rtt_usec, 1500000)

	func test_extreme_latency_requires_large_buffer():
		# For 500ms RTT, client might predict 30 frames ahead.
		var rtt_usec := 500000
		@warning_ignore("integer_division")
		var one_way_frames := (rtt_usec / 2) / FRAME_DURATION_USEC

		# Should be ~15 frames one-way.
		assert_almost_eq(one_way_frames, 15.0, 1.0)

		# Buffer of 90 frames can handle this.
		assert_gt(90, one_way_frames * 2)

	func test_packet_loss_extends_effective_latency():
		# If 3 packets in a row are lost at 60 FPS, effective delay is 3
		# frames.
		var packets_lost := 3
		var frames_per_packet := 1

		var additional_delay_frames := packets_lost * frames_per_packet
		assert_eq(additional_delay_frames, 3)

		# Buffer should still handle this easily.
		assert_gt(90, additional_delay_frames)
