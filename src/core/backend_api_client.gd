class_name BackendApiClient
extends Node
## Nakama-backed client for non-auth backend operations:
## leaderboards, player stats/profile/settings, match history,
## and game-version compatibility check.
##
## The legacy GameLift fleet warmup methods (warm_up_fleet,
## fetch_fleet_status, is_fleet_ready, etc.) are gone — Edgegap
## allocates per-match on demand, so there's nothing to warm.
## UI references to those have been removed (see lobby_level
## and loading_screen).


## Emitted by fetch_leaderboard() with parse_public_leaderboard()'s
## data.
signal leaderboard_received(data: Dictionary)
## Emitted when fetch_leaderboard() fails. The reason is for logs,
## never for players.
signal leaderboard_failed(reason: String)
## Emitted by fetch_own_standing() with parse_player_standing()'s
## data.
signal own_standing_received(data: Dictionary)
## Emitted by fetch_my_stats() with build_my_stats()'s data.
signal my_stats_received(data: Dictionary)
## Emitted when fetch_my_stats() fails: NOT_SIGNED_IN without a
## session, otherwise a reason for logs.
signal my_stats_failed(reason: String)
signal player_stats_received(data: Dictionary)
signal profile_received(data: Dictionary)
signal match_history_received(data: Dictionary)
signal request_failed(error: String)

## The board the leaderboards show: game.yaml's `ffa`, each player's
## best single-match score.
const LEADERBOARD_ID := "ffa"
## Players the in-game leaderboard lists: as many as the website.
const LEADERBOARD_LIMIT := 100
## Matches My Stats lists.
const MY_STATS_RECENT_MATCHES := 10
## my_stats_failed's reason when the player has no session.
const NOT_SIGNED_IN := "not_signed_in"
## The public leaderboard reply's schema version this client reads.
const _PUBLIC_LEADERBOARD_VERSION := 1
const _HTTP_TIMEOUT_SEC := 10.0
const _HTTP_OK := 200

# Cached legal_version reported by the runtime's version_check
# response. Empty until the first successful check_version call.
# Stage 3.10: clients call LegalVersion.get_current() which prefers
# this value and falls back to LegalVersion.LEGAL_VERSION when the
# runtime hasn't responded yet (offline boot, pre-fetch).
var server_legal_version: String = ""

# Cached matchmaker rules surfaced by the runtime's version_check
# response (read from game.yaml's `matchmaker_rules` block).
# Zero / empty mean "no override; use the matchmaker's compile-
# time fallback". Stage 3.8.
var server_matchmaker_min_players: int = 0
var server_matchmaker_max_players: int = 0
var server_matchmaker_query: String = ""

# Cached game-mode list surfaced by version_check
# (game.yaml `matchmaker_rules.modes`). Each entry is a
# Dictionary with keys: id (String), display_name_key (String),
# description_key (String), min_players (int), max_players (int),
# query (String), is_default (bool). Empty array means "no
# modes; hide the picker". Stage 4.7 / 5.7.
var server_matchmaker_modes: Array = []

## Counts fetch_leaderboard() calls, so a slow reply can't overwrite
## a newer one.
var _leaderboard_request_count := 0

## Deprecated. Kept so the legacy lobby-level warmup connection
## still resolves. Never emitted now that Edgegap auto-allocates.
signal fleet_status_updated(data: Dictionary)

## Emitted after the startup version check completes.
## is_compatible is false only when the server returned a
## different protocol_version. Server values come from the
## runtime's unauthenticated version-check route (the
## `version_check` RPC's answer); a failed or unreachable check
## reports -1 and is treated as "compatible".
signal version_checked(
	is_compatible: bool,
	server_protocol_version: int,
	server_game_version: String,
)


## Public no-op stubs preserved so the existing UI code still
## compiles. Phase D removed warmup, but a few call sites still
## query these methods. They were kept inert (always
## "ready, not warming") so the lobby/loading screens don't
## hang waiting for a warmup that never happens.
func is_fleet_ready() -> bool:
	return true


func is_fleet_warming_up() -> bool:
	return false


func get_fleet_estimated_remaining_sec() -> int:
	return 0


func get_fleet_warmup_elapsed_sec() -> float:
	return 0.0


func get_fleet_status_data() -> Dictionary:
	return {"status": "ready"}


