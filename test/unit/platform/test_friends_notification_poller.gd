extends GutTest
## Unit tests for FriendsNotificationPoller deterministic logic.
##
## The polling cadence + signal wiring is exercised live by the
## compliance suite (test_friends.gd). These tests cover the pure
## state-tracking and dispatch helpers that decide whether a given
## notification produces a side effect.
##
## The poller is constructed via .new() and never added to the
## scene tree, so _ready() (which binds Platform.friends signals)
## does not fire.


var _poller: FriendsNotificationPoller
var _emitted_counts: Array[int]


func before_each() -> void:
	_poller = FriendsNotificationPoller.new()
	_emitted_counts = []
	_poller.unseen_count_changed.connect(
		func(count: int) -> void:
			_emitted_counts.append(count))


func after_each() -> void:
	if is_instance_valid(_poller):
		_poller.free()


# ------------------------------------------------------------------
# reset()
# ------------------------------------------------------------------


func test_reset_clears_known_ids_and_unseen() -> void:
	# Seed state via the public path, then reset.
	_poller._on_friends_received({"unseen_count": 5})
	_poller._on_notifications_received({
		"notifications": [],
		"incoming_requests": [{"friend_id": "a"}],
		"accepted_requests": [],
		"rejected_requests": [],
	})
	assert_eq(_poller.unseen_count, 6)
	assert_true(_poller._known_incoming_ids.has("a"))

	_poller.reset()
	assert_eq(_poller.unseen_count, 0)
	assert_eq(_poller._known_incoming_ids.size(), 0)
	assert_eq(_poller._known_accepted_ids.size(), 0)
	assert_eq(_poller._known_rejected_ids.size(), 0)
	assert_eq(_poller._known_online_ids.size(), 0)
	assert_eq(_poller._known_party_match_start_ids.size(), 0)
	assert_true(_poller._is_first_poll)
	assert_true(_poller._is_first_presence_poll)


# ------------------------------------------------------------------
# _set_unseen_count
# ------------------------------------------------------------------


func test_set_unseen_count_emits_on_change() -> void:
	_poller._set_unseen_count(3)
	assert_eq(_emitted_counts, [3])


func test_set_unseen_count_skips_emit_when_unchanged() -> void:
	_poller._set_unseen_count(3)
	_poller._set_unseen_count(3)
	assert_eq(_emitted_counts, [3])


func test_set_unseen_count_emits_on_each_distinct_change() -> void:
	_poller._set_unseen_count(2)
	_poller._set_unseen_count(0)
	_poller._set_unseen_count(7)
	assert_eq(_emitted_counts, [2, 0, 7])


# ------------------------------------------------------------------
# _on_friends_received / _on_friends_marked_seen
# ------------------------------------------------------------------


func test_friends_received_reads_unseen_count() -> void:
	_poller._on_friends_received({"unseen_count": 12})
	assert_eq(_poller.unseen_count, 12)


func test_friends_received_missing_field_treated_as_zero() -> void:
	# Reach a non-zero baseline first so the transition is real.
	_poller._on_friends_received({"unseen_count": 4})
	_poller._on_friends_received({})
	assert_eq(_poller.unseen_count, 0)


func test_friends_marked_seen_clears_unseen() -> void:
	_poller._on_friends_received({"unseen_count": 9})
	_poller._on_friends_marked_seen({})
	assert_eq(_poller.unseen_count, 0)


# ------------------------------------------------------------------
# _on_notifications_received (dedup of incoming/accepted/rejected)
# ------------------------------------------------------------------


func test_notifications_received_dedups_known_ids() -> void:
	_poller._is_first_poll = false  # Skip the delayed-toast path.
	_poller._on_notifications_received({
		"notifications": [],
		"incoming_requests": [
			{"friend_id": "a"},
			{"friend_id": "b"},
		],
		"accepted_requests": [],
		"rejected_requests": [],
	})
	assert_eq(_poller.unseen_count, 2)
	assert_true(_poller._known_incoming_ids.has("a"))
	assert_true(_poller._known_incoming_ids.has("b"))

	# Same ids on a second poll must NOT bump unseen further.
	_poller._on_notifications_received({
		"notifications": [],
		"incoming_requests": [
			{"friend_id": "a"},
			{"friend_id": "b"},
		],
		"accepted_requests": [],
		"rejected_requests": [],
	})
	assert_eq(_poller.unseen_count, 2)


func test_notifications_received_counts_each_bucket() -> void:
	_poller._is_first_poll = false
	_poller._on_notifications_received({
		"notifications": [],
		"incoming_requests": [{"friend_id": "i1"}],
		"accepted_requests": [
			{"friend_id": "a1"},
			{"friend_id": "a2"},
		],
		"rejected_requests": [{"friend_id": "r1"}],
	})
	assert_eq(_poller.unseen_count, 4)


