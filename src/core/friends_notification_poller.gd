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

## Track known IDs to detect new arrivals.
var _known_incoming_ids: Dictionary = {}
var _known_accepted_ids: Dictionary = {}
var _known_rejected_ids: Dictionary = {}
var _known_online_ids: Dictionary = {}
## Dedupe persistent `party_matchmaking_start` notifications so a
## follower doesn't re-enqueue every poll cycle. Keyed by Nakama
## notification id.
var _known_party_match_start_ids: Dictionary = {}

## Rich presence string surfaced on the friends UI of other
## players. Updated from match lifecycle signals; sent on the
## next presence heartbeat. Localized via tr() so the addon's
## consumer game owns the actual labels.
var _current_rich_presence := ""
var _current_status := "online"


func _ready() -> void:
	G.friends_api_client\
		.notifications_received.connect(
			_on_notifications_received)
	# Also update unseen count when the full
	# friends list is fetched.
	G.friends_api_client\
		.friends_received.connect(
			_on_friends_received)
	# Clear unseen state when user views friends.
	G.friends_api_client\
		.friends_marked_seen.connect(
			_on_friends_marked_seen)
	G.friends_api_client\
		.presence_received.connect(
			_on_presence_received)
	# Prefetch friends list on auth so the cache
	# is warm before the panel ever opens.
	G.auth_client.auth_completed.connect(
		_on_auth_completed)
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
	_current_status = "in_match"


func _on_match_ended() -> void:
	_current_rich_presence = tr("PRESENCE.IN_LOBBY")
	_current_status = "online"


