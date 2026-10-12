extends GutTest
## Unit tests for PlatformAuthScreen's boot-time session resume.
##
## When the stored access token has expired, the auth screen refreshes
## the session before letting the player in. It used to sign the
## player out on any failed refresh, so a dropped connection at launch
## cost a signed-in player their session. Now only a refresh token
## that Nakama rejects signs them out. Any other failure keeps the
## session and continues to the lobby, and the auth client keeps
## retrying in the background.
##
## Drives the addon's auth screen scene against a fake Nakama client,
## with a fresh auth client and a throwaway token store swapped into
## Platform. The live auth node is paused meanwhile, since it would
## otherwise refresh the throwaway store itself.


const _AUTH_SCREEN_SCENE_PATH := (
	"res://addons/snoringcat_platform_client/ui/screens/auth_screen.tscn"
)
const _TEST_AUTH_FILE := "user://test_auth_screen_resume.cfg"
const _TEST_PLAYER_ID := "test-player"
const _ACCESS_TOKEN_EXPIRED_AGO_SEC := 60
const _ACCESS_TOKEN_LIFETIME_SEC := 7200
const _REFRESH_TOKEN_LIFETIME_SEC := 604800
## gRPC status codes, as Nakama sends them.
const _GRPC_NOT_FOUND := 5
const _GRPC_UNAVAILABLE := 14
const _GRPC_UNAUTHENTICATED := 16
## Status codes on failures that never reached Nakama's own handler.
const _NO_GRPC_STATUS := -1
const _HTTP_UNAUTHORIZED := 401
const _HTTP_NOT_FOUND := 404
const _HTTP_BAD_GATEWAY := 502
const _HTTP_SERVICE_UNAVAILABLE := 503


## Stands in for Platform.nakama_client. Answers session_refresh_async
## with a canned result, without network I/O.
class FakeNakamaClient extends NakamaClient:
	var next_result: NakamaSession

	func _init() -> void:
		super(
			Nakama.get_client_adapter(),
			"",
			"https",
			"fake.invalid",
			443,
			Nakama.DEFAULT_TIMEOUT,
		)

	func session_refresh_async(
		_p_session: NakamaSession,
		_p_vars = null,
	) -> NakamaSession:
		return next_result


var _screen: PlatformAuthScreen
var _client: PlatformAuthApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _jwt_serial := 0
var _jwt_before := ""
var _refresh_token_before := ""
var _lobby_requests := 0
var _state_resets := 0
var _offline_errors: Array = []
var _original_auth
var _original_token_store
var _original_nakama_client
var _was_original_auth_processing := false


func before_each() -> void:
	_original_auth = Platform.auth
	_original_token_store = Platform.token_store
	_original_nakama_client = Platform.nakama_client
	_was_original_auth_processing = _original_auth.is_processing()
	_original_auth.set_process(false)

	# A signed-in player launching the game after their access token
	# expired: the auth screen must refresh before letting them in.
	var now := int(Time.get_unix_time_from_system())
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.provider = "google"
	_store.player_id = _TEST_PLAYER_ID
	_store.expires_at = now - _ACCESS_TOKEN_EXPIRED_AGO_SEC
	_store.jwt_token = _fake_jwt(_store.expires_at)
	_store.refresh_token = _fake_jwt(now + _REFRESH_TOKEN_LIFETIME_SEC)
	_store.save_tokens()
	_jwt_before = _store.jwt_token
	_refresh_token_before = _store.refresh_token
	Platform.token_store = _store

	_nakama = FakeNakamaClient.new()
	Platform.nakama_client = _nakama

	# Never added to the tree, so its own _process never runs.
	_client = PlatformAuthApiClient.new()
	Platform.register_subsystem("auth", _client)

	_lobby_requests = 0
	_state_resets = 0
	_offline_errors = []
	var scene: PackedScene = load(_AUTH_SCREEN_SCENE_PATH)
	_screen = scene.instantiate()
	add_child_autofree(_screen)
	_screen.lobby_navigation_requested.connect(_on_lobby_navigation_requested)
	_screen.force_anonymous_state_reset_requested.connect(_on_state_reset)
	_screen.continued_offline.connect(_on_continued_offline)


func after_each() -> void:
	Platform.register_subsystem("auth", _original_auth)
	_original_auth.set_process(_was_original_auth_processing)
	_client.free()
	# Deletes the test auth file.
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client


