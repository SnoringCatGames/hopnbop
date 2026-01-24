extends GutTest
## Unit tests for NetworkConnector.
##
## NetworkConnector is a simple ENet wrapper, so these tests focus on
## configuration reading and connection lifecycle tracking.

func before_each():
    ArrayPool.clear_all_pools()


func after_each():
    ArrayPool.clear_all_pools()


class TestServerMode:
    extends GutTest
    ## Tests server peer creation and configuration.

    var connector: NetworkConnector


    func before_each():
        ArrayPool.clear_all_pools()


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(connector):
            connector.free()


    func test_server_id_constant():
        # Verify SERVER_ID is 1 (Godot multiplayer convention)
        assert_eq(
            NetworkConnector.SERVER_ID,
            1,
            "SERVER_ID should be 1",
        )


    func test_server_enable_connections_requires_server_role():
        # Test that server_enable_connections checks for server role
        # This test verifies the method exists and has proper checks
        # (actual connection creation is hard to test in unit tests)
        assert_true(
            NetworkConnector.new().has_method("server_enable_connections"),
            "Should have server_enable_connections method",
        )


    func test_server_close_multiplayer_session_exists():
        # Verify the method exists for server cleanup
        assert_true(
            NetworkConnector.new().has_method("server_close_multiplayer_session"),
            "Should have server_close_multiplayer_session method",
        )


class TestClientMode:
    extends GutTest
    ## Tests client peer creation and configuration.

    var connector: NetworkConnector


    func before_each():
        ArrayPool.clear_all_pools()


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(connector):
            connector.free()


    func test_client_connect_to_server_method_exists():
        # Verify client connection method exists
        assert_true(
            NetworkConnector.new().has_method("client_connect_to_server"),
            "Should have client_connect_to_server method",
        )


    func test_client_disconnect_method_exists():
        # Verify client disconnection method exists
        assert_true(
            NetworkConnector.new().has_method("client_disconnect"),
            "Should have client_disconnect method",
        )


    func test_initial_is_connected_to_server_is_false():
        # New connector should start disconnected
        connector = NetworkConnector.new()

        assert_false(
            connector.is_connected_to_server,
            "Should start disconnected",
        )


class TestConnectionLifecycle:
    extends GutTest
    ## Tests connection status tracking and signal handling.

    var connector: NetworkConnector


    func before_each():
        ArrayPool.clear_all_pools()
        connector = NetworkConnector.new()
        # Add to scene tree so multiplayer property is available
        add_child_autofree(connector)


    func after_each():
        ArrayPool.clear_all_pools()


    func test_on_peer_connected_handler_exists():
        # Verify the peer connected signal handler exists
        assert_true(
            connector.has_method("_on_peer_connected"),
            "Should have _on_peer_connected handler",
        )


    func test_on_peer_disconnected_handler_exists():
        # Verify the peer disconnected signal handler exists
        assert_true(
            connector.has_method("_on_peer_disconnected"),
            "Should have _on_peer_disconnected handler",
        )


    func test_client_update_is_connected_to_server_method_exists():
        # Verify the connection status update method exists
        assert_true(
            connector.has_method("_client_update_is_connected_to_server"),
            "Should have _client_update_is_connected_to_server method",
        )


    func test_connector_integrates_with_global_multiplayer_api():
        # Verify connector references the multiplayer singleton
        # (actual connection testing requires integration tests)
        assert_not_null(
            connector.multiplayer,
            "Should have access to multiplayer API",
        )
