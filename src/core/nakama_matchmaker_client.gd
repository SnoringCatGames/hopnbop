class_name NakamaMatchmakerClient
extends SessionProvider
## Game-side SessionProvider adapter that bridges
## `Platform.matchmaking` (the addon's Nakama matchmaker socket
## layer) to the rollback-netcode `SessionProvider` contract.
##
## Responsibilities:
##   - Resolve matchmaker rules (query / min / max) from
##     BackendApiClient (set by version_check, sourced from
##     `game.yaml.matchmaker_rules`) with compile-time fallbacks.
##   - Build the matchmaker properties dict, including
##     game-specific keys (platform, player_count, game_id,
##     level_id, party_id, game_mode).
##   - Translate the match_ready `transport_type` string to
##     `NetworkSettings.TransportType` and apply it before
##     emitting `session_ids_received`.
##   - Mint a per-instance preview device id when running
##     Netcode preview slot > 0 so each editor preview instance
##     looks like a distinct user to the matchmaker pool.
##
## The Nakama socket lifecycle and matchmaker ticket lifecycle
## both live in `Platform.matchmaking` (a boot-time singleton
## registered from `global.gd._enter_tree`). This adapter is
## instantiated per-session by `GameSessionManager` and is
## responsible for cleanly connecting / disconnecting its
## signal handlers from the singleton.


## Compile-time fallbacks for matchmaker rules. Stage 3.8
## prefers runtime-reported values surfaced via
## BackendApiClient.server_matchmaker_* (from
## `game.yaml.matchmaker_rules`). Keep these in sync with
## game.yaml so an offline / pre-version-check matchmaker still
## queues against the right pool shape.
const _DEFAULT_MATCHMAKER_QUERY := "*"
const _DEFAULT_MIN_COUNT := 2
const _DEFAULT_MAX_COUNT := 4


