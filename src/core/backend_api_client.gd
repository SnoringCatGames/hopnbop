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
signal settings_received(data: Dictionary)
signal settings_saved(data: Dictionary)
signal match_history_received(data: Dictionary)
signal request_failed(error: String)

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
	board_id: String = "ffa",
	limit: int = 50,
	cursor: String = "",
) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().list_leaderboard_records_async(
		session, board_id, null, null, limit, cursor)
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
		"leaderboard_id": board_id,
		"entries": entries,
		"cursor": result.next_cursor,
	})


func fetch_player_stats(player_id: String = "") -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var pid := player_id if player_id else session.user_id
	var rpc_result = await G.auth_client._get_nakama_client().rpc_async(
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
	var account = await G.auth_client._get_nakama_client().get_account_async(
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
# Settings (Nakama Storage, collection="settings", key="user")
# --------------------------------------------------------------

func fetch_player_settings() -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var ids := [NakamaStorageObjectId.new(
		"settings", "user", session.user_id)]
	var result = await G.auth_client._get_nakama_client().read_storage_objects_async(
		session, ids)
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	if result.objects.size() == 0:
		settings_received.emit({})
		return
	var raw: String = result.objects[0].value
	var data: Variant = JSON.parse_string(raw)
	settings_received.emit(data if data is Dictionary else {})


func save_player_settings(settings: Dictionary) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var obj := NakamaWriteStorageObject.new(
		"settings", "user", 1, 1, JSON.stringify(settings), "")
	var result = await G.auth_client._get_nakama_client().write_storage_objects_async(
		session, [obj])
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	settings_saved.emit(settings)


# --------------------------------------------------------------
# Match history (custom RPC backed by Nakama Storage / leaderboard
# joins on the runtime side)
# --------------------------------------------------------------

func fetch_match_history() -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var rpc_result = await G.auth_client._get_nakama_client().rpc_async(
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
	# version_check is unauthenticated — call without a session.
	# Nakama supports HTTP key for unauthenticated RPCs; lacking
	# one, we fall through to "compatible" so offline/preview
	# instances don't fail at startup.
	var session := await _ensure_session_optional()
	if session == null:
		version_checked.emit(true, -1, client_game_version)
		return
	var rpc_result = await G.auth_client._get_nakama_client().rpc_async(
		session, "version_check",
		JSON.stringify({
			"client_protocol_version": client_protocol,
			"client_game_version": client_game_version,
		}))
	if rpc_result.is_exception():
		# RPC missing / not yet deployed: assume compatible.
		version_checked.emit(true, -1, client_game_version)
		return
	var data: Variant = JSON.parse_string(rpc_result.payload)
	if not (data is Dictionary):
		version_checked.emit(true, -1, client_game_version)
		return
	var server_protocol := int(data.get("protocol_version", -1))
	var server_game_version := str(data.get("game_version", ""))
	var compatible := (
		server_protocol < 0
		or server_protocol == client_protocol)
	version_checked.emit(
		compatible, server_protocol, server_game_version)


# --------------------------------------------------------------
# Internals
# --------------------------------------------------------------

func _ensure_session() -> NakamaSession:
	var s := G.auth_client._build_session_from_store()
	if s == null:
		await G.auth_client.get_guest_jwt()
		s = G.auth_client._build_session_from_store()
	if s == null:
		request_failed.emit("Not authenticated")
		return null
	return s


func _ensure_session_optional() -> NakamaSession:
	var s := G.auth_client._build_session_from_store()
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
