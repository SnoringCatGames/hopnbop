class_name GameLiftClient
extends SessionProvider
## Client-side GameLift session manager.
##
## Requests matchmaking from backend using a two-step flow:
## 1. POST /matchmaking/start to get a ticket ID.
## 2. Poll GET /matchmaking/status/{ticket_id} until match
##    is found or timeout.


## Backend API base URL
## (e.g., "https://api.example.com/prod").
var backend_api_url := ""

## Seconds between status polls.
const _POLL_INTERVAL_SEC := 2.0

## Maximum time to poll before giving up.
const _MAX_POLL_TIME_SEC := 120.0

var _http_request: HTTPRequest
var _poll_timer: Timer
var _ticket_id := ""
var _poll_elapsed_sec := 0.0
var _is_polling := false
var _estimated_total_sec := -1.0


func _init(
	p_backend_url: String = ""
) -> void:
	backend_api_url = p_backend_url


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 15.0
	add_child(_http_request)

	_poll_timer = Timer.new()
	_poll_timer.one_shot = true
	_poll_timer.timeout.connect(_poll_status)
	add_child(_poll_timer)


func is_active() -> bool:
	return not backend_api_url.is_empty()


func client_request_session_ids(
	player_count: int,
	session_prefs: Dictionary = {},
) -> void:
	if backend_api_url.is_empty():
		session_request_failed.emit(
			"Backend API URL not configured")
		return

	var request_body := {
		"player_count": player_count,
		"client_id": _generate_client_id(),
		"platform": (
			"web"
			if OS.has_feature("web")
			else "native"),
	}

	if not session_prefs.is_empty():
		request_body["session_preferences"] = (
			session_prefs)

	_start_matchmaking(request_body)


func _get_auth_headers() -> PackedStringArray:
	var headers: PackedStringArray = [
		"Content-Type: application/json",
	]
	if (
		is_instance_valid(G)
		and G.auth_token_store != null
		and G.auth_token_store.is_token_valid()
	):
		headers.append(
			"Authorization: Bearer %s"
			% G.auth_token_store.jwt_token
		)
	return headers


