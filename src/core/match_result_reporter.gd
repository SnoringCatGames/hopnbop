class_name MatchResultReporter
extends Node
## Sends match lifecycle RPCs from the authoritative game server
## to the Nakama runtime: `match_end` (results + leaderboard
## writes) and `match_cancel` (no results, just terminate the
## Edgegap deployment). Both are server-to-server RPCs gated
## by NAKAMA_HTTP_KEY.
##
## Runs inside the Edgegap container. Calls Nakama via the
## HTTP-key path (no session) using the key Edgegap injects as
## NAKAMA_HTTP_KEY.


const _MATCH_END_RPC_PATH := "/v2/rpc/match_end?http_key=%s&unwrap=true"
const _MATCH_CANCEL_RPC_PATH := (
	"/v2/rpc/match_cancel?http_key=%s&unwrap=true")

## Per-attempt HTTPRequest timeout. Sized so the full retry
## budget (2 attempts + 1 backoff) fits within the 12s server-
## quit window in game_session_manager.gd.
const _HTTP_TIMEOUT_SEC := 5.0

## Backoff before the second attempt. Total worst-case end-to-
## end: 5 + 1 + 5 = 11s, just under the 12s quit window.
const _RETRY_BACKOFF_SEC := 1.0


## Reports match results to the platform runtime via the
## match_end RPC. Fire-and-forget from the caller's perspective
## but internally retries once on transport error or 5xx.
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

	var body := JSON.stringify({
		"request_id": request_id,
		"winner_id": winner_id,
		"players": players,
		"stats": stats,
	})
	await _post_with_retry(
		_MATCH_END_RPC_PATH % http_key.uri_encode(),
		body,
		"match_end",
	)


## Cancels the deployment without reporting results. Use when
## bailing out before a real match plays — idle timeout, grace
## timeout with one peer, mid-match all-clients-dropped. The
## runtime calls Edgegap's Stop endpoint and deletes the
## server_registrations row. Idempotent: a second cancel (or a
## cancel after a successful match_end) returns ok+noop.
##
## - request_id: Edgegap deployment request ID, from
##   ARBITRIUM_REQUEST_ID.
## - reason: Free-form short tag for diagnostics ("idle_timeout",
##   "grace_only_one_peer", "all_clients_dropped"). Logged
##   server-side; not used for routing.
func cancel(request_id: String, reason: String = "") -> void:
	var http_key := OS.get_environment("NAKAMA_HTTP_KEY")
	if http_key.is_empty() or request_id.is_empty():
		Netcode.print(
			(
				"Skipping match_cancel RPC: missing"
				+ " NAKAMA_HTTP_KEY or request_id"
			),
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	var body := JSON.stringify({
		"request_id": request_id,
		"reason": reason,
	})
	await _post_with_retry(
		_MATCH_CANCEL_RPC_PATH % http_key.uri_encode(),
		body,
		"match_cancel",
	)


# --- Internals ---


# Posts JSON to a Nakama HTTP-key RPC path with one retry on
# transport error or 5xx. Returns when complete; callers may
# await this to gate further work on the request finishing.
func _post_with_retry(
	rpc_path: String,
	body: String,
	tag: String,
) -> void:
	var url := Platform.get_nakama_base_url() + rpc_path
	var headers := PackedStringArray([
		"Content-Type: application/json",
	])

	# 2 attempts total: initial + 1 retry.
	for attempt in range(2):
		var http := HTTPRequest.new()
		http.timeout = _HTTP_TIMEOUT_SEC
		add_child(http)
		var err := http.request(
			url, headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			http.queue_free()
			Netcode.print(
				(
					"%s request failed to start (attempt"
					+ " %d): %s"
				) % [tag, attempt + 1, error_string(err)],
				NetworkLogger.CATEGORY_GAME_STATE,
			)
			if _should_retry_transport(attempt):
				await get_tree().create_timer(
					_RETRY_BACKOFF_SEC).timeout
				continue
			return

		var result_data: Array = await http.request_completed
		http.queue_free()
		var result: int = result_data[0]
		var response_code: int = result_data[1]
		var body_bytes: PackedByteArray = result_data[3]

		if (
			result == HTTPRequest.RESULT_SUCCESS
			and response_code == 200
		):
			Netcode.print(
				"%s reported to Nakama runtime." % tag,
				NetworkLogger.CATEGORY_GAME_STATE,
			)
			return

		# Failed. Decide whether to retry.
		var is_transport := (
			result != HTTPRequest.RESULT_SUCCESS)
		var is_server_error := (
			response_code >= 500 and response_code < 600)
		var msg: String
		if is_transport:
			msg = "transport error %d" % result
		else:
			msg = "HTTP %d: %s" % [
				response_code,
				body_bytes.get_string_from_utf8(),
			]
		if (
			(is_transport or is_server_error)
			and attempt < 1
		):
			Netcode.print(
				(
					"%s failed (attempt %d): %s."
					+ " Retrying in %.1fs."
				) % [
					tag,
					attempt + 1,
					msg,
					_RETRY_BACKOFF_SEC,
				],
				NetworkLogger.CATEGORY_GAME_STATE,
			)
			await get_tree().create_timer(
				_RETRY_BACKOFF_SEC).timeout
			continue

		Netcode.print(
			"%s RPC failed (attempt %d): %s" % [
				tag, attempt + 1, msg,
			],
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return


# Whether to retry after `request()` itself returned non-OK
# (i.e. the HTTPRequest never sent). Most causes here are
# transient (resource limits, brief allocation failure) so
# retry is appropriate, but only if attempts remain.
func _should_retry_transport(attempt: int) -> bool:
	return attempt < 1
