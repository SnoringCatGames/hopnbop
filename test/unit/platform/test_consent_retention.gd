extends GutTest
## Unit tests for when the platform SDK keeps the player's consent.
##
## The token store keeps consent (the acceptance time and the legal
## version accepted) in the same encrypted file as the session, and
## every sign-out used to delete that file, so a player the SDK signed
## out on its own had to consent again at the next launch. Now:
## - an automatic sign-out (Nakama rejected the refresh token, or the
##   stored one cannot be used) keeps consent, in memory and on disk;
## - account deletion forgets it, and so does log-out (see
##   test_sign_out_router.gd, which runs the game's log-out);
## - kept consent is asked for again once the legal version changes.
##
## The auth client and screens under test never enter the scene tree
## on their own, or are swapped in with a throwaway token store and a
## fake Nakama client. The live auth node and friends poller are paused
## meanwhile, since they act on Platform.token_store every frame.


const _AUTH_SCREEN_SCENE_PATH := (
	"res://addons/snoringcat_platform_client/ui/screens/auth_screen.tscn")
const _CONSENT_SCREEN_SCENE_PATH := (
	"res://addons/snoringcat_platform_client/ui/screens"
	+ "/consent_screen.tscn")
const _TEST_AUTH_FILE := "user://test_consent_retention.cfg"
const _TEST_PLAYER_ID := "test-player"
## What PlatformConsentScreen asks for unless a game overrides it.
const _CURRENT_LEGAL_VERSION := "1.0"
const _OLDER_LEGAL_VERSION := "0.9"
const _CONSENT_ACCEPTED_AT := 1760000000
const _ACCESS_TOKEN_EXPIRED_AGO_SEC := 60
const _REFRESH_TOKEN_LIFETIME_SEC := 604800
## gRPC status codes, as Nakama sends them.
const _GRPC_PERMISSION_DENIED := 7
const _GRPC_UNAVAILABLE := 14
const _GRPC_UNAUTHENTICATED := 16
const _HTTP_UNAUTHORIZED := 401
const _HTTP_FORBIDDEN := 403
const _HTTP_SERVICE_UNAVAILABLE := 503


## Stands in for Platform.nakama_client, without network I/O.
class FakeNakamaClient extends NakamaClient:
	var next_refresh: NakamaSession
	var rpc_ids: Array = []

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
		return next_refresh

	func rpc_async(
		_p_session: NakamaSession,
		p_id: String,
		_p_payload = null,
	):
		rpc_ids.append(p_id)
		return NakamaAPI.ApiRpc.new()


var _client: PlatformAuthApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _jwt_serial := 0
var _original_auth
var _original_token_store
var _original_nakama_client
var _was_original_auth_processing := false
var _was_live_poller_processing := false


func before_each() -> void:
	_original_auth = Platform.auth
	_original_token_store = Platform.token_store
	_original_nakama_client = Platform.nakama_client
	_was_original_auth_processing = _original_auth.is_processing()
	_original_auth.set_process(false)
	_was_live_poller_processing = (
		G.friends_notification_poller.is_processing())
	G.friends_notification_poller.set_process(false)

	# A signed-in player who consented to the current legal version,
	# and whose access token has expired.
	var now := int(Time.get_unix_time_from_system())
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.provider = "google"
	_store.player_id = _TEST_PLAYER_ID
	_store.display_name = "Player"
	_store.expires_at = now - _ACCESS_TOKEN_EXPIRED_AGO_SEC
	_store.jwt_token = _fake_jwt(_store.expires_at)
	_store.refresh_token = _fake_jwt(now + _REFRESH_TOKEN_LIFETIME_SEC)
	_store.consent_accepted_at = _CONSENT_ACCEPTED_AT
	_store.consent_legal_version = _CURRENT_LEGAL_VERSION
	_store.save_tokens()
	Platform.token_store = _store

	_nakama = FakeNakamaClient.new()
	Platform.nakama_client = _nakama

	# Never added to the tree, so its own _process never runs.
	_client = PlatformAuthApiClient.new()
	Platform.register_subsystem("auth", _client)


func after_each() -> void:
	Platform.register_subsystem("auth", _original_auth)
	_original_auth.set_process(_was_original_auth_processing)
	G.friends_notification_poller.set_process(_was_live_poller_processing)
	_client.free()
	# Deletes the test auth file if a test left one.
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client


# ------------------------------------------------------------------
# PlatformAuthTokenStore
# ------------------------------------------------------------------


func test_clear_session_drops_the_session_and_keeps_consent() -> void:
	_store.clear_session()

	assert_true(_store.jwt_token.is_empty(), "access token gone")
	assert_true(_store.refresh_token.is_empty(), "refresh token gone")
	assert_true(_store.player_id.is_empty(), "account gone")
	assert_true(_store.display_name.is_empty(), "display name gone")
	_assert_consent_kept(_store)


func test_clear_session_keeps_only_consent_on_disk() -> void:
	_store.clear_session()

	var reloaded := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_assert_consent_kept(reloaded)
	assert_true(reloaded.jwt_token.is_empty())
	assert_true(reloaded.refresh_token.is_empty())
	assert_true(reloaded.player_id.is_empty())
	assert_true(reloaded.display_name.is_empty())


func test_clear_session_without_consent_deletes_the_auth_file() -> void:
	_store.consent_accepted_at = 0
	_store.consent_legal_version = ""
	_store.save_tokens()

	_store.clear_session()

	assert_false(FileAccess.file_exists(_TEST_AUTH_FILE))


