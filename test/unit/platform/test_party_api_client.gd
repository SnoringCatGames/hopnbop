extends GutTest
## Unit tests for PlatformPartyApiClient pure-logic helpers.
##
## The Nakama-driven RPC paths (create_party, fetch_party_status,
## etc.) are exercised by the live compliance suite. These tests
## cover the deterministic role mapping, id helper, and constants.


var _client: PlatformPartyApiClient


func before_each() -> void:
	_client = PlatformPartyApiClient.new()


func after_each() -> void:
	if is_instance_valid(_client):
		_client.free()


# ------------------------------------------------------------------
# is_busy
# ------------------------------------------------------------------


func test_is_busy_starts_false() -> void:
	assert_false(_client.is_busy())


func test_is_busy_reflects_internal_flag() -> void:
	_client._is_busy = true
	assert_true(_client.is_busy())


# ------------------------------------------------------------------
# _short_id
# ------------------------------------------------------------------


func test_short_id_strips_hyphens_and_truncates() -> void:
	assert_eq(
		_client._short_id("12345678-90ab-cdef-1234-567890abcdef"),
		"12345678")


func test_short_id_handles_input_without_hyphens() -> void:
	assert_eq(
		_client._short_id("12345678abcdef"), "12345678")


func test_short_id_pads_when_input_is_short() -> void:
	# substr(0, 8) on a 4-char string returns the full 4 chars.
	assert_eq(_client._short_id("abcd"), "abcd")


func test_short_id_empty_returns_empty() -> void:
	assert_eq(_client._short_id(""), "")


# ------------------------------------------------------------------
# _group_state_to_role (protocol-critical mapping)
# ------------------------------------------------------------------


func test_group_state_to_role_maps_known_states() -> void:
	# Nakama group_user state enum:
	#   0 = Superadmin (creator/owner)
	#   1 = Admin
	#   2 = Member
	#   3 = JoinRequest (pending invite the user has not accepted)
	# This mapping is protocol-critical: fetch_party_status splits
	# active members vs pending invites by the role, and the lobby
	# UI gates leader-only actions on role == "leader".
	assert_eq(_client._group_state_to_role(0), "leader")
	assert_eq(_client._group_state_to_role(1), "admin")
	assert_eq(_client._group_state_to_role(2), "member")
	assert_eq(_client._group_state_to_role(3), "invited")


func test_group_state_to_role_unknown_falls_through() -> void:
	# Defensive: a future Nakama enum extension must not collide
	# with any of our known role keywords. Returning "unknown"
	# means the UI safely treats them as non-leader, non-active.
	assert_eq(_client._group_state_to_role(42), "unknown")
	assert_eq(_client._group_state_to_role(-1), "unknown")


# ------------------------------------------------------------------
# Constants (protocol invariants)
# ------------------------------------------------------------------


func test_party_group_prefix_constant() -> void:
	# Must stay in lockstep with the platform runtime's
	# `partyGroupPrefix` — fetch_party_status uses this prefix to
	# distinguish party groups from other Nakama groups the user
	# may be in. Drift breaks party membership detection silently.
	assert_eq(
		PlatformPartyApiClient._PARTY_GROUP_PREFIX, "party-")


func test_party_storage_collection_constants() -> void:
	# Mirror third_party/snoringcat-platform/runtime/party.go:
	#   partyReadyCollection   = "party_ready"
	#   partyLeaderCollection  = "party_leader"
	#   partyModeCollection    = "party_mode"
	# These are the keys the runtime RPCs write to and the client
	# reads back in fetch_party_status's batched read.
	assert_eq(
		PlatformPartyApiClient._PARTY_READY_COLLECTION,
		"party_ready")
	assert_eq(
		PlatformPartyApiClient._PARTY_LEADER_COLLECTION,
		"party_leader")
	assert_eq(
		PlatformPartyApiClient._PARTY_MODE_COLLECTION,
		"party_mode")


# ------------------------------------------------------------------
# _describe (exception formatting)
# ------------------------------------------------------------------


func test_describe_handles_null_exception() -> void:
	assert_eq(
		_client._describe(null), "Unknown Nakama error")
