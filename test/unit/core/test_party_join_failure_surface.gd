extends GutTest
## A party follower whose realtime-party join fails gets exactly
## one failure surface (H21). join_rt_party emits the SDK's
## matchmaking_failed, which NakamaMatchmakerClient forwards as
## session_request_failed; the party path used to emit a second
## one on top, so the follower saw two toasts for one failure.


## Mirrors PlatformMatchmakingClient.join_rt_party's contract:
## an empty id fails silently; any other failure emits
## matchmaking_failed before returning false.
class FakeMatchmakingClient extends PlatformMatchmakingClient:
	const JOIN_ERROR := "Party join failed: boom"

	func join_rt_party(rt_party_id: String) -> bool:
		if rt_party_id.is_empty():
			return false
		matchmaking_failed.emit(JOIN_ERROR)
		return false


var _adapter: NakamaMatchmakerClient
var _failures: Array = []
var _original_matchmaking: PlatformMatchmakingClient


func before_each() -> void:
	_original_matchmaking = Platform.matchmaking
	Platform.register_subsystem(
		"matchmaking", FakeMatchmakingClient.new())
	_adapter = NakamaMatchmakerClient.new()
	add_child_autofree(_adapter)
	_failures = []
	_adapter.session_request_failed.connect(_on_failure)


func after_each() -> void:
	Platform.register_subsystem(
		"matchmaking", _original_matchmaking)


func test_failed_join_surfaces_exactly_once() -> void:
	await _adapter._request_party_session_ids(
		{"rt_party_id": "rt-1", "is_rt_leader": false},
		"*", 2, 4, {}, {}, 2)

	assert_eq(_failures.size(), 1, "one failure surface")
	assert_eq(_failures[0], FakeMatchmakingClient.JOIN_ERROR)


func test_empty_party_id_still_surfaces_once() -> void:
	await _adapter._request_party_session_ids(
		{"rt_party_id": "", "is_rt_leader": false},
		"*", 2, 4, {}, {}, 2)

	assert_eq(_failures.size(), 1, "one failure surface")
	assert_eq(_failures[0], tr("PARTY.JOIN_MATCHMAKING_FAILED"))


func _on_failure(reason: String) -> void:
	_failures.append(reason)
