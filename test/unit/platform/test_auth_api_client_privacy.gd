extends GutTest
## Unit tests for PlatformAuthApiClient's personal-data behavior:
##
##   - Google sign-in asks for no email, and an account's email is
##     never reported as a sign-in provider.
##   - cancel_account_deletion(): a deletion request clears the
##     profile on the server and keeps no copy, so a successful
##     cancel puts back the display name and picture from this
##     session's Google sign-in (only for the account that signed
##     in), then refreshes the token store from the account.
##   - export_player_data() keeps the server's JSON text in
##     last_export_json, so the game saves it as sent instead of
##     re-encoding Godot's float-only parse of it.
##
## The client under test is constructed via .new() and never added
## to the scene tree. Each test swaps a throwaway token store and a
## fake Nakama client into Platform, and pauses the live
## Platform.auth node meanwhile, as test_auth_api_client_refresh.gd
## does.


const _TEST_AUTH_FILE := "user://test_auth_api_client_privacy.cfg"
const _TEST_PLAYER_ID := "test-player"
const _OTHER_PLAYER_ID := "someone-else"
const _ACCESS_TOKEN_LIFETIME_SEC := 7200
const _GOOGLE_NAME := "Ada Lovelace"
const _GOOGLE_PICTURE := "https://example.invalid/ada.png"
const _DELETED_MARKER := "[deleted]"
const _CANCEL_RPC := "cancel_account_deletion"
const _EXPORT_RPC := "export_player_data"
const _GRPC_INTERNAL := 13


## Stands in for Platform.nakama_client: answers RPCs from
## rpc_results (an empty success by default), records profile
## updates, and serves `account` to get_account_async.
class FakeNakamaClient extends NakamaClient:
	var rpc_calls: Array = []
	var rpc_results: Dictionary = {}
	var updates: Array = []
	var account: Dictionary = {}

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
		rpc_calls.append(p_id)
		if rpc_results.has(p_id):
			return rpc_results[p_id]
		return NakamaAPI.ApiRpc.create(
			NakamaAPI, {"id": p_id, "payload": "{}"})

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


var _client: PlatformAuthApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _cancel_results: Array = []
var _export_results: Array = []
var _original_token_store
var _original_nakama_client
var _was_platform_auth_processing := false


func before_each() -> void:
	_was_platform_auth_processing = Platform.auth.is_processing()
	Platform.auth.set_process(false)
	_original_token_store = Platform.token_store
	_original_nakama_client = Platform.nakama_client

	# A Google player signed in to an account pending deletion: the
	# server cleared the profile, so the store holds the marker.
	var now := int(Time.get_unix_time_from_system())
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.provider = "google"
	_store.player_id = _TEST_PLAYER_ID
	_store.display_name = _DELETED_MARKER
	_store.expires_at = now + _ACCESS_TOKEN_LIFETIME_SEC
	_store.jwt_token = _fake_jwt({
		"exp": _store.expires_at, "uid": _TEST_PLAYER_ID,
	})
	_store.refresh_token = _fake_jwt({
		"exp": _store.expires_at, "uid": _TEST_PLAYER_ID,
	})
	Platform.token_store = _store

	_nakama = FakeNakamaClient.new()
	Platform.nakama_client = _nakama

	_client = PlatformAuthApiClient.new()
	_cancel_results = []
	_export_results = []
	_client.deletion_cancel_completed.connect(_on_cancel_completed)
	_client.export_completed.connect(_on_export_completed)


func after_each() -> void:
	_client.free()
	# Deletes the test auth file if a test saved one.
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client
	Platform.auth.set_process(_was_platform_auth_processing)


# ------------------------------------------------------------------
# No email
# ------------------------------------------------------------------


func test_google_sign_in_asks_for_no_email() -> void:
	var url := _client._build_google_auth_url(
		"http://127.0.0.1:9876", "state")

	assert_string_contains(url, "&scope=openid%20profile&")
	assert_false(url.contains("email"), "asks Google for an email")


func test_account_email_is_not_a_sign_in_provider() -> void:
	var account := NakamaAPI.ApiAccount.create(NakamaAPI, {
		"email": "player@example.invalid",
		"devices": [{"id": "device-1"}],
		"user": {"id": _TEST_PLAYER_ID, "google_id": "google-1"},
	})

	assert_eq(
		_client._account_to_provider_list(account),
		["anonymous", "google"],
	)


func test_provider_profile_comes_from_id_token_claims() -> void:
	var id_token := _fake_jwt({
		"sub": "google-1",
		"name": _GOOGLE_NAME,
		"picture": _GOOGLE_PICTURE,
	})

	var profile := _client._provider_profile_from_claims(
		_client._parse_jwt_claims(id_token))

	assert_eq(profile, {
		"display_name": _GOOGLE_NAME,
		"profile_image_url": _GOOGLE_PICTURE,
	})


