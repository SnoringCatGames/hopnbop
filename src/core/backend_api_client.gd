class_name BackendApiClient
extends Node
## HTTP client for non-auth backend API calls.
## Handles leaderboard, player stats, profile,
## settings, and match history queries.


signal leaderboard_received(data: Dictionary)
signal player_stats_received(data: Dictionary)
signal profile_received(data: Dictionary)
signal settings_received(data: Dictionary)
signal settings_saved(data: Dictionary)
signal match_history_received(data: Dictionary)
signal request_failed(error: String)

## Emitted after the startup version check completes.
## is_compatible is false only when the server
## returned a different protocol_version.
signal version_checked(
	is_compatible: bool,
	server_protocol_version: int,
)

var _http_request: HTTPRequest
var _pending_signal: StringName = ""


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(
		_on_request_completed)


func fetch_leaderboard(
	type: String = "alltime",
	scope: String = "global",
	limit: int = 50,
) -> void:
	if not _check_available():
		return
	_pending_signal = "leaderboard_received"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/leaderboard?type=%s&scope=%s&limit=%d"
		% [type, scope, limit]
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


func fetch_player_profile() -> void:
	if not _check_available():
		return
	_pending_signal = "profile_received"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/player/profile"
	)
	_send_get_request(url)


func fetch_player_settings() -> void:
	if not _check_available():
		return
	_pending_signal = "settings_received"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/player/settings"
	)
	_send_get_request(url)


func save_player_settings(
	settings: Dictionary,
) -> void:
	if not _check_available():
		return
	_pending_signal = "settings_saved"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/player/settings"
	)
	var body := {
		"settings": settings,
		"updated_at": int(
			Time.get_unix_time_from_system()),
	}
	_send_put_request(url, body)


func fetch_match_history() -> void:
	if not _check_available():
		return
	_pending_signal = "match_history_received"
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/player/history"
	)
	_send_get_request(url)


func _check_available() -> bool:
	if not G.auth_token_store.is_token_valid():
		request_failed.emit("Not authenticated")
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
		request_failed.emit(error_string(error))


func _send_put_request(
	url: String, body: Dictionary,
) -> void:
	var json_body := JSON.stringify(body)
	var error := _http_request.request(
		url,
		_get_auth_headers(),
		HTTPClient.METHOD_PUT,
		json_body,
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
	match signal_name:
		"leaderboard_received":
			leaderboard_received.emit(parsed)
		"player_stats_received":
			player_stats_received.emit(parsed)
		"profile_received":
			profile_received.emit(parsed)
		"settings_received":
			settings_received.emit(parsed)
		"settings_saved":
			settings_saved.emit(parsed)
		"match_history_received":
			match_history_received.emit(parsed)


## Check protocol version against the backend.
## No authentication required. Uses a separate
## HTTPRequest so it does not block other calls.
## Emits version_checked when done. On any error,
## emits compatible=true so the app is not blocked.
func check_version() -> void:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(
		_on_version_check_completed.bind(http),
		CONNECT_ONE_SHOT,
	)
	var url := (
		G.settings.gamelift_backend_api_url
		+ "/version")
	var error := http.request(
		url,
		PackedStringArray([
			"Content-Type: application/json",
		]),
		HTTPClient.METHOD_GET,
	)
	if error != OK:
		http.queue_free()
		version_checked.emit(true, -1)


func _on_version_check_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
) -> void:
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		version_checked.emit(true, -1)
		return

	var parsed = JSON.parse_string(
		body.get_string_from_utf8())
	if (
		parsed == null
		or not parsed is Dictionary
		or response_code != 200
	):
		version_checked.emit(true, -1)
		return

	var server_protocol: int = parsed.get(
		"protocol_version", -1)
	if server_protocol < 0:
		version_checked.emit(true, -1)
		return

	var client_protocol: int = (
		ProjectSettings.get_setting(
			"application/config/protocol_version",
			1,
		))
	var is_compatible := (
		server_protocol == client_protocol)
	version_checked.emit(
		is_compatible, server_protocol)
