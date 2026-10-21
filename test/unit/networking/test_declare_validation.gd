extends GutTest
## Regression tests for the server declare path (H41, H43, H17;
## flipped from the H37 probes in docs/design/H37/artifacts/).
## A MultiplayerAPIExtension fakes the RPC sender and records RPCs;
## nothing binds a port, nothing reaches a backend (the provider is
## never added to the tree, so its timers never run).


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


const USER_A := "user-a"
const USER_B := "user-b"
const TOKEN_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const TOKEN_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var _api: FakeApi
var _holder: Node
var _connector: NetworkConnector
var _provider: ProbeProvider
var _declared: Array = []
var _rejections: Array = []
var _saved_is_server: bool


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_saved_is_server = Netcode.is_server
	Netcode.is_server = true
	_declared = []
	_rejections = []
	_api = FakeApi.new()
	_holder = Node.new()
	_holder.name = "DeclareValidationTest"
	add_child(_holder)
	get_tree().set_multiplayer(_api, _holder.get_path())
	_connector = NetworkConnector.new()
	_holder.add_child(_connector)
	_provider = ProbeProvider.new()
	_provider._allowed_session_ids = {TOKEN_A: true, TOKEN_B: true}
	_provider._session_id_to_user_id = {
		TOKEN_A: USER_A,
		TOKEN_B: USER_B,
	}
	_provider.session_request_failed.connect(
		func(message: String) -> void: _rejections.append(message))
	_connector.session_provider = _provider
	_connector.peer_players_declared.connect(
		func(peer_id: int, ids: Array, _attributes: Array) -> void:
			_declared.append([peer_id, ids.duplicate()]))


func after_each() -> void:
	get_tree().set_multiplayer(null, _holder.get_path())
	_holder.queue_free()
	_provider.free()
	Netcode.is_server = _saved_is_server
	ArrayPool.clear_all_pools()


func _declare(peer_id: int, token: String, backend_id: String) -> void:
	_api.sender = peer_id
	_connector._server_rpc_declare_players(
		[token],
		[{}],
		str(ProjectSettings.get_setting(
			"application/config/protocol_version", 1)),
		backend_id,
	)


func _ids_sent_to(peer_id: int) -> Array:
	for entry in _api.rpcs:
		if entry[0] == peer_id and entry[1] == "_client_rpc_receive_player_ids":
			return entry[2][0]
	return []


# Control: a valid token is accepted and the peer gets its id.
func test_valid_token_is_accepted() -> void:
	_declare(5, TOKEN_A, USER_A)
	assert_eq(_rejections.size(), 0, "control: no rejection")
	assert_eq(_ids_sent_to(5).size(), 1, "control: id sent")
	assert_eq(_declared.size(), 1, "control: players declared")
	var player_id: int = _ids_sent_to(5)[0]
	assert_eq(
		_provider.get_backend_player_id_map().get(player_id, ""), USER_A,
		"control: backend id derived from the token",
	)


# G1.1: an unknown token is rejected before any id exists: the
# peer is sent nothing and the level never hears about it.
func test_unknown_token_gets_no_ids_and_no_spawn() -> void:
	_declare(7, "ffffffffffffffffffffffffffffffff", USER_A)
	assert_eq(_rejections.size(), 1, "provider rejected the forged token")
	assert_eq(_ids_sent_to(7).size(), 0, "G1.1: no ids sent to rejected peer")
	assert_eq(_declared.size(), 0, "G1.1: rejected peer never declared")


# H17: presenting another account's token while declaring your
# own backend id is a forgery, not a claim.
func test_token_with_foreign_backend_id_is_rejected() -> void:
	_declare(5, TOKEN_B, USER_A)
	assert_eq(_rejections.size(), 1, "H17: declared id is not the owner")
	assert_eq(_ids_sent_to(5).size(), 0, "H17: no ids sent")
	assert_eq(_declared.size(), 0, "H17: never declared")


# G1.3/H43: the same token re-claimed from a new peer transfers
# the slot (same player id, peer mapping moved, count unchanged)
# instead of the later declarer silently winning or the owner
# being kicked.
func test_reclaim_transfers_slot_to_new_peer() -> void:
	_declare(5, TOKEN_A, USER_A)
	var first_ids: Array = _ids_sent_to(5)
	_declare(6, TOKEN_A, USER_A)
	assert_eq(_rejections.size(), 0, "re-claim by the owner is accepted")
	assert_eq(_ids_sent_to(6), first_ids, "same player id reused")
	assert_eq(_declared.size(), 2, "transfer announced to the level")
	var player_id: int = first_ids[0]
	assert_eq(
		_connector._player_id_to_peer_id.get(player_id, -1), 6,
		"player id now maps to the new peer",
	)
	assert_eq(
		_provider._validated_player_count, 1,
		"re-claim does not count the player twice",
	)
	assert_eq(
		_provider.get_backend_player_id_map().get(player_id, ""), USER_A,
		"backend id still derived from the token",
	)


# One declare may not carry the same token twice.
func test_duplicate_token_in_one_declare_is_rejected() -> void:
	_api.sender = 5
	_connector._server_rpc_declare_players(
		[TOKEN_A, TOKEN_A],
		[{}, {}],
		str(ProjectSettings.get_setting(
			"application/config/protocol_version", 1)),
		USER_A,
	)
	assert_eq(_rejections.size(), 1, "duplicate token rejected")
	assert_eq(_declared.size(), 0, "never declared")
