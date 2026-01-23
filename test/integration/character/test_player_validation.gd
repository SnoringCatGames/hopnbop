extends GutTest
## Integration tests for Player class scene configuration validation.
##
## Tests that the Player class correctly validates the presence of
## ForwardedPlayerInputFromServer and provides appropriate warnings.

const TestEnvironmentMock = preload("res://test/helpers/test_environment_mock.gd")


func before_each():
    ArrayPool.clear_all_pools()


func after_each():
    ArrayPool.clear_all_pools()


class TestSceneConfiguration:
    extends GutTest

    var root_node: Node


    func before_each():
        ArrayPool.clear_all_pools()

        root_node = Node.new()
        root_node.name = "Root"
        add_child_autofree(root_node)

        # Setup mock level for Player lifecycle.
        TestEnvironmentMock.setup_mock_level(root_node)


    func after_each():
        ArrayPool.clear_all_pools()
        TestEnvironmentMock.cleanup_mock_level()
