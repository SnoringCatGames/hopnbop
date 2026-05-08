class_name MatchResultReporter
extends Node
## Sends match results from the authoritative game server to
## the Nakama runtime's `match_end` RPC. Fire-and-forget.
##
## Runs inside the Edgegap container; the runtime writes
## leaderboard records and per-user match_history rows from
## the payload. Calls Nakama via the HTTP-key path (no session)
## using the key Edgegap injects as NAKAMA_HTTP_KEY.


const _RPC_PATH := "/v2/rpc/match_end?http_key=%s&unwrap=true"


## Reports match results to the platform runtime.
##
## - request_id: Edgegap deployment request ID (matches the one
##   the runtime stamped on the match_ready notification, and
##   what register_server posted at boot). Read at the call
##   site from ARBITRIUM_REQUEST_ID.
## - winner_id: backend (Nakama user_id) of the player at
##   rank 1. Empty string if no clear winner.
## - players: Array of Dictionaries shaped like
##   { user_id: String, score: int, kills: int, bumps: int }.
##   The runtime writes one match_history row + leaderboard
##   record per entry; couch co-op players sharing an account
##   should be deduped to one entry by the caller.
## - stats: Optional Dictionary of free-form per-match stats
##   (duration_sec, level_id, etc.). Forwarded to the runtime
##   as the `stats` field.
func report(
	request_id: String,
	winner_id: String,
	players: Array,
	stats: Dictionary = {},
) -> void:
	var http_key := OS.get_environment("NAKAMA_HTTP_KEY")
	if http_key.is_empty():
		Netcode.print(
			"No NAKAMA_HTTP_KEY env var on this server."
			+ " Skipping match_end RPC.",
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return
	if request_id.is_empty():
		Netcode.print(
			"No request_id (ARBITRIUM_REQUEST_ID)"
			+ " for this match. Skipping match_end RPC.",
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return
	if players.is_empty():
		Netcode.print(
			"No player results to report. Skipping"
			+ " match_end RPC.",
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	var url := AuthClient.get_nakama_base_url() + (
		_RPC_PATH % http_key.uri_encode())
	var headers := PackedStringArray([
		"Content-Type: application/json",
	])
	# With ?unwrap=true, Nakama's HTTP gateway forwards the raw
	# request body as the RPC payload — send the bare JSON
	# object directly. Wrapping it as a JSON-encoded string
	# silently fails parse on the runtime side (string-into-
	# struct unmarshal error).
	var body := JSON.stringify({
		"request_id": request_id,
		"winner_id": winner_id,
		"players": players,
		"stats": stats,
	})

	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(
		_on_request_completed.bind(http),
		CONNECT_ONE_SHOT,
	)
	var err := http.request(
		url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		Netcode.print(
			"match_end request failed to start: %s"
			% error_string(err),
			NetworkLogger.CATEGORY_GAME_STATE,
		)


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		Netcode.print(
			"match_end transport error: %s" % result,
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return
	if response_code == 200:
		Netcode.print(
			"Match result reported to Nakama runtime.",
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return
	Netcode.print(
		"match_end RPC failed (%d): %s"
		% [response_code, body.get_string_from_utf8()],
		NetworkLogger.CATEGORY_GAME_STATE,
	)
