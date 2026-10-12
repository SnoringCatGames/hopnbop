extends GutTest
## Unit tests for what a player is told when starting an online match
## fails before any server is reached.
##
## A failed session refresh before matchmaking used to raise
## connection_lost("Auth token expired"), so every player saw that
## English text, even after a dropped connection that had left them
## signed in. GameSessionManager now reports the refresh failure and
## whether the SDK signed the player out, and GamePanel sends them to
## the lobby with a translated message or, signed out, to the auth
## screen. The rest checks the SDK diagnostics that reach a toast.
##
## Each refresh test swaps a fresh auth client, a throwaway token
## store, and a fake Nakama client into Platform, and pauses the live
## auth node. The GameSessionManager under test never enters the tree,
## so it sets up no session provider of its own.


const _TEST_AUTH_FILE := "user://test_matchmaking_session_failures.cfg"
const _TEST_PLAYER_ID := "test-player"
const _ACCESS_TOKEN_EXPIRED_AGO_SEC := 60
## Inside the SDK's refresh margin, so a refresh is due, but still
## usable.
const _ACCESS_TOKEN_EXPIRES_SOON_SEC := 600
const _REFRESH_TOKEN_LIFETIME_SEC := 604800
## gRPC status codes, as Nakama sends them.
const _GRPC_UNAVAILABLE := 14
const _GRPC_UNAUTHENTICATED := 16
const _HTTP_UNAUTHORIZED := 401
const _HTTP_SERVICE_UNAVAILABLE := 503
const _SIGNED_OUT_REASON := "signed_out"
const _SESSION_REFRESH_FAILED_REASON := "session_refresh_failed"
## Frames to let deferred emissions land.
const _SETTLE_FRAMES := 2


## Stands in for Platform.nakama_client. Answers session_refresh_async
## with a canned result, without network I/O, and counts the calls.
class FakeNakamaClient extends NakamaClient:
	var refresh_calls := 0
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
		refresh_calls += 1
		return next_result


## Records the matchmaking request that a usable session goes on to.
class FakeSessionProvider extends SessionProvider:
	var requests := 0

	func client_request_session_ids(
		_player_count: int,
		_session_prefs: Dictionary = {},
	) -> void:
		requests += 1


var _manager: GameSessionManager
var _router: SignOutRouter
var _client: PlatformAuthApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _refresh_failures: Array = []
## SignOutRouter.is_sign_in_required when each failure was reported.
var _router_states: Array = []
var _observed_reasons: Array = []
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
	# With a usable session in the store, the live poller would send its
	# presence heartbeat through the fake client's real HTTP adapter.
	_was_live_poller_processing = (
		G.friends_notification_poller.is_processing())
	G.friends_notification_poller.set_process(false)

	# A signed-in player whose access token has expired presses Play.
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

	_refresh_failures = []
	_router_states = []
	_observed_reasons = []
	_manager = GameSessionManager.new()
	_manager.session_refresh_failed.connect(_on_session_refresh_failed)
	Platform.session.matchmaking_failed.connect(_on_observed_failure)


func after_each() -> void:
	Platform.session.matchmaking_failed.disconnect(_on_observed_failure)
	_manager.free()
	Platform.register_subsystem("auth", _original_auth)
	_original_auth.set_process(_was_original_auth_processing)
	G.friends_notification_poller.set_process(_was_live_poller_processing)
	_client.free()
	# Deletes the test auth file if a test saved one.
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client


# ------------------------------------------------------------------
# The refresh before matchmaking
# ------------------------------------------------------------------


func test_transient_failure_reports_a_kept_session() -> void:
	var refresh_token_before := _store.refresh_token
	_nakama.next_result = _failure(
		"Service unavailable",
		_HTTP_SERVICE_UNAVAILABLE,
		_GRPC_UNAVAILABLE,
	)

	_manager.client_request_session()
	await _settle()

	assert_eq(_refresh_failures, [false], "session kept")
	assert_eq(_store.refresh_token, refresh_token_before)
	assert_false(_router.is_sign_in_required, "no sign-in needed")
	assert_eq(
		_observed_reasons,
		[_SESSION_REFRESH_FAILED_REASON],
	)


func test_network_error_reports_a_kept_session() -> void:
	_nakama.next_result = _failure(
		"HTTPRequest failed!", HTTPRequest.RESULT_CANT_CONNECT, -1)

	_manager.client_request_session()
	await _settle()

	assert_eq(_refresh_failures, [false])
	assert_false(_store.refresh_token.is_empty())


func test_rejected_refresh_reports_a_sign_out() -> void:
	_nakama.next_result = _failure(
		"Refresh token invalid or expired.",
		_HTTP_UNAUTHORIZED,
		_GRPC_UNAUTHENTICATED,
	)

	_manager.client_request_session()
	await _settle()

	assert_eq(_refresh_failures, [true], "signed out")
	assert_true(_store.refresh_token.is_empty())
	assert_eq(
		_router_states,
		[true],
		"SignOutRouter heard of the sign-out first",
	)
	assert_eq(_observed_reasons, [_SIGNED_OUT_REASON])


