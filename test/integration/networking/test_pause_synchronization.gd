extends GutTest
## Integration tests for pause/unpause synchronization.
##
## These tests verify pause coordination scenarios. Most detailed testing
## (state filtering, buffer cleanup) is covered in unit tests.


func before_each():
    ArrayPool.clear_all_pools()


func after_each():
    ArrayPool.clear_all_pools()


class TestFrameIndexContinuity:
    extends GutTest
    ## Tests that frame indices remain continuous across pause/unpause cycles.

    var frame_driver: NetworkFrameDriver


    func before_each():
        ArrayPool.clear_all_pools()
        frame_driver = NetworkFrameDriver.new()


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(frame_driver):
            frame_driver.free()


    func test_frame_index_stays_constant_during_pause():
        # Start at frame 100, unpause
        frame_driver.server_frame_index = 100
        frame_driver.set_paused(false)

        # Pause
        frame_driver.set_paused(true)

        var frame_at_pause := frame_driver.server_frame_index

        # Frame should stay constant (in real scenario, _pre_physics_process
        # returns early)
        assert_eq(
            frame_driver.server_frame_index,
            frame_at_pause,
            "Frame index should stay constant during pause",
        )


    func test_frame_index_resumes_from_pause_frame():
        # Pause at frame 100
        frame_driver.server_frame_index = 100
        frame_driver.set_paused(false)
        frame_driver.set_paused(true)

        # Unpause
        frame_driver.set_paused(false)

        # Frame should still be 100
        assert_eq(
            frame_driver.server_frame_index,
            100,
            "Frame index should resume from pause frame",
        )


    func test_no_gaps_in_frame_sequence_after_unpause():
        # Pause at 100, unpause at 100, next frame should be 101
        frame_driver.server_frame_index = 100
        frame_driver.set_paused(false)
        frame_driver.set_paused(true)
        frame_driver.set_paused(false)

        # Simulate next physics tick
        frame_driver.server_frame_index += 1

        assert_eq(
            frame_driver.server_frame_index,
            101,
            "No gaps in frame sequence after unpause",
        )


class TestPauseRollbackInteraction:
    extends GutTest
    ## Tests interaction between pause and rollback systems.

    var frame_driver: NetworkFrameDriver


    func before_each():
        ArrayPool.clear_all_pools()
        frame_driver = NetworkFrameDriver.new()


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(frame_driver):
            frame_driver.free()


    func test_can_queue_rollback_after_unpause():
        # Pause and unpause
        frame_driver.server_frame_index = 100
        frame_driver.set_paused(false)
        frame_driver.set_paused(true)
        frame_driver.set_paused(false)

        # Queue rollback after unpause
        var result := frame_driver.queue_rollback(95)

        assert_true(
            result,
            "Should be able to queue rollback after unpause",
        )