func _start_matchmaking(
	request_body: Dictionary,
) -> void:
	var url := (
		backend_api_url + "/matchmaking/start")
	var body := JSON.stringify(request_body)

	Netcode.log.print(
		"Starting matchmaking via %s" % url,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Disconnect any previous handler.
	if _http_request.request_completed.is_connected(
		_on_start_response
	):
		_http_request.request_completed.disconnect(
			_on_start_response)
	if _http_request.request_completed.is_connected(
		_on_status_response
	):
		_http_request.request_completed.disconnect(
			_on_status_response)

	_http_request.request_completed.connect(
		_on_start_response)

	var error := _http_request.request(
		url,
		_get_auth_headers(),
		HTTPClient.METHOD_POST,
		body,
	)
	if error != OK:
		_http_request.request_completed.disconnect(
			_on_start_response)
		session_request_failed.emit(
			"HTTP request failed: %d" % error)


func _on_start_response(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	_http_request.request_completed.disconnect(
		_on_start_response)

	if result != HTTPRequest.RESULT_SUCCESS:
		session_request_failed.emit(
			"Start request failed: %d" % result)
		return

	if response_code != 200:
		var error_msg := body.get_string_from_utf8()
		session_request_failed.emit(
			"HTTP %d: %s"
			% [response_code, error_msg])
		return

	var data := _parse_json(body)
	if data.is_empty():
		return

	if data.get("status") != "success":
		var error_msg: String = data.get(
			"message", "Unknown error")
		session_request_failed.emit(error_msg)
		return

	_ticket_id = data.get("ticket_id", "")
	if _ticket_id.is_empty():
		session_request_failed.emit(
			"No ticket ID in response")
		return

	# Store estimated wait from backend.
	var estimated_wait_ms: float = data.get(
		"estimated_wait_ms", -1.0)
	_estimated_total_sec = (
		estimated_wait_ms / 1000.0
		if estimated_wait_ms > 0
		else -1.0)

	Netcode.log.print(
		"Matchmaking ticket: %s" % _ticket_id,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	# Begin polling.
	_poll_elapsed_sec = 0.0
	_is_polling = true

	# Emit initial progress.
	matchmaking_progress_updated.emit(
		"queued", 0.0, _estimated_total_sec)

	_poll_timer.start(_POLL_INTERVAL_SEC)


func _poll_status() -> void:
	if not _is_polling:
		return

	_poll_elapsed_sec += _POLL_INTERVAL_SEC
	if _poll_elapsed_sec >= _MAX_POLL_TIME_SEC:
		_is_polling = false
		session_request_failed.emit(
			"Matchmaking timed out after"
			+ " %.0f seconds"
			% _MAX_POLL_TIME_SEC)
		return

	var url := (
		backend_api_url
		+ "/matchmaking/status/"
		+ _ticket_id)

	# Disconnect previous and connect status
	# handler.
	if _http_request.request_completed.is_connected(
		_on_status_response
	):
		_http_request.request_completed.disconnect(
			_on_status_response)

	_http_request.request_completed.connect(
		_on_status_response)

	var error := _http_request.request(
		url,
		_get_auth_headers(),
		HTTPClient.METHOD_GET,
	)
	if error != OK:
		_http_request.request_completed.disconnect(
			_on_status_response)
		_is_polling = false
		session_request_failed.emit(
			"Status poll failed: %d" % error)


func _on_status_response(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	_http_request.request_completed.disconnect(
		_on_status_response)

	if not _is_polling:
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		_is_polling = false
		session_request_failed.emit(
			"Status request failed: %d" % result)
		return

	if response_code != 200:
		_is_polling = false
		var error_msg := body.get_string_from_utf8()
		session_request_failed.emit(
			"HTTP %d: %s"
			% [response_code, error_msg])
		return

	var data := _parse_json(body)
	if data.is_empty():
		_is_polling = false
		return

	var status: String = data.get("status", "")

	# Still in progress. Schedule next poll.
	if status in [
		"queued", "searching", "placing",
	]:
		# Update estimate if backend provides one.
		var est_ms: float = data.get(
			"estimated_wait_ms", -1.0)
		if est_ms > 0:
			_estimated_total_sec = est_ms / 1000.0

		Netcode.log.print(
			"Matchmaking status: %s (%.0fs)"
			% [status, _poll_elapsed_sec],
			NetworkLogger.CATEGORY_CONNECTIONS,
		)

		matchmaking_progress_updated.emit(
			status,
			_poll_elapsed_sec,
			_estimated_total_sec,
		)

		_poll_timer.start(_POLL_INTERVAL_SEC)
		return

	_is_polling = false

	# Match found.
	if status == "success":
		_handle_match_found(data)
		return

	# Failed or unknown status.
	var error_msg: String = data.get(
		"message",
		"Matchmaking %s" % status,
	)
	session_request_failed.emit(error_msg)


func _handle_match_found(
	data: Dictionary,
) -> void:
	var session_ids: Array = data.get(
		"player_session_ids", [])
	var server_ip: String = data.get(
		"server_ip", "")
	var server_port: int = data.get(
		"server_port", 4433)

	# Validate protocol version.
	var server_protocol: int = data.get(
		"protocol_version", -1)
	if server_protocol > 0:
		var client_protocol: int = (
			ProjectSettings.get_setting(
				"application/config/"
				+ "protocol_version",
				1,
			))
		if server_protocol != client_protocol:
			session_request_failed.emit(
				("Version mismatch: Client"
				+ " protocol v%d, Server"
				+ " requires v%d. Please"
				+ " update your game client.")
				% [client_protocol,
					server_protocol])
			return
		Netcode.log.print(
			"Protocol version validated: v%d"
			% client_protocol,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)

	if session_ids.is_empty():
		session_request_failed.emit(
			"No session IDs returned")
		return

	var selected_level_id: String = data.get(
		"selected_level_id", "")

	# Set transport type from backend response.
	# The backend determines this based on whether
	# any matched player is on web.
	var transport_type: String = data.get(
		"transport_type", "enet")
	if transport_type == "websocket":
		Netcode.settings.transport_type = (
			NetworkSettings
				.TransportType.WEBSOCKET)
	else:
		Netcode.settings.transport_type = (
			NetworkSettings.TransportType.ENET)

	Netcode.log.print(
		("Match found: %d session ID(s),"
		+ " server %s:%d, level: %s,"
		+ " transport: %s") % [
			session_ids.size(),
			server_ip,
			server_port,
			selected_level_id
			if not selected_level_id.is_empty()
			else "(default)",
			transport_type],
		NetworkLogger.CATEGORY_CONNECTIONS,
	)

	session_ids_received.emit(
		session_ids,
		server_ip,
		server_port,
		selected_level_id,
	)


func _parse_json(
	body: PackedByteArray,
) -> Dictionary:
	var json := JSON.new()
	var parse_error := json.parse(
		body.get_string_from_utf8())
	if parse_error != OK:
		session_request_failed.emit(
			"JSON parse error at line %d: %s"
			% [
				json.get_error_line(),
				json.get_error_message(),
			])
		return {}
	return json.data


func _generate_client_id() -> String:
	return "%s_%d" % [
		OS.get_unique_id(),
		Time.get_ticks_msec(),
	]
