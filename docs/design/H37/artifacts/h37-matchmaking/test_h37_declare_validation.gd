extends GutTest
## H37 probe (h37-matchmaking, F1 G1.1 and G1.3): the server's declare path
## assigns ids and announces the players whatever the session validation
## says. A MultiplayerAPIExtension fakes the RPC sender and records RPCs;
## nothing binds a port, nothing reaches a backend (the provider is never
## added to the tree, so its idle timer and allowlist loader never run).


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
	_holder.name = "H37DeclareProbe"
	add_child(_holder)
	get_tree().set_multiplayer(_api, _holder.get_path())
	_connector = NetworkConnector.new()
	_holder.add_child(_connector)
	_provider = ProbeProvider.new()
	_provider._allowed_session_ids = {"userA_0": true, "userB_0": true}
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


func _declare(peer_id: int, session_id: String) -> void:
	_api.sender = peer_id
	_connector._server_rpc_declare_players(
		[session_id],
		[{}],
		str(ProjectSettings.get_setting(
			"application/config/protocol_version", 1)),
		"backend-of-peer-%d" % peer_id,
	)


func _ids_sent_to(peer_id: int) -> Array:
	for entry in _api.rpcs:
		if entry[0] == peer_id and entry[1] == "_client_rpc_receive_player_ids":
			return entry[2][0]
	return []


# Control: a valid session id is accepted and the peer gets its id.
func test_valid_session_is_accepted() -> void:
	_declare(5, "userA_0")
	assert_eq(_rejections.size(), 0, "control: no rejection")
	assert_eq(_ids_sent_to(5).size(), 1, "control: id sent")
	assert_eq(_declared.size(), 1, "control: players declared")


# G1.1: a session id that is not on the allowlist is rejected by the
# provider, and the connector sends ids and spawns the player anyway.
func test_unknown_session_still_gets_ids_and_spawn() -> void:
	_declare(7, "forged_0")
	assert_eq(_rejections.size(), 1, "provider rejected the forged id")
	assert_eq(_ids_sent_to(7).size(), 1, "G1.1: ids sent to rejected peer")
	assert_eq(_declared.size(), 1, "G1.1: rejected peer declared to level")
	assert_eq(_declared[0][0], 7)


# G1.3: a second peer presenting an already-claimed session id is rejected
# by the provider, gets the SAME player id, and takes over its peer mapping.
func test_duplicate_session_reuses_player_id_and_moves_peer() -> void:
	_declare(5, "userA_0")
	var first_ids: Array = _ids_sent_to(5)
	_declare(6, "userA_0")
	assert_eq(_rejections.size(), 1, "provider rejected the duplicate")
	var second_ids: Array = _ids_sent_to(6)
	assert_eq(second_ids, first_ids, "G1.3: same player id reused")
	assert_eq(_declared.size(), 2, "G1.3: duplicate declared to level")
	var player_id: int = first_ids[0]
	assert_eq(
		_connector._player_id_to_peer_id.get(player_id, -1), 6,
		"G1.3: the player id now maps to the second peer",
	)


# H17: the server stores whatever backend id the client declares, even one
# that is not the owner of the validated session id.
func test_declared_backend_id_is_trusted() -> void:
	_api.sender = 5
	_connector._server_rpc_declare_players(
		["userA_0"],
		[{}],
		str(ProjectSettings.get_setting(
			"application/config/protocol_version", 1)),
		"userB",
	)
	assert_eq(_rejections.size(), 0, "userA's session is valid")
	var player_id: int = _ids_sent_to(5)[0]
	assert_eq(
		_provider._player_to_backend_id.get(player_id, ""), "userB",
		"H17: userA's slot is recorded as account userB",
	)
