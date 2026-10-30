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


func test_failed_call_surfaces_and_changes_nothing() -> void:
	_fake.fail_next = "party is full"

	_fake.create_party()

	assert_false(_manager.is_in_party())
	assert_eq(_fake.calls.size(), 1, "no follow-up fetch on failure")
