class_name FriendsApiClient
extends Node
## Nakama-backed friends client. Wraps Nakama's friends API
## (list/add/delete) plus a few custom RPCs for friend-code
## lookup, notifications-mark-seen, and rich presence.
##
## Public method signatures + signal names match the legacy
## AWS-backed client so callers (FriendsScreen, NotificationPoller)
## don't have to change.


signal friends_received(data: Dictionary)
signal friend_request_sent(data: Dictionary)
signal friend_request_accepted(data: Dictionary)
signal friend_request_rejected(data: Dictionary)
signal friend_request_cancelled(data: Dictionary)
signal friend_removed(data: Dictionary)
signal friend_search_result(data: Dictionary)
signal notifications_received(data: Dictionary)
signal friends_marked_seen(data: Dictionary)
## Online IDs returned by the presence custom RPC.
signal presence_received(online_ids: Array[String])
## Rich presence (online friends with current game/state).
signal presence_received_rich(online_friends: Dictionary)
signal request_failed(error: String)


# Nakama Friend states (from the SDK API):
#   0=Friend, 1=PendingInvite, 2=PendingApproval, 3=Banned
const _STATE_FRIEND := 0
const _STATE_PENDING_OUTGOING := 1
const _STATE_PENDING_INCOMING := 2
const _STATE_BANNED := 3


var cached_friends: Array[Dictionary] = []
var cached_sent_requests: Array[Dictionary] = []
var cached_incoming_requests: Array[Dictionary] = []
var cached_online_ids: Array[String] = []
var cached_online_friends: Dictionary = {}

var _is_busy := false
var _is_poll_busy := false
var _is_presence_busy := false


func fetch_friends() -> void:
	if _is_busy:
		return
	_is_busy = true
	var session := await _ensure_session()
	if session == null:
		_is_busy = false
		return
	var result = await G.auth_client._get_nakama_client().list_friends_async(
		session, null, 100, null)
	_is_busy = false
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	cached_friends = []
	cached_sent_requests = []
	cached_incoming_requests = []
	for f in result.friends:
		var entry := {
			"player_id": f.user.id,
			"display_name": f.user.display_name,
			"username": f.user.username,
			"avatar_url": f.user.avatar_url,
			"online": f.user.online,
		}
		match f.state:
			_STATE_FRIEND:
				cached_friends.append(entry)
			_STATE_PENDING_OUTGOING:
				cached_sent_requests.append(entry)
			_STATE_PENDING_INCOMING:
				cached_incoming_requests.append(entry)
	friends_received.emit({
		"friends": cached_friends,
		"sent_requests": cached_sent_requests,
		"incoming_requests": cached_incoming_requests,
	})


func send_request_by_code(code: String) -> void:
	# Friend codes are stored as Nakama usernames in this
	# project (same uniqueness, simpler lookup).
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().add_friends_async(
		session, null, [code])
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	friend_request_sent.emit({"code": code})


func send_request_by_player_id(player_id: String) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().add_friends_async(
		session, [player_id], null)
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	friend_request_sent.emit({"player_id": player_id})


func accept_request(player_id: String) -> void:
	# Nakama: re-issuing add_friends_async on a pending-incoming
	# accepts the friendship.
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().add_friends_async(
		session, [player_id], null)
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	friend_request_accepted.emit({"player_id": player_id})


func reject_request(player_id: String) -> void:
	await _delete_friend(player_id, "rejected")


func cancel_request(player_id: String) -> void:
	await _delete_friend(player_id, "cancelled")


func remove_friend(player_id: String) -> void:
	await _delete_friend(player_id, "removed")


func search_friend_code(code: String) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().get_users_async(
		session, PackedStringArray(), [code], null)
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	if result.users.size() == 0:
		friend_search_result.emit({"code": code, "found": false})
		return
	var u = result.users[0]
	friend_search_result.emit({
		"code": code,
		"found": true,
		"player_id": u.id,
		"display_name": u.display_name,
		"avatar_url": u.avatar_url,
	})