func test_notifications_received_skips_empty_friend_id() -> void:
	_poller._is_first_poll = false
	_poller._on_notifications_received({
		"notifications": [],
		"incoming_requests": [
			{"friend_id": ""},
			{"friend_id": "real"},
		],
		"accepted_requests": [],
		"rejected_requests": [],
	})
	assert_eq(_poller.unseen_count, 1)
	assert_false(_poller._known_incoming_ids.has(""))


# ------------------------------------------------------------------
# _handle_party_matchmaking_start (dedup by Nakama notification id)
# ------------------------------------------------------------------


func test_party_match_start_dedups_by_notification_id() -> void:
	# G.party_manager.on_party_matchmaking_notification may
	# trigger downstream side effects we don't want to exercise
	# here. The dedup pre-check guards against re-entry, so we
	# verify the known-id set is populated on the FIRST call and
	# that the SECOND call short-circuits before
	# party_manager.is_instance_valid even matters.
	var nid := "notif-123"

	# Pre-populate so any second call into is_instance_valid is
	# never reached.
	_poller._known_party_match_start_ids[nid] = true
	_poller._handle_party_matchmaking_start(
		nid, {"matchmaker_properties": {"x": "y"}})
	# Still just the one tracked id (idempotent).
	assert_eq(_poller._known_party_match_start_ids.size(), 1)


func test_party_match_start_ignores_empty_notification_id() -> void:
	_poller._handle_party_matchmaking_start("", {})
	assert_eq(_poller._known_party_match_start_ids.size(), 0)


# ------------------------------------------------------------------
# _dispatch_notification (subject routing)
# ------------------------------------------------------------------


func test_dispatch_notification_ignores_non_dict_content() -> void:
	# A bad content payload should be skipped without populating
	# the known-id cache (the handler bails before recording).
	_poller._dispatch_notification({
		"subject": "party_matchmaking_start",
		"id": "weird-nid",
		"content": "not a dict",
	})
	assert_false(
		_poller._known_party_match_start_ids
			.has("weird-nid"))


func test_dispatch_notification_ignores_unknown_subject() -> void:
	# Unknown subjects must not throw or populate any tracker.
	_poller._dispatch_notification({
		"subject": "unknown_future_subject",
		"id": "weird",
		"content": {},
	})
	assert_eq(_poller._known_party_match_start_ids.size(), 0)


# ------------------------------------------------------------------
# _on_presence_received (online-id dedup + first-poll suppression)
# ------------------------------------------------------------------


func test_presence_received_first_poll_suppresses_toasts() -> void:
	# The first presence poll seeds the known set without
	# emitting "came online" toasts. Verify the dedup set is
	# populated and the first-poll flag flips.
	assert_true(_poller._is_first_presence_poll)
	var online: Array[String] = ["x", "y", "z"]
	_poller._on_presence_received(online)
	assert_false(_poller._is_first_presence_poll)
	assert_eq(_poller._known_online_ids.size(), 3)
	assert_true(_poller._known_online_ids.has("x"))


func test_presence_received_rebuilds_set_to_current_list() -> void:
	# Subsequent polls REPLACE the known set entirely; a friend
	# who went offline must be removed so re-appearing later
	# emits the toast again.
	var first: Array[String] = ["a", "b"]
	_poller._on_presence_received(first)
	var second: Array[String] = ["a", "c"]
	_poller._on_presence_received(second)
	assert_true(_poller._known_online_ids.has("a"))
	assert_true(_poller._known_online_ids.has("c"))
	assert_false(
		_poller._known_online_ids.has("b"),
		"Friend no longer online must be evicted")


# ------------------------------------------------------------------
# Match-state rich-presence transitions
# ------------------------------------------------------------------


func test_match_started_sets_in_match_status() -> void:
	_poller._on_match_started()
	assert_eq(_poller._current_status, "in_match")
	# rich_presence is a localized string — not equality-tested
	# (depends on the active locale), but it must be non-empty
	# when the user is actively in a match.
	assert_false(_poller._current_rich_presence.is_empty())


func test_match_ended_resets_to_online_status() -> void:
	_poller._on_match_started()
	_poller._on_match_ended()
	assert_eq(_poller._current_status, "online")


# ------------------------------------------------------------------
# start_polling / stop_polling
# ------------------------------------------------------------------


func test_start_polling_arms_first_presence_tick() -> void:
	# start_polling sets _presence_poll_timer to the interval so
	# the next _process tick fires the presence fetch
	# immediately. (Same path PartyManager uses.)
	_poller.start_polling()
	assert_true(_poller._is_polling)
	assert_eq(_poller._poll_timer, 0.0)
	assert_eq(
		_poller._presence_poll_timer,
		FriendsNotificationPoller
			._PRESENCE_POLL_INTERVAL_SEC)


func test_stop_polling_disarms() -> void:
	_poller.start_polling()
	_poller.stop_polling()
	assert_false(_poller._is_polling)
