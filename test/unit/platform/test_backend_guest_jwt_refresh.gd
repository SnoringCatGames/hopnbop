extends GutTest
## H64: BackendApiClient._ensure_session used to fetch a guest
## JWT only when no session existed, so after the 2-hour token
## expired a guest's calls went out with the dead JWT. It now
## re-authenticates the guest on expiry too. Signed-in players
## are left to the SDK's refresh.
##
## Same harness as the other platform tests: throwaway token
## store, fake Nakama client, real SDK auth client (paused).


const _TEST_AUTH_FILE := "user://test_backend_guest_jwt.cfg"
const _GUEST_ID := "guest-player"
const _ACCESS_TOKEN_LIFETIME_SEC := 7200


class FakeNakamaClient extends NakamaClient:
	var device_auth_ids: Array = []
	var device_session: NakamaSession

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


var _client: BackendApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
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
	Platform.nakama_client = _nakama

	_client = BackendApiClient.new()


func after_each() -> void:
	_client.free()
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client
	Platform.auth.set_process(_was_platform_auth_processing)


func _make_store(anonymous: bool, expired: bool) -> void:
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.is_anonymous = anonymous
	_store.provider = "anonymous" if anonymous else "google"
	_store.player_id = _GUEST_ID
	_store.local_player_id = "device-1"
	var now := int(Time.get_unix_time_from_system())
	_store.expires_at = (
		now - 10 if expired
		else now + _ACCESS_TOKEN_LIFETIME_SEC)
	_store.jwt_token = _fake_jwt(
		_GUEST_ID, _store.expires_at)
	_store.refresh_token = _fake_jwt(
		_GUEST_ID, _store.expires_at)
	Platform.token_store = _store


func _fake_jwt(uid: String, expires_at: int) -> String:
	var payload := Marshalls.utf8_to_base64(JSON.stringify({
		"exp": expires_at,
		"uid": uid,
	})).replace("+", "-").replace("/", "_").replace("=", "")
	return "test-header.%s.test-signature" % payload


func _session(uid: String) -> NakamaSession:
	var now := int(Time.get_unix_time_from_system())
	return NakamaSession.new(
		_fake_jwt(uid, now + _ACCESS_TOKEN_LIFETIME_SEC),
		false,
		_fake_jwt(uid, now + _ACCESS_TOKEN_LIFETIME_SEC))


func test_expired_guest_jwt_is_refetched() -> void:
	_make_store(true, true)

	var session = await _client._ensure_session()

	assert_not_null(session)
	assert_eq(_nakama.device_auth_ids, ["device-1"])
	assert_true(Platform.token_store.is_token_valid())


func test_valid_guest_jwt_is_reused() -> void:
	_make_store(true, false)

	var session = await _client._ensure_session()

	assert_not_null(session)
	assert_true(
		_nakama.device_auth_ids.is_empty(),
		"no re-auth while the token is valid")


func test_expired_signed_in_session_is_not_guest_authed() -> void:
	_make_store(false, true)

	var session = await _client._ensure_session()

	assert_not_null(session)
	assert_true(
		_nakama.device_auth_ids.is_empty(),
		"signed-in renewal belongs to the SDK refresh")