func warm_up_fleet(_source: String = "client") -> void:
	# No-op: Edgegap allocates per-match.
	pass


func fetch_fleet_status() -> void:
	# No-op: see warm_up_fleet.
	pass


# --------------------------------------------------------------
# Leaderboard
# --------------------------------------------------------------

## Fetches the game's public leaderboard from the platform runtime's
## unauthenticated route: the same players, ranks, and listing rules
## as hopnbop.net/leaderboard/ (only accounts with a display name; no
## account queued for deletion; no probe account). It needs no
## session, so opening the leaderboard never creates a guest account.
## Emits leaderboard_received, or leaderboard_failed.
##
## Until 2026-10-12 this listed raw Nakama records with a session,
## emitted them under a key the screen didn't read, and named each
## player by the record's username, which match_end never sets.
func fetch_leaderboard() -> void:
	_leaderboard_request_count += 1
	var request_number := _leaderboard_request_count
	var url: String = Platform.get_public_leaderboard_url(
		LEADERBOARD_ID, LEADERBOARD_LIMIT)
	var reply: Dictionary = await _http_get(url)
	if request_number != _leaderboard_request_count:
		return
	var parsed := parse_public_leaderboard(reply.status, reply.body)
	if not parsed.ok:
		leaderboard_failed.emit(parsed.error)
		return
	leaderboard_received.emit(parsed)


## Reads a public leaderboard reply. Returns {ok: true, entries:
## [{rank: int, display_name: String, score: int, spawn_name:
## Dictionary}] in board order, operator: String, sort_order:
## String, generated_at: String}, or {ok: false, error: String}.
## An entry with a malformed field is dropped rather than shown
## half-read. spawn_name (the scoring match's bunny-name indices,
## H59) is present only on records written since its capture; an
## entry needs a display name or a valid spawn_name to be kept.
func parse_public_leaderboard(status: int, body: String) -> Dictionary:
	if status != _HTTP_OK:
		return {"ok": false, "error": "HTTP %d" % status}
	var data: Variant = _parse_json(body)
	if not (data is Dictionary):
		return {"ok": false, "error": "the reply is not a JSON object"}
	var version: Variant = data.get("version")
	if (
		not _is_number(version)
		or int(version) != _PUBLIC_LEADERBOARD_VERSION
		or not (data.get("entries") is Array)
	):
		return {"ok": false, "error": "unexpected leaderboard version"}
	var entries: Array[Dictionary] = []
	for raw: Variant in data.entries:
		if not (raw is Dictionary):
			continue
		var rank: Variant = raw.get("rank")
		var score: Variant = raw.get("score")
		var display_name: Variant = raw.get("display_name")
		var spawn := _parse_spawn_name(raw.get("spawn_name"))
		var has_name := (
			display_name is String
			and not (display_name as String)
				.strip_edges().is_empty())
		if (
			not _is_number(rank)
			or not _is_number(score)
			or (not has_name and spawn.is_empty())
		):
			continue
		var entry := {
			"rank": int(rank),
			"display_name": (
				(display_name as String).strip_edges()
				if has_name else ""),
			"score": int(score),
		}
		if not spawn.is_empty():
			entry["spawn_name"] = spawn
		entries.append(entry)
	return {
		"ok": true,
		"entries": entries,
		"operator": str(data.get("operator", "")),
		"sort_order": str(data.get("sort_order", "")),
		"generated_at": str(data.get("generated_at", "")),
	}


