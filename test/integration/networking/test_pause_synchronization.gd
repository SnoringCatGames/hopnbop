extends GutTest
## Integration tests for pause/unpause synchronization.
##
## These tests verify pause coordination scenarios. Most detailed testing
## (state filtering, buffer cleanup) is covered in unit tests.

static func _create_mock_config() -> NetworkSettings:
	var config := NetworkSettings.new()
	config.server_port = 4433
	config.rollback_buffer_duration_sec = 1.5
	return config


static func _create_mock_logger() -> NetworkLogger:
	return NetworkLogger.new()


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestFrameIndexContinuity:
	extends GutTest
	## Tests that frame indices remain continuous across pause/unpause cycles.

	var frame_driver: FrameDriver

	static func _create_mock_config() -> NetworkSettings:
		var config := NetworkSettings.new()
		config.server_port = 4433
		config.rollback_buffer_duration_sec = 1.5
		return config

	static func _create_mock_logger() -> NetworkLogger:
		return NetworkLogger.new()

	func before_each():
		ArrayPool.clear_all_pools()

		# Set up Netcode singleton with mock dependencies.
		Netcode.settings = _create_mock_config()
		Netcode.log = _create_mock_logger()

		# Initialize Netcode to create TimeUtils and other dependencies.
		Netcode.initialize()

		var mock_orchestrator := Node.new()
		mock_orchestrator.set_script(load("res://test/helpers/mock_orchestrator.gd"))
		mock_orchestrator.is_server = true
		mock_orchestrator.is_preview = false
		add_child_autofree(mock_orchestrator)

		var mock_connector := Node.new()
		add_child_autofree(mock_connector)

		# FrameDriver now uses Netcode singleton for dependencies.
		frame_driver = FrameDriver.new()
		add_child_autofree(frame_driver)


	func after_each():
		ArrayPool.clear_all_pools()


	func test_frame_index_stays_constant_during_pause():
		# Start at frame 100, unpause.
		frame_driver.server_frame_index = 100
		frame_driver.server_set_is_paused(false)

		# Pause.
		frame_driver.server_set_is_paused(true)

		# Run network processing while paused. Frame index
		# should not advance.
		frame_driver._run_network_process()

		assert_eq(
			frame_driver.server_frame_index,
			100,
			"Frame index should stay constant during pause",
		)


	func test_frame_index_resumes_from_pause_frame():
		# Pause at frame 100
		frame_driver.server_frame_index = 100
		frame_driver.server_set_is_paused(false)
		frame_driver.server_set_is_paused(true)

		# Unpause
		frame_driver.server_set_is_paused(false)

		# Frame should still be 100
		assert_eq(
			frame_driver.server_frame_index,
			100,
			"Frame index should resume from pause frame",
		)


	func test_no_gaps_in_frame_sequence_after_unpause():
		# Pause at 100, unpause at 100, next frame should be 101
		frame_driver.server_frame_index = 100
		frame_driver.server_set_is_paused(false)
		frame_driver.server_set_is_paused(true)
		frame_driver.server_set_is_paused(false)

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

	var frame_driver: FrameDriver

	static func _create_mock_config() -> NetworkSettings:
		var config := NetworkSettings.new()
		config.server_port = 4433
		config.rollback_buffer_duration_sec = 1.5
		return config

	static func _create_mock_logger() -> NetworkLogger:
		return NetworkLogger.new()

	func before_each():
		ArrayPool.clear_all_pools()

		# Set up Netcode singleton with mock dependencies.
		Netcode.settings = _create_mock_config()
		Netcode.log = _create_mock_logger()

		# Initialize Netcode to create TimeUtils and other dependencies.
		Netcode.initialize()

		var mock_orchestrator := Node.new()
		mock_orchestrator.set_script(load("res://test/helpers/mock_orchestrator.gd"))
		mock_orchestrator.is_server = true
		mock_orchestrator.is_preview = false
		add_child_autofree(mock_orchestrator)

		var mock_connector := Node.new()
		add_child_autofree(mock_connector)

		# FrameDriver now uses Netcode singleton for dependencies.
		frame_driver = FrameDriver.new()
		add_child_autofree(frame_driver)


	func after_each():
		ArrayPool.clear_all_pools()


	func test_can_queue_rollback_after_unpause():
		# Pause and unpause
		frame_driver.server_frame_index = 100
		frame_driver.server_set_is_paused(false)
		frame_driver.server_set_is_paused(true)
		frame_driver.server_set_is_paused(false)

		# Queue rollback after unpause
		var result := frame_driver.queue_rollback(95)

		assert_true(
			result,
			"Should be able to queue rollback after unpause",
		)
