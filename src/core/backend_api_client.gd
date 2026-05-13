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


signal leaderboard_received(data: Dictionary)
signal player_stats_received(data: Dictionary)
signal profile_received(data: Dictionary)
signal match_history_received(data: Dictionary)
signal request_failed(error: String)

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

## Deprecated. Kept so the legacy lobby-level warmup connection
## still resolves. Never emitted now that Edgegap auto-allocates.
signal fleet_status_updated(data: Dictionary)

## Emitted after the startup version check completes.
## is_compatible is false only when the server returned a
## different protocol_version. Server values come from the
## `version_check` Nakama RPC; pre-RPC deploys return -1 and
## are treated as "compatible".
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

func fetch_leaderboard(
	type: String = "alltime",
	scope: String = "global",
	limit: int = 50,
) -> void:
	# Stage 3.6: read the per-game leaderboard the runtime
	# writes (`{game_id}_ffa`). The `type` parameter is echoed
	# back in the leaderboard_received payload below so the UI
	# can label which tab it came from. We don't have per-window
	# boards on the server today; when they land, switch this
	# to `"%s_ffa_%s" % [game_id, type]`.
	var game_id: String = Platform.game_id
	var board_id := (
		"%s_ffa" % game_id
		if not game_id.is_empty()
		else "ffa"
	)
	var session := await _ensure_session()
	if session == null:
		return
	var owner_ids = null
	if scope == "friends":
		# Restrict the listing to records owned by the current
		# user's friend graph.
		var friends_resp = await Platform.get_nakama_client().list_friends_async(
			session, null, 100, null)
		if not friends_resp.is_exception():
			var ids := PackedStringArray()
			for f in friends_resp.friends:
				ids.append(f.user.id)
			owner_ids = ids
	var result = await Platform.get_nakama_client().list_leaderboard_records_async(
		session, board_id, owner_ids, null, limit, "")
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	var entries := []
	for r in result.records:
		entries.append({
			"rank": r.rank,
			"player_id": r.owner_id,
			"display_name": r.username,
			"score": r.score,
			"metadata": JSON.parse_string(r.metadata) \
				if not r.metadata.is_empty() else {},
		})
	leaderboard_received.emit({
		"type": type,
		"scope": scope,
		"leaderboard_id": board_id,
		"entries": entries,
		"cursor": result.next_cursor,
	})


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
	profile_received.emit({
		"player_id": u.id,
		"display_name": u.display_name,
		"avatar_url": u.avatar_url,
		"lang_tag": u.lang_tag,
		"location": u.location,
		"timezone": u.timezone,
		"linked_providers": _account_linked_providers(account),
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

	# Hit the runtime's `version_check` RPC via Nakama's
	# HTTP-key path so this works pre-auth (the boot-time call
	# fires before any session exists). Nakama returns the
	# RPC's `result` envelope by default; `unwrap=true` strips
	# it down to the bare payload string.
	var url := "%s/v2/rpc/version_check?http_key=%s&unwrap=true" % [
		Platform.get_nakama_base_url(),
		Platform.nakama_http_key.uri_encode(),
	]
	var headers := PackedStringArray([
		"Content-Type: application/json",
	])
	# With ?unwrap=true, Nakama's HTTP gateway forwards the raw
	# request body as the RPC payload. Encode as a bare JSON
	# object — wrapping again (`JSON.stringify(JSON.stringify(…))`)
	# silently falls through to default-valued args because
	# the runtime's `_ = json.Unmarshal(payload, &args)` ignores
	# the unmarshal error.
	var body := JSON.stringify({
		"client_protocol_version": client_protocol,
		"client_game_version": client_game_version,
		# Stage 3.10: include game_id so the runtime returns
		# this game's protocol_version + legal_version from the
		# `games` table instead of the env-var-supplied
		# defaults. Empty game_id falls back to legacy
		# (env-var-only) response.
		"game_id": Platform.game_id,
	})

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
	var compatible := (
		server_protocol < 0
		or server_protocol == client_protocol)
	version_checked.emit(
		compatible, server_protocol, server_game_version)


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


func _account_linked_providers(account) -> Array:
	var out: Array = []
	if account.devices and account.devices.size() > 0:
		out.append("anonymous")
	if account.email and not account.email.is_empty():
		out.append("email")
	if account.google and account.google != null:
		out.append("google")
	if account.facebook and account.facebook != null:
		out.append("facebook")
	if account.apple and account.apple != null:
		out.append("apple")
	if account.steam and account.steam != null:
		out.append("steam")
	return out
