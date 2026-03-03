extends GutTest
## Unit tests for ScaffolderLog test environment detection.

func test_detects_test_environment():
	assert_true(
		TestEnvironmentDetector.is_running_in_test_env(G.log),
		"Should detect running in test environment",
	)


func test_check_does_not_quit_on_failure_in_tests():
	# This should not call get_tree().quit() in test environment
	var result = G.log.check(false, "Test check failure")

	# If we reach here, check didn't quit
	assert_false(result, "Check should return false for failed condition")
