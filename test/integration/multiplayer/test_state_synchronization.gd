extends GutTest
## Integration tests for state synchronization patterns in multiplayer.
##
## These tests simulate common scenarios that occur during networked gameplay:
## - Client prediction with server reconciliation
## - Late packet arrival and out-of-order processing
## - Multiple clients with different latencies
## - State divergence detection and correction


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestClientPrediction:
	extends GutTest

	var client_buffer: RollbackBuffer
	var server_buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [0.0, 0.0, 0.0, 0.0, 0]
		# Both buffers start at frame 0.
		client_buffer = RollbackBuffer.new(90, 0, default_state)
		server_buffer = RollbackBuffer.new(90, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_client_predicts_ahead_of_server():
		var delta := 1.0 / 60.0

		# Client is at frame 10, predicting with velocity.
		for i in range(11):
			var state := ArrayPool.acquire(5)
			state[0] = i * 10.0 * delta # x position
			state[1] = 0.0 # y position
			state[2] = 10.0 # x velocity
			state[3] = 0.0 # y velocity
			state[4] = ReconcilableState.FrameAuthority.CLIENT_PREDICTED
			client_buffer.set_at(i, state)

		# Server is only at frame 5.
		for i in range(6):
			var state := ArrayPool.acquire(5)
			state[0] = i * 10.0 * delta
			state[1] = 0.0
			state[2] = 10.0
			state[3] = 0.0
			state[4] = \
				ReconcilableState.FrameAuthority.AUTHORITATIVE
			server_buffer.set_at(i, state)

		# Client should be ahead.
		assert_gt(
			client_buffer.get_latest_index(),
			server_buffer.get_latest_index()
		)

		# States should match for overlapping frames.
		for i in range(6):
			var client_state: Array = client_buffer.get_at(i)
			var server_state: Array = server_buffer.get_at(i)
			assert_almost_eq(
				client_state[0],
				server_state[0],
				0.01,
				"Frame %d position should match" % i
			)

	func test_server_correction_updates_client_prediction():
		var delta := 1.0 / 60.0

		# Client predicts frames 0-10 with velocity 10.
		for i in range(11):
			var state := ArrayPool.acquire(5)
			state[0] = i * 10.0 * delta
			state[1] = 0.0
			state[2] = 10.0
			state[3] = 0.0
			state[4] = ReconcilableState.FrameAuthority.CLIENT_PREDICTED
			client_buffer.set_at(i, state)

		var client_pos_10_before: float = client_buffer.get_at(10)[0]

		# Server sends correction for frame 5 with different velocity.
		var server_correction := ArrayPool.acquire(5)
		server_correction[0] = 5 * 8.0 * delta # Different position
		server_correction[1] = 0.0
		server_correction[2] = 8.0 # Different velocity
		server_correction[3] = 0.0
		server_correction[4] = \
			ReconcilableState.FrameAuthority.AUTHORITATIVE

		# Apply server correction to client.
		client_buffer.set_at(5, server_correction)

		# Re-simulate frames 6-10 with corrected velocity.
		for i in range(6, 11):
			var prev_state: Array = client_buffer.get_at(i - 1)
			var new_state := ArrayPool.acquire(5)
			new_state[0] = prev_state[0] + prev_state[2] * delta
			new_state[1] = 0.0
			new_state[2] = prev_state[2]
			new_state[3] = 0.0
			new_state[4] = ReconcilableState.FrameAuthority.CLIENT_PREDICTED
			client_buffer.set_at(i, new_state)

		var client_pos_10_after: float = client_buffer.get_at(10)[0]

		# Client's frame 10 position should have changed.
		assert_ne(
			client_pos_10_before,
			client_pos_10_after,
            "Server correction should affect future frames"
		)


class TestOutOfOrderPackets:
	extends GutTest

	var buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [0.0, 0.0, 0]
		buffer = RollbackBuffer.new(90, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_handles_late_packet_arrival():
		# Client predicts frames 0-20.
		for i in range(21):
			var state := ArrayPool.acquire(3)
			state[0] = float(i * 5)
			state[1] = 0.0
			state[2] = ReconcilableState.FrameAuthority.CLIENT_PREDICTED
			buffer.set_at(i, state)

		# Server packet for frame 10 arrives late (client is already at
		# frame 20).
		var server_state_10 := ArrayPool.acquire(3)
		server_state_10[0] = 55.0 # Different from predicted (50.0)
		server_state_10[1] = 0.0
		server_state_10[2] = \
			ReconcilableState.FrameAuthority.AUTHORITATIVE

		# Should still be able to apply it.
		assert_true(buffer.has_at(10))
		buffer.set_at(10, server_state_10)

		# Verify correction was applied.
		var corrected: Array = buffer.get_at(10)
		assert_eq(corrected[0], 55.0)
		assert_eq(
			corrected[2],
			ReconcilableState.FrameAuthority.AUTHORITATIVE
		)

	func test_ignores_extremely_old_packets():
		# Client is at frame 100.
		for i in range(101):
			var state := ArrayPool.acquire(3)
			state[0] = float(i)
			state[1] = 0.0
			state[2] = ReconcilableState.FrameAuthority.CLIENT_PREDICTED
			buffer.append(state)

		# Packet for frame 5 arrives (too old, beyond buffer capacity).
		assert_false(
			buffer.has_at(5),
            "Frame 5 should be beyond buffer capacity"
		)

		# Attempting to set it should fail gracefully.
		var old_packet := ArrayPool.acquire(3)
		old_packet[0] = 999.0
		old_packet[1] = 0.0
		old_packet[2] = \
			ReconcilableState.FrameAuthority.AUTHORITATIVE

		var result := buffer.set_at(5, old_packet)
		assert_false(result, "Should not be able to set too-old frame")


class TestMultipleClientsScenario:
	extends GutTest

	var client1_buffer: RollbackBuffer
	var client2_buffer: RollbackBuffer
	var server_buffer: RollbackBuffer

	func before_each():
		ArrayPool.clear_all_pools()
		var default_state := [0.0, 0.0, 0]

		client1_buffer = RollbackBuffer.new(90, 0, default_state)
		client2_buffer = RollbackBuffer.new(90, 0, default_state)
		server_buffer = RollbackBuffer.new(90, 0, default_state)

	func after_each():
		ArrayPool.clear_all_pools()

	func test_clients_with_different_latencies():
		# Client 1 has low latency (1 frame behind server).
		# Client 2 has high latency (5 frames behind server).
		# Server is at frame 10.
		for i in range(11):
			var state := ArrayPool.acquire(3)
			state[0] = float(i * 10)
			state[1] = 0.0
			state[2] = \
				ReconcilableState.FrameAuthority.AUTHORITATIVE
			server_buffer.set_at(i, state)

		# Client 1 has received up to frame 9.
		for i in range(10):
			var state := ArrayPool.acquire(3)
			state[0] = float(i * 10)
			state[1] = 0.0
			state[2] = \
				ReconcilableState.FrameAuthority.AUTHORITATIVE
			client1_buffer.set_at(i, state)

		# Client 2 has only received up to frame 5.
		for i in range(6):
			var state := ArrayPool.acquire(3)
			state[0] = float(i * 10)
			state[1] = 0.0
			state[2] = \
				ReconcilableState.FrameAuthority.AUTHORITATIVE
			client2_buffer.set_at(i, state)

		# Verify different latest indices.
		assert_eq(server_buffer.get_latest_index(), 10)
		assert_eq(client1_buffer.get_latest_index(), 9)
		assert_eq(client2_buffer.get_latest_index(), 5)

		# All should have consistent state for frames they share.
		for i in range(6):
			var server_state: Array = server_buffer.get_at(i)
			var client1_state: Array = client1_buffer.get_at(i)
			var client2_state: Array = client2_buffer.get_at(i)

			assert_eq(server_state[0], client1_state[0])
			assert_eq(server_state[0], client2_state[0])


class TestStateDivergenceDetection:
	extends GutTest

	var entity: TestNetworkedEntity

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()
		if is_instance_valid(entity):
			entity.queue_free()

	func _create_entity(
		initial_position := Vector2.ZERO,
		initial_velocity := Vector2.ZERO,
	) -> TestNetworkedEntity:
		entity = TestNetworkedEntity.create_test_entity(
			initial_position,
			initial_velocity,
		)
		add_child_autofree(entity)
		entity._ready()
		entity.record_initial_state()
		return entity

	func test_detects_position_divergence():
		var e := _create_entity(Vector2(100, 50))
		var frame := Netcode.server_frame_index

		# Server state with position diverged by 5
		# (above threshold of 1.0).
		var server_state := ArrayPool.acquire(4)
		server_state[0] = Vector2(105, 50)
		server_state[1] = Vector2.ZERO
		server_state[2] = 0
		server_state[3] = (
			ReconcilableState.FrameAuthority.AUTHORITATIVE
		)

		var mismatched: Array = (
			e._get_mismatched_properties(server_state, frame)
		)
		assert_has(mismatched, "position")

	func test_ignores_small_position_differences():
		var e := _create_entity(Vector2(100, 50))
		var frame := Netcode.server_frame_index

		# Server state with position diverged by 0.5
		# (below threshold of 1.0).
		var server_state := ArrayPool.acquire(4)
		server_state[0] = Vector2(100.5, 50)
		server_state[1] = Vector2.ZERO
		server_state[2] = 0
		server_state[3] = (
			ReconcilableState.FrameAuthority.AUTHORITATIVE
		)

		var mismatched: Array = (
			e._get_mismatched_properties(server_state, frame)
		)
		assert_does_not_have(mismatched, "position")

	func test_detects_velocity_divergence():
		var e := _create_entity(
			Vector2.ZERO,
			Vector2(10, 0),
		)
		var frame := Netcode.server_frame_index

		# Server state with velocity diverged by 2
		# (above threshold of 0.5).
		var server_state := ArrayPool.acquire(4)
		server_state[0] = Vector2.ZERO
		server_state[1] = Vector2(12, 0)
		server_state[2] = 0
		server_state[3] = (
			ReconcilableState.FrameAuthority.AUTHORITATIVE
		)

		var mismatched: Array = (
			e._get_mismatched_properties(server_state, frame)
		)
		assert_has(mismatched, "velocity")


class TestFrameCatchup:
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

	func test_client_catches_up_to_server():
		# Client is at frame 5.
		for i in range(6):
			var state := ArrayPool.acquire(3)
			state[0] = float(i)
			state[1] = 0.0
			state[2] = ReconcilableState.FrameAuthority.CLIENT_PREDICTED
			buffer.set_at(i, state)

		assert_eq(buffer.get_latest_index(), 5)

		# Server tells client it should be at frame 20.
		# Client backfills to catch up.
		buffer.backfill_to_with_last_state(20)

		assert_eq(buffer.get_latest_index(), 20)

		# Backfilled frames should use last known state.
		for i in range(6, 21):
			var state: Array = buffer.get_at(i)
			assert_not_null(state)
			# Should be marked as SERVER_PREDICTED (tests run as server).
			assert_eq(
				state[2],
				ReconcilableState.FrameAuthority.SERVER_PREDICTED
			)

	func test_handles_burst_of_updates():
		# Simulate receiving multiple server updates in quick succession.
		var frames_to_update := [3, 5, 7, 9, 11]

		for frame_index in frames_to_update:
			var state := ArrayPool.acquire(3)
			state[0] = float(frame_index * 10)
			state[1] = 0.0
			state[2] = \
				ReconcilableState.FrameAuthority.AUTHORITATIVE

			# Backfill if needed.
			if frame_index > buffer.get_latest_index():
				buffer.backfill_to_with_last_state(frame_index)

			buffer.set_at(frame_index, state)

		# All frames should be present.
		for frame_index in frames_to_update:
			assert_true(buffer.has_at(frame_index))
			var state: Array = buffer.get_at(frame_index)
			assert_eq(state[0], float(frame_index * 10))
