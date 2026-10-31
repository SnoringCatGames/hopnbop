extends GutTest
## H58: a local-only guest can export and delete. Both flows
## need a server session the guest does not have yet, so the
## SDK starts the guest (device) session first and then calls
## the RPC as the guest's own account.
##
## Same harness as test_auth_link_guest.gd: a swapped-in
## throwaway token store and fake Nakama client, with the real
## PlatformAuthApiClient code under test.


const _TEST_AUTH_FILE := "user://test_auth_guest_ops.cfg"
const _GUEST_ID := "guest-player"
const _ACCESS_TOKEN_LIFETIME_SEC := 7200


class FakeNakamaClient extends NakamaClient:
	var device_auth_ids: Array = []
	var rpc_calls: Array = []
	var device_session: NakamaSession
	var rpc_result: NakamaAsyncResult

	func _init() -> void:
		super(
			Nakama.get_client_adapter(),
			"",
			"https",
			"fake.invalid",
			443,
			Nakama.DEFAULT_TIMEOUT,
		)

	func authenticate_device_async(
		p_id: String,
		_p_username = null,
		_p_create: bool = true,
		_p_vars = null,
	) -> NakamaSession:
		device_auth_ids.append(p_id)
		return device_session

	func rpc_async(
		_p_session: NakamaSession,
		p_id: String,
		_p_payload = null,
	) -> NakamaAsyncResult:
		rpc_calls.append(p_id)
		return rpc_result


var _client: PlatformAuthApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _export_results: Array = []
var _delete_results: Array = []
var _original_token_store
var _original_nakama_client
var _was_platform_auth_processing := false


func before_each() -> void:
	_was_platform_auth_processing = Platform.auth.is_processing()
	Platform.auth.set_process(false)
	_original_token_store = Platform.token_store
	_original_nakama_client = Platform.nakama_client

	_nakama = FakeNakamaClient.new()
	_nakama.device_session = _session(_GUEST_ID)
	_nakama.rpc_result = NakamaAPI.ApiRpc.create(NakamaAPI, {
		"payload": JSON.stringify({"player_id": _GUEST_ID}),
	})
	Platform.nakama_client = _nakama

	_client = PlatformAuthApiClient.new()
	_export_results = []
	_delete_results = []
	_client.export_completed.connect(_on_export_completed)
	_client.delete_completed.connect(_on_delete_completed)

	# A local-only guest: anonymous identity, no session yet.
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.is_anonymous = true
	_store.provider = "anonymous"
	_store.player_id = _GUEST_ID
	_store.local_player_id = "device-1"
	Platform.token_store = _store


func after_each() -> void:
	_client.free()
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client
	Platform.auth.set_process(_was_platform_auth_processing)


func _on_export_completed(
	success: bool,
	error: String,
	data: Dictionary,
) -> void:
	_export_results.append([success, error, data])


func _on_delete_completed(success: bool, error: String) -> void:
	_delete_results.append([success, error])


func _fake_jwt(uid: String) -> String:
	var now := int(Time.get_unix_time_from_system())
	var payload := Marshalls.utf8_to_base64(JSON.stringify({
		"exp": now + _ACCESS_TOKEN_LIFETIME_SEC,
		"uid": uid,
	})).replace("+", "-").replace("/", "_").replace("=", "")
	return "test-header.%s.test-signature" % payload


func _session(uid: String) -> NakamaSession:
	return NakamaSession.new(_fake_jwt(uid), false, _fake_jwt(uid))


func test_guest_without_saved_id_mints_one() -> void:
	# A saved file that loaded but holds no guest id has no
	# account to orphan: the guest mints a device id and
	# authenticates with it instead of failing every call.
	_store.local_player_id = ""

	_client.get_guest_jwt()
	for i in 60:
		if not _nakama.device_auth_ids.is_empty():
			break
		await get_tree().process_frame

	assert_eq(_nakama.device_auth_ids.size(), 1, "device auth ran")
	if _nakama.device_auth_ids.is_empty():
		return
	assert_ne(_nakama.device_auth_ids[0], "", "fresh id minted")
	assert_eq(
		_store.local_player_id, _nakama.device_auth_ids[0],
		"minted id kept")


func test_guest_export_starts_a_session_then_exports() -> void:
	_client.export_player_data()
	for i in 60:
		if not _export_results.is_empty():
			break
		await get_tree().process_frame

	assert_eq(_nakama.device_auth_ids, ["device-1"])
	assert_eq(_nakama.rpc_calls, ["export_player_data"])
	assert_eq(_export_results.size(), 1)
	assert_true(_export_results[0][0], "export succeeds")


func test_guest_delete_starts_a_session_then_requests() -> void:
	_client.delete_account()
	for i in 60:
		if not _delete_results.is_empty():
			break
		await get_tree().process_frame

	assert_eq(_nakama.device_auth_ids, ["device-1"])
	assert_eq(_nakama.rpc_calls, ["delete_account"])
	assert_eq(_delete_results, [[true, ""]])