## Reads a spawn_name value (the scoring match's bunny-name
## indices, H59) into {name_index, adj_list_id, adj_index} with
## int values. Returns {} when the value is absent or malformed;
## negative indices are malformed.
func _parse_spawn_name(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var out := {}
	var keys: Array[String] = [
		"name_index", "adj_list_id", "adj_index"]
	for key in keys:
		var index: Variant = (value as Dictionary).get(key)
		if not _is_number(index) or int(index) < 0:
			return {}
		out[key] = int(index)
	return out


## Fetches the caller's own standing through get_player_stats, only
## with a session the player already has: it never signs a guest in
## just to ask. Emits own_standing_received. A failure emits nothing.
func fetch_own_standing() -> void:
	var session := _ensure_session_optional()
	if session == null:
		return
	var result = await Platform.get_nakama_client().rpc_async(
		session, "get_player_stats", "{}")
	if result.is_exception():
		return
	own_standing_received.emit(
		parse_player_standing(_parse_json(result.payload)))


## Reads get_player_stats' reply into {rank: int, 0 when the player
## isn't on the public leaderboard; best_score: int, -1 before their
## first recorded match}. A runtime older than its best_score and
## rank fields reads as {rank: 0, best_score: -1}.
func parse_player_standing(data: Variant) -> Dictionary:
	var standing := {"rank": 0, "best_score": -1}
	if not (data is Dictionary):
		return standing
	var rank: Variant = data.get("rank")
	if _is_number(rank) and int(rank) > 0:
		standing.rank = int(rank)
	var best_score: Variant = data.get("best_score")
	if _is_number(best_score) and int(best_score) >= 0:
		standing.best_score = int(best_score)
	return standing


## Fetches the caller's stats for My Stats: get_player_stats (best
## score, rank) and get_match_history (totals, recent matches), with
## the player's own session. Emits my_stats_received, or
## my_stats_failed (NOT_SIGNED_IN without a session).
func fetch_my_stats() -> void:
	var session := _ensure_session_optional()
	if session == null:
		my_stats_failed.emit(NOT_SIGNED_IN)
		return
	var client := Platform.get_nakama_client()
	var stats = await client.rpc_async(session, "get_player_stats", "{}")
	if stats.is_exception():
		my_stats_failed.emit(_describe(stats.get_exception()))
		return
	var history = await client.rpc_async(
		session, "get_match_history", "{}")
	if history.is_exception():
		my_stats_failed.emit(_describe(history.get_exception()))
		return
	my_stats_received.emit(build_my_stats(
		_parse_json(stats.payload), _parse_json(history.payload)))


## Combines get_player_stats' and get_match_history's replies into My
## Stats' data: {best_score: int, -1 before the first match; rank:
## int, 0 when not listed; matches, wins, kills, bumps: int totals;
## recent_matches: [{is_winner: bool, score: int, kills: int, bumps:
## int}], newest first, at most MY_STATS_RECENT_MATCHES}. A runtime
## without totals is totalled from the matches it listed.
func build_my_stats(stats: Variant, history: Variant) -> Dictionary:
	var standing := parse_player_standing(stats)
	var listed: Array[Dictionary] = []
	var totals: Variant = null
	if history is Dictionary:
		var matches: Variant = history.get("matches")
		if matches is Array:
			for match_entry: Variant in matches:
				if match_entry is Dictionary:
					listed.append(match_entry)
		totals = history.get("totals")
	listed.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _number(a, "ended_at") > _number(b, "ended_at"))
	var recent: Array[Dictionary] = []
	for match_entry in listed.slice(0, MY_STATS_RECENT_MATCHES):
		recent.append({
			"is_winner": match_entry.get("is_winner") == true,
			"score": _number(match_entry, "score"),
			"kills": _number(match_entry, "kills"),
			"bumps": _number(match_entry, "bumps"),
		})
	var result := {
		"best_score": standing.best_score,
		"rank": standing.rank,
		"recent_matches": recent,
	}
	if totals is Dictionary:
		for key in ["matches", "wins", "kills", "bumps"]:
			result[key] = _number(totals, key)
	else:
		result.matches = listed.size()
		result.wins = listed.filter(
			func(m: Dictionary) -> bool: return m.get("is_winner") == true
		).size()
		result.kills = 0
		result.bumps = 0
		for match_entry in listed:
			result.kills += _number(match_entry, "kills")
			result.bumps += _number(match_entry, "bumps")
	return result


func fetch_player_stats(player_id: String = "") -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var pid := player_id if player_id else session.user_id
	var rpc_result = await Platform.get_nakama_client().rpc_async(
		session, "get_player_stats",
		JSON.stringify({"player_id": pid}))
	if rpc_result.is_exception():
		# Pre-RPC deploys return method-not-found; surface as empty
		# stats so the UI doesn't error.
		player_stats_received.emit(
			{"player_id": pid, "rating": 1500, "matches": 0})
		return
	var data: Variant = JSON.parse_string(rpc_result.payload)
	if data is Dictionary:
		player_stats_received.emit(data)
	else:
		player_stats_received.emit({"player_id": pid})


# --------------------------------------------------------------
# Profile
# --------------------------------------------------------------

