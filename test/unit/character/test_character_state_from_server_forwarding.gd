@tool
extends GutTest
## Unit tests for CharacterStateFromServer input forwarding logic.
##
## Tests the _network_process() method that copies input data from
## PlayerInputFromClient to ForwardedPlayerInputFromServer.

const TestEnvironmentMock = preload("res://test/helpers/test_environment_mock.gd")

func before_each():
    ArrayPool.clear_all_pools()


func after_each():
    ArrayPool.clear_all_pools()
    TestEnvironmentMock.cleanup_mock_level()


class TestForwardingLogic:
    extends GutTest

    var root_node: Node
    var player: Player
    var state_from_server: CharacterStateFromServer
    var input_from_client: PlayerInputFromClient
    var forwarded_input: ForwardedPlayerInputFromServer


    func before_each():
        ArrayPool.clear_all_pools()

        root_node = Node.new()
        root_node.name = "Root"
        add_child_autofree(root_node)

        # Setup mock level.
        TestEnvironmentMock.setup_mock_level(root_node)

        # Create full 3-node setup using helper.
        var setup = TestEnvironmentMock.setup_player_with_networking(root_node)
        player = setup.player
        state_from_server = setup.state_from_server
        input_from_client = setup.input_from_client
        forwarded_input = setup.forwarded_input

        # Initialize all nodes.
        state_from_server._ready()
        input_from_client._ready()
        forwarded_input._ready()


    func after_each():
        ArrayPool.clear_all_pools()


    func test_caches_forwarded_input_on_ready():
        # _ready() was called in before_each, check if cached.
        assert_not_null(
            state_from_server.forwarded_input,
            "Should cache forwarded_input reference",
        )
        assert_eq(
            state_from_server.forwarded_input,
            forwarded_input,
            "Should reference the correct ForwardedInput node",
        )


    func test_cached_forwarded_input_is_null_when_missing():
        # Create 2-node setup without ForwardedInput.
        var player2 = TestEnvironmentMock.setup_test_player(root_node)
        player2.name = "Player2"

        var state2 = CharacterStateFromServer.new()
        state2.name = "StateFromServer2"
        state2.root_path = NodePath(".")
        TestEnvironmentMock.init_replication_config(state2)
        state2.character = player2
        player2.add_child(state2)

        var input2 = PlayerInputFromClient.new()
        input2.name = "InputFromClient2"
        input2.root_path = NodePath(".")
        TestEnvironmentMock.init_replication_config(input2)
        input2.player = player2
        player2.add_child(input2)

        # Initialize.
        state2._ready()
        input2._ready()

        # Should be null (no ForwardedInput sibling).
        assert_null(
            state2.forwarded_input,
            "Should be null when ForwardedInput missing",
        )


    func test_network_process_forwards_actions():
        # Mock server authority.
        state_from_server.set_multiplayer_authority(NetworkConnector.SERVER_ID)

        # Set input from client.
        input_from_client.actions = 0b0101

        # Character remains valid - forwarding happens during normal flow.

        # Call network process (forwarding happens before character logic).
        state_from_server._network_process()

        # ForwardedInput should receive the actions.
        assert_eq(
            forwarded_input.actions,
            0b0101,
            "Should forward actions to ForwardedInput",
        )


    func test_network_process_forwards_jump_timestamp():
        # Mock server authority.
        state_from_server.set_multiplayer_authority(NetworkConnector.SERVER_ID)

        # Set jump timestamp.
        input_from_client.last_triggered_jump_time_usec = 2000000

        # Character remains valid - forwarding happens during normal flow.

        # Call network process (forwarding happens before character logic).
        state_from_server._network_process()

        # ForwardedInput should receive the timestamp.
        assert_eq(
            forwarded_input.last_triggered_jump_time_usec,
            2000000,
            "Should forward jump timestamp to ForwardedInput",
        )


    func test_network_process_forwards_frame_authority():
        # Mock server authority.
        state_from_server.set_multiplayer_authority(NetworkConnector.SERVER_ID)

        # Set frame authority.
        input_from_client.frame_authority = \
        ReconcilableNetworkedState.FrameAuthority.PREDICTED

        # Character remains valid - forwarding happens during normal flow.

        # Call network process (forwarding happens before character logic).
        state_from_server._network_process()

        # ForwardedInput should receive the authority marker.
        assert_eq(
            forwarded_input.frame_authority,
            ReconcilableNetworkedState.FrameAuthority.PREDICTED,
            "Should forward frame authority to ForwardedInput",
        )


    func test_network_process_skips_when_not_server():
        # Mock client authority (not server).
        state_from_server.set_multiplayer_authority(2) # Client peer ID

        # Set input from client.
        input_from_client.actions = 0b1111

        # Character remains valid - forwarding happens during normal flow.

        # Call network process (forwarding happens before character logic).
        state_from_server._network_process()

        # ForwardedInput should remain at default (not forwarded).
        assert_eq(
            forwarded_input.actions,
            0,
            "Should not forward when not server authority",
        )


    func test_network_process_skips_when_forwarded_input_null():
        # Remove forwarded_input reference.
        state_from_server.forwarded_input = null

        # Mock server authority.
        state_from_server.set_multiplayer_authority(NetworkConnector.SERVER_ID)

        # Set input from client.
        input_from_client.actions = 0b1111

        # Character remains valid - forwarding happens during normal flow.

        # Should not crash.
        state_from_server._network_process()

        # No assertions needed - just verify no crash.


    func test_network_process_skips_when_input_from_client_null():
        # This shouldn't normally happen, but test robustness.
        # Force input_from_client to null (simulating edge case).
        state_from_server.input_from_client = null

        # Mock server authority.
        state_from_server.set_multiplayer_authority(NetworkConnector.SERVER_ID)

        # Character remains valid - forwarding happens during normal flow.

        # Should not crash.
        state_from_server._network_process()

        # ForwardedInput should remain at default.
        assert_eq(
            forwarded_input.actions,
            0,
            "Should handle null input_from_client gracefully",
        )


    func test_network_process_forwards_all_properties_atomically():
        # Mock server authority.
        state_from_server.set_multiplayer_authority(NetworkConnector.SERVER_ID)

        # Set multiple input properties.
        input_from_client.actions = 0b1010
        input_from_client.last_triggered_jump_time_usec = 3500000
        input_from_client.frame_authority = \
        ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE

        # Character remains valid - forwarding happens during normal flow.

        # Call network process (forwarding happens before character logic).
        state_from_server._network_process()

        # All properties should be forwarded.
        assert_eq(
            forwarded_input.actions,
            0b1010,
            "Should forward actions",
        )
        assert_eq(
            forwarded_input.last_triggered_jump_time_usec,
            3500000,
            "Should forward jump timestamp",
        )
        assert_eq(
            forwarded_input.frame_authority,
            ReconcilableNetworkedState.FrameAuthority.AUTHORITATIVE,
            "Should forward frame authority",
        )
