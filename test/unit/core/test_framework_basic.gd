extends GutTest
## Simple test to verify testing framework is working

func test_basic_assertion():
    assert_true(true, "Basic assertion should pass")


func test_can_access_global():
    # Test that we can access the global singleton
    assert_not_null(G, "Global singleton should be accessible")


func test_scaffolder_classes_loaded():
    # Test that Scaffolder classes are properly loaded
    var log_instance = ScaffolderLog.new()
    assert_not_null(log_instance, "ScaffolderLog should be instantiable")
    log_instance.queue_free()

    var time_instance = ScaffolderTime.new()
    assert_not_null(time_instance, "ScaffolderTime should be instantiable")
    time_instance.queue_free()

    var utils_instance = Utils.new()
    assert_not_null(utils_instance, "Utils should be instantiable")
    utils_instance.queue_free()
