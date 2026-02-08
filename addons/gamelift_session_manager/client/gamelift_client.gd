class_name GameLiftClient
extends SessionProvider
## Client-side GameLift session manager.
##
## Requests session IDs from backend matchmaking service and validates
## server version compatibility.


## Backend API base URL (e.g., "https://api.example.com").
var backend_api_url := ""

## Request timeout in seconds.
var request_timeout_sec := 30.0

var _http_request: HTTPRequest
var _request_timer: Timer


func _init(
	p_backend_url: String = ""
) -> void:
	backend_api_url = p_backend_url


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


func is_active() -> bool:
	return not backend_api_url.is_empty()


func client_request_session_ids(player_count: int, level_prefs: Dictionary = {}) -> void:
	if backend_api_url.is_empty():
		session_request_failed.emit("Backend API URL not configured")
		return

	var request_body := {
		"player_count": player_count,
		"client_id": _generate_client_id()
	}

	# Include level preferences if provided.
	if not level_prefs.is_empty():
		request_body["level_preferences"] = level_prefs

	var body := JSON.stringify(request_body)

	var headers := ["Content-Type: application/json"]
	var url := backend_api_url + "/matchmaking/join"

	Netcode.log.print(
		"Requesting %d session ID(s) from %s" % [player_count, url],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	var error := _http_request.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		body
	)

	if error != OK:
		session_request_failed.emit("HTTP request failed: %d" % error)
		return

	# Start timeout timer.
	_request_timer.start(request_timeout_sec)


## Generates a unique client identifier for matchmaking requests.
func _generate_client_id() -> String:
	return "%s_%d" % [OS.get_unique_id(), Time.get_ticks_msec()]


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
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

	if not GameliftSemanticVersion.compare(client_version, server_version):
		session_request_failed.emit(
			"Version mismatch: Client v%s, Server requires v%s. " +
			"Please update your game client." % [
				client_version,
				server_version
			]
		)
		return

	Netcode.log.print(
		"Version validated: Client v%s matches Server v%s" % [
			client_version,
			server_version
		],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	if session_ids.is_empty():
		session_request_failed.emit(
			"No session IDs returned from backend"
		)
		return

	# Extract selected level (may be empty if backend doesn't support it yet).
	var selected_level_id: String = data.get("selected_level_id", "")

	Netcode.log.print(
		"Received %d session ID(s) from backend, level: %s" % [
			session_ids.size(),
			selected_level_id if not selected_level_id.is_empty() else "(default)"
		],
		NetworkLogger.CATEGORY_CONNECTIONS
	)

	# Emit success signal.
	session_ids_received.emit(session_ids, server_ip, server_port, selected_level_id)


func _on_request_timeout() -> void:
	# Cancel the HTTP request.
	_http_request.cancel_request()

	session_request_failed.emit(
		"Request timed out after %.1f seconds" % request_timeout_sec
	)
