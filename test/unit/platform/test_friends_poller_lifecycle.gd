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
class FakeFriends extends PlatformFriendsApiClient:
	var notification_fetches := 0
	var friends_fetches := 0

	func fetch_notifications(
		_limit: int = 50,
		_cacheable_cursor: String = "",
	) -> void:
		notification_fetches += 1

	func fetch_friends() -> void:
		friends_fetches += 1

	func is_busy() -> bool:
		return false

	func is_poll_busy() -> bool:
		return false


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


## Stands in for G.toast_overlay: records toasts instead of showing
## them.
class FakeToastOverlay extends ToastOverlay:
	var messages: Array[String] = []

	func show_toast(message: String, _type: Type = Type.INFO) -> void:
		messages.append(message)


var _poller: FriendsNotificationPoller
var _client: PlatformAuthApiClient
var _friends: FakeFriends
var _presence: FakePresence
var _socket: PlatformNotificationSocketClient
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
	_socket = PlatformNotificationSocketClient.new()
	Platform.register_subsystem("notification_socket", _socket)
	_toasts = FakeToastOverlay.new()
	G.toast_overlay = _toasts

	_poller = FriendsNotificationPoller.new()
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


# ------------------------------------------------------------------
# Sign-out and sign-in
# ------------------------------------------------------------------


func test_polls_a_signed_in_player() -> void:
	_sign_in_with_provider()

	_tick(_POLL_INTERVAL_SEC)

	assert_eq(_friends.notification_fetches, 1)
	assert_eq(_presence.presence_fetches, 1, "heartbeat on the first tick")


func test_sign_out_stops_polling() -> void:
	_sign_in_with_provider()
	_sign_out()
	# Even with a usable session in the store, a stopped poller stays
	# quiet: the stop does it, not the token check.
	_store_provider_session()

	_tick(_POLL_INTERVAL_SEC)

	assert_false(_poller._is_polling)
	assert_eq(_friends.notification_fetches, 0)
	assert_eq(_presence.presence_fetches, 0)


func test_provider_sign_in_after_log_out_polls_again() -> void:
	_sign_in_with_provider()
	_sign_out()

	_sign_in_with_provider()
	_tick(_POLL_INTERVAL_SEC)

	assert_true(_poller._is_polling)
	assert_eq(_friends.notification_fetches, 1)
	assert_eq(_presence.presence_fetches, 1, "heartbeat on the first tick")
	assert_eq(_friends.friends_fetches, 2, "friends prefetched per sign-in")


func test_guest_sign_in_after_log_out_restarts_the_poller() -> void:
	_sign_in_with_provider()
	_sign_out()

	_sign_in_as_guest()
	_tick(_POLL_INTERVAL_SEC)

	assert_true(_poller._is_polling, "running again")
	assert_eq(_friends.notification_fetches, 0, "guests have no friends")
	assert_eq(_presence.presence_fetches, 0)

	# The guest then signs in with a provider.
	_sign_in_with_provider()
	_tick(_POLL_INTERVAL_SEC)

	assert_eq(_friends.notification_fetches, 1)
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
	assert_eq(_friends.notification_fetches, 1, "one poll per interval")


func test_repeated_cycles_neither_double_nor_leak() -> void:
	for cycle in range(_SIGN_OUT_CYCLES):
		if cycle % 2 == 0:
			_sign_in_as_guest()
		else:
			_sign_in_with_provider()
		_sign_out()
	_sign_in_with_provider()

	_tick(_POLL_INTERVAL_SEC)

	assert_eq(_friends.notification_fetches, 1, "one poll per interval")
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


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


## What SignOutRouter.clear_session_state does to the poller, plus the
## credentials a sign-out clears.
func _sign_out() -> void:
	_poller.stop_polling()
	_poller.reset()
	_store.clear_tokens()


func _sign_in_with_provider() -> void:
	_store_provider_session()
	_client.auth_completed.emit(true, "")


func _sign_in_as_guest() -> void:
	_store.is_anonymous = true
	_store.display_name = "Guest"
	_client.auth_completed.emit(true, "")


func _store_provider_session() -> void:
	_store.is_anonymous = false
	_store.provider = "google"
	_store.player_id = "test-player"
	_store.jwt_token = "test-access-token"
	_store.refresh_token = "test-refresh-token"
	_store.expires_at = (
		int(Time.get_unix_time_from_system()) + _SESSION_LIFETIME_SEC)


func _tick(delta: float) -> void:
	_poller._process(delta)


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
