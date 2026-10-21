extends GutTest
## H57/H62: a guest links a provider onto their device account
## (never a sign-in that abandons it), a linked guest stops being
## anonymous, Nakama's AlreadyExists surfaces as PROVIDER_CONFLICT,
## and unlinking the last identity answers LAST_PROVIDER locally.
##
## The client under test is constructed via .new() and never added
## to the scene tree, with a throwaway token store and a fake
## Nakama client swapped into Platform, as
## test_auth_api_client_privacy.gd does. Only the Google code
## exchange is stubbed (it would call Google); everything else
## runs the real SDK code against the fake client.


const _TEST_AUTH_FILE := "user://test_auth_link_guest.cfg"
const _GUEST_ID := "guest-player"
const _ACCESS_TOKEN_LIFETIME_SEC := 7200
const _GENERATED_NAME := "SwiftOtter_4821"
const _PICTURE := "https://example.invalid/pic.png"
const _GRPC_ALREADY_EXISTS := 6


## Stands in for Platform.nakama_client: records device auth and
## link/unlink calls, and answers from the knobs below.
class FakeNakamaClient extends NakamaClient:
	var device_auth_ids: Array = []
	var link_calls: Array = []
	var unlink_calls: Array = []
	var updates: Array = []
	var account: Dictionary = {}
	var device_session: NakamaSession
	var link_result: NakamaAsyncResult
	var unlink_result: NakamaAsyncResult

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

	func link_google_async(
		_p_session: NakamaSession,
		p_token: String,
	) -> NakamaAsyncResult:
		link_calls.append(p_token)
		return link_result

	func unlink_google_async(
		_p_session: NakamaSession,
		_p_token: String,
	) -> NakamaAsyncResult:
		unlink_calls.append(_p_token)
		return unlink_result

	func update_account_async(
		_p_session: NakamaSession,
		p_username = null,
		p_display_name = null,
		p_avatar_url = null,
		_p_lang_tag = null,
		_p_location = null,
		_p_timezone = null,
	) -> NakamaAsyncResult:
		updates.append({
			"username": p_username,
			"display_name": p_display_name,
			"avatar_url": p_avatar_url,
		})
		return NakamaAsyncResult.new()

	func get_account_async(_p_session: NakamaSession):
		return NakamaAPI.ApiAccount.create(NakamaAPI, account)


## The real client, with only the Google code exchange stubbed:
## it would make an HTTPS call to Google with the auth code.
class TestAuthClient extends PlatformAuthApiClient:
	func _exchange_google_code_for_id_token(
		_code: String,
		_redirect_uri: String,
	) -> String:
		var payload := Marshalls.utf8_to_base64(JSON.stringify({
			"sub": "google-1",
			"picture": "https://example.invalid/pic.png",
		})).replace("+", "-").replace("/", "_").replace("=", "")
		return "test-header.%s.test-signature" % payload


var _client: TestAuthClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _link_results: Array = []
var _unlink_results: Array = []
var _original_token_store
var _original_nakama_client
var _was_platform_auth_processing := false


func before_each() -> void:
	_was_platform_auth_processing = Platform.auth.is_processing()
	Platform.auth.set_process(false)
	_original_token_store = Platform.token_store
	_original_nakama_client = Platform.nakama_client

	_nakama = FakeNakamaClient.new()
	_nakama.account = {
		"devices": [{"id": "device-1"}],
		"user": {
			"id": _GUEST_ID,
			"display_name": _GENERATED_NAME,
			"avatar_url": _PICTURE,
			"google_id": "google-1",
		},
	}
	_nakama.link_result = NakamaAsyncResult.new()
	_nakama.unlink_result = NakamaAsyncResult.new()
	Platform.nakama_client = _nakama

	_client = TestAuthClient.new()
	_link_results = []
	_unlink_results = []
	_client.link_completed.connect(_on_link_completed)
	_client.unlink_completed.connect(_on_unlink_completed)


func after_each() -> void:
	_client.free()
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client
	Platform.auth.set_process(_was_platform_auth_processing)


func _on_link_completed(
	success: bool,
	error: String,
	provider: String,
) -> void:
	_link_results.append([success, error, provider])


