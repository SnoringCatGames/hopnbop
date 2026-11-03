extends GutTest
## Unit tests for FriendsNotificationPoller across sign-outs and
## sign-ins.
##
## Log-out stopped the poller and nothing started it again, so friend
## requests, accepts, and "came online" toasts stayed silent until the
## game was relaunched. These tests sign a player out and back in, as
## a guest and with a provider, and count the requests the poller
## makes. They also check that nothing from the old session reaches
## the new one: late responses, pushes, and a toast batch that was
## waiting out its delay.
##
## The poller under test is added to the tree so _ready connects it,
## then its _process is paused and driven by hand. Platform's auth,
## friends, presence, notification socket, and token store are swapped
## for fakes, and the live poller and auth node are paused meanwhile.


const _POLL_INTERVAL_SEC := FriendsNotificationPoller._POLL_INTERVAL_SEC
const _FIRST_TOAST_DELAY_SEC := (
	FriendsNotificationPoller._FIRST_POLL_TOAST_DELAY_SEC)
## Waits past the first batch's delay.
const _TOAST_DELAY_SLACK_SEC := 0.3
const _TEST_AUTH_FILE := "user://test_friends_poller_lifecycle.cfg"
const _SESSION_LIFETIME_SEC := 7200
const _SIGN_OUT_CYCLES := 5
const _SENDER_ID := "sender-1"
const _SENDER_NAME := "Requester"


## Stands in for Platform.friends: counts requests, sends none.
## With is_emitting_canned set, a fetch answers at once with
## canned_notifications, as a stored backlog would. With
## canned_pages set, each fetch answers with the next page
## instead, so a backlog can span pages without the fake
## answering a full page forever.
class FakeFriends extends PlatformFriendsApiClient:
	var notification_fetches := 0
	var friends_fetches := 0
	var canned_notifications: Array = []
	var is_emitting_canned := false
	var is_poll_busy_fake := false
	## Each entry is one notifications_received payload.
	var canned_pages: Array[Dictionary] = []
	## The cursor each notification fetch asked for.
	var fetched_cursors: Array[String] = []

	func fetch_notifications(
		_limit: int = 50,
		cacheable_cursor: String = "",
	) -> void:
		notification_fetches += 1
		fetched_cursors.append(cacheable_cursor)
		if not canned_pages.is_empty():
			notifications_received.emit(canned_pages.pop_front())
		elif is_emitting_canned:
			notifications_received.emit({
				"notifications": canned_notifications.duplicate(),
				"cacheable_cursor": "",
			})

	func fetch_friends() -> void:
		friends_fetches += 1

	func is_busy() -> bool:
		return false

	func is_poll_busy() -> bool:
		return is_poll_busy_fake


## Stands in for Platform.presence: counts heartbeats, sends none.
class FakePresence extends PlatformPresenceApiClient:
	var presence_fetches := 0

	func fetch_presence(
		_rich_presence: String = "",
		_status: String = STATUS_ONLINE,
		_include_other_games: bool = true,
	) -> void:
		presence_fetches += 1

	func is_presence_busy() -> bool:
		return false


## Stands in for Platform.notification_socket: reports the
## connection state a test chooses.
class FakeSocket extends PlatformNotificationSocketClient:
	var is_connected_fake := false

	func is_socket_connected() -> bool:
		return is_connected_fake


## Stands in for G.toast_overlay: records toasts instead of showing
## them.
class FakeToastOverlay extends ToastOverlay:
	var messages: Array[String] = []

	func show_toast(message: String, _type: Type = Type.INFO) -> void:
		messages.append(message)


const _TEST_SEEN_PATH := (
	"user://test_friends_poller_lifecycle_seen.cfg")

var _poller: FriendsNotificationPoller
var _client: PlatformAuthApiClient
var _friends: FakeFriends
var _presence: FakePresence
var _socket: FakeSocket
var _toasts: FakeToastOverlay
var _store: PlatformAuthTokenStore
var _original_auth
var _original_friends
var _original_presence
var _original_socket
var _original_token_store
var _original_toast_overlay: ToastOverlay
var _was_live_poller_processing := false
var _was_original_auth_processing := false