func fetch_player_profile() -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var account = await Platform.get_nakama_client().get_account_async(
		session)
	if account.is_exception():
		request_failed.emit(_describe(account.get_exception()))
		return
	var u = account.user
	# The friend code is generated per-account and is NOT the Nakama
	# username (runtime/friend_code.go). Falls back to "" when the
	# runtime predates the RPC, so the UI shows a placeholder rather
	# than a bogus username-as-code.
	var friend_code: String = (
		await Platform.friends.get_my_friend_code())
	profile_received.emit({
		"player": {
			"player_id": u.id,
			"display_name": u.display_name,
			"friend_code": friend_code,
			"avatar_url": u.avatar_url,
			"lang_tag": u.lang_tag,
			"location": u.location,
			"timezone": u.timezone,
			"linked_providers": (
				_account_linked_providers(account)),
		},
	})


# --------------------------------------------------------------
# Match history (custom RPC backed by Nakama Storage / leaderboard
# joins on the runtime side)
# --------------------------------------------------------------

func fetch_match_history() -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var rpc_result = await Platform.get_nakama_client().rpc_async(
		session, "get_match_history", "{}")
	if rpc_result.is_exception():
		# Pre-RPC deploys: return empty.
		match_history_received.emit({"matches": []})
		return
	var data: Variant = JSON.parse_string(rpc_result.payload)
	if data is Dictionary:
		match_history_received.emit(data)
	else:
		match_history_received.emit({"matches": []})


# --------------------------------------------------------------
# Version check (server-side runtime RPC)
# --------------------------------------------------------------