# ------------------------------------------------------------------
# Transient failures keep the session
# ------------------------------------------------------------------


func test_server_error_keeps_session() -> void:
	_nakama.next_result = _failure(
		"Service unavailable",
		_HTTP_SERVICE_UNAVAILABLE,
		_GRPC_UNAVAILABLE,
	)

	_screen.on_open()

	_assert_continued_with_stored_session()


func test_network_error_keeps_session() -> void:
	_nakama.next_result = _failure(
		"HTTPRequest failed!",
		HTTPRequest.RESULT_CANT_CONNECT,
		_NO_GRPC_STATUS,
	)

	_screen.on_open()

	_assert_continued_with_stored_session()


func test_timeout_keeps_session() -> void:
	_nakama.next_result = _failure(
		"HTTPRequest failed!",
		HTTPRequest.RESULT_TIMEOUT,
		_NO_GRPC_STATUS,
	)

	_screen.on_open()

	_assert_continued_with_stored_session()


func test_response_not_from_nakama_keeps_session() -> void:
	# A proxy's error page: an HTTP error without Nakama's gRPC code.
	_nakama.next_result = _failure(
		"Failed to decode JSON response",
		_HTTP_BAD_GATEWAY,
		_NO_GRPC_STATUS,
	)

	_screen.on_open()

	_assert_continued_with_stored_session()


# ------------------------------------------------------------------
# A definitive rejection signs the player out
# ------------------------------------------------------------------


func test_rejected_refresh_token_signs_out() -> void:
	_nakama.next_result = _failure(
		"Refresh token invalid or expired.",
		_HTTP_UNAUTHORIZED,
		_GRPC_UNAUTHENTICATED,
	)

	_screen.on_open()

	_assert_signed_out()


func test_deleted_account_signs_out() -> void:
	_nakama.next_result = _failure(
		"User account not found.",
		_HTTP_NOT_FOUND,
		_GRPC_NOT_FOUND,
	)

	_screen.on_open()

	_assert_signed_out()


# ------------------------------------------------------------------
# Success
# ------------------------------------------------------------------


func test_success_continues_without_offline_notice() -> void:
	_nakama.next_result = _success()

	_screen.on_open()

	assert_eq(_lobby_requests, 1, "continued to the lobby")
	assert_eq(_offline_errors, [], "no offline notice")
	assert_true(_store.is_token_valid(), "the new session is stored")


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


func _assert_continued_with_stored_session() -> void:
	assert_eq(_lobby_requests, 1, "continued to the lobby")
	assert_eq(_offline_errors.size(), 1, "told the game it is offline")
	assert_eq(_state_resets, 0, "no sign-out reset")
	assert_eq(_store.jwt_token, _jwt_before, "access token kept")
	assert_eq(
		_store.refresh_token, _refresh_token_before, "refresh token kept")
	assert_true(
		FileAccess.file_exists(_TEST_AUTH_FILE), "auth file kept on disk")


func _assert_signed_out() -> void:
	assert_eq(_lobby_requests, 0, "stays on the auth screen")
	assert_eq(_offline_errors, [], "no offline notice")
	assert_eq(_state_resets, 1, "game-side caches reset")
	assert_true(_store.refresh_token.is_empty(), "signed out")
	assert_false(
		FileAccess.file_exists(_TEST_AUTH_FILE), "auth file deleted")
	assert_true(
		_screen.get_node("%ButtonsContainer").visible,
		"sign-in buttons offered",
	)


func _on_lobby_navigation_requested() -> void:
	_lobby_requests += 1


func _on_state_reset() -> void:
	_state_resets += 1


func _on_continued_offline(error: String) -> void:
	_offline_errors.append(error)


func _failure(
	message: String,
	status_code: int,
	grpc_status_code: int,
) -> NakamaSession:
	return NakamaSession.new(
		null,
		false,
		null,
		NakamaException.new(message, status_code, grpc_status_code),
	)


func _success() -> NakamaSession:
	var now := int(Time.get_unix_time_from_system())
	return NakamaSession.new(
		_fake_jwt(now + _ACCESS_TOKEN_LIFETIME_SEC),
		false,
		_fake_jwt(now + _REFRESH_TOKEN_LIFETIME_SEC),
	)


## A JWT-shaped string that NakamaSession can parse. Unsigned, and
## unique per call so stored tokens can be told apart.
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
