extends GutTest
## Unit tests for PartyManager deterministic helpers.
##
## The socket-driven update path + chat lifecycle are exercised
## live by the compliance suite (test_party.gd / test_party_invite_
## flow.gd / test_party_to_matchmaking.gd). These tests cover the
## pure inspectors + state-mutators that don't touch the network.
##
## Construction via .new() (no add_child) skips _ready() so the
## class does not bind Platform.party / notification_socket /
## auth signals at fixture time.


var _pm: PartyManager
var _emitted_updates: Array
var _original_player_id: String


func before_each() -> void:
	_pm = PartyManager.new()
	_emitted_updates = []
	_pm.party_updated.connect(
		func(data: Dictionary) -> void:
			_emitted_updates.append(data))
	# Pin a deterministic player_id so is_leader / is_self_ready
	# tests don't depend on the live signed-in user.
	_original_player_id = Platform.token_store.player_id
	Platform.token_store.player_id = "viewer-id"


func after_each() -> void:
	if is_instance_valid(_pm):
		_pm.free()
	Platform.token_store.player_id = _original_player_id


# ------------------------------------------------------------------
# is_in_party / has_pending_invite / get_party_id / get_party_mode
# ------------------------------------------------------------------


func test_is_in_party_false_when_current_party_empty() -> void:
	assert_false(_pm.is_in_party())


func test_is_in_party_true_when_current_party_set() -> void:
	_pm.current_party = {"party_id": "p1"}
	assert_true(_pm.is_in_party())


func test_has_pending_invite_reflects_array_state() -> void:
	assert_false(_pm.has_pending_invite())
	_pm.pending_invites = [{"party_id": "p1"}]
	assert_true(_pm.has_pending_invite())


func test_get_party_id_returns_field_or_empty() -> void:
	assert_eq(_pm.get_party_id(), "")
	_pm.current_party = {"party_id": "p1"}
	assert_eq(_pm.get_party_id(), "p1")


func test_get_party_mode_empty_when_not_in_party() -> void:
	# Mode is meaningless outside a party — resolver returns "" so
	# the caller falls back to the server's default-flagged mode.
	assert_eq(_pm.get_party_mode(), "")


func test_get_party_mode_returns_stored_mode() -> void:
	_pm.current_party = {
		"party_id": "p1",
		"game_mode": "duo",
	}
	assert_eq(_pm.get_party_mode(), "duo")


# ------------------------------------------------------------------
# is_leader
# ------------------------------------------------------------------


func test_is_leader_false_when_not_in_party() -> void:
	assert_false(_pm.is_leader())


func test_is_leader_true_when_token_matches_leader_id() -> void:
	_pm.current_party = {
		"party_id": "p1",
		"leader_id": "viewer-id",
	}
	assert_true(_pm.is_leader())


func test_is_leader_false_when_token_differs() -> void:
	_pm.current_party = {
		"party_id": "p1",
		"leader_id": "someone-else",
	}
	assert_false(_pm.is_leader())


# ------------------------------------------------------------------
# is_self_ready / all_active_members_ready / _patch_member_ready
# ------------------------------------------------------------------


func test_is_self_ready_false_when_not_in_party() -> void:
	assert_false(_pm.is_self_ready())


func test_is_self_ready_reads_member_ready_flag() -> void:
	_pm.current_party = {
		"party_id": "p1",
		"members": [
			{"user_id": "viewer-id", "ready": true},
			{"user_id": "other", "ready": false},
		],
	}
	assert_true(_pm.is_self_ready())


func test_is_self_ready_false_when_viewer_not_in_members() -> void:
	_pm.current_party = {
		"party_id": "p1",
		"members": [
			{"user_id": "other", "ready": true},
		],
	}
	assert_false(_pm.is_self_ready())


func test_all_active_members_ready_false_when_no_party() -> void:
	assert_false(_pm.all_active_members_ready())


func test_all_active_members_ready_true_when_all_ready() -> void:
	_pm.current_party = {
		"party_id": "p1",
		"members": [
			{"user_id": "a", "ready": true},
			{"user_id": "b", "ready": true},
		],
	}
	assert_true(_pm.all_active_members_ready())


func test_all_active_members_ready_false_when_any_not_ready() -> void:
	_pm.current_party = {
		"party_id": "p1",
		"members": [
			{"user_id": "a", "ready": true},
			{"user_id": "b", "ready": false},
		],
	}
	assert_false(_pm.all_active_members_ready())


func test_all_active_members_ready_ignores_invited_role() -> void:
	# Pending invites (role=invited) don't gate the leader's
	# Start button — they haven't accepted yet, so requiring them
	# to be "ready" would soft-lock the party.
	_pm.current_party = {
		"party_id": "p1",
		"members": [
			{"user_id": "a", "ready": true},
			{"user_id": "b", "ready": false, "role": "invited"},
		],
	}
	assert_true(_pm.all_active_members_ready())


func test_all_active_members_ready_false_when_zero_active() -> void:
	# Degenerate party with only an invited slot — the leader
	# alone shouldn't see Start enabled.
	_pm.current_party = {
		"party_id": "p1",
		"members": [
			{"user_id": "a", "ready": true, "role": "invited"},
		],
	}
	assert_false(_pm.all_active_members_ready())


