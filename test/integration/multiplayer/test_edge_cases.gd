extends GutTest
## Integration tests for extreme conditions and boundary cases.
##
## These tests verify system behavior under unusual or extreme conditions
## that could occur in real gameplay.


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestEdgeCases:
	extends GutTest
	## Tests extreme conditions and boundary cases.

	var frame_driver: NetworkFrameDriver
	var entity: TestNetworkedEntity


	func before_each():
		ArrayPool.clear_all_pools()
		frame_driver = G.network.frame_driver


	func after_each():
		ArrayPool.clear_all_pools()
		if is_instance_valid(entity):
			entity.queue_free()


	func test_rollback_at_frame_one():
		# Test rollback to the earliest possible frame
		frame_driver.server_frame_index = 10

		# Try to rollback to frame 0 (conflict), target would be 1
		var result := frame_driver.queue_rollback(0)

		assert_true(
			result,
			"Should accept rollback to frame 1",
		)


	func test_rollback_to_buffer_capacity_limit():
		# Test rollback to the oldest accessible frame
		frame_driver.server_frame_index = 200
		# Oldest rollbackable = 83

		# Rollback to frame 82 (conflict), target = 83
		var result := frame_driver.queue_rollback(82)

		assert_true(
			result,
			"Should accept rollback at capacity limit",
		)


	func test_rollback_just_beyond_capacity():
		# Test that rollback just beyond capacity is rejected
		frame_driver.server_frame_index = 200
		# Oldest rollbackable = 83

		# Rollback to frame 81 (conflict), target = 82 (too old)
		var result := frame_driver.queue_rollback(81)

		assert_false(
			result,
			"Should reject rollback beyond capacity",
		)


	func test_fast_forward_from_early_frame():
		# Test fast forward from very early frame to much later frame
		frame_driver.server_frame_index = 1
		frame_driver.server_frame_time_usec = (
			frame_driver.get_time_usec_from_frame_index(1)
		)

		frame_driver.fast_forward(50)

		assert_eq(
			frame_driver.server_frame_index,
			50,
			"Should fast forward to frame 50",
		)


	func test_fast_forward_large_gap_100_frames():
		# Test fast forward with 100 frame gap
		frame_driver.server_frame_index = 10

		frame_driver.fast_forward(110)

		assert_eq(
			frame_driver.server_frame_index,
			110,
			"Should handle 100-frame gap",
		)


	func test_frame_index_never_goes_negative():
		# Verify frame index stays positive
		frame_driver.server_frame_index = 0

		# Even at frame 0, oldest rollbackable should be 1
		var oldest := frame_driver.oldest_rollbackable_frame_index

		assert_gte(oldest, 1, "Oldest should never be less than 1")


	func test_time_conversion_at_frame_zero():
		# Test time conversion edge case at frame 0
		var time_at_zero := frame_driver.get_time_usec_from_frame_index(0)
		var frame_from_zero := (
			frame_driver.get_frame_index_from_time_usec(0)
		)

		assert_eq(frame_from_zero, 0, "Time 0 should map to frame 0")
		assert_gt(time_at_zero, 0, "Frame 0 should have positive time (midpoint)")


	func test_buffer_size_with_different_duration_settings():
		# Test that buffer size correctly responds to settings
		var original_duration := G.settings.rollback_buffer_duration_sec

		# Calculate expected buffer size
		var expected := ceili(
			original_duration * NetworkFrameDriver.TARGET_NETWORK_FPS,
		)
		var actual := frame_driver.rollback_buffer_size

		assert_eq(
			actual,
			expected,
			"Buffer size should match settings",
		)
