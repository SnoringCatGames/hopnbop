extends GutTest
## H37 phase 2b probe (h37-verify2, item 1, G1.2): a fellow player of a
## matched set can compute another player's session id and claim it on the
## game server before its owner does. The allowlist is loaded the way the
## server loads it (EXPECTED_SESSION_IDS), with the ids the runtime minted in
## h37-verify2/go-test-hook.log for two made-up users: A (2 local players)
## and B (1). Every value a declare uses here is in Nakama's
## MatchmakerMatched envelope (user ids, player_count property), which
## every member of the set receives. Template: h37-matchmaking's
## test_h37_declare_validation.gd. Nothing binds a port or reaches a backend.


class FakeApi extends MultiplayerAPIExtension:
	var sender := 0
	var rpcs: Array = []
	var _peer := OfflineMultiplayerPeer.new()

	func _poll() -> Error:
		return OK

	func _set_multiplayer_peer(multiplayer_peer: MultiplayerPeer) -> void:
		pass

	func _get_multiplayer_peer() -> MultiplayerPeer:
		return _peer

	func _get_unique_id() -> int:
		return 1

	func _get_peer_ids() -> PackedInt32Array:
		return PackedInt32Array()

	func _rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
		rpcs.append([peer, String(method), args])
		return OK

	func _get_remote_sender_id() -> int:
		return sender

	func _object_configuration_add(object: Object, configuration: Variant) -> Error:
		return OK

	func _object_configuration_remove(object: Object, configuration: Variant) -> Error:
		return OK


# The real grace timer could end in match_cancel to a backend; never start it.
class ProbeProvider extends EdgegapServerProvider:
	func _start_grace_timer() -> void:
		pass


# Made-up user ids, the same ones the Go probe used.
const USER_A := "3f2b9c1e-6a4d-4e8b-9d21-5c7a0e4f8b13"
const USER_B := "8d61a0f4-2c3e-4b7a-a9f5-0e1d2c3b4a59"

var _api: FakeApi
var _holder: Node
var _connector: NetworkConnector
var _provider: ProbeProvider
var _rejections: Array = []
var _saved_is_server: bool
var _saved_env: String


# The runtime's rule (fleet_allocator.go:722-727): "<user id>_<index>" for
# index in 0..player_count-1.
static func _sid(user_id: String, index: int) -> String:
	return "%s_%d" % [user_id, index]


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_saved_is_server = Netcode.is_server
	Netcode.is_server = true
	_rejections = []
	_api = FakeApi.new()
	_holder = Node.new()
	_holder.name = "H37v2SidProbe"
	add_child(_holder)
	get_tree().set_multiplayer(_api, _holder.get_path())
	_connector = NetworkConnector.new()
	_holder.add_child(_connector)
	_provider = ProbeProvider.new()
	_saved_env = OS.get_environment("EXPECTED_SESSION_IDS")
	OS.set_environment("EXPECTED_SESSION_IDS", ",".join([
		_sid(USER_A, 0), _sid(USER_A, 1), _sid(USER_B, 0)]))
	_provider._load_allowlist_from_env()
	# Record which peer was being validated when the provider rejected.
	_provider.session_request_failed.connect(
		func(message: String) -> void:
			_rejections.append([_api.sender, message]))
	_connector.session_provider = _provider


func after_each() -> void:
	if _saved_env.is_empty():
		OS.unset_environment("EXPECTED_SESSION_IDS")
	else:
		OS.set_environment("EXPECTED_SESSION_IDS", _saved_env)
	get_tree().set_multiplayer(null, _holder.get_path())
	_holder.queue_free()
	_provider.free()
	Netcode.is_server = _saved_is_server
	ArrayPool.clear_all_pools()


func _declare(peer_id: int, session_ids: Array, backend_id: String) -> void:
	var attributes: Array = []
	for i in session_ids.size():
		attributes.append({})
	_api.sender = peer_id
	_connector._server_rpc_declare_players(
		session_ids,
		attributes,
		str(ProjectSettings.get_setting(
			"application/config/protocol_version", 1)),
		backend_id,
	)


func _ids_sent_to(peer_id: int) -> Array:
	for entry in _api.rpcs:
		if entry[0] == peer_id and entry[1] == "_client_rpc_receive_player_ids":
			return entry[2][0]
	return []


# G1.2: player A's client (peer 5) declares B's computed id, and B's account
# id as its backend id, before B connects. The provider accepts it; B
# (peer 6) is the one rejected.
func test_fellow_player_claims_computed_sid_first() -> void:
	assert_eq(_provider._allowed_session_ids.size(), 3, "allowlist loaded")
	_declare(5, [_sid(USER_B, 0)], USER_B)
	assert_eq(_rejections.size(), 0, "G1.2: A's claim of B's id accepted")
	assert_true(
		_provider._claimed_session_ids.has(_sid(USER_B, 0)),
		"G1.2: B's id is now claimed by peer 5",
	)
	var stolen_ids: Array = _ids_sent_to(5)
	assert_eq(stolen_ids.size(), 1, "peer 5 got B's player id")
	assert_eq(
		_provider._player_to_backend_id.get(stolen_ids[0], ""), USER_B,
		"H17: peer 5's slot is recorded as B's account",
	)
	_declare(6, [_sid(USER_B, 0)], USER_B)
	assert_eq(_rejections.size(), 1, "the owner is rejected")
	assert_eq(_rejections[0][0], 6, "the rejected peer is B, the owner")
	# Today (G1.3) the rejection is ignored and the last declarer wins.
	assert_eq(_ids_sent_to(6), stolen_ids, "G1.3: same player id reused")
	assert_eq(
		_connector._player_id_to_peer_id.get(stolen_ids[0], -1), 6,
		"G1.3: the slot moves to the later declarer",
	)


# G1.2: one peer claims every slot of the set in a single declare (3 ids,
# under max_local_player_count = 4). Everyone else is then rejected.
func test_one_peer_claims_every_slot() -> void:
	_declare(5, [_sid(USER_A, 0), _sid(USER_A, 1), _sid(USER_B, 0)], USER_A)
	assert_eq(_rejections.size(), 0, "all three ids accepted from peer 5")
	assert_eq(_ids_sent_to(5).size(), 3, "peer 5 holds three player ids")
	_declare(6, [_sid(USER_B, 0)], USER_B)
	assert_eq(_rejections.size(), 1, "B rejected")
	assert_eq(_rejections[0][0], 6, "the rejected peer is B")


# Control: a name that the runtime would not mint is rejected.
func test_unminted_sid_rejected() -> void:
	_declare(7, [_sid(USER_B, 1)], USER_B)
	assert_eq(_rejections.size(), 1, "B_1 is not on the allowlist")
