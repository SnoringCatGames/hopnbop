class_name FakePartyApiClient
extends PlatformPartyApiClient
## In-memory Platform.party for GUT (H75): no Nakama, no socket.
##
## Register it in place of the real client, put a PartyManager in
## the tree so its _ready binds to this fake's signals, and drive
## create / invite / join / leave flows synchronously:
##
##     var fake := FakePartyApiClient.new()
##     Platform.register_subsystem("party", fake)
##     var manager := PartyManager.new()
##     add_child(manager)
##     fake.create_party()  # manager.current_party updates
##
## The fake keeps one party. fetch_party_status reports it back,
## so PartyManager's poll-driven refresh settles on the same
## state the signal handlers seeded.


## What fetch_party_status will report as the current party.
var party: Dictionary = {}
## Invites fetch_party_status will report.
var pending_invites: Array = []
## Every method call, in order, as "name" or "name:arg".
var calls: Array[String] = []
## The code get_invite_code will emit.
var invite_code := "FAKE42"
## Set to make the next call emit request_failed instead.
var fail_next := ""

var _party_serial := 0


func is_busy() -> bool:
	return false


func create_party() -> void:
	calls.append("create_party")
	if _fail_if_armed():
		return
	_party_serial += 1
	var party_id := "fake-party-%d" % _party_serial
	party = {
		"party_id": party_id,
		"name": "fake-party",
		"leader_id": Platform.token_store.player_id,
		"members": [],
		"game_mode": "ffa",
		"viewer_role": "leader",
	}
	party_created.emit({"party_id": party_id, "name": "fake-party"})


func invite_to_party(party_id: String, player_id: String) -> void:
	calls.append("invite_to_party:%s" % player_id)
	if _fail_if_armed():
		return
	party_invited.emit({"party_id": party_id, "player_id": player_id})


func join_party(party_id: String) -> void:
	calls.append("join_party")
	if _fail_if_armed():
		return
	party_joined.emit({"party_id": party_id})


func leave_party(party_id: String) -> void:
	calls.append("leave_party")
	if _fail_if_armed():
		return
	if party.get("party_id", "") == party_id:
		party = {}
	party_left.emit({"party_id": party_id})


func fetch_party_status() -> void:
	calls.append("fetch_party_status")
	if _fail_if_armed():
		return
	party_status_received.emit({
		"party": party,
		"pending_invites": pending_invites,
	})


func kick_from_party(party_id: String, player_id: String) -> void:
	calls.append("kick_from_party:%s" % player_id)
	if _fail_if_armed():
		return
	party_kicked.emit({"party_id": party_id, "player_id": player_id})


func set_ready(party_id: String, ready: bool) -> void:
	calls.append("set_ready:%s" % ready)
	if _fail_if_armed():
		return
	party_ready_updated.emit({"party_id": party_id, "ready": ready})


func set_mode(party_id: String, mode_id: String) -> void:
	calls.append("set_mode:%s" % mode_id)
	if _fail_if_armed():
		return
	if not party.is_empty():
		party["game_mode"] = mode_id
	party_mode_set.emit({"party_id": party_id, "mode_id": mode_id})


func set_prefs(
	party_id: String,
	mode_id: String,
	level_prefs: Dictionary,
	are_cheats_enabled: Variant,
	networked_cheats: Array,
) -> void:
	calls.append("set_prefs")
	if _fail_if_armed():
		return
	if not party.is_empty() and not mode_id.is_empty():
		party["game_mode"] = mode_id


func set_level_prefs(party_id: String, prefs: Dictionary) -> void:
	calls.append("set_level_prefs")
	_fail_if_armed()


func set_cheat_prefs(
	party_id: String,
	are_cheats_enabled: bool,
	networked_cheats: Array,
) -> void:
	calls.append("set_cheat_prefs")
	_fail_if_armed()


func abort_matchmaking(party_id: String, _reason: String = "") -> void:
	calls.append("abort_matchmaking")
	_fail_if_armed()


func get_invite_code(party_id: String) -> void:
	calls.append("get_invite_code")
	if _fail_if_armed():
		return
	party_invite_code_received.emit({
		"party_id": party_id,
		"code": invite_code,
	})


func join_by_code(code: String) -> void:
	calls.append("join_by_code:%s" % code)
	if _fail_if_armed():
		return
	var party_id := str(party.get("party_id", ""))
	party_invite_code_redeemed.emit({
		"party_id": party_id,
		"code": code,
	})
	party_joined.emit({"party_id": party_id})


func transfer_leadership(party_id: String, new_leader_id: String) -> void:
	calls.append("transfer_leadership:%s" % new_leader_id)
	if _fail_if_armed():
		return
	if not party.is_empty():
		party["leader_id"] = new_leader_id
	party_leader_transferred.emit({
		"party_id": party_id,
		"leader_id": new_leader_id,
	})


func disband_party(party_id: String) -> void:
	calls.append("disband_party")
	if _fail_if_armed():
		return
	party = {}
	party_disbanded.emit({"party_id": party_id})


func start_matchmaking(
	party_id: String,
	rt_party_id: String,
	game_mode: String = "ffa",
) -> void:
	calls.append("start_matchmaking")
	if _fail_if_armed():
		return
	party_matchmaking_started.emit({
		"party_id": party_id,
		"rt_party_id": rt_party_id,
		"game_mode": game_mode,
	})


func _fail_if_armed() -> bool:
	if fail_next.is_empty():
		return false
	var message := fail_next
	fail_next = ""
	request_failed.emit(message)
	return true