## Stable per (machine, preview slot). Empty for the primary
## instance and for production. When non-empty, the addon-side
## matchmaker authenticates this device id as a separate Nakama
## account so each preview slot is a distinct matchmaker entry.
var _preview_device_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var client: PlatformMatchmakingClient = Platform.matchmaking
	if client == null:
		Netcode.log.warning(
			(
				"[NakamaMatchmaker] Platform.matchmaking not"
				+ " registered; matchmaking will fail until"
				+ " bootstrap wires it up"
			),
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return
	client.match_ready_received.connect(
		_on_match_ready_received)
	client.matchmaking_failed.connect(_on_matchmaking_failed)
	client.progress_updated.connect(_on_progress_updated)


func _exit_tree() -> void:
	var client: PlatformMatchmakingClient = Platform.matchmaking
	if client == null:
		return
	if client.match_ready_received.is_connected(
			_on_match_ready_received):
		client.match_ready_received.disconnect(
			_on_match_ready_received)
	if client.matchmaking_failed.is_connected(
			_on_matchmaking_failed):
		client.matchmaking_failed.disconnect(
			_on_matchmaking_failed)
	if client.progress_updated.is_connected(
			_on_progress_updated):
		client.progress_updated.disconnect(
			_on_progress_updated)


func is_active() -> bool:
	return true


func client_request_session_ids(
	player_count: int,
	session_prefs: Dictionary = {},
) -> void:
	var client: PlatformMatchmakingClient = Platform.matchmaking
	if client == null:
		session_request_failed.emit(
			"Platform.matchmaking not registered")
		return
	if client.is_searching():
		Netcode.log.warning(
			"[NakamaMatchmaker] Already searching",
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
		return

	var preview_device_id := _resolve_preview_device_id()
	var query := _build_query(session_prefs)
	var min_count := _resolve_min_count(session_prefs)
	var max_count := _resolve_max_count(session_prefs)
	var string_props := _build_string_props(
		player_count, session_prefs)
	var numeric_props := _build_numeric_props(
		player_count, session_prefs)

	client.start_matchmaking(
		query,
		min_count,
		max_count,
		string_props,
		numeric_props,
		preview_device_id,
		player_count,
	)


func clear_session() -> void:
	var client: PlatformMatchmakingClient = Platform.matchmaking
	if client == null:
		return
	client.cancel_matchmaking()


func cleanup() -> void:
	var client: PlatformMatchmakingClient = Platform.matchmaking
	if client == null:
		return
	client.cleanup()


# --------------------------------------------------------------
# Internals
# --------------------------------------------------------------


func _resolve_preview_device_id() -> String:
	if not (Netcode.is_preview
			and Netcode.preview_client_number > 0):
		return ""
	if _preview_device_id.is_empty():
		# Stable per (machine, preview slot) so re-runs reuse
		# the same Nakama account and don't sprawl test users
		# across Nakama. Distinct between preview slots and
		# between machines.
		var base := OS.get_unique_id()
		if base.is_empty():
			base = "preview"
		_preview_device_id = "preview_%s_C%d" % [
			base, Netcode.preview_client_number]
	return _preview_device_id


func _build_query(session_prefs: Dictionary) -> String:
	# Stage 4.7 / 5.7: prefer the selected mode's query first
	# so a duo ticket only matches other duo tickets. Empty
	# mode_query falls through to the game-level default below.
	var mode := _resolve_mode_dict(session_prefs)
	if (mode.has("query")
			and not str(mode.get("query", "")).is_empty()):
		return str(mode["query"])
	# Stage 3.8: prefer the runtime-reported query (from
	# game.yaml's matchmaker_rules) over the compile-time
	# default. Empty means "no override; use the default".
	# Per-level / per-region matchmaking can layer onto either
	# source once the runtime echoes the selected level back
	# through the match_ready payload.
	if (is_instance_valid(G.backend_api_client)
			and not G.backend_api_client
				.server_matchmaker_query.is_empty()):
		return G.backend_api_client.server_matchmaker_query
	return _DEFAULT_MATCHMAKER_QUERY


func _resolve_min_count(session_prefs: Dictionary = {}) -> int:
	var mode := _resolve_mode_dict(session_prefs)
	if int(mode.get("min_players", 0)) > 0:
		return int(mode["min_players"])
	if (is_instance_valid(G.backend_api_client)
			and G.backend_api_client
				.server_matchmaker_min_players > 0):
		return (G.backend_api_client
			.server_matchmaker_min_players)
	return _DEFAULT_MIN_COUNT


func _resolve_max_count(session_prefs: Dictionary = {}) -> int:
	var mode := _resolve_mode_dict(session_prefs)
	if int(mode.get("max_players", 0)) > 0:
		return int(mode["max_players"])
	if (is_instance_valid(G.backend_api_client)
			and G.backend_api_client
				.server_matchmaker_max_players > 0):
		return (G.backend_api_client
			.server_matchmaker_max_players)
	return _DEFAULT_MAX_COUNT


## Returns the selected mode dict (with keys: id, query,
## min_players, max_players, ...) for the current request, or an
## empty dict when no mode is selected and no server modes are
## known. Resolution order:
##   1. session_prefs.game_mode (party flow injects this).
##   2. LocalSettings.get_selected_game_mode() (solo picker).
##   3. server_matchmaker_modes' is_default entry.
##   4. {} (no mode; caller falls back to game-level rules).
## Stage 4.7 / 5.7.
func _resolve_mode_dict(session_prefs: Dictionary) -> Dictionary:
	if not is_instance_valid(G.backend_api_client):
		return {}
	var modes: Array = G.backend_api_client.server_matchmaker_modes
	if modes.is_empty():
		return {}
	var picked_id := ""
	if session_prefs.has("game_mode"):
		picked_id = str(session_prefs["game_mode"])
	if picked_id.is_empty() and is_instance_valid(G.local_settings):
		picked_id = G.local_settings.get_selected_game_mode()
	if picked_id.is_empty():
		for m in modes:
			if (m is Dictionary
					and bool(m.get("is_default", false))):
				return m
		return {}
	for m in modes:
		if m is Dictionary and str(m.get("id", "")) == picked_id:
			return m
	return {}


func _build_string_props(
	player_count: int,
	session_prefs: Dictionary,
) -> Dictionary:
	# `client_ip` is recorded server-side by the addon's
	# `record_client_ip` RPC call inside start_matchmaking;
	# fleet_allocator.go reads it back from storage. The
	# remaining keys ride as matchmaker ticket properties so
	# the allocator (and future per-game-mode logic) can see
	# them on the runtime.MatchmakerEntry.
	var props := {
		"platform": (
			"web" if OS.has_feature("web") else "native"),
		"player_count": str(player_count),
	}
	# game_id is read by fleet_allocator.go to scope match
	# metadata (and downstream leaderboard writes via
	# Stage 3.6) to the correct game. Empty Platform.game_id
	# falls back to the legacy bare leaderboard ID on the
	# server — shouldn't happen in production because
	# Platform.initialize is called from global.gd._enter_tree.
	if not Platform.game_id.is_empty():
		props["game_id"] = Platform.game_id
	# Stage 3.9: declare our protocol_version so the fleet
	# allocator can short-circuit a stale-client match before
	# burning an Edgegap deploy. The value is the integer the
	# CI parity guard already keeps in lockstep with
	# game.yaml::protocol_version. Stringified per the
	# matchmaker-property contract (Nakama matchmaker entries
	# carry string properties only). Server-side validation is
	# graceful: pre-Stage-3.9 clients omit the key and pass
	# through, so the rollout doesn't lock anyone out.
	var protocol_version := int(ProjectSettings.get_setting(
		"application/config/protocol_version", 0))
	if protocol_version > 0:
		props["client_protocol_version"] = str(protocol_version)
	if session_prefs.has("selected_level_id"):
		props["level_id"] = str(
			session_prefs["selected_level_id"])
	# Party matchmaking: PartyManager seeds session_prefs with
	# the matchmaker_properties echoed by
	# `party_start_matchmaking`. The shared `party_id` flows
	# into Nakama as a ticket property so the fleet allocator
	# (and future per-game-mode logic) can tell matched
	# players came from the same party.
	for key in ["party_id", "game_mode"]:
		if session_prefs.has(key):
			props[key] = str(session_prefs[key])
	# Stage 4.7 / 5.7: when no explicit game_mode rode in via
	# session_prefs, fall back to the device's solo pick (or the
	# server's default-flagged mode). The resolved id is also the
	# mode that drove _build_query / _resolve_min/max above, so
	# the ticket property and the query stay coherent.
	if not props.has("game_mode"):
		var fallback_mode := _resolve_mode_dict(session_prefs)
		if not fallback_mode.is_empty():
			var mode_id := str(fallback_mode.get("id", ""))
			if not mode_id.is_empty():
				props["game_mode"] = mode_id
	return props


func _build_numeric_props(
	_player_count: int,
	_session_prefs: Dictionary,
) -> Dictionary:
	# Reserved for rating-based matchmaking later.
	return {}


func _on_match_ready_received(payload: Dictionary) -> void:
	# Apply transport_type before emitting session_ids_received
	# so GameSessionManager's connect step picks the right
	# transport. The runtime sends "enet" for ENet-only pools
	# and "webrtc" once any web player is in the match.
	var transport_type_str: String = str(
		payload.get("transport_type", ""))
	if not transport_type_str.is_empty():
		_apply_transport_type(transport_type_str)

	var session_ids: Array = payload.get("session_ids", [])
	var server_ip: String = str(payload.get("server_ip", ""))
	var server_port: int = int(payload.get("server_port", 0))
	var signaling_url: String = str(
		payload.get("signaling_url", ""))
	var level_id: String = str(payload.get("level_id", ""))

	session_ids_received.emit(
		session_ids,
		server_ip,
		server_port,
		level_id,
		signaling_url,
	)


func _on_matchmaking_failed(error: String) -> void:
	session_request_failed.emit(error)


func _on_progress_updated(
	phase: String,
	elapsed_sec: float,
	estimated_total_sec: float,
) -> void:
	matchmaking_progress_updated.emit(
		phase, elapsed_sec, estimated_total_sec)


func _apply_transport_type(raw: String) -> void:
	match raw.to_lower():
		"enet":
			Netcode.settings.transport_type = (
				NetworkSettings.TransportType.ENET)
		"webrtc":
			Netcode.settings.transport_type = (
				NetworkSettings.TransportType.WEBRTC)
		"websocket":
			Netcode.settings.transport_type = (
				NetworkSettings.TransportType.WEBSOCKET)
		_:
			Netcode.log.warning(
				(
					"[NakamaMatchmaker] unknown"
					+ " transport_type '%s' from match_ready;"
					+ " keeping current setting"
				) % raw,
				NetworkLogger.CATEGORY_CONNECTIONS,
			)
