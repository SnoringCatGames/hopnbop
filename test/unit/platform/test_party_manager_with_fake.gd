extends GutTest
## PartyManager's signal-driven flow against FakePartyApiClient
## (H75): the manager goes in the tree so _ready binds to the
## fake's signals, and create / status / leave update its state
## with no backend.
##
## The older test_party_manager.gd covers the deterministic
## helpers on an unbound manager; this file covers the wiring.


var _fake: FakePartyApiClient
var _manager: PartyManager
var _original_party: PlatformPartyApiClient
var _original_player_id: String


func before_each() -> void:
	_original_party = Platform.party
	_original_player_id = Platform.token_store.player_id
	Platform.token_store.player_id = "viewer-id"
	_fake = FakePartyApiClient.new()
	Platform.register_subsystem("party", _fake)
	_manager = PartyManager.new()
	add_child_autofree(_manager)


func after_each() -> void:
	Platform.register_subsystem("party", _original_party)
	Platform.token_store.player_id = _original_player_id
	_fake.free()


func test_create_party_seeds_leader_state() -> void:
	_fake.create_party()

	assert_true(_manager.is_in_party())
	assert_eq(_manager.get_party_id(), "fake-party-1")
	assert_eq(_manager.current_party.get("viewer_role", ""), "leader")
	assert_true(_fake.calls.has("fetch_party_status"),
		"the create handler asks for an immediate status fetch")


func test_status_fetch_settles_members() -> void:
	_fake.create_party()
	_fake.party["members"] = [
		{"user_id": "viewer-id"},
		{"user_id": "other-id"},
	]

	_fake.fetch_party_status()

	assert_eq(_manager.current_party.get("members", []).size(), 2)


func test_leave_clears_the_party() -> void:
	_fake.create_party()

	_fake.leave_party(_manager.get_party_id())

	assert_false(_manager.is_in_party())


## H114: a start that arrived while we had no party yet
## (it raced our join) is followed once a refresh shows
## us in that party, marked ready.
func test_start_racing_our_join_is_followed_after_refresh() -> void:
	_fake.party = {
		"party_id": "party-A",
		"leader_id": "other-id",
		"members": [
			{"user_id": "viewer-id", "ready": true},
		],
	}
	await _manager.on_party_matchmaking_notification({
		"party_id": "party-A",
		"rt_party_id": "rt-party-1",
		"game_mode": "ffa",
	})
	assert_true(
		_fake.calls.has("fetch_party_status"),
		"the start asked for one party refresh")
	assert_eq(
		_manager.pending_party_match_context.get(
			"rt_party_id", ""),
		"rt-party-1",
		"the raced start is followed after the refresh")


## H114: the same raced start is ignored when the refresh
## shows a different party.
func test_start_racing_our_join_is_ignored_for_other_party(
) -> void:
	_fake.party = {
		"party_id": "party-B",
		"leader_id": "other-id",
		"members": [
			{"user_id": "viewer-id", "ready": true},
		],
	}
	await _manager.on_party_matchmaking_notification({
		"party_id": "party-A",
		"rt_party_id": "rt-party-1",
		"game_mode": "ffa",
	})
	assert_true(
		_manager.pending_party_match_context.is_empty(),
		"a start for a party the refresh does not show is"
		+ " ignored")


## H114: the refresh after a start shows us unready (the
## server spent the party's readiness before notifying),
## but the start's own roster names us, so we follow.
func test_start_followed_when_in_member_ids_despite_unready(
) -> void:
	_fake.party = {
		"party_id": "party-A",
		"leader_id": "other-id",
		"members": [
			{"user_id": "viewer-id", "ready": false},
		],
	}
	await _manager.on_party_matchmaking_notification({
		"party_id": "party-A",
		"rt_party_id": "rt-party-1",
		"game_mode": "ffa",
		"member_ids": ["other-id", "viewer-id"],
	})
	assert_eq(
		_manager.pending_party_match_context.get(
			"rt_party_id", ""),
		"rt-party-1",
		"a follower in the start's roster follows it even"
		+ " though the refresh reads unready")


## H114: we are absent from the start's roster, so we
## ignore it even though the refresh reads us ready (a
## roster from a later attempt must not pull us in).
func test_start_ignored_when_not_in_member_ids() -> void:
	_fake.party = {
		"party_id": "party-A",
		"leader_id": "other-id",
		"members": [
			{"user_id": "viewer-id", "ready": true},
		],
	}
	await _manager.on_party_matchmaking_notification({
		"party_id": "party-A",
		"rt_party_id": "rt-party-1",
		"game_mode": "ffa",
		"member_ids": ["other-id", "third-id"],
	})
	assert_true(
		_manager.pending_party_match_context.is_empty(),
		"a follower outside the start's roster ignores it")


func test_failed_call_surfaces_and_changes_nothing() -> void:
	_fake.fail_next = "party is full"

	_fake.create_party()

	assert_false(_manager.is_in_party())
	assert_eq(_fake.calls.size(), 1, "no follow-up fetch on failure")
