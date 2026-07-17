extends GutTest
## Contract tests for PartyManager's party_left handling against the
## payload PlatformPartyApiClient actually emits.
##
## party_api_client.gd:121 emits `{"party_id": <id>}` and nothing
## else — there is no `disbanded` key produced anywhere in the
## codebase. PartyManager._on_party_left reads `data.disbanded` and
## clears `current_party` unconditionally, without checking which
## party the leave referred to.
##
## Nakama models "decline a pending invite" as leaving the (state=3)
## group, so decline_invite() routes through the same leave_party()
## call as a real leave. That makes "which party_id" load-bearing.


var _manager: PartyManager


func before_each() -> void:
	_manager = PartyManager.new()


func after_each() -> void:
	if is_instance_valid(_manager):
		_manager.free()


func test_leaving_current_party_clears_it() -> void:
	_manager.current_party = {
		"party_id": "party-A",
		"members": [],
		"viewer_role": "member",
	}
	_manager._on_party_left({"party_id": "party-A"})
	assert_true(
		_manager.current_party.is_empty(),
		"leaving the active party should clear it")


func test_declining_invite_to_other_party_keeps_current_party() -> void:
	# Viewer is an active member of party-A and has a pending invite
	# to party-B. Declining B routes through leave_party("party-B").
	_manager.current_party = {
		"party_id": "party-A",
		"members": [],
		"viewer_role": "member",
	}
	_manager._on_party_left({"party_id": "party-B"})
	assert_false(
		_manager.current_party.is_empty(),
		"declining an invite to another party must not clear the"
		+ " party the viewer is actually in")
	assert_eq(
		_manager.current_party.get("party_id", ""), "party-A",
		"the viewer should still be in party-A after declining B")
