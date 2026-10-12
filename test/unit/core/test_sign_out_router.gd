extends GutTest
## Unit tests for SignOutRouter, which sends the player to the auth
## screen after the platform SDK signs them out mid-session.
##
## GUT runs without main.tscn, so there is no ScreensMain, lobby, or
## match here, and the router waits, as it does during a match, for
## the next request to open the lobby. The agent-harness scenarios
## sign-out-lobby and sign-out-local-match cover the screen flow.
##
## Each test swaps a fresh auth client, a throwaway token store, and a
## fake Nakama client into Platform, and pauses the live auth node,
## which would otherwise refresh the throwaway store itself.


const _TEST_AUTH_FILE := "user://test_sign_out_router.cfg"
const _TEST_PLAYER_ID := "test-player"
const _ACCESS_TOKEN_EXPIRED_AGO_SEC := 60
const _REFRESH_TOKEN_LIFETIME_SEC := 604800
## gRPC status codes, as Nakama sends them.
const _GRPC_UNAVAILABLE := 14
const _GRPC_UNAUTHENTICATED := 16
const _HTTP_UNAUTHORIZED := 401
const _HTTP_SERVICE_UNAVAILABLE := 503
## Screens that never give way to the auth screen.
const _SCREENS_LEFT_ALONE := [
	ScreensMain.ScreenType.GAME,
	ScreensMain.ScreenType.PAUSE,
	ScreensMain.ScreenType.LOADING,
	ScreensMain.ScreenType.GAME_OVER,
	ScreensMain.ScreenType.CONSENT,
]


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


var _router: SignOutRouter
var _client: PlatformAuthApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _jwt_serial := 0
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

	# A signed-in player whose access token has expired: the next
	# refresh decides whether they stay signed in.
	var now := int(Time.get_unix_time_from_system())
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.provider = "google"
	_store.player_id = _TEST_PLAYER_ID
	_store.expires_at = now - _ACCESS_TOKEN_EXPIRED_AGO_SEC
	_store.jwt_token = _fake_jwt(_store.expires_at)
	_store.refresh_token = _fake_jwt(now + _REFRESH_TOKEN_LIFETIME_SEC)
	Platform.token_store = _store

	_nakama = FakeNakamaClient.new()
	Platform.nakama_client = _nakama

	# Never added to the tree, so its own _process never runs.
	_client = PlatformAuthApiClient.new()
	Platform.register_subsystem("auth", _client)

	# Connects to Platform.auth, so it must come after the swap.
	_router = SignOutRouter.new()
	add_child_autofree(_router)


func after_each() -> void:
	Platform.register_subsystem("auth", _original_auth)
	_original_auth.set_process(_was_original_auth_processing)
	_client.free()
	# Deletes the test auth file if a test saved one.
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client


# ------------------------------------------------------------------
# Sign-out
# ------------------------------------------------------------------


func test_starts_signed_in() -> void:
	assert_false(_router.is_sign_in_required)


func test_signed_out_requires_sign_in() -> void:
	_client.signed_out.emit("Refresh token invalid or expired.")

	assert_true(_router.is_sign_in_required)


func test_rejected_refresh_requires_sign_in() -> void:
	_nakama.next_result = _failure(
		"Refresh token invalid or expired.",
		_HTTP_UNAUTHORIZED,
		_GRPC_UNAUTHENTICATED,
	)

	_client._check_auto_refresh()

	assert_true(_store.refresh_token.is_empty(), "the SDK signed out")
	assert_true(_router.is_sign_in_required)


func test_transient_refresh_failure_keeps_player_in_place() -> void:
	_nakama.next_result = _failure(
		"Service unavailable",
		_HTTP_SERVICE_UNAVAILABLE,
		_GRPC_UNAVAILABLE,
	)

	_client._check_auto_refresh()

	assert_false(_store.refresh_token.is_empty(), "still signed in")
	assert_false(_router.is_sign_in_required)


# ------------------------------------------------------------------
# resolve_screen
# ------------------------------------------------------------------


func test_screens_pass_through_while_signed_in() -> void:
	assert_eq(
		_router.resolve_screen(ScreensMain.ScreenType.LOBBY),
		ScreensMain.ScreenType.LOBBY,
	)
	assert_false(_router.is_sign_in_required)


func test_lobby_gives_way_to_auth() -> void:
	_client.signed_out.emit("Refresh token invalid or expired.")

	assert_eq(
		_router.resolve_screen(ScreensMain.ScreenType.LOBBY),
		ScreensMain.ScreenType.AUTH,
	)
	assert_false(_router.is_sign_in_required, "settled by the auth screen")
	assert_eq(
		_router.resolve_screen(ScreensMain.ScreenType.LOBBY),
		ScreensMain.ScreenType.LOBBY,
		"the lobby opens normally after sign-in",
	)


func test_matches_and_their_screens_are_not_interrupted() -> void:
	_client.signed_out.emit("Refresh token invalid or expired.")

	for screen_type in _SCREENS_LEFT_ALONE:
		assert_eq(
			_router.resolve_screen(screen_type),
			screen_type,
			ScreensMain.ScreenType.find_key(screen_type),
		)
	assert_true(_router.is_sign_in_required, "still waiting for the lobby")


func test_opening_auth_settles_sign_in() -> void:
	_client.signed_out.emit("Refresh token invalid or expired.")

	assert_eq(
		_router.resolve_screen(ScreensMain.ScreenType.AUTH),
		ScreensMain.ScreenType.AUTH,
	)
	assert_false(_router.is_sign_in_required)


func test_opening_auth_clears_the_old_session_caches() -> void:
	Platform.friends.cached_friends.append({"user_id": "friend"})
	Platform.presence.cached_online_ids.append("friend")
	_client.signed_out.emit("Refresh token invalid or expired.")

	_router.resolve_screen(ScreensMain.ScreenType.LOBBY)

	assert_true(Platform.friends.cached_friends.is_empty())
	assert_true(Platform.presence.cached_online_ids.is_empty())


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


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
