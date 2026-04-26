class_name MatchResultReporter
extends Node
## Sends match results from the authoritative
## game server to the backend API. Fire-and-forget.


# Match result reporting lives on the
# snoringcat-platform stack at /v1/matches/result.
# This client runs inside the GameLift container, so
# every change here requires a fleet redeploy.
const _PLATFORM_API_URL := (
	"https://r20b7wqop6.execute-api.us-west-2.amazonaws.com"
	+ "/prod/v1"
)
const _ENDPOINT := "/matches/result"

var _http_request: HTTPRequest


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(
		_on_request_completed)


func report(
	game_session_id: String,
	match_duration_sec: float,
	level_id: String,
	player_results: Array,
) -> void:
	var api_key := G.settings.server_api_key
	if api_key.is_empty():
		Netcode.print(
			"No server API key configured."
			+ " Skipping match report.",
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	var url := (
		_PLATFORM_API_URL
		+ _ENDPOINT
	)
	var headers := [
		"Content-Type: application/json",
		"X-Server-Key: %s" % api_key,
	]
	var body := JSON.stringify({
		"game_session_id": game_session_id,
		"match_duration_sec": match_duration_sec,
		"level_id": level_id,
		"player_results": player_results,
	})

	var error := _http_request.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		body,
	)
	if error != OK:
		Netcode.print(
			"Match report request failed: %s"
			% error_string(error),
			NetworkLogger.CATEGORY_GAME_STATE,
		)


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		Netcode.print(
			"Match report HTTP error: %s"
			% result,
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	if response_code == 200:
		Netcode.print(
			"Match result reported successfully.",
			NetworkLogger.CATEGORY_GAME_STATE,
		)
	else:
		var response_text := (
			body.get_string_from_utf8())
		Netcode.print(
			"Match report failed (%d): %s"
			% [response_code, response_text],
			NetworkLogger.CATEGORY_GAME_STATE,
		)