## The SDK answers a stored refresh token it cannot read before
## refresh_token() returns. Matchmaking used to await a signal that had
## already fired, and sat on "Authenticating..." for good.
func test_unusable_stored_token_reports_a_sign_out() -> void:
	_store.refresh_token = "not-a-jwt"

	_manager.client_request_session()
	await _settle()

	assert_eq(_nakama.refresh_calls, 0, "no request")
	assert_eq(_refresh_failures, [true])


func test_usable_access_token_goes_on_to_matchmaking() -> void:
	# The refresh fails, but the access token has a few minutes left.
	var now := int(Time.get_unix_time_from_system())
	_store.expires_at = now + _ACCESS_TOKEN_EXPIRES_SOON_SEC
	_store.jwt_token = _fake_jwt(_store.expires_at)
	_nakama.next_result = _failure(
		"Service unavailable",
		_HTTP_SERVICE_UNAVAILABLE,
		_GRPC_UNAVAILABLE,
	)
	var provider := FakeSessionProvider.new()
	_manager.session_provider = provider
	var original_client_session := G.client_session
	G.client_session = ClientSession.new()

	_manager.client_request_session()
	await _settle()

	assert_eq(provider.requests, 1, "matchmaking asked for")
	assert_eq(_refresh_failures, [], "no failure reported")
	G.client_session = original_client_session
	provider.free()


# ------------------------------------------------------------------
# Other failures on the way to a match
# ------------------------------------------------------------------


func test_out_of_date_client_gets_the_translated_update_dialog() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var original_confirm_layer := G.confirm_layer
	G.confirm_layer = layer
	watch_signals(_manager)

	_manager._on_session_request_failed(
		"Your client is out of date (protocol 3, server expects 4)."
		+ " Please restart the game to update.")

	assert_eq(layer.get_child_count(), 1, "one dialog")
	var dialog: ConfirmOverlay = layer.get_child(0)
	assert_eq(
		dialog.get_node("%MessageLabel").text,
		tr("VERSION.UPDATE_REQUIRED"),
	)
	assert_eq(
		dialog.get_node("%AcceptLabel").text, tr("VERSION.CLOSE_GAME"))
	assert_signal_not_emitted(_manager, "matchmaking_failed")
	G.confirm_layer = original_confirm_layer


func test_guest_session_failure_is_a_connection_failure() -> void:
	var panel := GamePanel.new()

	assert_eq(
		panel._classify_matchmaking_failure(
			"Failed to get session token: HTTPRequest failed!"
			+ " (status=2, grpc=-1)"),
		"LOADING.CONNECTION_FAILED",
	)
	panel.free()


func test_another_players_old_client_is_recoverable() -> void:
	var panel := GamePanel.new()

	assert_eq(
		panel._classify_matchmaking_failure(
			"Match aborted: another player's client is out of date"
			+ " (server expects protocol 4)."),
		"LOADING.PEER_OUT_OF_DATE",
	)
	panel.free()


func test_sdk_diagnostics_reach_the_player_translated() -> void:
	var panel := GamePanel.new()

	assert_eq(
		panel._get_fatal_failure_message("The party stopped matchmaking"),
		tr("PARTY.MATCHMAKING_ABORTED"),
	)
	assert_eq(
		panel._get_fatal_failure_message(
			"Party create failed: HTTPRequest failed!"),
		tr("LOADING.CONNECTION_FAILED"),
	)
	assert_eq(
		panel._get_fatal_failure_message(
			"Party join failed: Party not found."),
		tr("LOADING.CONNECTION_FAILED"),
	)
	panel.free()


func test_the_games_own_messages_pass_through() -> void:
	var panel := GamePanel.new()
	var message := tr("PARTY.MEMBERS_NEVER_JOINED")

	assert_eq(panel._get_fatal_failure_message(message), message)
	panel.free()


func test_every_message_is_in_the_translation_table() -> void:
	for key in [
		"TOAST.SESSION_KEPT_OFFLINE",
		"TOAST.SIGNED_OUT",
		"LOADING.PEER_OUT_OF_DATE",
		"LOADING.CONNECTION_FAILED",
		"PARTY.MATCHMAKING_ABORTED",
		"VERSION.UPDATE_REQUIRED",
		"VERSION.CLOSE_GAME",
	]:
		assert_ne(tr(key), key, "%s is translated" % key)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


func _on_session_refresh_failed(is_signed_out: bool) -> void:
	_refresh_failures.append(is_signed_out)
	_router_states.append(_router.is_sign_in_required)


func _on_observed_failure(reason: String) -> void:
	_observed_reasons.append(reason)


## Lets deferred emissions land. The tree is paused during GUT runs,
## but process_frame still fires.
func _settle() -> void:
	for i in range(_SETTLE_FRAMES):
		await get_tree().process_frame


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