func before_each() -> void:
	_original_auth = Platform.auth
	_original_friends = Platform.friends
	_original_presence = Platform.presence
	_original_socket = Platform.notification_socket
	_original_token_store = Platform.token_store
	_original_toast_overlay = G.toast_overlay
	_was_original_auth_processing = _original_auth.is_processing()
	_original_auth.set_process(false)
	_was_live_poller_processing = (
		G.friends_notification_poller.is_processing())
	G.friends_notification_poller.set_process(false)

	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	Platform.token_store = _store
	# None of these enter the tree, so their own _ready never runs.
	_client = PlatformAuthApiClient.new()
	Platform.register_subsystem("auth", _client)
	_friends = FakeFriends.new()
	Platform.register_subsystem("friends", _friends)
	_presence = FakePresence.new()
	Platform.register_subsystem("presence", _presence)
	_socket = FakeSocket.new()
	Platform.register_subsystem("notification_socket", _socket)
	_toasts = FakeToastOverlay.new()
	G.toast_overlay = _toasts

	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_TEST_SEEN_PATH))
	_poller = FriendsNotificationPoller.new()
	_poller.seen_toasts_path = _TEST_SEEN_PATH
	add_child_autofree(_poller)
	_poller.set_process(false)
	# What G does at boot.
	_poller.start_polling()


func after_each() -> void:
	Platform.register_subsystem("auth", _original_auth)
	Platform.register_subsystem("friends", _original_friends)
	Platform.register_subsystem("presence", _original_presence)
	Platform.register_subsystem("notification_socket", _original_socket)
	Platform.token_store = _original_token_store
	G.toast_overlay = _original_toast_overlay
	_original_auth.set_process(_was_original_auth_processing)
	G.friends_notification_poller.set_process(_was_live_poller_processing)
	_client.free()
	_friends.free()
	_presence.free()
	_socket.free()
	_toasts.free()
	# Deletes the test auth file if a test saved one.
	_store.clear_tokens()
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_TEST_SEEN_PATH))


# ------------------------------------------------------------------
# Sign-out and sign-in
# ------------------------------------------------------------------


func test_polls_a_signed_in_player() -> void:
	_sign_in_with_provider()

	_tick(_POLL_INTERVAL_SEC)

	# The sign-in drain (H134) plus one tick poll.
	assert_eq(_friends.notification_fetches, 2)
	assert_eq(_presence.presence_fetches, 1, "heartbeat on the first tick")


func test_sign_out_stops_polling() -> void:
	_sign_in_with_provider()
	_sign_out()
	# Even with a usable session in the store, a stopped poller stays
	# quiet: the stop does it, not the token check.
	_store_provider_session()

	_tick(_POLL_INTERVAL_SEC)

	assert_false(_poller._is_polling)
	# Only the drain from the sign-in before the sign-out.
	assert_eq(_friends.notification_fetches, 1)
	assert_eq(_presence.presence_fetches, 0)


func test_provider_sign_in_after_log_out_polls_again() -> void:
	_sign_in_with_provider()
	_sign_out()

	_sign_in_with_provider()
	_tick(_POLL_INTERVAL_SEC)

	assert_true(_poller._is_polling)
	# A drain at each sign-in (H134) plus one tick poll.
	assert_eq(_friends.notification_fetches, 3)
	assert_eq(_presence.presence_fetches, 1, "heartbeat on the first tick")
	assert_eq(_friends.friends_fetches, 2, "friends prefetched per sign-in")


func test_guest_sign_in_after_log_out_restarts_the_poller() -> void:
	_sign_in_with_provider()
	_sign_out()
	# Count only what the guest phase does.
	_friends.notification_fetches = 0

	_sign_in_as_guest()
	_tick(_POLL_INTERVAL_SEC)

	assert_true(_poller._is_polling, "running again")
	assert_eq(_friends.notification_fetches, 0, "guests have no friends")
	assert_eq(_presence.presence_fetches, 0)

	# The guest then signs in with a provider.
	_sign_in_with_provider()
	_tick(_POLL_INTERVAL_SEC)

	# The provider sign-in drain (H134) plus one tick poll.
	assert_eq(_friends.notification_fetches, 2)
	assert_eq(_presence.presence_fetches, 1)


func test_failed_sign_in_leaves_the_poller_stopped() -> void:
	_sign_in_with_provider()
	_sign_out()

	_client.auth_completed.emit(false, "Sign-in cancelled")

	assert_false(_poller._is_polling)


func test_token_refresh_keeps_the_schedule() -> void:
	_sign_in_with_provider()
	_tick(_POLL_INTERVAL_SEC - 1.0)
	var poll_timer := _poller._poll_timer
	var presence_timer := _poller._presence_poll_timer

	# A refresh completes another sign-in.
	_client.auth_completed.emit(true, "")

	assert_eq(_poller._poll_timer, poll_timer, "notification timer kept")
	assert_eq(
		_poller._presence_poll_timer, presence_timer, "heartbeat timer kept")
	_tick(1.0)
	# Drains at sign-in and at the refresh (H134), plus
	# the one tick poll.
	assert_eq(_friends.notification_fetches, 3, "one poll per interval")


