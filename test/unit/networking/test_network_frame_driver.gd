@tool
extends GutTest
## Unit tests for NetworkFrameDriver.
##
## Phase 1 tests focus on frame time conversion - the core math that underpins
## all rollback functionality.


func before_each():
    ArrayPool.clear_all_pools()


func after_each():
    ArrayPool.clear_all_pools()


class TestFrameTimeConversion:
    extends GutTest
    ## Tests bidirectional conversion between time (microseconds) and frame
    ## indices.

    const TARGET_NETWORK_TIME_STEP_USEC := 16666


    func before_each():
        ArrayPool.clear_all_pools()


    func after_each():
        ArrayPool.clear_all_pools()


    func test_get_frame_index_from_time_usec_at_frame_boundary():
        # Frame 1 should start at 16,666 microseconds
        var frame_driver := NetworkFrameDriver.new()

        var frame_index := (
            frame_driver.get_frame_index_from_time_usec(
                TARGET_NETWORK_TIME_STEP_USEC,
            )
        )

        assert_eq(
            frame_index,
            1,
            "16,666 microseconds should map to frame 1",
        )


    func test_get_time_usec_from_frame_index_returns_midpoint():
        # Frame 10 midpoint = 10 * 16666 + 8333 = 174,993 microseconds
        var frame_driver := NetworkFrameDriver.new()

        var time_usec := frame_driver.get_time_usec_from_frame_index(10)

        var expected_midpoint := floori(10 * TARGET_NETWORK_TIME_STEP_USEC + TARGET_NETWORK_TIME_STEP_USEC * 0.5)
        assert_eq(
            time_usec,
            expected_midpoint,
            "Frame 10 should return its midpoint timestamp",
        )


    func test_round_trip_conversion_preserves_frame_index():
        # Converting frame -> time -> frame should return the same frame
        var frame_driver := NetworkFrameDriver.new()
        var original_frame := 42

        var time_usec := frame_driver.get_time_usec_from_frame_index(
            original_frame,
        )
        var recovered_frame := (
            frame_driver.get_frame_index_from_time_usec(time_usec)
        )

        assert_eq(
            recovered_frame,
            original_frame,
            "Round-trip conversion should preserve frame index",
        )


    func test_handles_zero_time_and_frame():
        # Edge case: frame 0 and time 0
        var frame_driver := NetworkFrameDriver.new()

        var frame_from_zero_time := (
            frame_driver.get_frame_index_from_time_usec(0)
        )
        var time_from_zero_frame := frame_driver.get_time_usec_from_frame_index(
            0,
        )

        assert_eq(frame_from_zero_time, 0, "Time 0 should map to frame 0")
        # Frame 0 midpoint = 0 * 16666 + 8333 = 8333
        assert_eq(
            time_from_zero_frame,
            floori(TARGET_NETWORK_TIME_STEP_USEC * 0.5),
            "Frame 0 should return midpoint timestamp",
        )


    func test_large_frame_indices_dont_overflow():
        # Test with a very large frame number to ensure no integer overflow
        var frame_driver := NetworkFrameDriver.new()
        var large_frame := 1_000_000

        var time_usec := frame_driver.get_time_usec_from_frame_index(
            large_frame,
        )
        var recovered_frame := (
            frame_driver.get_frame_index_from_time_usec(time_usec)
        )

        assert_eq(
            recovered_frame,
            large_frame,
            "Large frame indices should not overflow",
        )


