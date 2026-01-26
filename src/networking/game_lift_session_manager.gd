class_name GameLiftSessionManager
extends Node


# FIXME: LEFT OFF HERE: Review this.


## Emitted when session IDs are successfully received from backend.
signal local_session_ids_received(
	session_ids: Array,
	server_ip: String,
	server_port: int
)

## Emitted when session ID request fails.
signal session_request_failed(error_message: String)

## Backend API base URL.
var backend_api_url := ""

## Request timeout in seconds.
var request_timeout_sec := 30.0

var _http_request: HTTPRequest
var _request_timer: Timer


func _ready() -> void:
	# Create HTTP request node.
	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout_sec
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

	# Create manual timeout timer as backup.
	_request_timer = Timer.new()
	_request_timer.one_shot = true
	_request_timer.timeout.connect(_on_request_timeout)
	add_child(_request_timer)


## Requests session IDs from backend for the specified number of players.
func request_session_ids(player_count: int) -> void:
	if not G.network.should_connect_to_local_preview_server:
		_handle_preview_local_server_mode(player_count)
		return

	# Production mode: make actual API request.
	if backend_api_url.is_empty():
		session_request_failed.emit("Backend API URL not configured")
		return

	var body := JSON.stringify({
		"player_count": player_count,
		"client_id": _generate_client_id()
	})

	var headers := ["Content-Type: application/json"]
	var url := backend_api_url + "/matchmaking/join"

	G.print(
		"Requesting %d session ID(s) from %s" % [player_count, url],
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS
	)

	var error := _http_request.request(url, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		session_request_failed.emit("HTTP request failed: %d" % error)
		return

	# Start timeout timer.
	_request_timer.start(request_timeout_sec)


## Handles preview mode by generating debug session IDs immediately.
func _handle_preview_local_server_mode(player_count: int) -> void:
	var debug_ids: Array[String] = []
	for i in range(player_count):
		debug_ids.append("DEBUG_ID_%d" % i)

	# Use local server settings.
	var server_ip := G.settings.local_preview_server_ip_address
	var server_port := G.settings.local_preview_server_port

	G.print(
		"Preview local-server mode: using %d debug session ID(s)" %
			player_count,
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS
	)

	# Defer to next frame to maintain consistent async behavior.
	await get_tree().process_frame

	local_session_ids_received.emit(debug_ids, server_ip, server_port)


## Generates a unique client identifier for matchmaking requests.
func _generate_client_id() -> String:
	return "%s_%d" % [OS.get_unique_id(), Time.get_ticks_msec()]


func _on_request_completed(
		result: int,
		response_code: int,
		_headers: PackedStringArray,
		body: PackedByteArray) -> void:
	# Cancel timeout timer.
	_request_timer.stop()

	# Check for request errors.
	if result != HTTPRequest.RESULT_SUCCESS:
		session_request_failed.emit("Request failed: %d" % result)
		return

	# Check HTTP status code.
	if response_code != 200:
		var error_msg := body.get_string_from_utf8()
		session_request_failed.emit(
			"HTTP %d: %s" % [response_code, error_msg]
		)
		return

	# Parse JSON response.
	var json := JSON.new()
	var parse_error := json.parse(body.get_string_from_utf8())

	if parse_error != OK:
		session_request_failed.emit(
			"JSON parse error at line %d: %s" % [
				json.get_error_line(),
				json.get_error_message()
			]
		)
		return

	var data: Dictionary = json.data

	# Check for error status.
	if data.get("status") != "success":
		var error_msg: String = data.get("message", "Unknown error")
		session_request_failed.emit(error_msg)
		return

	# Extract session IDs and connection info.
	var session_ids: Array = data.get("player_session_ids", [])
	var server_ip: String = data.get("server_ip", "")
	var server_port: int = data.get("server_port", 4433)

	# Extract and validate server version.
	var server_version: String = data.get("server_version", "")
	var client_version: String = ProjectSettings.get_setting(
		"application/config/version",
		"unknown"
	)

	if server_version.is_empty():
		session_request_failed.emit(
			"Server did not provide version information"
		)
		return

	if not SemanticVersion.compare(client_version, server_version):
		session_request_failed.emit(
			"Version mismatch: Client v%s, Server requires v%s. " +
			"Please update your game client." % [client_version, server_version]
		)
		return

	G.print(
		"Version validated: Client v%s matches Server v%s" % [
			client_version,
			server_version
		],
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS
	)

	if session_ids.is_empty():
		session_request_failed.emit("No session IDs returned from backend")
		return

	G.print(
		"Received %d session ID(s) from backend" % session_ids.size(),
		ScaffolderLog.CATEGORY_NETWORK_CONNECTIONS
	)

	# Emit success signal.
	local_session_ids_received.emit(session_ids, server_ip, server_port)


func _on_request_timeout() -> void:
	# Cancel the HTTP request.
	_http_request.cancel_request()

	session_request_failed.emit(
		"Request timed out after %.1f seconds" % request_timeout_sec
	)