func test_repeated_cycles_neither_double_nor_leak() -> void:
	for cycle in range(_SIGN_OUT_CYCLES):
		if cycle % 2 == 0:
			_sign_in_as_guest()
		else:
			_sign_in_with_provider()
		_sign_out()
	_sign_in_with_provider()

	_tick(_POLL_INTERVAL_SEC)

	# Provider sign-in drains (H134; two in the cycles,
	# one at the end) plus one tick poll.
	assert_eq(_friends.notification_fetches, 4, "one poll per interval")
	assert_eq(_presence.presence_fetches, 1, "one heartbeat")
	assert_eq(
		_count_connections(_client.auth_completed), 1, "one sign-in hook")
	assert_eq(
		_count_connections(_friends.notifications_received),
		1,
		"one notification hook",
	)
	assert_eq(
		_count_connections(_socket.notification_received),
		1,
		"one socket hook",
	)
	assert_eq(_poller._known_friend_event_ids.size(), 0)
	assert_eq(_poller.unseen_count, 0)


# ------------------------------------------------------------------
# Nothing from the old session reaches the next
# ------------------------------------------------------------------


func test_drops_a_late_poll_response_after_sign_out() -> void:
	_sign_in_with_provider()
	_sign_out()

	_friends.notifications_received.emit(
		{"notifications": [_friend_request("n1")]})

	assert_eq(_poller._pending_friend_toasts.size(), 0)
	assert_eq(_poller._known_friend_event_ids.size(), 0)
	assert_eq(_friends.friends_fetches, 1, "only the sign-in prefetch")


func test_drops_a_socket_push_after_sign_out() -> void:
	_sign_in_with_provider()
	_sign_out()

	_socket.notification_received.emit(_friend_request("n1"))

	assert_eq(_poller._pending_friend_toasts.size(), 0)
	assert_eq(_poller._known_friend_event_ids.size(), 0)


func test_drops_late_friends_and_presence_after_sign_out() -> void:
	_sign_in_with_provider()
	_sign_out()

	_friends.friends_received.emit({
		"incoming_requests": [{"player_id": _SENDER_ID}],
	})
	var online: Array[String] = [_SENDER_ID]
	_presence.presence_received.emit(online)

	assert_eq(_poller.unseen_count, 0, "no badge for the old account")
	assert_eq(_poller._known_online_ids.size(), 0)


func test_first_toast_batch_shows_after_its_delay() -> void:
	_sign_in_with_provider()
	_queue_friend_request_toast()

	await get_tree().create_timer(
		_FIRST_TOAST_DELAY_SEC + _TOAST_DELAY_SLACK_SEC).timeout

	assert_eq(_toasts.messages.size(), 1)
	assert_string_contains(_toasts.messages[0], _SENDER_NAME)


func test_sign_out_drops_a_waiting_toast_batch() -> void:
	_sign_in_with_provider()
	_queue_friend_request_toast()

	# Signed out, and signed straight back in, while the batch waits.
	_sign_out()
	_sign_in_with_provider()
	await get_tree().create_timer(
		_FIRST_TOAST_DELAY_SEC + _TOAST_DELAY_SLACK_SEC).timeout

	assert_eq(_toasts.messages.size(), 0, "\n".join(_toasts.messages))


func test_toast_id_is_persisted_only_after_the_toast_shows() -> void:
	_sign_in_with_provider()
	_queue_friend_request_toast()

	assert_true(
		_a_fresh_poller_can_queue("n1"),
		"queued but not yet shown is not persisted as seen")

	await get_tree().create_timer(
		_FIRST_TOAST_DELAY_SEC + _TOAST_DELAY_SLACK_SEC).timeout

	assert_eq(_toasts.messages.size(), 1)
	assert_false(
		_a_fresh_poller_can_queue("n1"),
		"shown is persisted as seen for the next launch")


func test_the_same_toast_can_show_for_another_account() -> void:
	_sign_in_with_provider("account-a")
	_queue_friend_request_toast()
	await get_tree().create_timer(
		_FIRST_TOAST_DELAY_SEC + _TOAST_DELAY_SLACK_SEC).timeout
	assert_eq(_toasts.messages.size(), 1)

	_sign_out()
	_sign_in_with_provider("account-b")
	_queue_friend_request_toast()
	await get_tree().create_timer(
		_FIRST_TOAST_DELAY_SEC + _TOAST_DELAY_SLACK_SEC).timeout

	assert_eq(
		_toasts.messages.size(), 2,
		"account A's seen ids do not hide account B's toast")


