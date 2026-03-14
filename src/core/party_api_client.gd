class_name PartyApiClient
extends Node
## HTTP client for party API calls. Has its own
## HTTPRequest node for independent operation.


signal party_created(data: Dictionary)
signal party_invited(data: Dictionary)
signal party_joined(data: Dictionary)
signal party_left(data: Dictionary)
signal party_status_received(data: Dictionary)
signal party_matchmaking_started(data: Dictionary)
signal request_failed(error: String)

var _http_request: HTTPRequest
var _pending_signal: StringName = ""


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(
		_on_request_completed)


func create_party() -> void:
	if not _check_available():
		return
	_pending_signal = "party_created"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/party/create"
	)
	_send_post_request(url, {})


func invite_to_party(
	party_id: String,
	player_id: String,
) -> void:
	if not _check_available():
		return
	_pending_signal = "party_invited"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/party/invite"
	)
	var body := {
		"party_id": party_id,
		"player_id": player_id,
	}
	_send_post_request(url, body)


func join_party(party_id: String) -> void:
	if not _check_available():
		return
	_pending_signal = "party_joined"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/party/join"
	)
	var body := {"party_id": party_id}
	_send_post_request(url, body)


func leave_party(party_id: String) -> void:
	if not _check_available():
		return
	_pending_signal = "party_left"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/party/leave"
	)
	var body := {"party_id": party_id}
	_send_post_request(url, body)


func fetch_party_status() -> void:
	if not _check_available():
		return
	_pending_signal = "party_status_received"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/party/status"
	)
	_send_get_request(url)


func start_matchmaking(
	party_id: String,
) -> void:
	if not _check_available():
		return
	_pending_signal = "party_matchmaking_started"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/party/start"
	)
	var body := {"party_id": party_id}
	_send_post_request(url, body)


func is_busy() -> bool:
	return not _pending_signal.is_empty()


func _check_available() -> bool:
	if not G.auth_token_store.is_token_valid():
		request_failed.emit("Not authenticated")
		return false
	if is_busy():
		request_failed.emit("Request in progress")
		return false
	return true


func _get_auth_headers() -> PackedStringArray:
	return [
		"Content-Type: application/json",
		"Authorization: Bearer %s"
		% G.auth_token_store.jwt_token,
	]


func _send_get_request(url: String) -> void:
	var error := _http_request.request(
		url,
		_get_auth_headers(),
		HTTPClient.METHOD_GET,
	)
	if error != OK:
		_pending_signal = ""
		request_failed.emit(error_string(error))


func _send_post_request(
	url: String, body: Dictionary,
) -> void:
	var json_body := JSON.stringify(body)
	var error := _http_request.request(
		url,
		_get_auth_headers(),
		HTTPClient.METHOD_POST,
		json_body,
	)
	if error != OK:
		_pending_signal = ""
		request_failed.emit(error_string(error))


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	var signal_name := _pending_signal
	_pending_signal = ""

	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit(
			"HTTP error: %s" % result)
		return

	var response_text := (
		body.get_string_from_utf8())
	var parsed = JSON.parse_string(response_text)
	if parsed == null or not parsed is Dictionary:
		request_failed.emit("Invalid response")
		return

	if response_code != 200:
		var msg: String = parsed.get(
			"message", "Request failed")
		request_failed.emit(msg)
		return

	match signal_name:
		"party_created":
			party_created.emit(parsed)
		"party_invited":
			party_invited.emit(parsed)
		"party_joined":
			party_joined.emit(parsed)
		"party_left":
			party_left.emit(parsed)
		"party_status_received":
			party_status_received.emit(parsed)
		"party_matchmaking_started":
			party_matchmaking_started.emit(parsed)
