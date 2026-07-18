extends GutTest
## PartyManager's party-matchmaking context: the handoff that tells
## NakamaMatchmakerClient whether to submit the party's single
## ticket, join and wait, or do neither.
##
## Party matchmaking used to work by having every member submit an
## independent solo ticket tagged with `party_id`. No matchmaker
## query ever read that property and fleet_allocator never looked
## at it, so Nakama was free to split a party across separate
## matches whenever other players were queued at the same time. The
## fix routes the group through a Nakama realtime party so the
## leader can submit ONE ticket for everyone.
##
## These tests cover the deterministic half — what lands in
## `pending_party_match_context`. The socket choreography it drives
## (create / join / wait-for-roster / submit) needs two live
## authenticated clients and is not reachable from a unit test.


var _manager: PartyManager


func before_each() -> void:
	_manager = PartyManager.new()


func after_each() -> void:
	if is_instance_valid(_manager):
		_manager.free()


## The runtime's party_start_matchmaking response, as
## PlatformPartyApiClient re-emits it to the leader.
func _leader_rpc_response(
	member_count: int,
) -> Dictionary:
	var member_ids: Array = []
	for i in member_count:
		member_ids.append("member-%d" % i)
	return {
		"ok": true,
		"party_id": "party-A",
		"rt_party_id": "rt-party-1",
		"game_mode": "ffa",
		"leader_id": "member-0",
		"member_ids": member_ids,
		"matchmaker_properties": {
			"party_id": "party-A",
			"game_mode": "ffa",
		},
	}


## The transient notification a follower receives. Note it carries
## no member_ids — only the leader waits on the roster.
func _follower_notification() -> Dictionary:
	return {
		"party_id": "party-A",
		"rt_party_id": "rt-party-1",
		"game_mode": "ffa",
		"leader_id": "member-0",
		"matchmaker_properties": {
			"party_id": "party-A",
			"game_mode": "ffa",
		},
	}


# ------------------------------------------------------------------
# Leader context
# ------------------------------------------------------------------


func test_leader_context_carries_rt_party_and_leader_flag() -> void:
	_manager._on_matchmaking_started(_leader_rpc_response(3))
	var context := _manager.pending_party_match_context
	assert_eq(context.get("rt_party_id", ""), "rt-party-1")
	assert_true(
		context.get("is_rt_leader", false),
		"the RPC caller is the realtime party's leader and is the"
		+ " only client that submits a ticket")
	assert_eq(context.get("party_id", ""), "party-A")
	assert_eq(context.get("game_mode", ""), "ffa")


## The leader waits for everyone EXCEPT itself, so the expected
## presence count is one less than the roster. Getting this wrong by
## one either aborts a healthy party or ticket-submits before the
## last member has joined.
func test_leader_expects_roster_minus_self() -> void:
	_manager._on_matchmaking_started(_leader_rpc_response(3))
	assert_eq(
		_manager.pending_party_match_context.get(
			"expected_others", -1),
		2)


func test_solo_party_expects_no_others() -> void:
	_manager._on_matchmaking_started(_leader_rpc_response(1))
	assert_eq(
		_manager.pending_party_match_context.get(
			"expected_others", -1),
		0,
		"a one-member party has nobody to wait for and should"
		+ " ticket immediately")


## Defensive: never negative, even if the runtime reports an empty
## roster. A negative expectation would make the leader's wait
## trivially succeed on a party it knows nothing about.
func test_empty_roster_does_not_produce_negative_expectation() -> void:
	_manager._on_matchmaking_started(_leader_rpc_response(0))
	assert_eq(
		_manager.pending_party_match_context.get(
			"expected_others", -1),
		0)


# ------------------------------------------------------------------
# Follower context
# ------------------------------------------------------------------


func test_follower_context_is_not_flagged_leader() -> void:
	_manager.on_party_matchmaking_notification(
		_follower_notification())
	var context := _manager.pending_party_match_context
	assert_eq(context.get("rt_party_id", ""), "rt-party-1")
	assert_false(
		context.get("is_rt_leader", true),
		"a follower must never submit its own ticket — that is"
		+ " precisely the bug this flow replaces")


# ------------------------------------------------------------------
# Guards
# ------------------------------------------------------------------


## A start without a realtime party cannot hold the group together.
## Degrading to a solo ticket would silently reintroduce the split-
## party bug, so the kickoff is refused outright.
func test_start_without_rt_party_id_is_refused() -> void:
	var payload := _follower_notification()
	payload.erase("rt_party_id")
	_manager.on_party_matchmaking_notification(payload)
	assert_true(
		_manager.pending_party_match_context.is_empty(),
		"no rt_party_id must mean no party matchmaking at all")


## A leader+follower race, or a match already in flight, must not
## stash context that would then attach to the running match.
##
## G.client_session is an autoload field that bootstrap populates;
## it's null here, so stand a real one up and put it back after.
func test_start_is_skipped_while_a_match_is_already_loading() -> void:
	var previous: ClientSession = G.client_session
	var stub := ClientSession.new()
	stub.is_game_loading = true
	G.client_session = stub
	_manager.on_party_matchmaking_notification(
		_follower_notification())
	G.client_session = previous
	assert_true(
		_manager.pending_party_match_context.is_empty(),
		"a party start arriving mid-load must not stash context"
		+ " that would then attach to the in-flight match")


func test_start_is_skipped_while_a_match_is_active() -> void:
	var previous: ClientSession = G.client_session
	var stub := ClientSession.new()
	stub.is_game_active = true
	G.client_session = stub
	_manager.on_party_matchmaking_notification(
		_follower_notification())
	G.client_session = previous
	assert_true(
		_manager.pending_party_match_context.is_empty())


# ------------------------------------------------------------------
# Abort
# ------------------------------------------------------------------


func test_abort_for_a_different_party_is_ignored() -> void:
	_manager.current_party = {
		"party_id": "party-A",
		"members": [],
	}
	_manager.on_party_matchmaking_notification(
		_follower_notification())
	assert_false(_manager.pending_party_match_context.is_empty())

	_manager._on_party_matchmaking_abort({
		"party_id": "party-OTHER",
		"reason": "members_never_joined",
	})
	assert_false(
		_manager.pending_party_match_context.is_empty(),
		"an abort naming another party must not cancel our own"
		+ " in-flight matchmaking")


func test_abort_for_our_party_clears_context() -> void:
	_manager.current_party = {
		"party_id": "party-A",
		"members": [],
	}
	_manager.on_party_matchmaking_notification(
		_follower_notification())
	assert_false(_manager.pending_party_match_context.is_empty())

	_manager._on_party_matchmaking_abort({
		"party_id": "party-A",
		"reason": "members_never_joined",
	})
	assert_true(
		_manager.pending_party_match_context.is_empty(),
		"the leader gave up; we must stop waiting for a match that"
		+ " is never coming")


func test_reset_clears_the_starting_guard() -> void:
	_manager._is_starting_matchmaking = true
	_manager.reset()
	assert_false(
		_manager._is_starting_matchmaking,
		"a stale guard would wedge Start Match permanently after a"
		+ " sign-out mid-attempt")
