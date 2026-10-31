extends GutTest
## SP41: a failed delete_account must report through
## delete_completed, not auth_completed. _send_delete_request
## cleared _is_deleting before _emit_failure, so the failure
## took the sign-in branch and the Delete panel stayed busy.
## The H37 probe (test_h37_account_probe.gd DEL-2) asserted the
## buggy routing; this test asserts the fixed routing.


const _TEST_AUTH_FILE := "user://test_auth_delete_failure.cfg"
const _TEST_PLAYER_ID := "test-player"
const _ACCESS_TOKEN_LIFETIME_SEC := 7200
const _REFRESH_TOKEN_LIFETIME_SEC := 604800
const _HTTP_SERVICE_UNAVAILABLE := 503
const _GRPC_UNAVAILABLE := 14


## Stands in for Platform.nakama_client, without network I/O.
class FakeNakamaClient extends NakamaClient:
	var rpc_ids: Array = []
	var next_rpc_exception: NakamaException

	func _init() -> void:
		super(
			Nakama.get_client_adapter(),
			"",
			"https",
			"fake.invalid",
			443,
			Nakama.DEFAULT_TIMEOUT,
		)

	func rpc_async(
		_p_session: NakamaSession,
		p_id: String,
		_p_payload = null,
	):
		rpc_ids.append(p_id)
		if next_rpc_exception != null:
			return NakamaAPI.ApiRpc.new(next_rpc_exception)
		return NakamaAPI.ApiRpc.new()


var _client: PlatformAuthApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _delete_results: Array = []
var _auth_results: Array = []
var _jwt_serial := 0
var _original_token_store
var _original_nakama_client
var _was_platform_auth_processing := false


func before_each() -> void:
	_was_platform_auth_processing = Platform.auth.is_processing()
	Platform.auth.set_process(false)
	_original_token_store = Platform.token_store
	_original_nakama_client = Platform.nakama_client

	var now := int(Time.get_unix_time_from_system())
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.provider = "google"
	_store.player_id = _TEST_PLAYER_ID
	_store.display_name = "Player"
	_store.expires_at = now + _ACCESS_TOKEN_LIFETIME_SEC
	_store.jwt_token = _fake_jwt(_store.expires_at)
	_store.refresh_token = _fake_jwt(
		now + _REFRESH_TOKEN_LIFETIME_SEC)
	Platform.token_store = _store

	_nakama = FakeNakamaClient.new()
	Platform.nakama_client = _nakama

	_client = PlatformAuthApiClient.new()
	_delete_results = []
	_auth_results = []
	_client.delete_completed.connect(_on_delete_completed)
	_client.auth_completed.connect(_on_auth_completed)


func after_each() -> void:
	_client.free()
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client
	Platform.auth.set_process(_was_platform_auth_processing)


func _on_delete_completed(success: bool, error: String) -> void:
	_delete_results.append([success, error])


func _on_auth_completed(success: bool, error: String) -> void:
	_auth_results.append([success, error])


func test_failed_delete_reports_delete_completed() -> void:
	_nakama.next_rpc_exception = NakamaException.new(
		"Service unavailable",
		_HTTP_SERVICE_UNAVAILABLE,
		_GRPC_UNAVAILABLE,
	)

	_client.delete_account()
	for _i in 60:
		if not _delete_results.is_empty():
			break
		await get_tree().process_frame

	assert_has(_nakama.rpc_ids, "delete_account")
	assert_eq(_delete_results.size(), 1)
	if _delete_results.is_empty():
		return
	assert_false(_delete_results[0][0], "delete failed")
	assert_ne(_delete_results[0][1], "", "error text present")
	assert_true(_auth_results.is_empty(), "not a sign-in failure")
	assert_false(_client._is_deleting, "delete state cleared")
	assert_false(_store.jwt_token.is_empty(), "still signed in")


func test_delete_refused_while_link_pending() -> void:
	# A delete started while a link waits for its result
	# would share the failure routing. It refuses up front
	# through delete_completed and sends nothing.
	_client._is_linking = true

	_client.delete_account()

	assert_eq(_delete_results.size(), 1, "refusal reported")
	if _delete_results.is_empty():
		return
	assert_false(_delete_results[0][0], "delete refused")
	assert_ne(_delete_results[0][1], "", "error text present")
	assert_false(_client._is_deleting, "delete never started")
	assert_true(_nakama.rpc_ids.is_empty(), "no delete sent")
	assert_true(_client._is_linking, "link left pending")


func test_delete_refused_while_unlink_pending() -> void:
	_client._is_unlinking = true

	_client.delete_account()

	assert_eq(_delete_results.size(), 1, "refusal reported")
	if _delete_results.is_empty():
		return
	assert_false(_delete_results[0][0], "delete refused")
	assert_false(_client._is_deleting, "delete never started")
	assert_true(_nakama.rpc_ids.is_empty(), "no delete sent")


func test_delete_waits_for_in_flight_refresh() -> void:
	# The delete waits out a refresh already in flight, so
	# the refresh result cannot land after the delete clears
	# the store. delete_account runs to its wait
	# synchronously, so no frames need pumping here.
	_client._is_refreshing = true

	_client.delete_account()

	assert_false(
		_nakama.rpc_ids.has("delete_account"),
		"delete held for the refresh")
	assert_true(_client._is_deleting, "delete still pending")
	assert_true(_delete_results.is_empty(), "nothing reported yet")

	_client._is_refreshing = false
	_client.auth_completed.emit(true, "")

	assert_has(_nakama.rpc_ids, "delete_account")
	assert_eq(_delete_results.size(), 1)
	if _delete_results.is_empty():
		return
	assert_true(_delete_results[0][0], "delete completed")
	assert_true(_store.jwt_token.is_empty(), "session cleared")


## A JWT-shaped string that NakamaSession can parse. Unsigned,
## and unique per call so stored tokens can be told apart.
func _fake_jwt(expires_at: int) -> String:
	_jwt_serial += 1
	var claims := JSON.stringify({
		"exp": expires_at,
		"uid": _TEST_PLAYER_ID,
		"tid": "test-token-%d" % _jwt_serial,
	})
	var payload := (
		Marshalls.utf8_to_base64(claims)
		.replace("+", "-")
		.replace("/", "_")
		.replace("=", "")
	)
	return "test-header.%s.test-signature" % payload