func test_patch_member_ready_mutates_existing_entry() -> void:
	_pm.current_party = {
		"party_id": "p1",
		"members": [
			{"user_id": "a", "ready": false},
		],
	}
	_pm._patch_member_ready("a", true)
	assert_true(_pm.current_party.members[0].ready)


func test_patch_member_ready_skips_unknown_user_id() -> void:
	# No-op when the user isn't in the local cache. The next
	# fetch_party_status will reconcile.
	_pm.current_party = {
		"party_id": "p1",
		"members": [
			{"user_id": "a", "ready": false},
		],
	}
	_pm._patch_member_ready("ghost", true)
	assert_false(_pm.current_party.members[0].ready)


# ------------------------------------------------------------------
# _remove_pending_invite
# ------------------------------------------------------------------


func test_remove_pending_invite_strips_matching_entry() -> void:
	_pm.pending_invites = [
		{"party_id": "p1"},
		{"party_id": "p2"},
	]
	_pm._known_invite_ids["p1"] = true
	_pm._known_invite_ids["p2"] = true
	_pm._remove_pending_invite("p1")
	assert_eq(_pm.pending_invites.size(), 1)
	assert_eq(_pm.pending_invites[0].party_id, "p2")
	assert_false(_pm._known_invite_ids.has("p1"))
	assert_true(_pm._known_invite_ids.has("p2"))


func test_remove_pending_invite_emits_party_updated() -> void:
	_pm.pending_invites = [{"party_id": "p1"}]
	_pm._remove_pending_invite("p1")
	assert_eq(_emitted_updates.size(), 1)


# ------------------------------------------------------------------
# reset
# ------------------------------------------------------------------


func test_reset_clears_all_tracked_state() -> void:
	_pm.current_party = {"party_id": "p1"}
	_pm.pending_invites = [{"party_id": "p2"}]
	_pm.pending_party_match_context = {"party_id": "p1"}
	_pm._known_invite_ids["p2"] = true
	_pm._known_state_changed_ids["nid-1"] = true
	_pm._initial_party_check_done = true
	_pm._local_party_action_taken = true
	_pm.start_polling()

	_pm.reset()

	assert_true(_pm.current_party.is_empty())
	assert_true(_pm.pending_invites.is_empty())
	assert_true(_pm.pending_party_match_context.is_empty())
	assert_eq(_pm._known_invite_ids.size(), 0)
	assert_eq(_pm._known_state_changed_ids.size(), 0)
	assert_false(_pm._initial_party_check_done)
	assert_false(_pm._local_party_action_taken)
	assert_false(_pm._is_polling)


# ------------------------------------------------------------------
# _resolve_member_display_name
# ------------------------------------------------------------------


func test_resolve_display_name_returns_display_when_set() -> void:
	var party := {
		"members": [
			{
				"user_id": "a",
				"display_name": "Alice",
				"username": "alice_u",
			},
		],
	}
	assert_eq(
		_pm._resolve_member_display_name(party, "a"), "Alice")


func test_resolve_display_name_falls_back_to_username() -> void:
	var party := {
		"members": [
			{
				"user_id": "a",
				"display_name": "",
				"username": "alice_u",
			},
		],
	}
	assert_eq(
		_pm._resolve_member_display_name(party, "a"),
		"alice_u")


func test_resolve_display_name_empty_for_unknown_user() -> void:
	var party := {"members": [{"user_id": "a"}]}
	assert_eq(
		_pm._resolve_member_display_name(party, "ghost"), "")


func test_resolve_display_name_empty_for_empty_user_id() -> void:
	var party := {
		"members": [{"user_id": "a", "display_name": "Alice"}],
	}
	assert_eq(
		_pm._resolve_member_display_name(party, ""), "")


# ------------------------------------------------------------------
# _on_party_status_received (initial fetch flag)
# ------------------------------------------------------------------


func test_party_status_received_marks_initial_check_done() -> void:
	# First receipt with no active party — the rejoin check still
	# flips the "initial check done" flag so subsequent receipts
	# don't re-prompt.
	_pm._on_party_status_received({})
	# No party present, so initial_check_done is not flipped on
	# the no-active-party branch (the prompt only matters when
	# there IS a party). Verify the inverse: a receipt with an
	# active party flips it.
	_pm._on_party_status_received({
		"party": {
			"party_id": "p1",
			"leader_id": "viewer-id",
			"members": [],
		},
	})
	assert_true(_pm._initial_party_check_done)


# ------------------------------------------------------------------
# set_party_mode (optimistic local patch)
# ------------------------------------------------------------------


func test_set_party_mode_noop_when_not_in_party() -> void:
	_pm.set_party_mode("duo")
	# Nothing in current_party means no party, no emit.
	assert_eq(_emitted_updates.size(), 0)


func test_set_party_mode_noop_when_unchanged() -> void:
	# Skip the live Platform.party.set_mode network call — the
	# unchanged guard short-circuits before the network call.
	_pm.current_party = {
		"party_id": "p1",
		"game_mode": "duo",
	}
	_pm.set_party_mode("duo")
	assert_eq(_emitted_updates.size(), 0)


# ------------------------------------------------------------------
# Polling lifecycle
# ------------------------------------------------------------------


func test_start_polling_arms_state() -> void:
	_pm.start_polling()
	assert_true(_pm._is_polling)
	assert_eq(_pm._poll_timer, 0.0)


func test_stop_polling_disarms() -> void:
	_pm.start_polling()
	_pm.stop_polling()
	assert_false(_pm._is_polling)
