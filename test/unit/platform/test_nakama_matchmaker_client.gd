extends GutTest
## Unit tests for NakamaMatchmakerClient pure-logic helpers.
##
## The class wraps the addon's Platform.matchmaking subsystem
## and translates session-pref Dictionaries into matchmaker
## tickets. The network-side methods (start_matchmaking,
## _on_match_ready_received) are exercised by the compliance
## suite against live Nakama. These tests cover the
## deterministic resolution helpers that decide which query /
## min / max / mode / props to forward.
##
## Inner-class test grouping is intentionally avoided: the
## GUT 9.5.0 + Godot 4.7-beta1 cmdline path in this repo does
## not discover tests inside inner classes (see project CLAUDE.md
## "Known Test Failures"). Group via name prefix instead.


var _snap: Dictionary
var _client: NakamaMatchmakerClient
var _original_local_mode: String
var _original_transport: int


func before_each() -> void:
	_snap = {
		"server_matchmaker_query": (
			G.backend_api_client.server_matchmaker_query),
		"server_matchmaker_min_players": (
			G.backend_api_client.server_matchmaker_min_players),
		"server_matchmaker_max_players": (
			G.backend_api_client.server_matchmaker_max_players),
		"server_matchmaker_modes": (
			G.backend_api_client.server_matchmaker_modes),
		"game_id": Platform.game_id,
	}
	G.backend_api_client.server_matchmaker_query = ""
	G.backend_api_client.server_matchmaker_min_players = 0
	G.backend_api_client.server_matchmaker_max_players = 0
	G.backend_api_client.server_matchmaker_modes = []
	Platform.game_id = "hopnbop"

	_original_local_mode = (
		G.local_settings.get_selected_game_mode())
	G.local_settings.set_selected_game_mode("")

	_original_transport = Netcode.settings.transport_type

	# Build a client without entering the tree so _ready() does
	# not try to bind Platform.matchmaking signals.
	_client = NakamaMatchmakerClient.new()


func after_each() -> void:
	if is_instance_valid(_client):
		_client.free()
	G.backend_api_client.server_matchmaker_query = (
		_snap.server_matchmaker_query)
	G.backend_api_client.server_matchmaker_min_players = (
		_snap.server_matchmaker_min_players)
	G.backend_api_client.server_matchmaker_max_players = (
		_snap.server_matchmaker_max_players)
	G.backend_api_client.server_matchmaker_modes = (
		_snap.server_matchmaker_modes)
	Platform.game_id = _snap.game_id
	G.local_settings.set_selected_game_mode(
		_original_local_mode)
	Netcode.settings.transport_type = _original_transport


# ------------------------------------------------------------------
# _build_query
# ------------------------------------------------------------------


func test_build_query_compile_time_default_when_no_overrides() -> void:
	assert_eq(_client._build_query({}), "*")


func test_build_query_server_query_used_when_set() -> void:
	G.backend_api_client.server_matchmaker_query = (
		"+properties.game_id:hopnbop")
	assert_eq(
		_client._build_query({}),
		"+properties.game_id:hopnbop")


func test_build_query_mode_query_wins_over_server_query() -> void:
	G.backend_api_client.server_matchmaker_query = (
		"+properties.region:us-west")
	G.backend_api_client.server_matchmaker_modes = [
		{
			"id": "duo",
			"query": "+properties.mode:duo",
			"min_players": 2,
			"max_players": 2,
		},
		{
			"id": "ffa",
			"query": "",
			"min_players": 2,
			"max_players": 4,
			"is_default": true,
		},
	]
	var query := _client._build_query({"game_mode": "duo"})
	assert_eq(query, "+properties.mode:duo")


func test_build_query_empty_mode_query_falls_through_to_server() -> void:
	G.backend_api_client.server_matchmaker_query = (
		"+properties.region:us-west")
	G.backend_api_client.server_matchmaker_modes = [
		{
			"id": "ffa",
			"query": "",
			"min_players": 2,
			"max_players": 4,
			"is_default": true,
		},
	]
	var query := _client._build_query({})
	assert_eq(query, "+properties.region:us-west")


# ------------------------------------------------------------------
# _resolve_min_count / _resolve_max_count
# ------------------------------------------------------------------


func test_resolve_min_max_compile_time_defaults() -> void:
	assert_eq(_client._resolve_min_count({}), 2)
	assert_eq(_client._resolve_max_count({}), 4)


