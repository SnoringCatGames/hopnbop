class_name PartyApiClient
extends Node
## Nakama-backed party client. Parties are mapped onto Nakama
## groups (closed, max-size 4 by default) plus a custom RPC for
## starting matchmaking on behalf of the whole party.


signal party_created(data: Dictionary)
signal party_invited(data: Dictionary)
signal party_joined(data: Dictionary)
signal party_left(data: Dictionary)
signal party_kicked(data: Dictionary)
signal party_status_received(data: Dictionary)
signal party_matchmaking_started(data: Dictionary)
signal party_ready_updated(data: Dictionary)
signal party_invite_code_received(data: Dictionary)
signal party_invite_code_redeemed(data: Dictionary)
signal request_failed(error: String)


const _PARTY_GROUP_PREFIX := "party-"

## Storage collection name for per-member ready rows. Mirrors
## third_party/snoringcat-platform/runtime/party.go
## :partyReadyCollection.
const _PARTY_READY_COLLECTION := "party_ready"


var _is_busy := false


func is_busy() -> bool:
	return _is_busy


func create_party() -> void:
	if _is_busy:
		return
	_is_busy = true
	var session := await _ensure_session()
	if session == null:
		_is_busy = false
		return
	var name := _PARTY_GROUP_PREFIX + _short_id(session.user_id)
	var result = await G.auth_client._get_nakama_client().create_group_async(
		session, name, "", "", "en", false, 4)
	_is_busy = false
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	party_created.emit({
		"party_id": result.id,
		"name": result.name,
	})


func invite_to_party(
	party_id: String,
	player_id: String,
) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().add_group_users_async(
		session, party_id, [player_id])
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	party_invited.emit({
		"party_id": party_id,
		"player_id": player_id,
	})


func join_party(party_id: String) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().join_group_async(
		session, party_id)
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	party_joined.emit({"party_id": party_id})


func leave_party(party_id: String) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().leave_group_async(
		session, party_id)
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	party_left.emit({"party_id": party_id})


func fetch_party_status() -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().list_user_groups_async(
		session, session.user_id, null, null, null)
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	# Nakama parties are closed groups. The viewer can be either an
	# active member (state 0/1/2) or a pending invitee (state 3) for
	# the same group shape. Split the two so the UI can render an
	# accept/decline path for invites instead of falsely showing the
	# user as "in a party" before they've accepted.
	var party: Dictionary = {}
	var pending_invites: Array[Dictionary] = []
	for ug in result.user_groups:
		var g = ug.group
		if not g.name.begins_with(_PARTY_GROUP_PREFIX):
			continue
		var state := int(ug.state)
		if state == 3:
			pending_invites.append({
				"party_id": g.id,
				"party_name": g.name,
				"leader_id": g.creator_id,
				# leader_display_name resolved by the
				# UI from cached friends/members; the
				# list_user_groups response doesn't
				# carry it.
			})
			continue
		if party.is_empty():
			party = {
				"party_id": g.id,
				"name": g.name,
				"leader_id": g.creator_id,
				"member_count": g.edge_count,
				"members": [],
				"viewer_role": _group_state_to_role(state),
			}
	if not party.is_empty():
		var members_result = (
			await G.auth_client._get_nakama_client()
				.list_group_users_async(
					session,
					party["party_id"],
					null,
					null,
					null,
				)
		)
		if members_result.is_exception():
			request_failed.emit(
				_describe(members_result.get_exception()))
			return
		var members: Array[Dictionary] = []
		for gu in members_result.group_users:
			var u = gu.user
			if u == null:
				continue
			members.append({
				"user_id": u.id,
				"username": u.username,
				"display_name": u.display_name,
				"role": _group_state_to_role(gu.state),
				"ready": false,
			})
		# Batch-read every active member's ready row. Each row is
		# owned by the corresponding member; pending invitees
		# (state=3) are skipped because they can't ready up until
		# they accept the invite. Skipping the read entirely when
		# there are no active members keeps the call count off
		# the empty-party path.
		var ready_ids: Array[NakamaStorageObjectId] = []
		for m in members:
			if m.get("role", "") == "invited":
				continue
			ready_ids.append(NakamaStorageObjectId.new(
				_PARTY_READY_COLLECTION,
				party["party_id"],
				m["user_id"],
			))
		if not ready_ids.is_empty():
			var ready_result = (
				await G.auth_client._get_nakama_client()
					.read_storage_objects_async(
						session, ready_ids)
			)
			if ready_result.is_exception():
				# Ready state is non-critical — log via the
				# error signal but still surface the party so
				# the panel can render. Most likely cause is a
				# transient network blip; the next poll picks
				# the readies up.
				request_failed.emit(
					_describe(ready_result.get_exception()))
			else:
				var ready_by_user: Dictionary = {}
				for obj in ready_result.objects:
					var parsed: Variant = JSON.parse_string(
						obj.value)
					if parsed is Dictionary:
						ready_by_user[obj.user_id] = (
							bool(parsed.get("ready", false)))
				for m in members:
					m["ready"] = bool(
						ready_by_user.get(
							m["user_id"], false))
		party["members"] = members
	# Wrapped emit so PartyManager._on_party_status_received can read
	# both surfaces. The pre-wrap shape (bare party Dict) silently
	# never matched the receiver's `data.get("party")` lookup, which
	# is why polling-cycle updates appeared to do nothing in
	# production.
	party_status_received.emit({
		"party": party,
		"pending_invites": pending_invites,
	})


