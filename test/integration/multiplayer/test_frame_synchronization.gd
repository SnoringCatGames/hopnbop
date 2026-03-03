extends GutTest
## Integration tests for frame synchronization and timing.
##
## Tests the interaction between server time tracking, frame index calculation,
## and rollback buffer management across different latency scenarios.


const FRAME_DURATION_USEC := 16666 # ~60 FPS (1/60 second in microseconds)


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestFrameSynchronization:
	extends GutTest

	var client_buffer: RollbackBuffer
	var server_buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [0.0, 0.0, 0, 0] # x, y, frame, authority
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
				ReconcilableState.FrameAuthority.CLIENT_PREDICTED
			client_buffer.append(client_state)

			var server_state := ArrayPool.acquire(4)
			server_state[0] = float(i)
			server_state[1] = 0.0
			server_state[2] = current_frame
			server_state[3] = \
				ReconcilableState.FrameAuthority.AUTHORITATIVE
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

		var client_time := 500000 # Client thinks it's 500ms
		var server_time := client_time + clock_offset_usec # Server is 600ms

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

	func test_variable_latency_jitter():
		# Simulate packets arriving with variable delay.
		var packet_frames := [5, 7, 6, 9, 8] # Out of order

		for frame in packet_frames:
			var state := ArrayPool.acquire(3)
			state[0] = float(frame * 10)
			state[1] = 0.0
			state[2] = \
				ReconcilableState.FrameAuthority.AUTHORITATIVE

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
	var _saved_is_server: bool

	func before_each():
		ArrayPool.clear_all_pools()
		_saved_is_server = Netcode.is_server
		Netcode.is_server = true
		var default_state := [0.0, 0.0, 0]
		buffer = RollbackBuffer.new(90, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()
		Netcode.is_server = _saved_is_server

	func test_detects_frame_skip():
		# Simulate frames 0-5, then skip to 10.
		for i in range(6):
			var state := ArrayPool.acquire(3)
			state[0] = float(i)
			state[1] = 0.0
			state[2] = ReconcilableState.FrameAuthority.CLIENT_PREDICTED
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
			state[2] = ReconcilableState.FrameAuthority.CLIENT_PREDICTED
			buffer.set_at(i, state)

		# Jump to frame 15 (skipping 6-14).
		buffer.backfill_to_with_last_state(15)

		# Verify all frames 6-14 were backfilled.
		for i in range(6, 15):
			assert_true(buffer.has_at(i), "Frame %d should be backfilled" % i)
			var state: Array = buffer.get_at(i)
			# Should have last known state.
			assert_eq(state[0], float(5 * 5))
			# Should be marked SERVER_PREDICTED (tests run as server).
			assert_eq(
				state[2],
				ReconcilableState.FrameAuthority.SERVER_PREDICTED
			)
