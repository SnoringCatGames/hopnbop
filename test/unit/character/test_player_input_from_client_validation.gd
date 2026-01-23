@tool
extends GutTest
## Unit tests for PlayerInputFromClient sibling validation and sync guards.
##
## Tests the validation logic that ensures ForwardedPlayerInputFromServer is
## present and has matching synced properties, and the authority guards that
## prevent sync conflicts.

func before_each():
    ArrayPool.clear_all_pools()


func after_each():
    ArrayPool.clear_all_pools()


class TestSiblingValidation:
    extends GutTest

    var root_node: Node
    var player: Player
    var input_from_client: PlayerInputFromClient


    func before_each():
        ArrayPool.clear_all_pools()

        root_node = Node.new()
        root_node.name = "Root"
        add_child_autofree(root_node)

        player = Player.new()
        player.name = "Player"
        root_node.add_child(player)


    func after_each():
        ArrayPool.clear_all_pools()


    func test_warning_when_forwarded_input_sibling_missing():
        # Create PlayerInputFromClient without ForwardedInput sibling.
        input_from_client = PlayerInputFromClient.new()
        input_from_client.name = "InputFromClient"
        input_from_client.root_path = NodePath(".")
        input_from_client.player = player
        player.add_child(input_from_client)

        input_from_client._ready()

        var warnings := input_from_client._get_configuration_warnings()

        var has_sibling_warning := false
        for warning in warnings:
            if "requires a ForwardedPlayerInputFromServer sibling" in warning:
                has_sibling_warning = true
                break

        assert_true(
            has_sibling_warning,
            "Should warn when ForwardedInput sibling is missing",
        )


    func test_no_warning_when_siblings_present_and_match():
        # Create full setup with matching properties.
        var state_from_server = CharacterStateFromServer.new()
        state_from_server.name = "StateFromServer"
        state_from_server.root_path = NodePath(".")
        state_from_server.character = player
        player.add_child(state_from_server)

        input_from_client = PlayerInputFromClient.new()
        input_from_client.name = "InputFromClient"
        input_from_client.root_path = NodePath(".")
        input_from_client.player = player
        player.add_child(input_from_client)

        var forwarded_input = ForwardedPlayerInputFromServer.new()
        forwarded_input.name = "ForwardedInput"
        forwarded_input.root_path = NodePath(".")
        forwarded_input.player = player
        player.add_child(forwarded_input)

        # Initialize all nodes.
        state_from_server._ready()
        input_from_client._ready()
        forwarded_input._ready()

        var warnings := input_from_client._get_configuration_warnings()

        # Filter to input-specific warnings.
        var input_specific_warnings := PackedStringArray()
        for warning in warnings:
            if "sibling" in warning or "properties" in warning:
                input_specific_warnings.append(warning)

        assert_eq(
            input_specific_warnings.size(),
            0,
            "Should have no warnings when siblings match",
        )


class TestSyncGuard:
    extends GutTest

    var root_node: Node
    var player: Player
    var input_from_client: PlayerInputFromClient


    func before_each():
        ArrayPool.clear_all_pools()

        root_node = Node.new()
        root_node.name = "Root"
        add_child_autofree(root_node)

        player = Player.new()
        player.name = "Player"
        root_node.add_child(player)

        input_from_client = PlayerInputFromClient.new()
        input_from_client.name = "InputFromClient"
        input_from_client.root_path = NodePath(".")
        input_from_client.player = player
        player.add_child(input_from_client)

        input_from_client._ready()
        # Initialize rollback buffer.
        if input_from_client._rollback_buffer == null:
            input_from_client._set_up_rollback_buffer()
        input_from_client._parse_property_names()


    func after_each():
        ArrayPool.clear_all_pools()


    func test_sync_to_scene_state_only_runs_for_authority():
        # Mock remote player (no authority).
        input_from_client.set_multiplayer_authority(2) # Different peer

        # Set actions.
        input_from_client.actions = 0b1111

        # Create previous state.
        var previous_state := ArrayPool.acquire(2)
        previous_state[0] = 0b0001
        previous_state[1] = -1

        # Sync to scene state.
        input_from_client._sync_to_scene_state(previous_state)

        # Player actions should NOT be modified (no authority).
        assert_eq(
            player.actions.bitmask,
            0,
            "Should not sync when not authority",
        )

        ArrayPool.release(previous_state)


    func test_sync_to_scene_state_runs_for_authority():
        # Mock local authority.
        input_from_client.set_multiplayer_authority(
            multiplayer.get_unique_id(),
        )

        # Set actions.
        input_from_client.actions = 0b0110

        # Create previous state.
        var previous_state := ArrayPool.acquire(2)
        previous_state[0] = 0b0010
        previous_state[1] = -1

        # Sync to scene state.
        input_from_client._sync_to_scene_state(previous_state)

        # Player actions should be updated.
        assert_eq(
            player.actions.bitmask,
            0b0110,
            "Should sync when has authority",
        )
        assert_eq(
            player.actions.previous_bitmask,
            0b0010,
            "Should update previous actions",
        )

        ArrayPool.release(previous_state)


    func test_sync_to_scene_state_updates_jump_frame_index_for_authority():
        # Mock local authority.
        input_from_client.set_multiplayer_authority(
            multiplayer.get_unique_id(),
        )

        # Set jump timestamp.
        var frame_100_time := \
        G.network.frame_driver.get_time_usec_from_frame_index(100)
        input_from_client.last_triggered_jump_time_usec = frame_100_time

        # Create previous state.
        var previous_state := ArrayPool.acquire(2)
        previous_state[0] = 0
        previous_state[1] = -1

        # Sync to scene state.
        input_from_client._sync_to_scene_state(previous_state)

        # Player should have jump frame index.
        assert_eq(
            player.last_triggered_jump_frame_index,
            100,
            "Should update jump frame when has authority",
        )

        ArrayPool.release(previous_state)