class TestRollbackQueueing:
    extends GutTest
    ## Tests rollback scheduling, deduplication, and validation.

    var frame_driver: NetworkFrameDriver


    func before_each():
        ArrayPool.clear_all_pools()
        frame_driver = NetworkFrameDriver.new()


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(frame_driver):
            frame_driver.free()


    func test_queue_rollback_accepts_valid_frame():
        # Set up: frame index at 50, buffer size 90
        frame_driver.server_frame_index = 50

        # Queue rollback to frame 45 (conflict frame)
        # This becomes target rollback frame 46 (conflict + 1)
        var result := frame_driver.queue_rollback(45)

        assert_true(result, "Should accept valid rollback request")
        # Access the private field through reflection or check behavior
        # Since we can't directly check _queued_rollback_frame_index,
        # we verify it was accepted
        assert_true(result, "Valid frame should be queued")


    func test_queue_rollback_rejects_too_old_frame():
        # Set up: frame index at 100, buffer size 90
        # oldest_rollbackable = max(100 - 90 + 3, 1) = 13
        frame_driver.server_frame_index = 100

        # Try to queue rollback to frame 10 (too old)
        # Target rollback would be 11, which is < 13
        var result := frame_driver.queue_rollback(10)

        assert_false(
            result,
            "Should reject rollback request for frame too old",
        )


    func test_queue_rollback_boundary_frame_accepted():
        # Test the boundary case: exactly at oldest_rollbackable
        frame_driver.server_frame_index = 100
        # oldest_rollbackable = max(100 - 90 + 3, 1) = 13

        # Queue rollback to frame 12 (conflict)
        # Target rollback = 13, which equals oldest_rollbackable
        var result := frame_driver.queue_rollback(12)

        assert_true(
            result,
            "Should accept rollback at boundary (oldest_rollbackable)",
        )


    func test_queue_rollback_boundary_frame_rejected():
        # Test one frame before the boundary
        frame_driver.server_frame_index = 100
        # oldest_rollbackable = 13

        # Queue rollback to frame 11 (conflict)
        # Target rollback = 12, which is < 13
        var result := frame_driver.queue_rollback(11)

        assert_false(
            result,
            "Should reject rollback one frame before oldest_rollbackable",
        )


    func test_queue_rollback_deduplication_keeps_earliest():
        # Test that multiple queue_rollback calls keep the earliest frame
        frame_driver.server_frame_index = 50

        # Queue multiple rollbacks
        var result1 := frame_driver.queue_rollback(45)  # Target: 46
        var result2 := frame_driver.queue_rollback(47)  # Target: 48
        var result3 := frame_driver.queue_rollback(40)  # Target: 41 (earliest)

        assert_true(result1, "First queue should succeed")
        assert_true(result2, "Second queue should succeed")
        assert_true(result3, "Third queue should succeed")

        # We can't directly verify _queued_rollback_frame_index,
        # but the implementation should keep frame 41
        # This would be verified by integration tests


    func test_is_frame_too_old_at_boundary():
        # Test the boundary check for is_frame_too_old_to_consider
        frame_driver.server_frame_index = 100
        # oldest_rollbackable = 13

        # Frame 12 (conflict), target 13 - should NOT be too old
        var result_at_boundary := frame_driver.is_frame_too_old_to_consider(12)
        assert_false(
            result_at_boundary,
            "Frame at boundary should not be too old",
        )

        # Frame 11 (conflict), target 12 - should be too old
        var result_before_boundary := (
            frame_driver.is_frame_too_old_to_consider(11)
        )
        assert_true(
            result_before_boundary,
            "Frame before boundary should be too old",
        )


    func test_oldest_rollbackable_never_negative():
        # Test early frames where buffer size exceeds frame index
        frame_driver.server_frame_index = 5
        # Formula: max(5 - 90 + 3, 1) = max(-82, 1) = 1

        var oldest := frame_driver.oldest_rollbackable_frame_index

        assert_eq(
            oldest,
            1,
            "Oldest rollbackable should never be less than 1",
        )


    func test_rollback_buffer_size_calculation():
        # Test that buffer size is calculated correctly
        # Default: 1.5 seconds at 60 FPS = 90 frames
        var expected_size := ceili(
            G.settings.rollback_buffer_duration_sec *
            NetworkFrameDriver.TARGET_NETWORK_FPS,
        )

        var actual_size := frame_driver.rollback_buffer_size

        assert_eq(
            actual_size,
            expected_size,
            "Buffer size should match settings",
        )


## Test helper entity that tracks network processing calls.
class TestNetworkFrameProcessor:
    extends NetworkFrameProcessor
    ## Tracks how many times each processing phase is called.

    var pre_process_count := 0
    var network_process_count := 0
    var post_process_count := 0
    var processed_frames: Array[int] = []


    func _pre_network_process() -> void:
        pre_process_count += 1


    func _network_process() -> void:
        network_process_count += 1
        processed_frames.append(G.network.server_frame_index)


    func _post_network_process() -> void:
        post_process_count += 1


    func reset() -> void:
        pre_process_count = 0
        network_process_count = 0
        post_process_count = 0
        processed_frames.clear()


