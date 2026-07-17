class_name FriendsNotificationPoller
extends Node
## Polls for friend notifications (incoming
## requests, accepted requests) and emits signals
## for toasts and badge updates. Follows the
## PartyManager polling pattern.


signal unseen_count_changed(count: int)

const _POLL_INTERVAL_SEC := 10.0
const _FIRST_POLL_TOAST_DELAY_SEC := 1.0
const _PRESENCE_POLL_INTERVAL_SEC := 30.0

var unseen_count := 0

var _poll_timer := 0.0
var _presence_poll_timer := 0.0
var _is_polling := false
var _is_first_poll := true
var _is_first_presence_poll := true

var _known_online_ids: Dictionary = {}
## Dedupe persistent `party_matchmaking_start` notifications so a
## follower doesn't re-enqueue every poll cycle. Keyed by Nakama
## notification id.
var _known_party_match_start_ids: Dictionary = {}
## Dedupe friend-event toasts across poll cycles and across the
## socket/HTTP delivery paths. Keyed by Nakama notification id.
## Nakama keeps friend notifications persistent until read, and we
## always re-list from a blank cursor, so the same id resurfaces on
## every poll.
var _known_friend_event_ids: Dictionary = {}
## Player ids whose pending friend request the user has already
## looked at. Subtracted from the pending-request count to produce
## `unseen_count`. In-memory only: on a fresh launch a still-
## pending request badges again, which is the behavior we want —
## it's an unresolved item, not a stale toast.
var _seen_request_ids: Dictionary = {}
## Friend events classified but not yet rendered, because a brand-
## new requester isn't in any local cache until the next
## fetch_friends lands. Flushed from `_on_friends_received` once
## the caches are warm enough to resolve a display name.
var _pending_friend_toasts: Array[Dictionary] = []

## Rich presence string surfaced on the friends UI of other
## players. Updated from match lifecycle signals; sent on the
## next presence heartbeat. Localized via tr() so the addon's
## consumer game owns the actual labels.
##
## `_current_status` is the machine-readable counterpart the
## runtime reasons about (visibility, "in a match" badging); the
## rich string is display-only and never parsed.
var _current_rich_presence := ""
var _current_status := PlatformPresenceApiClient.STATUS_ONLINE


func _ready() -> void:
	Platform.friends\
		.notifications_received.connect(
			_on_notifications_received)
	# Also update unseen count when the full
	# friends list is fetched.
	Platform.friends\
		.friends_received.connect(
			_on_friends_received)
	# Clear unseen state when user views friends.
	Platform.friends\
		.friends_marked_seen.connect(
			_on_friends_marked_seen)
	Platform.presence\
		.presence_received.connect(
			_on_presence_received)
	# Prefetch friends list on auth so the cache
	# is warm before the panel ever opens.
	Platform.auth.auth_completed.connect(
		_on_auth_completed)
	# Stage 5.4: party_matchmaking_start arrives over the long-lived
	# notification socket near-instantly. The 10 s HTTP poll below
	# stays as a fallback for socket-down windows; dedup by
	# Nakama notification id makes duplicate deliveries idempotent.
	Platform.notification_socket\
		.notification_received.connect(
			_on_socket_notification)
	# Track lobby/match transitions to feed the
	# rich-presence string sent on each heartbeat.
	# match_state may not exist yet on first ready
	# in some test contexts; defer the connection.
	call_deferred("_connect_match_state_signals")


func _connect_match_state_signals() -> void:
	if G.match_state == null:
		return
	if not G.match_state.match_started.is_connected(
		_on_match_started
	):
		G.match_state.match_started.connect(
			_on_match_started)
	if not G.match_state.match_ended.is_connected(
		_on_match_ended
	):
		G.match_state.match_ended.connect(
			_on_match_ended)


func _on_match_started() -> void:
	_current_rich_presence = tr("PRESENCE.IN_MATCH")
	_current_status = PlatformPresenceApiClient.STATUS_IN_MATCH
	# Push immediately rather than waiting out the heartbeat: the
	# lobby -> match transition is the one friends most want to see
	# promptly (it's the "can I still join them?" signal), and a
	# 30 s lag makes the badge feel broken.
	_request_immediate_presence_push()


func _on_match_ended() -> void:
	_current_rich_presence = tr("PRESENCE.IN_LOBBY")
	_current_status = PlatformPresenceApiClient.STATUS_ONLINE
	_request_immediate_presence_push()


## Force the next `_process` tick to send a presence heartbeat.
## Cheaper than calling fetch_presence directly here: it reuses the
## existing busy-guard and keeps a single call site.
func _request_immediate_presence_push() -> void:
	_presence_poll_timer = _PRESENCE_POLL_INTERVAL_SEC


func _process(delta: float) -> void:
	if not _is_polling:
		return
	if not Platform.token_store.is_token_valid():
		return
	if Platform.token_store.is_anonymous:
		return

	_poll_timer += delta
	if _poll_timer >= _POLL_INTERVAL_SEC:
		_poll_timer = 0.0
		if not Platform.friends.is_poll_busy():
			Platform.friends.fetch_notifications()

	_presence_poll_timer += delta
	if _presence_poll_timer >= _PRESENCE_POLL_INTERVAL_SEC:
		_presence_poll_timer = 0.0
		if not Platform.presence\
				.is_presence_busy():
			Platform.presence.fetch_presence(
				_current_rich_presence,
				_current_status,
			)