func test_a_toast_whose_sender_name_misses_can_show_later() -> void:
	_sign_in_with_provider()
	# The sender is in no cache, so the first flush drops it.
	_friends.notifications_received.emit(
		{"notifications": [_friend_request("n1")]})
	_friends.friends_received.emit({"incoming_requests": []})
	await get_tree().create_timer(
		_FIRST_TOAST_DELAY_SEC + _TOAST_DELAY_SLACK_SEC).timeout
	assert_eq(_toasts.messages.size(), 0)

	_cache_the_sender()
	_socket.notification_received.emit(_friend_request("n1"))
	_friends.friends_received.emit({
		"incoming_requests": [{"player_id": _SENDER_ID}],
	})
	await get_tree().create_timer(0.2).timeout

	assert_eq(_toasts.messages.size(), 1)


func _a_fresh_poller_can_queue(notification_id: String) -> bool:
	var fresh := FriendsNotificationPoller.new()
	fresh.seen_toasts_path = _TEST_SEEN_PATH
	fresh._load_seen_toasts()
	var can_queue := fresh._queue_friend_toast(
		_friend_request(notification_id))
	fresh.free()
	return can_queue


# ------------------------------------------------------------------
# Offline backlog drains (H134) and stale responses (H54-2)
# ------------------------------------------------------------------


func test_sign_in_drains_the_backlog_with_a_healthy_socket() -> void:
	_socket.is_connected_fake = true
	_cache_the_sender()
	_friends.canned_notifications = [_friend_request("n1")]
	_friends.is_emitting_canned = true

	_sign_in_with_provider()
	await _flush_the_queued_toasts()

	assert_gt(
		_friends.notification_fetches, 0, "sign-in listed the backlog")
	assert_eq(_toasts.messages.size(), 1)
	assert_string_contains(_toasts.messages[0], _SENDER_NAME)


func test_reconnect_drains_the_backlog() -> void:
	_sign_in_with_provider()
	var fetches_at_sign_in := _friends.notification_fetches
	_cache_the_sender()
	_friends.canned_notifications = [_friend_request("n1")]
	_friends.is_emitting_canned = true

	_socket.socket_connected.emit()
	await _flush_the_queued_toasts()

	assert_gt(
		_friends.notification_fetches,
		fetches_at_sign_in,
		"the reconnect listed the backlog",
	)
	assert_eq(_toasts.messages.size(), 1)


func test_backlog_event_toasts_once_across_list_and_socket() -> void:
	_cache_the_sender()
	_friends.canned_notifications = [_friend_request("n1")]
	_friends.is_emitting_canned = true

	_sign_in_with_provider()
	_socket.notification_received.emit(_friend_request("n1"))
	await _flush_the_queued_toasts()

	assert_eq(_toasts.messages.size(), 1, "one toast for one event")


func test_full_page_lists_the_next_page_until_a_short_one() -> void:
	_cache_the_sender()
	var full_page: Array = []
	for index in FriendsNotificationPoller._NOTIFICATION_PAGE_SIZE:
		full_page.append(_friend_request("n%d" % index))
	_friends.canned_pages.assign([
		{"notifications": full_page, "cacheable_cursor": "page-2"},
		{
			"notifications": [_friend_request("last")],
			"cacheable_cursor": "page-3",
		},
	])

	_sign_in_with_provider()

	assert_eq(
		_friends.fetched_cursors,
		["", "page-2"] as Array[String],
		"a full page lists the next one, and a short page stops",
	)
	assert_eq(_poller._notification_cursor, "page-3")


func test_full_page_with_a_repeated_cursor_stops_paging() -> void:
	var first_page := _full_notification_page("a")
	var second_page := _full_notification_page("b")
	_friends.canned_pages.assign([
		{"notifications": first_page, "cacheable_cursor": "same"},
		{"notifications": second_page, "cacheable_cursor": "same"},
	])

	_sign_in_with_provider()

	assert_eq(
		_friends.notification_fetches, 2,
		"a repeated cursor ends the drain instead of paging forever")
	assert_eq(
		_friends.fetched_cursors,
		["", "same"] as Array[String])