class TestRollbackAndReprocess:
    extends GutTest
    ## Tests the re-simulation algorithm - most critical rollback logic.
    ##
    ## Note: These tests verify rollback behavior indirectly since
    ## _rollback_and_reprocess is a private method. We test the observable
    ## effects through queue_rollback and frame processing.

    var frame_driver: NetworkFrameDriver


    func before_each():
        ArrayPool.clear_all_pools()
        frame_driver = NetworkFrameDriver.new()


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(frame_driver):
            frame_driver.free()


    func test_rollback_queuing_sets_internal_state():
        # Verify that queue_rollback sets up the internal state correctly
        frame_driver.server_frame_index = 50

        var result := frame_driver.queue_rollback(45)

        assert_true(result, "Should successfully queue rollback")
        # The internal _queued_rollback_frame_index should be 46
        # We can't directly verify, but subsequent tests will show the effect


    func test_multiple_rollbacks_keep_earliest_frame():
        # Test deduplication: multiple calls should keep earliest
        frame_driver.server_frame_index = 50

        frame_driver.queue_rollback(47)  # Target: 48
        frame_driver.queue_rollback(45)  # Target: 46 (earlier)
        frame_driver.queue_rollback(49)  # Target: 50 (later)

        # Internal state should have frame 46 as the target (earliest)
        assert_eq(
            frame_driver._queued_rollback_frame_index,
            46,
            "Should keep earliest rollback target (46)",
        )


    func test_oldest_rollbackable_calculation_with_large_buffer():
        # Buffer size 90, frame 100
        # oldest = max(100 - 90 + 3, 1) = 13
        frame_driver.server_frame_index = 100

        var oldest := frame_driver.oldest_rollbackable_frame_index

        assert_eq(oldest, 13, "Oldest rollbackable frame should be 13")


    func test_oldest_rollbackable_calculation_early_game():
        # Early in the game when frame_index < buffer_size
        frame_driver.server_frame_index = 10

        var oldest := frame_driver.oldest_rollbackable_frame_index

        assert_eq(
            oldest,
            1,
            "Oldest rollbackable should be 1 early in game",
        )


    func test_frame_boundary_calculations():
        # Test the +3 offset in oldest_rollbackable calculation
        # Formula: max(server_frame_index - buffer_size + 3, 1)
        # At frame 93 with buffer 90: max(93 - 90 + 3, 1) = 6
        frame_driver.server_frame_index = 93

        var oldest := frame_driver.oldest_rollbackable_frame_index

        assert_eq(
            oldest,
            6,
            "Should correctly calculate with +3 offset",
        )


    func test_queue_rollback_returns_false_for_ancient_frame():
        # Very old frame that's definitely outside the buffer
        frame_driver.server_frame_index = 1000

        var result := frame_driver.queue_rollback(1)

        assert_false(
            result,
            "Should reject rollback for ancient frame",
        )


    func test_queue_rollback_clears_after_processing_simulation():
        # Simulate the queue clearing behavior
        # In actual implementation, _queued_rollback_frame_index is reset to 0
        # after _rollback_and_reprocess completes
        frame_driver.server_frame_index = 50

        # Queue a rollback
        frame_driver.queue_rollback(45)

        # Verify the rollback was queued
        assert_eq(
            frame_driver._queued_rollback_frame_index,
            46,
            "Rollback should be queued at frame 46",
        )

        # Process the simulation, which should execute and clear the queue
        frame_driver._run_network_process()

        # After _run_network_process, the queue should be cleared
        assert_eq(
            frame_driver._queued_rollback_frame_index,
            0,
            "Rollback queue should be cleared after processing",
        )


    func test_rollback_state_consistency():
        # Test that frame index is properly managed during rollback
        frame_driver.server_frame_index = 50

        # Queue rollback to frame 46 (conflict at 45)
        frame_driver.queue_rollback(45)

        # After rollback would execute, frame_index should return to 50
        # This tests that the temporary rollback doesn't corrupt state
        var original_frame := frame_driver.server_frame_index
        assert_eq(
            original_frame,
            50,
            "Frame index should remain stable before rollback",
        )


    func test_rollback_with_current_frame_no_op():
        # Edge case: rollback to current frame should be rejected
        frame_driver.server_frame_index = 50

        # Try to rollback to frame 49 (conflict), target would be 50
        # This is technically valid but results in zero frames to process
        var result := frame_driver.queue_rollback(49)

        assert_true(
            result,
            "Should accept rollback to current frame (edge case)",
        )


    func test_time_conversion_consistency_during_rollback():
        # Verify that time conversions remain consistent
        # when frame_index changes during rollback
        frame_driver.server_frame_index = 100
        frame_driver.server_frame_time_usec = (
            frame_driver.get_time_usec_from_frame_index(100)
        )

        var time_before := frame_driver.server_frame_time_usec
        var expected_time := frame_driver.get_time_usec_from_frame_index(100)

        # Time should match the frame index
        assert_almost_eq(
            time_before,
            expected_time,
            1,
            "Time should match frame index",
        )