## Start polling for friend notifications and
## presence.
func start_polling() -> void:
	_is_polling = true
	_poll_timer = 0.0
	# Fire presence poll on the next process tick.
	_presence_poll_timer = _PRESENCE_POLL_INTERVAL_SEC


## Stop polling.
func stop_polling() -> void:
	_is_polling = false


## Reset state for a new session.
func reset() -> void:
	_is_first_poll = true
	_is_first_presence_poll = true
	_known_online_ids.clear()
	_known_party_match_start_ids.clear()
	_known_friend_event_ids.clear()
	_seen_request_ids.clear()
	_pending_friend_toasts.clear()
	_current_rich_presence = ""
	_current_status = PlatformPresenceApiClient.STATUS_ONLINE
	_set_unseen_count(0)


func _on_notifications_received(
	data: Dictionary,
) -> void:
	# PlatformFriendsApiClient.fetch_notifications emits the raw
	# Nakama notification list under the `notifications` key, and
	# nothing else — this handler previously read `incoming_requests`
	# / `accepted_requests` / `rejected_requests`, keys no emitter in
	# the codebase produces, so every friend toast and badge silently
	# no-opped.
	var notifications: Array = data.get(
		"notifications", [])
	var queued := 0
	for n in notifications:
		if not (n is Dictionary):
			continue
		_dispatch_notification(n)
		if _queue_friend_toast(n):
			queued += 1
	if queued == 0:
		return
	# Refresh the durable friend state. This both recomputes the
	# badge and warms the caches the queued toasts need to resolve a
	# display name; `_on_friends_received` flushes them.
	if not Platform.friends.is_busy():
		Platform.friends.fetch_friends()


## Dispatch a single Nakama notification to whichever manager owns
## it. Our runtime's own notifications carry a stable `subject`
## (and a non-negative `code`); Nakama's built-ins carry prose
## subjects and are routed on `code` by `_queue_friend_toast`.
func _dispatch_notification(n: Dictionary) -> void:
	var subj: String = n.get("subject", "")
	var nid: String = n.get("id", "")
	match subj:
		"party_matchmaking_start":
			var content_raw: Variant = n.get(
				"content", {})
			if not (content_raw is Dictionary):
				return
			_handle_party_matchmaking_start(
				nid, content_raw)


## Classify a Nakama notification as a friend event and queue a
## toast for it. Returns true when something was queued.
##
## Routes on `code`, not `subject`: Nakama's built-in friend
## notifications use a human-readable sentence as the subject ("X
## wants to add you as a friend"), which is not a stable contract.
## The `code` field is, and is now plumbed through by
## PlatformFriendsApiClient.fetch_notifications and the
## notification socket.
func _queue_friend_toast(n: Dictionary) -> bool:
	var nid: String = n.get("id", "")
	if nid.is_empty():
		return false
	if _known_friend_event_ids.has(nid):
		return false
	var key := _friend_toast_key(int(n.get("code", 0)))
	if key.is_empty():
		return false
	_known_friend_event_ids[nid] = true
	_pending_friend_toasts.append({
		"sender_id": str(n.get("sender_id", "")),
		"key": key,
	})
	return true


## Map a Nakama notification code onto a toast translation key.
## Returns "" for codes we don't surface.
func _friend_toast_key(code: int) -> String:
	match code:
		PlatformFriendsApiClient.CODE_FRIEND_REQUEST_RECEIVED:
			return "FRIENDS.REQUEST_RECEIVED"
		PlatformFriendsApiClient.CODE_FRIEND_REQUEST_ACCEPTED:
			return "FRIENDS.REQUEST_ACCEPTED"
		_:
			return ""


## Push from the long-lived notification socket. The socket emits
## the same per-entry shape the HTTP poll does, so both share one
## routing path; dedup by Nakama notification id keeps duplicate
## deliveries idempotent across the two.
func _on_socket_notification(
	notification: Dictionary,
) -> void:
	_dispatch_notification(notification)
	if not _queue_friend_toast(notification):
		return
	if not Platform.friends.is_busy():
		Platform.friends.fetch_friends()


func _handle_party_matchmaking_start(
	notification_id: String,
	content: Dictionary,
) -> void:
	if (notification_id.is_empty()
			or _known_party_match_start_ids
				.has(notification_id)):
		return
	_known_party_match_start_ids[notification_id] = true
	if not is_instance_valid(G.party_manager):
		return
	G.party_manager.on_party_matchmaking_notification(
		content)


