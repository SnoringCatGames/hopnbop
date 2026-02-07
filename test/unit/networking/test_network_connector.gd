extends GutTest
## Unit tests for NetworkConnector.
##
## NetworkConnector is accessed via Netcode.connector autoload.
## These tests verify the connector API and basic functionality.

func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestServerMode:
	extends GutTest
	## Tests server peer creation and configuration.

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_server_id_constant():
		# Verify SERVER_ID is 1 (Godot multiplayer convention)
		assert_eq(
			NetworkConnector.SERVER_ID,
			1,
			"SERVER_ID should be 1"
		)

	func test_server_enable_connections_method_exists():
		# Verify server connection method exists on Netcode.connector
		assert_true(
			Netcode.connector.has_method("server_enable_connections"),
			"Should have server_enable_connections method"
		)

	func test_server_close_multiplayer_session_exists():
		# Verify server cleanup method exists
		assert_true(
			Netcode.connector.has_method("server_close_multiplayer_session"),
			"Should have server_close_multiplayer_session method"
		)


class TestClientMode:
	extends GutTest
	## Tests client peer creation and configuration.

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_client_connect_to_server_method_exists():
		# Verify client connection method exists on Netcode.connector
		assert_true(
			Netcode.connector.has_method("client_connect_to_server"),
			"Should have client_connect_to_server method"
		)

	func test_client_disconnect_method_exists():
		# Verify client disconnection method exists
		assert_true(
			Netcode.connector.has_method("client_disconnect"),
			"Should have client_disconnect method"
		)

	func test_is_connected_to_server_property_exists():
		# Verify connection status property exists
		assert_true(
			"is_connected_to_server" in Netcode.connector,
			"Should have is_connected_to_server property"
		)


class TestConnectionLifecycle:
	extends GutTest
	## Tests connection status tracking and signal handling.

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_on_peer_connected_handler_exists():
		# Verify the peer connected signal handler exists
		assert_true(
			Netcode.connector.has_method("_on_peer_connected"),
			"Should have _on_peer_connected handler"
		)

	func test_on_peer_disconnected_handler_exists():
		# Verify the peer disconnected signal handler exists
		assert_true(
			Netcode.connector.has_method("_on_peer_disconnected"),
			"Should have _on_peer_disconnected handler"
		)

	func test_client_update_is_connected_to_server_method_exists():
		# Verify the connection status update method exists
		assert_true(
			Netcode.connector.has_method("_client_update_is_connected_to_server"),
			"Should have _client_update_is_connected_to_server method"
		)

	func test_connector_integrates_with_global_multiplayer_api():
		# Verify connector references the multiplayer singleton
		assert_not_null(
			Netcode.connector.multiplayer,
			"Should have access to multiplayer API"
		)
