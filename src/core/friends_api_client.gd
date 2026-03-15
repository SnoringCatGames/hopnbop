class_name FriendsApiClient
extends Node
## HTTP client for friends API calls. Has two
## HTTPRequest nodes: one for user-initiated
## actions and one for background polling.


signal friends_received(data: Dictionary)
signal friend_request_sent(data: Dictionary)
signal friend_request_accepted(data: Dictionary)
signal friend_request_rejected(data: Dictionary)
signal friend_request_cancelled(data: Dictionary)
signal friend_removed(data: Dictionary)
signal friend_search_result(data: Dictionary)
signal notifications_received(data: Dictionary)
signal friends_marked_seen(data: Dictionary)
signal request_failed(error: String)

## Cached relationship data, updated on every
## friends_received response.
var cached_friends: Array[Dictionary] = []
var cached_sent_requests: Array[Dictionary] = []
var cached_incoming_requests: Array[Dictionary] = []

var _http_request: HTTPRequest
var _poll_http_request: HTTPRequest
var _pending_signal: StringName = ""
var _poll_pending := false


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(
		_on_request_completed)

	_poll_http_request = HTTPRequest.new()
	_poll_http_request.name = "PollHTTPRequest"
	add_child(_poll_http_request)
	_poll_http_request.request_completed.connect(
		_on_poll_request_completed)


func fetch_friends() -> void:
	if not _check_available():
		return
	_pending_signal = "friends_received"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends"
	)
	_send_get_request(url)


func send_request_by_code(
	friend_code: String,
) -> void:
	if not _check_available():
		return
	_pending_signal = "friend_request_sent"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/add"
	)
	var body := {
		"friend_code": friend_code,
		"source": "friend_code",
	}
	_send_post_request(url, body)


func send_request_by_player_id(
	player_id: String,
	source: String = "recent_match",
) -> void:
	if not _check_available():
		return
	_pending_signal = "friend_request_sent"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/add"
	)
	var body := {
		"player_id": player_id,
		"source": source,
	}
	_send_post_request(url, body)


func accept_request(
	player_id: String,
) -> void:
	if not _check_available():
		return
	_pending_signal = "friend_request_accepted"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/accept"
	)
	var body := {"player_id": player_id}
	_send_post_request(url, body)


func reject_request(
	player_id: String,
) -> void:
	if not _check_available():
		return
	_pending_signal = "friend_request_rejected"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/reject"
	)
	var body := {"player_id": player_id}
	_send_post_request(url, body)


func cancel_request(
	player_id: String,
) -> void:
	if not _check_available():
		return
	_pending_signal = "friend_request_cancelled"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/cancel"
	)
	var body := {"player_id": player_id}
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


func mark_seen() -> void:
	if not _check_available():
		return
	_pending_signal = "friends_marked_seen"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/seen"
	)
	_send_post_request(url, {})


## Fetch notifications via the dedicated poll
## HTTPRequest. Does not block user-initiated
## requests.
func fetch_notifications(
	since_timestamp: int,
) -> void:
	if not _check_poll_available():
		return
	_poll_pending = true
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/friends/notifications?since=%d"
		% since_timestamp
	)
	var error := _poll_http_request.request(
		url,
		_get_auth_headers(),
		HTTPClient.METHOD_GET,
	)
	if error != OK:
		_poll_pending = false


func is_busy() -> bool:
	return not _pending_signal.is_empty()


func is_poll_busy() -> bool:
	return _poll_pending


## Check if a player ID is in the cached friends
## list.
func is_friend(player_id: String) -> bool:
	for entry in cached_friends:
		if entry.get("player_id", "") == player_id:
			return true
	return false


## Check if a sent request exists for a player ID.
func has_sent_request(
	player_id: String,
) -> bool:
	for entry in cached_sent_requests:
		if entry.get("player_id", "") == player_id:
			return true
	return false


## Check if an incoming request exists from a
## player ID.
func has_incoming_request(
	player_id: String,
) -> bool:
	for entry in cached_incoming_requests:
		if entry.get("player_id", "") == player_id:
			return true
	return false


func _check_available() -> bool:
	if not G.auth_token_store.is_token_valid():
		request_failed.emit("Not authenticated")
		return false
	if is_busy():
		request_failed.emit("Request in progress")
		return false
	return true


func _check_poll_available() -> bool:
	if not G.auth_token_store.is_token_valid():
		return false
	if is_poll_busy():
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

	# Update cached relationship data when
	# receiving a full friends list.
	if signal_name == "friends_received":
		_update_cache(parsed)

	match signal_name:
		"friends_received":
			friends_received.emit(parsed)
		"friend_request_sent":
			friend_request_sent.emit(parsed)
		"friend_request_accepted":
			friend_request_accepted.emit(parsed)
		"friend_request_rejected":
			friend_request_rejected.emit(parsed)
		"friend_request_cancelled":
			friend_request_cancelled.emit(parsed)
		"friend_removed":
			friend_removed.emit(parsed)
		"friend_search_result":
			friend_search_result.emit(parsed)
		"friends_marked_seen":
			friends_marked_seen.emit(parsed)


func _on_poll_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	_poll_pending = false

	if result != HTTPRequest.RESULT_SUCCESS:
		return
	var response_text := (
		body.get_string_from_utf8())
	var parsed = JSON.parse_string(response_text)
	if parsed == null or not parsed is Dictionary:
		return
	if response_code != 200:
		return

	notifications_received.emit(parsed)


func _update_cache(data: Dictionary) -> void:
	cached_friends = []
	for entry in data.get("friends", []):
		cached_friends.append(entry)
	cached_sent_requests = []
	for entry in data.get("sent_requests", []):
		cached_sent_requests.append(entry)
	cached_incoming_requests = []
	for entry in data.get(
		"incoming_requests", [],
	):
		cached_incoming_requests.append(entry)