func test_clear_tokens_forgets_consent() -> void:
	_store.clear_tokens()

	_assert_consent_forgotten(_store)
	assert_false(FileAccess.file_exists(_TEST_AUTH_FILE))


# ------------------------------------------------------------------
# Automatic sign-outs keep consent
# ------------------------------------------------------------------


func test_rejected_refresh_keeps_consent() -> void:
	_nakama.next_refresh = _failure(
		"Refresh token invalid or expired.",
		_HTTP_UNAUTHORIZED,
		_GRPC_UNAUTHENTICATED,
	)

	_client._check_auto_refresh()

	assert_true(_store.refresh_token.is_empty(), "signed out")
	_assert_consent_kept(_store)
	_assert_consent_kept(PlatformAuthTokenStore.new(_TEST_AUTH_FILE))


func test_banned_account_keeps_consent() -> void:
	_nakama.next_refresh = _failure(
		"User account banned.", _HTTP_FORBIDDEN, _GRPC_PERMISSION_DENIED)

	_client._check_auto_refresh()

	assert_true(_store.refresh_token.is_empty(), "signed out")
	_assert_consent_kept(PlatformAuthTokenStore.new(_TEST_AUTH_FILE))


func test_unusable_stored_token_keeps_consent() -> void:
	_store.refresh_token = "not-a-jwt"
	_store.save_tokens()

	_client._check_auto_refresh()

	assert_true(_store.refresh_token.is_empty(), "signed out")
	_assert_consent_kept(PlatformAuthTokenStore.new(_TEST_AUTH_FILE))


func test_transient_failure_keeps_everything() -> void:
	var refresh_token_before := _store.refresh_token
	_nakama.next_refresh = _failure(
		"Service unavailable",
		_HTTP_SERVICE_UNAVAILABLE,
		_GRPC_UNAVAILABLE,
	)

	_client._check_auto_refresh()

	assert_eq(_store.refresh_token, refresh_token_before, "still signed in")
	_assert_consent_kept(PlatformAuthTokenStore.new(_TEST_AUTH_FILE))


func test_launch_time_rejection_keeps_consent() -> void:
	_nakama.next_refresh = _failure(
		"Refresh token invalid or expired.",
		_HTTP_UNAUTHORIZED,
		_GRPC_UNAUTHENTICATED,
	)
	var scene: PackedScene = load(_AUTH_SCREEN_SCENE_PATH)
	var screen: PlatformAuthScreen = scene.instantiate()
	add_child_autofree(screen)

	screen.on_open()

	assert_true(_store.refresh_token.is_empty(), "signed out")
	assert_true(
		screen.get_node("%ButtonsContainer").visible, "sign-in offered")
	_assert_consent_kept(_store)
	_assert_consent_kept(PlatformAuthTokenStore.new(_TEST_AUTH_FILE))


# ------------------------------------------------------------------
# Account deletion forgets consent
# ------------------------------------------------------------------


func test_account_deletion_forgets_consent() -> void:
	# A usable session, which delete_account needs.
	var now := int(Time.get_unix_time_from_system())
	_store.expires_at = now + _REFRESH_TOKEN_LIFETIME_SEC
	_store.jwt_token = _fake_jwt(_store.expires_at)
	_store.save_tokens()
	watch_signals(_client)

	_client.delete_account()

	assert_eq(_nakama.rpc_ids, ["delete_account"])
	assert_signal_emitted_with_parameters(
		_client, "delete_completed", [true, ""])
	_assert_consent_forgotten(_store)
	assert_false(FileAccess.file_exists(_TEST_AUTH_FILE))


# ------------------------------------------------------------------
# The consent screen
# ------------------------------------------------------------------


func test_kept_consent_lets_the_player_past_the_consent_screen() -> void:
	_store.clear_session()
	var screen := _open_consent_screen()

	assert_signal_emitted(screen, "consent_accepted", "not asked again")


func test_kept_consent_is_asked_for_again_after_a_legal_change() -> void:
	_store.consent_legal_version = _OLDER_LEGAL_VERSION
	_store.save_tokens()
	_store.clear_session()
	var screen := _open_consent_screen()

	assert_signal_not_emitted(screen, "consent_accepted", "asked again")
	assert_true(
		screen.get_node("%ContinueButton").disabled,
		"the player must accept again",
	)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


func _open_consent_screen() -> PlatformConsentScreen:
	var scene: PackedScene = load(_CONSENT_SCREEN_SCENE_PATH)
	var screen: PlatformConsentScreen = scene.instantiate()
	# A game's inherited scene supplies these. The addon's bare scene
	# has none, and focusing a row without them logs engine errors.
	screen.focus_style = StyleBoxEmpty.new()
	screen.unfocused_style = StyleBoxEmpty.new()
	add_child_autofree(screen)
	watch_signals(screen)
	screen.on_open()
	return screen


func _assert_consent_kept(store: PlatformAuthTokenStore) -> void:
	assert_eq(store.consent_accepted_at, _CONSENT_ACCEPTED_AT)
	assert_eq(store.consent_legal_version, _CURRENT_LEGAL_VERSION)
	assert_true(
		store.has_valid_consent(_CURRENT_LEGAL_VERSION), "consent kept")


func _assert_consent_forgotten(store: PlatformAuthTokenStore) -> void:
	assert_eq(store.consent_accepted_at, 0)
	assert_eq(store.consent_legal_version, "")
	assert_false(
		store.has_valid_consent(_CURRENT_LEGAL_VERSION), "consent forgotten")


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