func _process(delta: float) -> void:
	if not _is_polling:
		return
	if not G.auth_token_store.is_token_valid():
		return
	if G.auth_token_store.is_anonymous:
		return

	_poll_timer += delta
	if _poll_timer >= _POLL_INTERVAL_SEC:
		_poll_timer = 0.0
		if not G.friends_api_client.is_poll_busy():
			G.friends_api_client.fetch_notifications()

	_presence_poll_timer += delta
	if _presence_poll_timer >= _PRESENCE_POLL_INTERVAL_SEC:
		_presence_poll_timer = 0.0
		if not G.friends_api_client\
				.is_presence_busy():
			G.friends_api_client.fetch_presence(
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
	_known_incoming_ids.clear()
	_known_accepted_ids.clear()
	_known_rejected_ids.clear()
	_known_online_ids.clear()
	_known_party_match_start_ids.clear()
	_set_unseen_count(0)


func _on_notifications_received(
	data: Dictionary,
) -> void:
	# FriendsApiClient.fetch_notifications emits the raw Nakama
	# notification list under the `notifications` key. Dispatch by
	# subject so non-friend subjects (party_matchmaking_start, etc.)
	# get routed to the right manager. Friend-request subjects fall
	# through to the existing incoming_requests / accepted_requests
	# / rejected_requests path below, which is fed by a different
	# emit shape (kept in place for compatibility with the
	# pre-multi-subject handler contract).
	var notifications: Array = data.get(
		"notifications", [])
	for n in notifications:
		_dispatch_notification(n)

	var incoming: Array = data.get(
		"incoming_requests", [])
	var accepted: Array = data.get(
		"accepted_requests", [])
	var rejected: Array = data.get(
		"rejected_requests", [])

	var new_incoming: Array[Dictionary] = []
	var new_accepted: Array[Dictionary] = []
	var new_rejected: Array[Dictionary] = []

	for entry in incoming:
		var fid: String = entry.get(
			"friend_id", "")
		if not fid.is_empty() \
				and not _known_incoming_ids.has(fid):
			_known_incoming_ids[fid] = true
			new_incoming.append(entry)

	for entry in accepted:
		var fid: String = entry.get(
			"friend_id", "")
		if not fid.is_empty() \
				and not _known_accepted_ids.has(fid):
			_known_accepted_ids[fid] = true
			new_accepted.append(entry)

	for entry in rejected:
		var fid: String = entry.get(
			"friend_id", "")
		if not fid.is_empty() \
				and not _known_rejected_ids.has(fid):
			_known_rejected_ids[fid] = true
			new_rejected.append(entry)

	# Update unseen count.
	var total_new := (
		new_incoming.size()
		+ new_accepted.size()
		+ new_rejected.size()
	)
	if total_new > 0:
		_set_unseen_count(
			unseen_count + total_new)

	# Show toasts for new notifications.
	if _is_first_poll:
		_is_first_poll = false
		if total_new > 0:
			_show_toasts_delayed(
				new_incoming,
				new_accepted,
				new_rejected,
			)
	else:
		_show_toasts(
			new_incoming,
			new_accepted,
			new_rejected,
		)

	# Refresh the full friends list so any open
	# panel reflects the changes immediately.
	if total_new > 0:
		if not G.friends_api_client.is_busy():
			G.friends_api_client.fetch_friends()


## Dispatch a single Nakama notification by subject. Friend-related
## subjects are handled by the legacy incoming_requests path; new
## subjects route here.
func _dispatch_notification(n: Dictionary) -> void:
	var subj: String = n.get("subject", "")
	var nid: String = n.get("id", "")
	match subj:
		"party_matchmaking_start":
			if nid.is_empty() \
					or _known_party_match_start_ids \
						.has(nid):
				return
			_known_party_match_start_ids[nid] = true
			var content_raw: Variant = n.get(
				"content", {})
			if not (content_raw is Dictionary):
				return
			if not is_instance_valid(G.party_manager):
				return
			G.party_manager\
				.on_party_matchmaking_notification(
					content_raw)


func _on_friends_received(
	data: Dictionary,
) -> void:
	var count: int = data.get("unseen_count", 0)
	_set_unseen_count(count)


func _on_friends_marked_seen(
	_data: Dictionary,
) -> void:
	_set_unseen_count(0)


func _set_unseen_count(count: int) -> void:
	if unseen_count != count:
		unseen_count = count
		unseen_count_changed.emit(count)


func _show_toasts(
	incoming: Array[Dictionary],
	accepted: Array[Dictionary],
	rejected: Array[Dictionary],
) -> void:
	if not is_instance_valid(G.toast_overlay):
		return
	for entry in incoming:
		var display_name: String = entry.get(
			"display_name", "")
		if not display_name.is_empty():
			G.toast_overlay.show_toast(
				tr("FRIENDS.REQUEST_RECEIVED")
				% display_name)
	for entry in accepted:
		var display_name: String = entry.get(
			"display_name", "")
		if not display_name.is_empty():
			G.toast_overlay.show_toast(
				tr("FRIENDS.REQUEST_ACCEPTED")
				% display_name)
	for entry in rejected:
		var display_name: String = entry.get(
			"display_name", "")
		if not display_name.is_empty():
			G.toast_overlay.show_toast(
				tr("FRIENDS.REQUEST_REJECTED")
				% display_name)


func _show_toasts_delayed(
	incoming: Array[Dictionary],
	accepted: Array[Dictionary],
	rejected: Array[Dictionary],
) -> void:
	if not is_instance_valid(G.toast_overlay):
		return
	# Delay toasts on first poll so they don't
	# appear during loading.
	await get_tree().create_timer(
		_FIRST_POLL_TOAST_DELAY_SEC).timeout
	_show_toasts(incoming, accepted, rejected)


func _on_auth_completed(
	success: bool, _error: String,
) -> void:
	if not success:
		return
	if not G.auth_token_store.is_token_valid():
		return
	if G.auth_token_store.is_anonymous:
		return
	if G.friends_api_client.is_busy():
		return
	G.friends_api_client.fetch_friends()


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
		for entry in G.friends_api_client\
				.cached_friends:
			if entry.get("player_id", "") == id:
				display_name = entry.get(
					"display_name", "")
				break
		if not display_name.is_empty():
			G.toast_overlay.show_toast(
				tr("FRIENDS.CAME_ONLINE")
				% display_name)
