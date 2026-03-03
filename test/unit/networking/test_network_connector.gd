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
	## Tests server-related constants and enums.

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_server_id_constant():
		# Verify SERVER_ID is 1 (Godot multiplayer convention).
		assert_eq(
			NetworkConnector.SERVER_ID,
			1,
			"SERVER_ID should be 1",
		)

	func test_disconnect_reason_enum_values():
		# Verify DisconnectReason enum has correct ordinal
		# values for protocol compatibility.
		assert_eq(
			NetworkConnector.DisconnectReason.UNKNOWN,
			0,
			"UNKNOWN should be 0",
		)
		assert_eq(
			NetworkConnector.DisconnectReason.CLIENT_INITIATED,
			1,
			"CLIENT_INITIATED should be 1",
		)
		assert_eq(
			NetworkConnector.DisconnectReason.SERVER_SHUTDOWN,
			2,
			"SERVER_SHUTDOWN should be 2",
		)
		assert_eq(
			NetworkConnector.DisconnectReason.CONNECTION_FAILED,
			3,
			"CONNECTION_FAILED should be 3",
		)
		assert_eq(
			NetworkConnector.DisconnectReason.CONNECTION_LOST,
			4,
			"CONNECTION_LOST should be 4",
		)
		assert_eq(
			NetworkConnector.DisconnectReason.MATCH_FINISHED,
			5,
			"MATCH_FINISHED should be 5",
		)

	func test_rpc_channel_constants():
		# Verify RPC channel constants match expected
		# assignments for ENet channel ordering.
		assert_eq(
			NetworkConnector.RPC_CHANNEL_DEFAULT,
			0,
			"RPC_CHANNEL_DEFAULT should be 0",
		)
		assert_eq(
			NetworkConnector.RPC_CHANNEL_SESSION_CONTROL,
			1,
			"RPC_CHANNEL_SESSION_CONTROL should be 1",
		)
		assert_eq(
			NetworkConnector.RPC_CHANNEL_CLOCK_SYNC,
			2,
			"RPC_CHANNEL_CLOCK_SYNC should be 2",
		)
		assert_eq(
			NetworkConnector.RPC_CHANNEL_GAME_EVENTS,
			3,
			"RPC_CHANNEL_GAME_EVENTS should be 3",
		)
		assert_eq(
			NetworkConnector.RPC_CHANNEL_STATS,
			4,
			"RPC_CHANNEL_STATS should be 4",
		)
		assert_eq(
			NetworkConnector.RPC_CHANNEL_DEBUG,
			5,
			"RPC_CHANNEL_DEBUG should be 5",
		)


class TestClientMode:
	extends GutTest
	## Tests client-side initial state.

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_initial_connection_status_is_disconnected():
		# A freshly created connector should not report
		# as connected.
		var connector := NetworkConnector.new()
		assert_false(
			connector.is_connected_to_server,
			"New connector should not be connected",
		)
		connector.free()

	func test_initial_disconnect_reason_is_unknown():
		# A freshly created connector should have UNKNOWN
		# as its last disconnect reason.
		var connector := NetworkConnector.new()
		assert_eq(
			connector.last_disconnect_reason,
			NetworkConnector.DisconnectReason.UNKNOWN,
			"Initial disconnect reason should be UNKNOWN",
		)
		connector.free()


class TestConnectionLifecycle:
	extends GutTest
	## Tests connection status tracking and signal handling.

	func before_each():
		ArrayPool.clear_all_pools()

	func after_each():
		ArrayPool.clear_all_pools()

	func test_connector_declares_expected_signals():
		# Verify the connector exposes the signals that
		# game code connects to.
		assert_true(
			Netcode.connector.has_signal("connected"),
			"Should have connected signal",
		)
		assert_true(
			Netcode.connector.has_signal("disconnected"),
			"Should have disconnected signal",
		)
		assert_true(
			Netcode.connector.has_signal("player_ids_assigned"),
			"Should have player_ids_assigned signal",
		)
		assert_true(
			Netcode.connector.has_signal("peer_players_declared"),
			"Should have peer_players_declared signal",
		)

	func test_player_id_lookup_returns_defaults_for_unknown_ids():
		# Looking up an unregistered player_id should
		# return safe default values.
		assert_eq(
			Netcode.connector.get_peer_id_from_player_id(999),
			0,
			"Unknown player_id should return peer_id 0",
		)
		assert_eq(
			Netcode.connector.get_local_player_index_from_player_id(999),
			-1,
			"Unknown player_id should return index -1",
		)

	func test_connector_integrates_with_global_multiplayer_api():
		# Verify connector references the multiplayer singleton.
		assert_not_null(
			Netcode.connector.multiplayer,
			"Should have access to multiplayer API",
		)