func check_version() -> void:
	var client_protocol: int = ProjectSettings.get_setting(
		"application/config/protocol_version", 1)
	var client_game_version: String = ProjectSettings.get_setting(
		"application/config/version", "")

	# The runtime's unauthenticated version-check route, which
	# answers like the `version_check` RPC with no session and no
	# key, so it works before sign-in (this call fires at boot,
	# before any session exists). Up to 0.47.0 this called the RPC
	# with Nakama's runtime HTTP key embedded in the client. That
	# key lets any holder call every runtime RPC as a trusted
	# server, so it must never ship in a build.
	var url := get_version_check_url()
	var headers := PackedStringArray([
		"Content-Type: application/json",
	])
	# A bare JSON object, the same body the RPC takes with
	# ?unwrap=true. Wrapping it again
	# (`JSON.stringify(JSON.stringify(…))`) silently falls through
	# to default-valued args, because the runtime ignores a body it
	# can't decode.
	var body := build_version_check_body(
		client_protocol, client_game_version)

	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	# Yield one frame so the HTTPRequest is fully inside the
	# scene tree before request() runs. Without this, on Godot
	# 4.7-beta1 the request fires before TLS init is ready and
	# returns RESULT_TLS_HANDSHAKE_ERROR / response_code=0
	# within milliseconds.
	await get_tree().process_frame
	var err := http.request(
		url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		Netcode.warning(
			"version_check request failed to start: %s"
			% error_string(err),
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		version_checked.emit(true, -1, client_game_version)
		return

	var result: Array = await http.request_completed
	http.queue_free()
	# request_completed signature:
	# (result, response_code, headers, body).
	var transport_result: int = result[0]
	var status: int = result[1]
	var response_body: PackedByteArray = result[3]

	if transport_result != HTTPRequest.RESULT_SUCCESS:
		# Transport-level failure (DNS, TLS, no response).
		# Assume compatible so a bad probe doesn't lock
		# players out.
		Netcode.warning(
			"version_check transport error: result=%d"
			% transport_result,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		version_checked.emit(true, -1, client_game_version)
		return

	if status != 200:
		Netcode.warning(
			"version_check returned HTTP %d" % status,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		version_checked.emit(true, -1, client_game_version)
		return

	var raw := response_body.get_string_from_utf8()
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		version_checked.emit(true, -1, client_game_version)
		return
	var server_protocol := int(data.get("protocol_version", -1))
	var server_game_version := str(data.get("game_version", ""))
	# Stage 3.10: cache the runtime's per-game legal_version so
	# LegalVersion.get_current() can hand it to the consent
	# screen. Empty (runtime didn't supply one, e.g. bootstrap
	# window before the first register_game sync) leaves the
	# compile-time fallback in effect.
	server_legal_version = str(data.get("legal_version", ""))
	# Stage 3.8: cache the runtime's per-game matchmaker rules
	# so nakama_matchmaker_client.gd can override its compile-
	# time _MIN_COUNT / _MAX_COUNT / _MATCHMAKER_QUERY without
	# a rebuild when game.yaml changes.
	server_matchmaker_min_players = int(
		data.get("matchmaker_min_players", 0))
	server_matchmaker_max_players = int(
		data.get("matchmaker_max_players", 0))
	server_matchmaker_query = str(
		data.get("matchmaker_query", ""))
	# Stage 4.7 / 5.7: cache the runtime's per-game mode list so
	# the picker UI and NakamaMatchmakerClient can route by
	# selected mode. Empty array (game declares no modes or pre-
	# 4.7 runtime) hides the picker and leaves the matchmaker on
	# its top-level rules.
	var raw_modes: Variant = data.get(
		"matchmaker_modes", null)
	if raw_modes is Array:
		server_matchmaker_modes = raw_modes
	else:
		server_matchmaker_modes = []
	var compatible := (
		server_protocol < 0
		or server_protocol == client_protocol)
	version_checked.emit(
		compatible, server_protocol, server_game_version)


## Returns the URL check_version() requests: the runtime's
## unauthenticated version-check route. It carries no credential.
func get_version_check_url() -> String:
	return Platform.get_version_check_url()


## Returns the JSON body check_version() sends.
func build_version_check_body(
	client_protocol: int,
	client_game_version: String,
) -> String:
	return JSON.stringify({
		"client_protocol_version": client_protocol,
		"client_game_version": client_game_version,
		# Stage 3.10: include game_id so the runtime returns this
		# game's protocol_version + legal_version from the `games`
		# table instead of the env-var-supplied defaults. Empty
		# game_id falls back to the legacy (env-var-only) response.
		"game_id": Platform.game_id,
	})


# --------------------------------------------------------------
# Internals
# --------------------------------------------------------------

func _ensure_session() -> NakamaSession:
	var s := Platform.build_session_from_store()
	if s == null:
		await Platform.auth.get_guest_jwt()
		s = Platform.build_session_from_store()
	if s == null:
		request_failed.emit("Not authenticated")
		return null
	return s


func _ensure_session_optional() -> NakamaSession:
	var s := Platform.build_session_from_store()
	if s == null:
		return null
	return s


func _describe(ex: NakamaException) -> String:
	if ex == null:
		return "Unknown Nakama error"
	return "%s (status=%d)" % [ex.message, ex.status_code]


## GETs `url` with no credential. Returns {status: int, body: String};
## status 0 means no response arrived.
func _http_get(url: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = _HTTP_TIMEOUT_SEC
	add_child(http)
	# Let the HTTPRequest finish entering the tree first; see
	# check_version() for the TLS failure an immediate request hits.
	await get_tree().process_frame
	var err := http.request(
		url, PackedStringArray(["Accept: application/json"]))
	if err != OK:
		http.queue_free()
		return {"status": 0, "body": ""}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": ""}
	var body: PackedByteArray = result[3]
	return {"status": result[1], "body": body.get_string_from_utf8()}


## Parses JSON quietly (JSON.parse_string logs an engine error on bad
## input). Returns null when `text` isn't JSON.
func _parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## True for a JSON number, which Godot's parser yields as a float.
func _is_number(value: Variant) -> bool:
	return value is float or value is int


## Returns `data[key]` as an int, or 0 when it isn't a number.
func _number(data: Dictionary, key: String) -> int:
	var value: Variant = data.get(key)
	return int(value) if _is_number(value) else 0


func _account_linked_providers(account) -> Array:
	# Provider IDs live on `account.user` (ApiUser), not directly
	# on ApiAccount. ApiAccount only carries `devices`, `email`,
	# and `user`; the social provider linkages are
	# `user.google_id` / `facebook_id` / `apple_id` / `steam_id`,
	# each a String that's empty when unlinked. The email is not a
	# provider: the platform offers no email sign-in, so an email on
	# an account only ever came from a provider's profile.
	var out: Array = []
	if account.devices and account.devices.size() > 0:
		out.append("anonymous")
	var u = account.user
	if u and not u.google_id.is_empty():
		out.append("google")
	if u and not u.facebook_id.is_empty():
		out.append("facebook")
	if u and not u.apple_id.is_empty():
		out.append("apple")
	if u and not u.steam_id.is_empty():
		out.append("steam")
	return out