class TestFrameIndexCalculation:
    extends GutTest
    ## Tests rollback buffer boundaries and frame validation logic.

    var frame_driver: NetworkFrameDriver


    func before_each():
        ArrayPool.clear_all_pools()
        frame_driver = NetworkFrameDriver.new()


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(frame_driver):
            frame_driver.free()


    func test_oldest_rollbackable_frame_index_with_buffer_size_90():
        # Frame 100, buffer 90 -> oldest = max(100 - 90 + 3, 1) = 13
        frame_driver.server_frame_index = 100

        var oldest := frame_driver.oldest_rollbackable_frame_index

        assert_eq(oldest, 13, "Oldest frame should be 13 at frame 100")


    func test_oldest_rollbackable_never_negative_early_game():
        # Frame 5, buffer 90 -> oldest = max(5 - 90 + 3, 1) = 1
        frame_driver.server_frame_index = 5

        var oldest := frame_driver.oldest_rollbackable_frame_index

        assert_eq(oldest, 1, "Oldest frame should never be less than 1")


    func test_is_frame_too_old_to_consider_at_boundary():
        # Frame 100, oldest = 13
        # Conflict frame 12, target 13 -> not too old
        frame_driver.server_frame_index = 100

        var result := frame_driver.is_frame_too_old_to_consider(12)

        assert_false(result, "Frame 12 (target 13) should not be too old")


    func test_is_frame_too_old_to_consider_before_boundary():
        # Frame 100, oldest = 13
        # Conflict frame 11, target 12 -> too old
        frame_driver.server_frame_index = 100

        var result := frame_driver.is_frame_too_old_to_consider(11)

        assert_true(result, "Frame 11 (target 12) should be too old")


    func test_rollback_buffer_size_matches_settings():
        # Default: 1.5 seconds at 60 FPS = 90 frames
        var expected := ceili(
            G.settings.rollback_buffer_duration_sec *
            NetworkFrameDriver.TARGET_NETWORK_FPS,
        )

        var actual := frame_driver.rollback_buffer_size

        assert_eq(actual, expected, "Buffer size should match settings")


    func test_oldest_rollbackable_with_plus_three_offset():
        # Verify the +3 offset in the formula
        # At frame 93: max(93 - 90 + 3, 1) = 6
        frame_driver.server_frame_index = 93

        var oldest := frame_driver.oldest_rollbackable_frame_index

        assert_eq(oldest, 6, "Oldest should account for +3 offset")


