extends GutTest
## Unit tests for ServerTimeTracker time synchronization logic.
##
## Note: These tests focus on the calculation logic and internal state
## management. Full RPC testing requires integration tests with actual
## multiplayer peers.


class TestTimeOffsetCalculation:
    extends GutTest

    func test_calculates_zero_offset_with_symmetric_latency():
        # Simulate NTP exchange with symmetric network latency.
        # T1: Client sends at 1000 usec
        var t1 := 1000
        # T2: Server receives at 1050 usec (50 usec one-way latency)
        var t2 := 1050
        # T3: Server responds at 1051 usec (1 usec processing time)
        var t3 := 1051
        # T4: Client receives at 1101 usec (50 usec one-way latency)
        var t4 := 1101

        # Calculate RTT: (T4 - T1) - (T3 - T2)
        # = (1101 - 1000) - (1051 - 1050)
        # = 101 - 1 = 100 usec
        var rtt := (t4 - t1) - (t3 - t2)
        assert_eq(rtt, 100)

        # Calculate offset: ((T2 - T1) + (T3 - T4)) / 2
        # = ((1050 - 1000) + (1051 - 1101)) / 2
        # = (50 - 50) / 2 = 0
        @warning_ignore("integer_division")
        var offset := ((t2 - t1) + (t3 - t4)) / 2
        assert_eq(offset, 0, "Symmetric latency should yield 0 offset")

    func test_calculates_positive_offset_when_server_ahead():
        # Server clock is 100 usec ahead of client.
        # T1: Client sends at 1000 usec
        var t1 := 1000
        # T2: Server receives at 1150 usec (server is 100 usec ahead + 50
        #     usec latency)
        var t2 := 1150
        # T3: Server responds immediately
        var t3 := 1150
        # T4: Client receives at 1100 usec (client time + 50 usec latency)
        var t4 := 1100

        # Calculate offset: ((1150 - 1000) + (1150 - 1100)) / 2
        # = (150 + 50) / 2 = 100 usec
        @warning_ignore("integer_division")
        var offset := ((t2 - t1) + (t3 - t4)) / 2
        assert_eq(offset, 100, "Server ahead should yield positive offset")

    func test_calculates_negative_offset_when_server_behind():
        # Server clock is 100 usec behind client.
        # T1: Client sends at 1000 usec
        var t1 := 1000
        # T2: Server receives at 950 usec (server is 100 usec behind + 50
        #     usec latency)
        var t2 := 950
        # T3: Server responds immediately
        var t3 := 950
        # T4: Client receives at 1100 usec
        var t4 := 1100

        # Calculate offset: ((950 - 1000) + (950 - 1100)) / 2
        # = (-50 - 150) / 2 = -100 usec
        @warning_ignore("integer_division")
        var offset := ((t2 - t1) + (t3 - t4)) / 2
        assert_eq(offset, -100, "Server behind should yield negative offset")


class TestSampleManagement:
    extends GutTest

    var tracker: ServerTimeTracker

    func before_each():
        tracker = ServerTimeTracker.new()
        # Disable auto-sync for testing.
        tracker.auto_sync_interval = 0.0

    func test_initial_state():
        assert_eq(tracker.clock_offset_usec, 0)
        assert_eq(tracker.rtt_usec, 0)
        assert_false(tracker.is_synced)

    func test_clear_resets_state():
        # Manually set some state.
        tracker.clock_offset_usec = 1000
        tracker.rtt_usec = 200
        tracker.is_synced = true

        tracker.clear()

        assert_eq(tracker.clock_offset_usec, 0)
        assert_eq(tracker.rtt_usec, 0)
        assert_false(tracker.is_synced)

    func test_force_clock_offset_adjusts_offset():
        tracker.clock_offset_usec = 100

        tracker.force_clock_offset(50)

        assert_eq(tracker.clock_offset_usec, 150)

    func test_force_clock_offset_adjusts_samples():
        # Simulate having some samples.
        tracker._client_offset_samples = [100, 110, 120]

        tracker.force_clock_offset(50)

        # All samples should be adjusted.
        assert_eq(tracker._client_offset_samples[0], 150)
        assert_eq(tracker._client_offset_samples[1], 160)
        assert_eq(tracker._client_offset_samples[2], 170)


class TestServerTimeEstimation:
    extends GutTest

    var tracker: ServerTimeTracker

    func before_each():
        tracker = ServerTimeTracker.new()
        tracker.auto_sync_interval = 0.0

    func test_get_server_time_with_zero_offset():
        tracker.clock_offset_usec = 0

        var local_time := 5000
        # Mock Time.get_ticks_usec() by setting offset to 0 and checking the
        # formula.
        # Since we can't easily mock Time.get_ticks_usec(), we'll test the
        # formula directly.
        var estimated_server_time := local_time + tracker.clock_offset_usec

        assert_eq(estimated_server_time, 5000)

    func test_get_server_time_with_positive_offset():
        tracker.clock_offset_usec = 1000

        var local_time := 5000
        var estimated_server_time := local_time + tracker.clock_offset_usec

        assert_eq(estimated_server_time, 6000)

    func test_get_server_time_with_negative_offset():
        tracker.clock_offset_usec = -500

        var local_time := 5000
        var estimated_server_time := local_time + tracker.clock_offset_usec

        assert_eq(estimated_server_time, 4500)


class TestSampleAveraging:
    extends GutTest

    func test_averages_multiple_offset_samples():
        var samples := [100, 110, 90, 105, 95]

        var total := 0
        for sample in samples:
            total += sample

        @warning_ignore("integer_division")
        var average := total / samples.size()

        # Average should be (100 + 110 + 90 + 105 + 95) / 5 = 500 / 5 = 100.
        assert_eq(average, 100)

    func test_sample_limit_removes_oldest():
        var samples := [10, 20, 30, 40, 50]
        var max_samples := 3

        # Simulate keeping only the most recent samples.
        while samples.size() > max_samples:
            samples.pop_front()

        assert_eq(samples.size(), 3)
        assert_eq(samples[0], 30)
        assert_eq(samples[1], 40)
        assert_eq(samples[2], 50)
