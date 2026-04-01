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
var _last_poll_timestamp := 0
var _is_first_poll := true
var _is_first_presence_poll := true

## Track known IDs to detect new arrivals.
var _known_incoming_ids: Dictionary = {}
var _known_accepted_ids: Dictionary = {}
var _known_rejected_ids: Dictionary = {}
var _known_online_ids: Dictionary = {}


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
			G.friends_api_client\
				.fetch_notifications(
					_last_poll_timestamp)

	_presence_poll_timer += delta
	if _presence_poll_timer >= _PRESENCE_POLL_INTERVAL_SEC:
		_presence_poll_timer = 0.0
		if not G.friends_api_client\
				.is_presence_busy():
			G.friends_api_client.fetch_presence()


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
	_last_poll_timestamp = 0
	_known_incoming_ids.clear()
	_known_accepted_ids.clear()
	_known_rejected_ids.clear()
	_known_online_ids.clear()
	_set_unseen_count(0)


func _on_notifications_received(
	data: Dictionary,
) -> void:
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

	# Update timestamp to the latest updated_at
	# seen in any notification.
	for entries in [incoming, accepted, rejected]:
		for entry in entries:
			var ts: int = entry.get(
				"updated_at", 0)
			if ts > _last_poll_timestamp:
				_last_poll_timestamp = ts

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