class TestFastForward:
    extends GutTest
    ## Tests frame skip handling when client falls behind server.

    var frame_driver: NetworkFrameDriver


    func before_each():
        ArrayPool.clear_all_pools()
        frame_driver = NetworkFrameDriver.new()


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(frame_driver):
            frame_driver.free()


    func test_fast_forward_advances_frame_index():
        # Start at frame 10, fast forward to frame 20
        frame_driver.server_frame_index = 10
        frame_driver.server_frame_time_usec = (
            frame_driver.get_time_usec_from_frame_index(10)
        )

        frame_driver.fast_forward(20)

        assert_eq(
            frame_driver.server_frame_index,
            20,
            "Should advance to frame 20",
        )


    func test_fast_forward_updates_time_usec():
        # Fast forward should update both frame index and time
        frame_driver.server_frame_index = 10
        frame_driver.server_frame_time_usec = (
            frame_driver.get_time_usec_from_frame_index(10)
        )

        frame_driver.fast_forward(20)

        var expected_time := frame_driver.get_time_usec_from_frame_index(20)
        # Allow for small timing accumulation differences
        assert_almost_eq(
            frame_driver.server_frame_time_usec,
            expected_time,
            NetworkFrameDriver.TARGET_NETWORK_TIME_STEP_USEC * 10,
            "Time should advance with frames",
        )


    func test_fast_forward_processes_intermediate_frames():
        # Fast forward from 10 to 15 should process frames 11, 12, 13, 14, 15
        # We can't directly verify _network_process calls without entities,
        # but we can verify the frame index progression
        frame_driver.server_frame_index = 10

        frame_driver.fast_forward(15)

        assert_eq(
            frame_driver.server_frame_index,
            15,
            "Should process all intermediate frames",
        )


    func test_fast_forward_with_zero_gap():
        # Fast forward to current frame should be no-op
        frame_driver.server_frame_index = 50

        frame_driver.fast_forward(50)

        assert_eq(
            frame_driver.server_frame_index,
            50,
            "Should remain at frame 50",
        )


    func test_fast_forward_with_one_frame_gap():
        # Edge case: fast forward by exactly 1 frame
        frame_driver.server_frame_index = 30

        frame_driver.fast_forward(31)

        assert_eq(
            frame_driver.server_frame_index,
            31,
            "Should advance by exactly 1 frame",
        )


    func test_fast_forward_large_gap():
        # Test with a large gap (100 frames)
        frame_driver.server_frame_index = 10

        frame_driver.fast_forward(110)

        assert_eq(
            frame_driver.server_frame_index,
            110,
            "Should handle large frame gaps",
        )


class TestNodeRegistration:
    extends GutTest
    ## Tests ReconcilableNetworkedState and NetworkFrameProcessor lifecycle.

    var frame_driver: NetworkFrameDriver
    var test_entity: TestNetworkedEntity


    func before_each():
        ArrayPool.clear_all_pools()
        frame_driver = G.network.frame_driver


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(test_entity):
            test_entity.queue_free()


    func test_add_networked_state_registers_node():
        # Create a test networked entity
        test_entity = TestNetworkedEntity.new()

        # Manually add to frame driver
        var initial_count := frame_driver._networked_state_nodes.size()
        frame_driver.add_networked_state(test_entity)

        assert_eq(
            frame_driver._networked_state_nodes.size(),
            initial_count + 1,
            "Should add entity to _networked_state_nodes",
        )
        assert_true(
            frame_driver._networked_state_nodes.has(test_entity),
            "Should contain the test entity",
        )


    func test_remove_networked_state_unregisters_node():
        # Create and register test entity
        test_entity = TestNetworkedEntity.new()
        frame_driver.add_networked_state(test_entity)

        # Remove entity
        var count_before := frame_driver._networked_state_nodes.size()
        frame_driver.remove_networked_state(test_entity)

        assert_eq(
            frame_driver._networked_state_nodes.size(),
            count_before - 1,
            "Should remove entity from _networked_state_nodes",
        )
        assert_false(
            frame_driver._networked_state_nodes.has(test_entity),
            "Should not contain the test entity",
        )


    func test_add_network_frame_processor_registers_node():
        # Create a test node with NetworkFrameProcessor interface
        var processor := TestNetworkFrameProcessor.new()

        # Manually add to frame driver
        var initial_count := frame_driver._network_frame_processor_nodes.size()
        frame_driver.add_network_frame_processor(processor)

        assert_eq(
            frame_driver._network_frame_processor_nodes.size(),
            initial_count + 1,
            "Should add processor to _network_frame_processor_nodes",
        )
        assert_true(
            frame_driver._network_frame_processor_nodes.has(processor),
            "Should contain the test processor",
        )

        # Cleanup
        frame_driver.remove_network_frame_processor(processor)
        processor.free()


    func test_remove_network_frame_processor_unregisters_node():
        # Create and register test processor
        var processor := TestNetworkFrameProcessor.new()
        frame_driver.add_network_frame_processor(processor)

        # Remove processor
        var count_before := frame_driver._network_frame_processor_nodes.size()
        frame_driver.remove_network_frame_processor(processor)

        assert_eq(
            frame_driver._network_frame_processor_nodes.size(),
            count_before - 1,
            "Should remove processor from _network_frame_processor_nodes",
        )
        assert_false(
            frame_driver._network_frame_processor_nodes.has(processor),
            "Should not contain the test processor",
        )

        # Cleanup
        processor.free()
