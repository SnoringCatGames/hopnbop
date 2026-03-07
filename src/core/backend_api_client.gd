class_name BackendApiClient
extends Node
## HTTP client for non-auth backend API calls.
## Handles leaderboard and player stats queries.


signal leaderboard_received(data: Dictionary)
signal player_stats_received(data: Dictionary)
signal request_failed(error: String)

var _http_request: HTTPRequest
var _pending_signal: StringName = ""


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(
		_on_request_completed)


func fetch_leaderboard(limit: int = 50) -> void:
	if not _check_available():
		return
	_pending_signal = "leaderboard_received"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/leaderboard?limit=%d" % limit
	)
	_send_get_request(url)


func fetch_player_stats(
	player_id: String,
) -> void:
	if not _check_available():
		return
	_pending_signal = "player_stats_received"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/players/%s/stats" % player_id
	)
	_send_get_request(url)


func _check_available() -> bool:
	if not G.auth_token_store.is_token_valid():
		request_failed.emit("Not authenticated")
		return false
	return true


func _send_get_request(url: String) -> void:
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s"
		% G.auth_token_store.jwt_token,
	]
	var error := _http_request.request(
		url,
		headers,
		HTTPClient.METHOD_GET,
	)
	if error != OK:
		request_failed.emit(error_string(error))


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
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

	var signal_name := _pending_signal
	_pending_signal = ""
	if signal_name == "leaderboard_received":
		leaderboard_received.emit(parsed)
	elif signal_name == "player_stats_received":
		player_stats_received.emit(parsed)
