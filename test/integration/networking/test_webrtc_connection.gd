@tool
extends GutTest
## Integration tests for WebRTC connection flow.
##
## These tests verify the signaling server and client
## lifecycle. Full DataChannel tests require the
## webrtc-native GDExtension to be installed.


func before_each():
	ArrayPool.clear_all_pools()


func after_each():
	ArrayPool.clear_all_pools()


class TestWebRTCSignalingServerLifecycle:
	extends GutTest
	## Tests that the signaling server starts and
	## stops without errors.


	func before_each():
		ArrayPool.clear_all_pools()


	func after_each():
		ArrayPool.clear_all_pools()


	func test_signaling_server_starts_and_stops():
		var server := WebRTCSignalingServer.new()
		add_child_autofree(server)

		server.start(14433)
		assert_true(
			server._is_running,
			"Server should be running after start",
		)

		server.stop()
		assert_false(
			server._is_running,
			"Server should be stopped after stop",
		)


	func test_signaling_server_double_stop_safe():
		var server := WebRTCSignalingServer.new()
		add_child_autofree(server)

		server.start(14434)
		server.stop()
		# Calling stop again should not crash.
		server.stop()
		assert_false(
			server._is_running,
			"Server should remain stopped",
		)


class TestWebRTCSignalingClientLifecycle:
	extends GutTest
	## Tests client signaling lifecycle.


	func before_each():
		ArrayPool.clear_all_pools()


	func after_each():
		ArrayPool.clear_all_pools()


	func test_client_stop_before_start():
		var client := WebRTCSignalingClient.new()
		add_child_autofree(client)
		# Should not crash.
		client.stop()
		assert_false(
			client._is_active,
			"Client should not be active",
		)


class TestWebRTCTransportEnum:
	extends GutTest
	## Tests that the WEBRTC transport type is
	## properly integrated.

	var _original_transport: int


	func before_each():
		ArrayPool.clear_all_pools()
		_original_transport = (
			Netcode.settings.transport_type)


	func after_each():
		ArrayPool.clear_all_pools()
		Netcode.settings.transport_type = (
			_original_transport)


	func test_transport_type_can_be_set_to_webrtc():
		Netcode.settings.transport_type = (
			NetworkSettings.TransportType.WEBRTC)
		assert_eq(
			Netcode.settings.transport_type,
			NetworkSettings.TransportType.WEBRTC,
			"Transport should be WEBRTC",
		)


	func test_webrtc_distinct_from_other_transports():
		var webrtc := (
			NetworkSettings.TransportType.WEBRTC)
		var enet := (
			NetworkSettings.TransportType.ENET)
		var websocket := (
			NetworkSettings.TransportType.WEBSOCKET)
		assert_ne(webrtc, enet)
		assert_ne(webrtc, websocket)
		assert_ne(enet, websocket)
