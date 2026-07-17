extends GutTest
## Contract tests binding FriendsNotificationPoller to the payload
## shapes PlatformFriendsApiClient actually emits.
##
## The sibling test_friends_notification_poller.gd feeds the handlers
## hand-built dicts (`incoming_requests` / `unseen_count`). Those keys
## are not produced by any emitter in the codebase, so those tests can
## pass while the production path is dead. These tests instead replay
## the literal emit payloads from
## addons/snoringcat_platform_client/core/friends_api_client.gd and
## assert the badge / toast side effects the UI depends on.


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
# fetch_friends() emit shape — friends_api_client.gd:112-116
# ------------------------------------------------------------------


## Replays the exact dict fetch_friends() emits when the viewer has
## one incoming friend request pending.
func _real_friends_received_payload() -> Dictionary:
	return {
		"friends": [],
		"sent_requests": [],
		"incoming_requests": [{
			"player_id": "requester-1",
			"display_name": "Requester",
			"username": "REQ001",
			"avatar_url": "",
			"online": true,
		}],
	}


func test_friends_received_real_shape_surfaces_pending_request() -> void:
	_poller._on_friends_received(
		_real_friends_received_payload())
	assert_eq(
		_poller.unseen_count, 1,
		"one pending incoming request should badge as 1 unseen")


func test_friends_received_real_shape_does_not_clobber_badge() -> void:
	_poller._set_unseen_count(3)
	_emitted_counts.clear()
	_poller._on_friends_received(
		_real_friends_received_payload())
	assert_ne(
		_poller.unseen_count, 0,
		"a friends refresh must not silently zero the badge")


# ------------------------------------------------------------------
# fetch_notifications() emit shape — friends_api_client.gd:245-248
# ------------------------------------------------------------------


## Replays the exact dict fetch_notifications() emits carrying
## Nakama's built-in friend-request notification (code -2). Nakama
## sets `subject` to a human sentence, so `code` is the only stable
## discriminator.
func _real_notifications_payload() -> Dictionary:
	return {
		"notifications": [{
			"id": "notif-1",
			"subject": "Requester wants to add you as a friend.",
			"content": {"username": "REQ001"},
			"sender_id": "requester-1",
			"create_time": 1,
			"persistent": true,
			"code": -2,
		}],
		"cacheable_cursor": "",
	}


func test_notifications_real_shape_is_recognized() -> void:
	_poller._is_first_poll = false
	_poller._on_notifications_received(
		_real_notifications_payload())
	assert_eq(
		_poller._pending_friend_toasts.size(), 1,
		"an inbound friend-request notification should be"
		+ " recognized and queued for a toast")


func test_notifications_real_shape_dedups_by_id() -> void:
	_poller._is_first_poll = false
	_poller._on_notifications_received(
		_real_notifications_payload())
	_poller._on_notifications_received(
		_real_notifications_payload())
	assert_eq(
		_poller._known_friend_event_ids.size(), 1,
		"re-polling the same notification must not double-count")