func test_resolve_min_max_server_overrides_when_positive() -> void:
	G.backend_api_client.server_matchmaker_min_players = 3
	G.backend_api_client.server_matchmaker_max_players = 8
	assert_eq(_client._resolve_min_count({}), 3)
	assert_eq(_client._resolve_max_count({}), 8)


func test_resolve_min_max_zero_falls_through_to_defaults() -> void:
	# Stage 3.8 contract: 0 means "no override".
	G.backend_api_client.server_matchmaker_min_players = 0
	G.backend_api_client.server_matchmaker_max_players = 0
	assert_eq(_client._resolve_min_count({}), 2)
	assert_eq(_client._resolve_max_count({}), 4)


func test_resolve_min_max_mode_overrides_server_values() -> void:
	G.backend_api_client.server_matchmaker_min_players = 3
	G.backend_api_client.server_matchmaker_max_players = 8
	G.backend_api_client.server_matchmaker_modes = [
		{
			"id": "duo",
			"query": "",
			"min_players": 2,
			"max_players": 2,
		},
	]
	var prefs := {"game_mode": "duo"}
	assert_eq(_client._resolve_min_count(prefs), 2)
	assert_eq(_client._resolve_max_count(prefs), 2)


func test_resolve_min_max_mode_partial_override_only_min() -> void:
	# A mode that sets min but leaves max=0 should override only
	# min; max should fall through to the server value.
	G.backend_api_client.server_matchmaker_max_players = 8
	G.backend_api_client.server_matchmaker_modes = [
		{
			"id": "weird",
			"query": "",
			"min_players": 5,
			"max_players": 0,
		},
	]
	var prefs := {"game_mode": "weird"}
	assert_eq(_client._resolve_min_count(prefs), 5)
	assert_eq(_client._resolve_max_count(prefs), 8)


# ------------------------------------------------------------------
# _resolve_mode_dict
# ------------------------------------------------------------------


func test_resolve_mode_dict_empty_when_no_modes_registered() -> void:
	assert_eq(_client._resolve_mode_dict({}), {})


func test_resolve_mode_dict_explicit_id_from_session_prefs() -> void:
	G.backend_api_client.server_matchmaker_modes = [
		{
			"id": "ffa",
			"min_players": 2,
			"max_players": 4,
			"is_default": true,
		},
		{
			"id": "duo",
			"min_players": 2,
			"max_players": 2,
		},
	]
	var mode := _client._resolve_mode_dict(
		{"game_mode": "duo"})
	assert_eq(mode.id, "duo")
	assert_eq(int(mode.max_players), 2)


func test_resolve_mode_dict_unknown_id_returns_empty() -> void:
	# Explicit but unknown id; resolver does NOT fall back to
	# default — caller falls back to game-level rules instead.
	G.backend_api_client.server_matchmaker_modes = [
		{
			"id": "ffa",
			"is_default": true,
		},
	]
	var mode := _client._resolve_mode_dict(
		{"game_mode": "ghost"})
	assert_eq(mode, {})


func test_resolve_mode_dict_local_pick_used_when_prefs_silent() -> void:
	G.backend_api_client.server_matchmaker_modes = [
		{"id": "ffa", "is_default": true},
		{"id": "duo"},
	]
	G.local_settings.set_selected_game_mode("duo")
	var mode := _client._resolve_mode_dict({})
	assert_eq(mode.id, "duo")


func test_resolve_mode_dict_server_default_when_nothing_picked() -> void:
	G.backend_api_client.server_matchmaker_modes = [
		{"id": "ffa"},
		{"id": "duo", "is_default": true},
	]
	var mode := _client._resolve_mode_dict({})
	assert_eq(mode.id, "duo")


func test_resolve_mode_dict_no_default_no_pick_returns_empty() -> void:
	G.backend_api_client.server_matchmaker_modes = [
		{"id": "ffa"},
		{"id": "duo"},
	]
	var mode := _client._resolve_mode_dict({})
	assert_eq(mode, {})


# ------------------------------------------------------------------
# _build_string_props
# ------------------------------------------------------------------