func _on_unlink_completed(
	success: bool,
	error: String,
	provider: String,
) -> void:
	_unlink_results.append([success, error, provider])


## A signed-out guest's local identity: no server session yet.
func _make_guest_store(with_session: bool) -> void:
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.is_anonymous = true
	_store.provider = "anonymous"
	_store.player_id = _GUEST_ID
	_store.local_player_id = "device-1"
	_store.display_name = _GENERATED_NAME
	if with_session:
		var now := int(Time.get_unix_time_from_system())
		_store.expires_at = now + _ACCESS_TOKEN_LIFETIME_SEC
		_store.jwt_token = _fake_jwt(_GUEST_ID)
		_store.refresh_token = _fake_jwt(_GUEST_ID)
	Platform.token_store = _store


func _fake_jwt(uid: String) -> String:
	var now := int(Time.get_unix_time_from_system())
	var payload := Marshalls.utf8_to_base64(JSON.stringify({
		"exp": now + _ACCESS_TOKEN_LIFETIME_SEC,
		"uid": uid,
	})).replace("+", "-").replace("/", "_").replace("=", "")
	return "test-header.%s.test-signature" % payload


func _session(uid: String) -> NakamaSession:
	return NakamaSession.new(_fake_jwt(uid), false, _fake_jwt(uid))


func _await_link() -> void:
	for i in 60:
		if not _link_results.is_empty():
			return
		await get_tree().process_frame


# ------------------------------------------------------------------
# Guest upgrade links onto the device account (H57)
# ------------------------------------------------------------------


func test_guest_link_keeps_account_and_clears_anonymous() -> void:
	_make_guest_store(true)

	_client.submit_platform_link(
		PlatformAuthApiClient.Provider.GOOGLE, "auth-code")
	await _await_link()

	assert_eq(_link_results, [[true, "", "google"]])
	assert_eq(_nakama.link_calls.size(), 1, "one link call")
	assert_false(
		_store.is_anonymous, "a linked guest is not a guest")
	assert_eq(_store.provider, "google")
	assert_eq(
		_store.player_id, _GUEST_ID,
		"the account is the guest's own, not a new one")


func test_guest_link_conflict_is_provider_conflict() -> void:
	_make_guest_store(true)
	_nakama.link_result = NakamaAPI.ApiRpc.new(
		NakamaException.new(
			"Google ID is already in use.", 400,
			_GRPC_ALREADY_EXISTS))

	_client.submit_platform_link(
		PlatformAuthApiClient.Provider.GOOGLE, "auth-code")
	await _await_link()

	assert_eq(
		_link_results, [[false, "PROVIDER_CONFLICT", "google"]])
	assert_true(
		_store.is_anonymous, "a failed link changes nothing")


func test_link_without_guest_session_starts_one_first() -> void:
	_make_guest_store(false)
	_nakama.device_session = _session(_GUEST_ID)

	var ok: bool = await _client._ensure_guest_session_for_link()

	assert_true(ok)
	assert_eq(_nakama.device_auth_ids, ["device-1"])
	assert_eq(_store.player_id, _GUEST_ID)


# ------------------------------------------------------------------
# Unlinking the last identity (LK-3 / H62)
# ------------------------------------------------------------------


func test_unlink_last_provider_is_refused_locally() -> void:
	_make_guest_store(true)
	_store.is_anonymous = false
	_store.provider = "google"
	_store.linked_providers = ["google"]

	_client.unlink_provider(PlatformAuthApiClient.Provider.GOOGLE)

	assert_eq(
		_unlink_results, [[false, "LAST_PROVIDER", "google"]])
	assert_true(
		_nakama.unlink_calls.is_empty(),
		"no server call for a local refusal")


func test_linked_guest_can_unlink_provider() -> void:
	_make_guest_store(true)
	_store.linked_providers = ["anonymous", "google"]

	_client.unlink_provider(PlatformAuthApiClient.Provider.GOOGLE)
	for i in 60:
		if not _unlink_results.is_empty():
			break
		await get_tree().process_frame

	assert_eq(_unlink_results, [[true, "", "google"]])
	assert_eq(_nakama.unlink_calls.size(), 1)
