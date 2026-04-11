class_name BackendApiClient
extends Node
## HTTP client for non-auth backend API calls.
## Handles leaderboard, player stats, profile,
## settings, match history queries, and GameLift
## fleet warmup/status polling.


signal leaderboard_received(data: Dictionary)
signal player_stats_received(data: Dictionary)
signal profile_received(data: Dictionary)
signal settings_received(data: Dictionary)
signal settings_saved(data: Dictionary)
signal match_history_received(data: Dictionary)
signal request_failed(error: String)

## Emitted whenever a fleet warmup or status response
## arrives. Listeners use the latest dictionary for UI.
signal fleet_status_updated(data: Dictionary)

## Emitted after the startup version check completes.
## is_compatible is false only when the server
## returned a different protocol_version.
signal version_checked(
	is_compatible: bool,
	server_protocol_version: int,
	server_game_version: String,
)

## Polling interval for fleet status while a warmup
## is in progress. Keeps the lobby countdown fresh.
const _FLEET_STATUS_POLL_INTERVAL_SEC := 10.0

## Maximum time to keep polling after a warmup. Even if
## the fleet never reaches ready (bad Spot day), polling
## stops so we do not spam the API forever.
const _FLEET_STATUS_POLL_TIMEOUT_SEC := 600.0

var _http_request: HTTPRequest
var _pending_signal: StringName = ""

# Fleet warmup state.
var _fleet_http_request: HTTPRequest
var _fleet_is_warming_up := false
var _fleet_warmup_started_at_unix := 0.0
var _fleet_last_status: Dictionary = {}
var _fleet_status_poll_timer: Timer


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(
		_on_request_completed)

	# Dedicated HTTPRequest for fleet warmup so it
	# does not collide with leaderboard/profile calls.
	_fleet_http_request = HTTPRequest.new()
	_fleet_http_request.name = "FleetHTTPRequest"
	_fleet_http_request.timeout = 15.0
	add_child(_fleet_http_request)
	_fleet_http_request.request_completed.connect(
		_on_fleet_request_completed)

	_fleet_status_poll_timer = Timer.new()
	_fleet_status_poll_timer.name = (
		"FleetStatusPollTimer")
	_fleet_status_poll_timer.one_shot = false
	_fleet_status_poll_timer.wait_time = (
		_FLEET_STATUS_POLL_INTERVAL_SEC)
	_fleet_status_poll_timer.autostart = false
	add_child(_fleet_status_poll_timer)
	_fleet_status_poll_timer.timeout.connect(
		_on_fleet_status_poll_timeout)


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


## Request the fleet be scaled up for an imminent
## online session. Safe to call at app startup and
## whenever the player toggles online mode. No auth
## required, so it can run before the guest JWT is
## obtained. Idempotent on the backend.
func warm_up_fleet(source: String = "client") -> void:
	if G.settings.gamelift_backend_api_url.is_empty():
		return

	_fleet_is_warming_up = true
	_fleet_warmup_started_at_unix = (
		Time.get_unix_time_from_system())

	var url := (
		G.settings.gamelift_backend_api_url
		+ "/fleet/warmup")
	var body := JSON.stringify({"source": source})
	var err := _fleet_http_request.request(
		url,
		PackedStringArray([
			"Content-Type: application/json",
		]),
		HTTPClient.METHOD_POST,
		body,
	)
	if err != OK:
		G.log.warning(
			"[BackendApi] Fleet warmup request"
			+ " failed: %d" % err)
		return

	if _fleet_status_poll_timer.is_stopped():
		_fleet_status_poll_timer.start()


## Fetch the current fleet status without triggering
## scale-up. Used by the periodic poll timer.
func fetch_fleet_status() -> void:
	if G.settings.gamelift_backend_api_url.is_empty():
		return

	var url := (
		G.settings.gamelift_backend_api_url
		+ "/fleet/status")
	var err := _fleet_http_request.request(
		url,
		PackedStringArray([
			"Content-Type: application/json",
		]),
		HTTPClient.METHOD_GET,
	)
	if err != OK:
		G.log.warning(
			"[BackendApi] Fleet status request"
			+ " failed: %d" % err)


## Seconds elapsed since the most recent warmup call.
## Returns 0 if no warmup has been requested.
func get_fleet_warmup_elapsed_sec() -> float:
	if _fleet_warmup_started_at_unix <= 0.0:
		return 0.0
	return (
		Time.get_unix_time_from_system()
		- _fleet_warmup_started_at_unix
	)


## Returns the most recent fleet status dictionary.
## Empty until a response has been received.
func get_fleet_status_data() -> Dictionary:
	return _fleet_last_status


## Whether the fleet currently has an ACTIVE instance
## with at least one IDLE game session slot.
func is_fleet_ready() -> bool:
	return _fleet_last_status.get("status", "") == "ready"


## Whether a warmup is in progress and we do not yet
## know the fleet is ready.
func is_fleet_warming_up() -> bool:
	if is_fleet_ready():
		return false
	return _fleet_is_warming_up


## Estimated seconds remaining before the fleet is
## ready. Returns 0 if ready or unknown.
func get_fleet_estimated_remaining_sec() -> int:
	if is_fleet_ready():
		return 0
	var from_backend: int = _fleet_last_status.get(
		"estimated_seconds_remaining", -1)
	if from_backend >= 0:
		return from_backend
	# Fallback: backend default estimate minus local
	# elapsed since warmup call.
	var default_estimate := 300
	var elapsed := int(
		get_fleet_warmup_elapsed_sec())
	return maxi(default_estimate - elapsed, 0)


func _on_fleet_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		G.log.warning(
			"[BackendApi] Fleet request HTTP"
			+ " result: %d" % result)
		return

	if response_code != 200:
		G.log.warning(
			"[BackendApi] Fleet request status:"
			+ " %d" % response_code)
		return

	var parsed = JSON.parse_string(
		body.get_string_from_utf8())
	if parsed == null or not parsed is Dictionary:
		return

	_fleet_last_status = parsed
	fleet_status_updated.emit(parsed)

	if parsed.get("status", "") == "ready":
		_fleet_is_warming_up = false
		_fleet_status_poll_timer.stop()


func _on_fleet_status_poll_timeout() -> void:
	var elapsed := get_fleet_warmup_elapsed_sec()
	if elapsed > _FLEET_STATUS_POLL_TIMEOUT_SEC:
		_fleet_status_poll_timer.stop()
		_fleet_is_warming_up = false
		return
	fetch_fleet_status()


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
		version_checked.emit(true, -1, "")


func _on_version_check_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
) -> void:
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		version_checked.emit(true, -1, "")
		return

	var parsed = JSON.parse_string(
		body.get_string_from_utf8())
	if (
		parsed == null
		or not parsed is Dictionary
		or response_code != 200
	):
		version_checked.emit(true, -1, "")
		return

	var server_protocol: int = parsed.get(
		"protocol_version", -1)
	if server_protocol < 0:
		version_checked.emit(true, -1, "")
		return

	var server_game_version: String = parsed.get(
		"game_version", "")

	var client_protocol: int = (
		ProjectSettings.get_setting(
			"application/config/protocol_version",
			1,
		))
	var is_compatible := (
		server_protocol == client_protocol)
	version_checked.emit(
		is_compatible,
		server_protocol,
		server_game_version,
	)
