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


    func test_player_warns_when_forwarded_input_missing():
        # Create Player with only InputFromClient (2-node setup).
        var player = Player.new()
        player.name = "Player"

        # Initialize required Character exports to prevent _ready() errors.
        player.movement_settings = MovementSettings.new()
        player.collision_shape = CollisionShape2D.new()
        player.animator = CharacterAnimator.new()

        root_node.add_child(player)

        var state_from_server = CharacterStateFromServer.new()
        state_from_server.name = "StateFromServer"
        state_from_server.root_path = NodePath(".")
        state_from_server.replication_config = SceneReplicationConfig.new()
        state_from_server.character = player
        player.add_child(state_from_server)

        var input_from_client = PlayerInputFromClient.new()
        input_from_client.name = "InputFromClient"
        input_from_client.root_path = NodePath(".")
        input_from_client.replication_config = SceneReplicationConfig.new()
        input_from_client.player = player
        player.add_child(input_from_client)

        # Set exports.
        player.state_from_server = state_from_server
        player.input_from_client = input_from_client
        # Don't set forwarded_input_from_server.

        var warnings := player._get_configuration_warnings()

        var has_forwarded_warning := false
        for warning in warnings:
            if "forwarded_input_from_server" in warning:
                has_forwarded_warning = true
                break

        assert_true(
            has_forwarded_warning,
            "Should warn when forwarded_input_from_server is missing",
        )


    func test_player_no_warnings_when_fully_configured():
        # Create full 3-node setup.
        var player = Player.new()
        player.name = "Player"

        # Initialize required Character exports to prevent _ready() errors.
        player.movement_settings = MovementSettings.new()
        player.collision_shape = CollisionShape2D.new()
        player.animator = CharacterAnimator.new()

        root_node.add_child(player)

        var state_from_server = CharacterStateFromServer.new()
        state_from_server.name = "StateFromServer"
        state_from_server.root_path = NodePath(".")
        state_from_server.replication_config = SceneReplicationConfig.new()
        state_from_server.character = player
        player.add_child(state_from_server)

        var input_from_client = PlayerInputFromClient.new()
        input_from_client.name = "InputFromClient"
        input_from_client.root_path = NodePath(".")
        input_from_client.replication_config = SceneReplicationConfig.new()
        input_from_client.player = player
        player.add_child(input_from_client)

        var forwarded_input = ForwardedPlayerInputFromServer.new()
        forwarded_input.name = "ForwardedInput"
        forwarded_input.root_path = NodePath(".")
        forwarded_input.replication_config = SceneReplicationConfig.new()
        forwarded_input.player = player
        player.add_child(forwarded_input)

        # Set all exports.
        player.state_from_server = state_from_server
        player.input_from_client = input_from_client
        player.forwarded_input_from_server = forwarded_input

        var warnings := player._get_configuration_warnings()

        assert_eq(
            warnings.size(),
            0,
            "Should have no warnings when fully configured",
        )


    func test_player_warns_when_input_from_client_missing():
        # Test that existing validation still works.
        var player = Player.new()
        player.name = "Player"

        # Initialize required Character exports to prevent _ready() errors.
        player.movement_settings = MovementSettings.new()
        player.collision_shape = CollisionShape2D.new()
        player.animator = CharacterAnimator.new()

        root_node.add_child(player)

        # Don't add any child nodes.

        var warnings := player._get_configuration_warnings()

        var has_input_warning := false
        for warning in warnings:
            if "input_from_client" in warning:
                has_input_warning = true
                break

        assert_true(
            has_input_warning,
            "Should warn when input_from_client is missing",
        )


class TestBunnySceneConfiguration:
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


    func test_bunny_scene_has_all_nodes():
        # Load Bunny scene.
        var bunny_scene := load("res://src/player/bunny.tscn")
        var bunny: Player = bunny_scene.instantiate()
        add_child_autofree(bunny)

        # Verify all 3 nodes are present.
        assert_not_null(
            bunny.state_from_server,
            "Bunny should have state_from_server",
        )
        assert_not_null(
            bunny.input_from_client,
            "Bunny should have input_from_client",
        )
        assert_not_null(
            bunny.forwarded_input_from_server,
            "Bunny should have forwarded_input_from_server",
        )


    func test_bunny_scene_node_paths_correct():
        # Load Bunny scene.
        var bunny_scene := load("res://src/player/bunny.tscn")
        var bunny: Player = bunny_scene.instantiate()
        add_child_autofree(bunny)

        # Verify node paths resolve correctly.
        var state_from_server := bunny.get_node("StateFromServer")
        var input_from_client := bunny.get_node("InputFromClient")
        var forwarded_input := bunny.get_node("ForwardedInputFromServer")

        assert_not_null(state_from_server, "StateFromServer node should exist")
        assert_not_null(input_from_client, "InputFromClient node should exist")
        assert_not_null(forwarded_input, "ForwardedInputFromServer node should exist")

        # Verify exported properties reference the correct nodes.
        assert_eq(
            bunny.state_from_server,
            state_from_server,
            "state_from_server export should reference StateFromServer node",
        )
        assert_eq(
            bunny.input_from_client,
            input_from_client,
            "input_from_client export should reference InputFromClient node",
        )
        assert_eq(
            bunny.forwarded_input_from_server,
            forwarded_input,
            "forwarded_input_from_server export should reference ForwardedInputFromServer node",
        )


    func test_bunny_scene_no_warnings():
        # Load Bunny scene.
        var bunny_scene := load("res://src/player/bunny.tscn")
        var bunny: Player = bunny_scene.instantiate()
        add_child_autofree(bunny)

        # Scene should have no configuration warnings.
        var warnings := bunny._get_configuration_warnings()

        assert_eq(
            warnings.size(),
            0,
            "Bunny scene should have no configuration warnings",
        )