func test_paging_stops_after_the_page_cap_for_one_poll() -> void:
	var pages: Array[Dictionary] = []
	for page_index in range(15):
		pages.append({
			"notifications": _full_notification_page(
				"p%d" % page_index),
			"cacheable_cursor": "cursor-%d" % (page_index + 1),
		})
	_friends.canned_pages.assign(pages)

	_sign_in_with_provider()

	assert_eq(
		_friends.notification_fetches, 10,
		"one poll drains at most the page cap")
	assert_eq(_poller._notification_cursor, "cursor-10")


func _full_notification_page(prefix: String) -> Array:
	var page: Array = []
	for index in FriendsNotificationPoller._NOTIFICATION_PAGE_SIZE:
		page.append({
			"id": "%s-%d" % [prefix, index],
			"code": 0,
			"sender_id": _SENDER_ID,
		})
	return page


func test_sign_in_drain_waits_out_a_stale_fetch_then_runs() -> void:
	_friends.is_poll_busy_fake = true

	_sign_in_with_provider()

	assert_eq(
		_friends.notification_fetches, 0,
		"the stale fetch blocks the drain while it is in flight")

	_friends.is_poll_busy_fake = false
	_tick(0.1)

	assert_eq(
		_friends.notification_fetches, 1,
		"the drain runs once the stale fetch clears")


func test_a_pending_drain_does_not_run_after_sign_out() -> void:
	_friends.is_poll_busy_fake = true
	_sign_in_with_provider()
	_sign_out()
	_friends.is_poll_busy_fake = false

	_tick(0.1)

	assert_eq(_friends.notification_fetches, 0)


func test_late_list_response_keeps_the_new_sessions_cursor() -> void:
	_sign_in_with_provider()
	_sign_out()
	_store_provider_session()
	_poller.start_polling()

	_friends.notifications_received.emit({
		"notifications": [],
		"cacheable_cursor": "old-account-cursor",
	})

	assert_eq(_poller._notification_cursor, "")


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


## What SignOutRouter.clear_session_state does to the poller, plus the
## credentials a sign-out clears.
func _sign_out() -> void:
	_poller.stop_polling()
	_poller.reset()
	_store.clear_tokens()


func _sign_in_with_provider(
	player_id: String = "test-player",
) -> void:
	_store_provider_session(player_id)
	_client.auth_completed.emit(true, "")


func _sign_in_as_guest() -> void:
	_store.is_anonymous = true
	_store.display_name = "Guest"
	_client.auth_completed.emit(true, "")


func _store_provider_session(
	player_id: String = "test-player",
) -> void:
	_store.is_anonymous = false
	_store.provider = "google"
	_store.player_id = player_id
	_store.jwt_token = "test-access-token"
	_store.refresh_token = "test-refresh-token"
	_store.expires_at = (
		int(Time.get_unix_time_from_system()) + _SESSION_LIFETIME_SEC)


func _tick(delta: float) -> void:
	_poller._process(delta)


## Caches the toast sender so its display name resolves.
func _cache_the_sender() -> void:
	_friends.cached_incoming_requests.assign([{
		"player_id": _SENDER_ID,
		"display_name": _SENDER_NAME,
	}])


## Delivers the friend list that flushes queued toasts, then
## waits out the first batch's delay.
func _flush_the_queued_toasts() -> void:
	_friends.friends_received.emit({
		"incoming_requests": [{"player_id": _SENDER_ID}],
	})
	await get_tree().create_timer(
		_FIRST_TOAST_DELAY_SEC + _TOAST_DELAY_SLACK_SEC).timeout


## A friend request arrives and the friend list that resolves its
## sender's name comes back, so the first batch starts its delay.
func _queue_friend_request_toast() -> void:
	_friends.cached_incoming_requests.assign([{
		"player_id": _SENDER_ID,
		"display_name": _SENDER_NAME,
	}])
	_friends.notifications_received.emit(
		{"notifications": [_friend_request("n1")]})
	_friends.friends_received.emit({
		"incoming_requests": [{"player_id": _SENDER_ID}],
	})


func _friend_request(notification_id: String) -> Dictionary:
	return {
		"id": notification_id,
		"subject": "Requester wants to add you as a friend.",
		"code": PlatformFriendsApiClient.CODE_FRIEND_REQUEST_RECEIVED,
		"content": {},
		"sender_id": _SENDER_ID,
		"create_time": 1,
		"persistent": true,
	}


func _count_connections(target_signal: Signal) -> int:
	var count := 0
	for connection: Dictionary in target_signal.get_connections():
		var callable: Callable = connection["callable"]
		if callable.get_object() == _poller:
			count += 1
	return count