func kick_from_party(
	party_id: String,
	player_id: String,
) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var result = await G.auth_client._get_nakama_client().kick_group_users_async(
		session, party_id, [player_id])
	if result.is_exception():
		request_failed.emit(_describe(result.get_exception()))
		return
	party_kicked.emit({
		"party_id": party_id,
		"player_id": player_id,
	})


## Toggle the caller's per-party ready flag. Calls the
## party_set_ready runtime RPC, which validates membership,
## writes the storage row server-side, and fans out a
## party_state_changed notification so every member's UI
## refreshes without waiting for the catch-up poll.
func set_ready(party_id: String, ready: bool) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var rpc_result = await G.auth_client._get_nakama_client().rpc_async(
		session, "party_set_ready",
		JSON.stringify({
			"party_id": party_id,
			"ready": ready,
		}))
	if rpc_result.is_exception():
		request_failed.emit(_describe(rpc_result.get_exception()))
		return
	var data: Variant = JSON.parse_string(rpc_result.payload)
	party_ready_updated.emit(
		data if data is Dictionary else
		{"party_id": party_id, "ready": ready})


## Fetch (or generate) the shareable 6-char invite code for the
## given party. Any active member can call; pending invitees are
## rejected by the runtime. Emits `party_invite_code_received`
## with `{party_id, code}` on success.
func get_invite_code(party_id: String) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var rpc_result = await G.auth_client._get_nakama_client().rpc_async(
		session, "party_get_invite_code",
		JSON.stringify({
			"party_id": party_id,
		}))
	if rpc_result.is_exception():
		request_failed.emit(_describe(rpc_result.get_exception()))
		return
	var data: Variant = JSON.parse_string(rpc_result.payload)
	if data is Dictionary:
		party_invite_code_received.emit(data)
	else:
		party_invite_code_received.emit({
			"party_id": party_id, "code": ""})


## Join a party by previously-issued invite code. Server validates
## the code, confirms the party still exists and has room, then
## adds the caller as an active member (state=2). Emits both
## `party_invite_code_redeemed` (so UI can show success copy) and
## `party_joined` (so PartyManager runs its standard join-state
## machinery).
func join_by_code(code: String) -> void:
	var session := await _ensure_session()
	if session == null:
		return
	var normalized := code.strip_edges().to_upper()
	var rpc_result = await G.auth_client._get_nakama_client().rpc_async(
		session, "party_join_by_code",
		JSON.stringify({
			"code": normalized,
		}))
	if rpc_result.is_exception():
		request_failed.emit(_describe(rpc_result.get_exception()))
		return
	var data: Variant = JSON.parse_string(rpc_result.payload)
	if not (data is Dictionary):
		data = {"party_id": "", "code": normalized}
	party_invite_code_redeemed.emit(data)
	# Routing the success through party_joined keeps PartyManager's
	# state machine simple: the join-by-code path is just another
	# way of becoming a party member, so the same post-join
	# bookkeeping (seed current_party, immediate refetch, kick off
	# polling) applies.
	party_joined.emit({"party_id": data.get("party_id", "")})


func start_matchmaking(
	party_id: String,
	game_mode: String = "ffa",
) -> void:
	# Custom Nakama RPC: enqueues every party member into the
	# matchmaker simultaneously so they end up in the same match.
	var session := await _ensure_session()
	if session == null:
		return
	var rpc_result = await G.auth_client._get_nakama_client().rpc_async(
		session, "party_start_matchmaking",
		JSON.stringify({
			"party_id": party_id,
			"game_mode": game_mode,
		}))
	if rpc_result.is_exception():
		request_failed.emit(_describe(rpc_result.get_exception()))
		return
	var data: Variant = JSON.parse_string(rpc_result.payload)
	party_matchmaking_started.emit(
		data if data is Dictionary else
		{"party_id": party_id, "ticket_id": ""})


# --------------------------------------------------------------
# Internals
# --------------------------------------------------------------

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


func _short_id(uuid: String) -> String:
	return uuid.replace("-", "").substr(0, 8)


# Nakama group_user state enum:
#   0 = Superadmin (creator/owner)
#   1 = Admin
#   2 = Member
#   3 = JoinRequest (pending invite the user has not yet accepted).
func _group_state_to_role(state: int) -> String:
	match state:
		0:
			return "leader"
		1:
			return "admin"
		2:
			return "member"
		3:
			return "invited"
		_:
			return "unknown"
