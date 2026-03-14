class_name FriendsApiClient
extends Node
## HTTP client for friends API calls. Has its own
## HTTPRequest node so it can operate independently
## of BackendApiClient.


signal friends_received(data: Dictionary)
signal friend_added(data: Dictionary)
signal friend_removed(data: Dictionary)
signal friend_search_result(data: Dictionary)
signal request_failed(error: String)

var _http_request: HTTPRequest
var _pending_signal: StringName = ""


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(
		_on_request_completed)


func fetch_friends() -> void:
	if not _check_available():
		return
	_pending_signal = "friends_received"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends"
	)
	_send_get_request(url)


func add_friend_by_code(friend_code: String) -> void:
	if not _check_available():
		return
	_pending_signal = "friend_added"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/add"
	)
	var body := {
		"friend_code": friend_code,
		"source": "friend_code",
	}
	_send_post_request(url, body)


func add_friend_by_player_id(
	player_id: String,
	source: String = "recent_match",
) -> void:
	if not _check_available():
		return
	_pending_signal = "friend_added"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/add"
	)
	var body := {
		"player_id": player_id,
		"source": source,
	}
	_send_post_request(url, body)


func remove_friend(player_id: String) -> void:
	if not _check_available():
		return
	_pending_signal = "friend_removed"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/remove"
	)
	var body := {"player_id": player_id}
	_send_post_request(url, body)


func search_friend_code(code: String) -> void:
	if not _check_available():
		return
	_pending_signal = "friend_search_result"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/search?code=%s" % code
	)
	_send_get_request(url)


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
		"friends_received":
			friends_received.emit(parsed)
		"friend_added":
			friend_added.emit(parsed)
		"friend_removed":
			friend_removed.emit(parsed)
		"friend_search_result":
			friend_search_result.emit(parsed)