func test_build_string_props_baseline_keys_present() -> void:
	var props := _client._build_string_props(3, {})
	# platform follows OS.has_feature("web") — assert it is one
	# of the two valid values rather than pinning to one, since
	# the test runner is native but the contract allows either.
	assert_true(
		props.platform == "native"
			or props.platform == "web")
	assert_eq(props.player_count, "3")
	assert_eq(props.game_id, "hopnbop")


func test_build_string_props_empty_game_id_omits_key() -> void:
	Platform.game_id = ""
	var props := _client._build_string_props(2, {})
	assert_false(
		props.has("game_id"),
		"Empty Platform.game_id must NOT inject the key")


func test_build_string_props_protocol_version_stringified() -> void:
	# ProjectSettings carries a protocol_version int (declared in
	# project.godot); _build_string_props stringifies it as
	# `client_protocol_version` when > 0.
	var protocol := int(ProjectSettings.get_setting(
		"application/config/protocol_version", 0))
	var props := _client._build_string_props(2, {})
	if protocol > 0:
		assert_eq(
			props.client_protocol_version, str(protocol))
	else:
		assert_false(props.has("client_protocol_version"))


func test_build_string_props_level_id_passed_through() -> void:
	var props := _client._build_string_props(
		2, {"selected_level_id": "arena_01"})
	assert_eq(props.level_id, "arena_01")


func test_build_string_props_party_and_game_mode_passed_through() -> void:
	var props := _client._build_string_props(
		2,
		{
			"party_id": "p-abc",
			"game_mode": "duo",
		},
	)
	assert_eq(props.party_id, "p-abc")
	assert_eq(props.game_mode, "duo")


func test_build_string_props_game_mode_falls_back_to_resolved() -> void:
	# When session_prefs lacks game_mode, the builder should fall
	# back to the resolved mode dict's id. Stage 4.7 / 5.7
	# coherence contract.
	G.backend_api_client.server_matchmaker_modes = [
		{"id": "ffa", "is_default": true},
	]
	var props := _client._build_string_props(2, {})
	assert_eq(props.game_mode, "ffa")


func test_build_string_props_no_game_mode_when_no_resolution() -> void:
	# Truly no modes registered + no pref: builder must NOT
	# inject a stale game_mode.
	var props := _client._build_string_props(2, {})
	assert_false(props.has("game_mode"))


# ------------------------------------------------------------------
# _build_numeric_props
# ------------------------------------------------------------------


func test_build_numeric_props_always_empty() -> void:
	# Reserved for future rating-based matchmaking.
	assert_eq(_client._build_numeric_props(2, {}), {})
	assert_eq(_client._build_numeric_props(0, {"x": 1}), {})


# ------------------------------------------------------------------
# _apply_transport_type
# ------------------------------------------------------------------


func test_apply_transport_type_enet_recognized() -> void:
	Netcode.settings.transport_type = (
		NetworkSettings.TransportType.WEBRTC)
	_client._apply_transport_type("enet")
	assert_eq(
		Netcode.settings.transport_type,
		NetworkSettings.TransportType.ENET)


func test_apply_transport_type_webrtc_recognized() -> void:
	Netcode.settings.transport_type = (
		NetworkSettings.TransportType.ENET)
	_client._apply_transport_type("webrtc")
	assert_eq(
		Netcode.settings.transport_type,
		NetworkSettings.TransportType.WEBRTC)


func test_apply_transport_type_websocket_recognized() -> void:
	Netcode.settings.transport_type = (
		NetworkSettings.TransportType.ENET)
	_client._apply_transport_type("websocket")
	assert_eq(
		Netcode.settings.transport_type,
		NetworkSettings.TransportType.WEBSOCKET)


func test_apply_transport_type_case_insensitive() -> void:
	Netcode.settings.transport_type = (
		NetworkSettings.TransportType.ENET)
	_client._apply_transport_type("WebRTC")
	assert_eq(
		Netcode.settings.transport_type,
		NetworkSettings.TransportType.WEBRTC)


func test_apply_transport_type_unknown_value_does_not_mutate() -> void:
	# Runtime should warn (we don't assert on the log output) but
	# the current transport must persist so a malformed
	# match_ready doesn't drop the client into an undefined state.
	Netcode.settings.transport_type = (
		NetworkSettings.TransportType.WEBRTC)
	_client._apply_transport_type("quantum")
	assert_eq(
		Netcode.settings.transport_type,
		NetworkSettings.TransportType.WEBRTC)