## Recompute the badge from durable server state and render any
## friend toasts that were waiting on a warm cache.
##
## `unseen_count` is derived from the pending-request list rather
## than accumulated from notification arrivals. Deriving it means
## the badge is self-healing: accepting a request on another device,
## or the requester cancelling, clears the badge on the next refresh
## with no event to miss. The previous handler read
## `data.unseen_count` — a key PlatformFriendsApiClient never emits
## — so it force-cleared the badge on every single refresh.
func _on_friends_received(
	data: Dictionary,
) -> void:
	_recompute_unseen(data.get("incoming_requests", []))
	_flush_pending_friend_toasts()


## Badge = pending incoming requests the user hasn't looked at yet.
func _recompute_unseen(incoming: Array) -> void:
	var current: Dictionary = {}
	var count := 0
	for entry in incoming:
		if not (entry is Dictionary):
			continue
		var pid: String = entry.get("player_id", "")
		if pid.is_empty():
			continue
		current[pid] = true
		if not _seen_request_ids.has(pid):
			count += 1
	# Forget seen-marks for requests that no longer exist, so a
	# player who withdraws and re-sends badges again rather than
	# being permanently muted.
	for known in _seen_request_ids.keys():
		if not current.has(known):
			_seen_request_ids.erase(known)
	_set_unseen_count(count)


## The user opened the friends list: mark everything currently
## pending as seen.
##
## Fires regardless of whether the `mark_friends_seen` RPC
## succeeded — PlatformFriendsApiClient emits `friends_marked_seen`
## with ok=false when the RPC is unavailable, and the badge is
## local state, so it clears either way.
func _on_friends_marked_seen(
	_data: Dictionary,
) -> void:
	for entry in Platform.friends.cached_incoming_requests:
		if not (entry is Dictionary):
			continue
		var pid: String = entry.get("player_id", "")
		if not pid.is_empty():
			_seen_request_ids[pid] = true
	_set_unseen_count(0)


func _set_unseen_count(count: int) -> void:
	if unseen_count != count:
		unseen_count = count
		unseen_count_changed.emit(count)


## Render queued friend toasts now that the friend caches have been
## refreshed and a sender's display name is resolvable.
##
## Toasts are queued at classification time and rendered here rather
## than inline, because the sender of a brand-new incoming request
## is in no local cache until the fetch_friends that this flush
## follows. An event whose name still won't resolve is dropped
## (a nameless "someone sent you a request" is noise), but its
## badge contribution survives via `_recompute_unseen`.
func _flush_pending_friend_toasts() -> void:
	if _pending_friend_toasts.is_empty():
		return
	# Take the queue before any await so a second friends_received
	# arriving mid-flush can't double-render the same batch.
	var events: Array[Dictionary] = _pending_friend_toasts.duplicate()
	_pending_friend_toasts.clear()
	if _is_first_poll:
		_is_first_poll = false
		# Hold the first batch back so a backlog of persistent
		# notifications doesn't land on top of the loading screen.
		await get_tree().create_timer(
			_FIRST_POLL_TOAST_DELAY_SEC).timeout
	if not is_instance_valid(G.toast_overlay):
		return
	for event in events:
		var display_name := _resolve_sender_display_name(
			event.get("sender_id", ""))
		if display_name.is_empty():
			continue
		G.toast_overlay.show_toast(
			tr(event.get("key", "")) % display_name)


## Resolve a notification sender to something worth showing a user.
## Walks every friend cache: an accepted-request sender is now a
## friend, an incoming-request sender is a pending entry.
##
## Falls back to `username` only when `display_name` is blank.
## Note `username` is this project's friend code, so it's a poor
## last resort — but a code is still more identifying than nothing.
func _resolve_sender_display_name(
	sender_id: String,
) -> String:
	if sender_id.is_empty():
		return ""
	var caches: Array = [
		Platform.friends.cached_friends,
		Platform.friends.cached_incoming_requests,
		Platform.friends.cached_sent_requests,
	]
	for cache in caches:
		for entry in cache:
			if not (entry is Dictionary):
				continue
			if entry.get("player_id", "") != sender_id:
				continue
			var display_name: String = entry.get(
				"display_name", "")
			if not display_name.is_empty():
				return display_name
			return entry.get("username", "")
	return ""


func _on_auth_completed(
	success: bool, _error: String,
) -> void:
	if not success:
		return
	if not Platform.token_store.is_token_valid():
		return
	if Platform.token_store.is_anonymous:
		return
	if Platform.friends.is_busy():
		return
	Platform.friends.fetch_friends()


func _on_presence_received(
	online_ids: Array[String],
) -> void:
	var new_online: Array[String] = []
	for id in online_ids:
		if not _known_online_ids.has(id):
			new_online.append(id)

	# Rebuild known set to exactly current list.
	_known_online_ids.clear()
	for id in online_ids:
		_known_online_ids[id] = true

	if _is_first_presence_poll:
		_is_first_presence_poll = false
		return

	if not is_instance_valid(G.toast_overlay):
		return
	for id in new_online:
		var display_name := ""
		for entry in Platform.friends\
				.cached_friends:
			if entry.get("player_id", "") == id:
				display_name = entry.get(
					"display_name", "")
				break
		if not display_name.is_empty():
			G.toast_overlay.show_toast(
				tr("FRIENDS.CAME_ONLINE")
				% display_name)
