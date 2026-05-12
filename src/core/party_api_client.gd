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
signal request_failed(error: String)


const _PARTY_GROUP_PREFIX := "party-"


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
	var party: Dictionary = {}
	for ug in result.user_groups:
		var g = ug.group
		if g.name.begins_with(_PARTY_GROUP_PREFIX):
			party = {
				"party_id": g.id,
				"name": g.name,
				"leader_id": g.creator_id,
				"member_count": g.edge_count,
				"members": [],
			}
			break
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
			})
		party["members"] = members
	party_status_received.emit(party)


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