# ------------------------------------------------------------------
# cancel_account_deletion
# ------------------------------------------------------------------


func test_cancel_restores_this_sessions_google_profile() -> void:
	_client._provider_profile = {
		"user_id": _TEST_PLAYER_ID,
		"display_name": _GOOGLE_NAME,
		"profile_image_url": _GOOGLE_PICTURE,
	}
	_nakama.account = _account(_GOOGLE_NAME, _GOOGLE_PICTURE)

	await _client.cancel_account_deletion()

	assert_eq(_nakama.rpc_calls, [_CANCEL_RPC])
	assert_eq(_nakama.updates, [{
		"username": null,
		"display_name": _GOOGLE_NAME,
		"avatar_url": _GOOGLE_PICTURE,
	}])
	assert_eq(_store.display_name, _GOOGLE_NAME)
	assert_eq(_store.profile_image_url, _GOOGLE_PICTURE)
	assert_eq(_cancel_results, [true])


func test_cancel_without_a_google_sign_in_restores_nothing() -> void:
	# A session resumed by refresh has no ID token to take a profile
	# from. The store still drops the marker the server cleared.
	_nakama.account = _account("", "")

	await _client.cancel_account_deletion()

	assert_eq(_nakama.updates, [])
	assert_eq(_store.display_name, "")
	assert_eq(_cancel_results, [true])


func test_cancel_never_applies_another_accounts_profile() -> void:
	_client._provider_profile = {
		"user_id": _OTHER_PLAYER_ID,
		"display_name": _GOOGLE_NAME,
		"profile_image_url": _GOOGLE_PICTURE,
	}
	_nakama.account = _account("", "")

	await _client.cancel_account_deletion()

	assert_eq(_nakama.updates, [], "wrote another account's profile")
	assert_eq(_cancel_results, [true])


func test_failed_cancel_reports_and_changes_nothing() -> void:
	_client._provider_profile = {
		"user_id": _TEST_PLAYER_ID,
		"display_name": _GOOGLE_NAME,
		"profile_image_url": _GOOGLE_PICTURE,
	}
	_nakama.rpc_results[_CANCEL_RPC] = _failure()

	await _client.cancel_account_deletion()

	assert_eq(_cancel_results, [false])
	assert_eq(_nakama.updates, [])
	assert_eq(_store.display_name, _DELETED_MARKER)


func test_cancel_without_a_session_reports_failure() -> void:
	_store.jwt_token = ""
	_store.refresh_token = ""

	await _client.cancel_account_deletion()

	assert_eq(_cancel_results, [false])
	assert_eq(_nakama.rpc_calls, [])


# ------------------------------------------------------------------
# export_player_data
# ------------------------------------------------------------------


func test_export_keeps_the_servers_text() -> void:
	var payload := "{\n  \"format_version\": 2,\n  \"score\": 1500\n}"
	_nakama.rpc_results[_EXPORT_RPC] = NakamaAPI.ApiRpc.create(
		NakamaAPI, {"id": _EXPORT_RPC, "payload": payload})

	await _client.export_player_data()

	assert_eq(_client.last_export_json, payload)
	assert_eq(_export_results.size(), 1)
	if _export_results.size() == 1:
		assert_true(_export_results[0].success)
		assert_eq(int(_export_results[0].data.get("score", 0)), 1500)


func test_failed_export_leaves_no_stale_text() -> void:
	_client.last_export_json = "{\"from\": \"an earlier export\"}"
	_nakama.rpc_results[_EXPORT_RPC] = _failure()

	await _client.export_player_data()

	assert_eq(_client.last_export_json, "")
	assert_eq(_export_results.size(), 1)
	if _export_results.size() == 1:
		assert_false(_export_results[0].success)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


func _on_cancel_completed(success: bool, _error: String) -> void:
	_cancel_results.append(success)


func _on_export_completed(
	success: bool,
	_error: String,
	data: Dictionary,
) -> void:
	_export_results.append({"success": success, "data": data})


func _account(display_name: String, avatar_url: String) -> Dictionary:
	return {
		"devices": [],
		"user": {
			"id": _TEST_PLAYER_ID,
			"display_name": display_name,
			"avatar_url": avatar_url,
			"google_id": "google-1",
		},
	}


func _failure() -> NakamaAsyncResult:
	return NakamaAPI.ApiRpc.new(
		NakamaException.new("failed", 500, _GRPC_INTERNAL))


## An unsigned JWT-shaped string carrying `claims`, which
## NakamaSession and _parse_jwt_claims can both read.
func _fake_jwt(claims: Dictionary) -> String:
	var payload := (
		Marshalls.utf8_to_base64(JSON.stringify(claims))
		.replace("+", "-")
		.replace("/", "_")
		.replace("=", "")
	)
	return "test-header.%s.test-signature" % payload