func mark_seen() -> void:
	# Custom RPC on the runtime side. Bumps last_friends_seen_at.
	var session := await _ensure_session()
	if session == null:
		return
	var rpc_result = await G.auth_client._get_nakama_client().rpc_async(
		session, "mark_friends_seen", "{}")
	if rpc_result.is_exception():
		# RPC missing on older deploys: silent fail.
		friends_marked_seen.emit({"ok": false})
		return
	friends_marked_seen.emit({"ok": true})


func fetch_notifications(
	limit: int = 50,
	cacheable_cursor: String = "",
) -> void:
	if _is_poll_busy:
		return
	_is_poll_busy = true
	var session := await _ensure_session()
	if session == null:
		_is_poll_busy = false
		return
	var result = await G.auth_client._get_nakama_client().list_notifications_async(
		session, limit, cacheable_cursor)
	_is_poll_busy = false
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	var entries := []
	for n in result.notifications:
		entries.append({
			"id": n.id,
			"subject": n.subject,
			"content": JSON.parse_string(n.content) \
				if not n.content.is_empty() else {},
			"sender_id": n.sender_id,
			"create_time": n.create_time,
			"persistent": n.persistent,
		})
	notifications_received.emit({
		"notifications": entries,
		"cacheable_cursor": result.cacheable_cursor,
	})


func fetch_presence(player_ids: Array[String]) -> void:
	if _is_presence_busy:
		return
	_is_presence_busy = true
	var session := await _ensure_session()
	if session == null:
		_is_presence_busy = false
		return
	var rpc_result = await G.auth_client._get_nakama_client().rpc_async(
		session, "get_friends_presence",
		JSON.stringify({"player_ids": player_ids}))
	_is_presence_busy = false
	if rpc_result.is_exception():
		# Pre-RPC deploys: assume nobody online.
		cached_online_ids = []
		cached_online_friends = {}
		presence_received.emit(cached_online_ids)
		presence_received_rich.emit(cached_online_friends)
		return
	var data: Variant = JSON.parse_string(rpc_result.payload)
	if not (data is Dictionary):
		presence_received.emit([])
		presence_received_rich.emit({})
		return
	cached_online_ids.clear()
	for v in data.get("online_ids", []):
		cached_online_ids.append(str(v))
	cached_online_friends = data.get("online_friends", {})
	presence_received.emit(cached_online_ids)
	presence_received_rich.emit(cached_online_friends)


# --------------------------------------------------------------
# Status
# --------------------------------------------------------------

func is_busy() -> bool: return _is_busy
func is_poll_busy() -> bool: return _is_poll_busy
func is_presence_busy() -> bool: return _is_presence_busy


func is_friend(player_id: String) -> bool:
	for f in cached_friends:
		if f.get("player_id", "") == player_id:
			return true
	return false


func has_sent_request(player_id: String) -> bool:
	for f in cached_sent_requests:
		if f.get("player_id", "") == player_id:
			return true
	return false


func has_incoming_request(player_id: String) -> bool:
	for f in cached_incoming_requests:
		if f.get("player_id", "") == player_id:
			return true
	return false


# --------------------------------------------------------------
# Internals
# --------------------------------------------------------------

func _delete_friend(player_id: String, kind: String) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().delete_friends_async(
		session, [player_id], null)
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	match kind:
		"rejected":
			friend_request_rejected.emit({"player_id": player_id})
		"cancelled":
			friend_request_cancelled.emit({"player_id": player_id})
		"removed":
			friend_removed.emit({"player_id": player_id})


func _ensure_session() -> NakamaSession:
	var s := G.auth_client._build_session_from_store()
	if s == null:
		request_failed.emit("Not authenticated")
		return null
	return s


func _describe(ex: NakamaException) -> String:
	if ex == null:
		return "Unknown Nakama error"
	return "%s (status=%d)" % [ex.message, ex.status_code]
