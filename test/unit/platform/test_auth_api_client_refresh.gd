extends GutTest
## Unit tests for PlatformAuthApiClient's session refresh: its retry
## policy, and what a successful refresh keeps.
##
## A failed refresh used to be retried as fast as each request
## completed, forever: _check_auto_refresh runs every frame, and its
## cooldown only started after a success. These tests drive
## _check_auto_refresh against a fake Nakama client and count the
## refresh requests that reach it. A failure that may be transient
## backs off exponentially. A refresh token that Nakama rejects
## signs the player out, which ends the retries.
##
## A successful refresh used to empty the player's linked accounts,
## so the account panel showed Google as unlinked after every one.
##
## The client under test is constructed via .new() and never added
## to the scene tree, so its own _process() never runs. Each test
## swaps a throwaway token store and the fake client into Platform,
## and pauses the live Platform.auth node meanwhile. That node
## auto-refreshes from Platform.token_store every frame, and would
## otherwise send the test store's refresh to the real Nakama
## server.


const _TEST_AUTH_FILE := "user://test_auth_api_client_refresh.cfg"
const _TEST_PLAYER_ID := "test-player"
const _ACCESS_TOKEN_EXPIRED_AGO_SEC := 60
const _ACCESS_TOKEN_LIFETIME_SEC := 7200
const _REFRESH_TOKEN_LIFETIME_SEC := 604800
const _REPEATED_TICKS := 10
## The client's backoff: 5 s, doubling per consecutive failure,
## capped at 300 s.
const _INITIAL_RETRY_DELAY_SEC := 5.0
const _EXPECTED_RETRY_WAITS_SEC := [
	5.0, 10.0, 20.0, 40.0, 80.0, 160.0, 300.0, 300.0,
]
## Slack for comparing a scheduled retry time with the clock the
## test reads a moment later.
const _TIME_TOLERANCE_SEC := 1.0
## gRPC status codes, as Nakama sends them.
const _GRPC_INVALID_ARGUMENT := 3
const _GRPC_NOT_FOUND := 5
const _GRPC_PERMISSION_DENIED := 7
const _GRPC_INTERNAL := 13
const _GRPC_UNAVAILABLE := 14
const _GRPC_UNAUTHENTICATED := 16
const _LINKED_PROVIDERS := ["anonymous", "google"]


## Stands in for Platform.nakama_client. Answers
## session_refresh_async with a canned result, without network I/O,
## and counts the calls.
class FakeNakamaClient extends NakamaClient:
	var refresh_calls := 0
	var next_result: NakamaSession
	## Runs before each answer, to model something that happens
	## while the request is in flight.
	var on_refresh := Callable()

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
		if on_refresh.is_valid():
			on_refresh.call()
		return next_result


var _client: PlatformAuthApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _completions: Array = []
var _completion_errors: Array = []
var _link_results: Array = []
## auth_completed and signed_out, in the order they fired.
var _signals: Array = []
var _jwt_serial := 0
var _original_token_store
var _original_nakama_client
var _was_platform_auth_processing := false


func before_each() -> void:
	_was_platform_auth_processing = Platform.auth.is_processing()
	Platform.auth.set_process(false)
	_original_token_store = Platform.token_store
	_original_nakama_client = Platform.nakama_client

	# A signed-in player whose access token has expired but whose
	# refresh token is still good: needs_refresh() is true.
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

	_client = PlatformAuthApiClient.new()
	_completions = []
	_completion_errors = []
	_link_results = []
	_signals = []
	_client.auth_completed.connect(_on_auth_completed)
	_client.signed_out.connect(_on_signed_out)
	_client.link_completed.connect(_on_link_completed)


func after_each() -> void:
	_client.free()
	# Deletes the test auth file if a test saved one.
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client
	Platform.auth.set_process(_was_platform_auth_processing)


# ------------------------------------------------------------------
# Rejected refresh token
# ------------------------------------------------------------------


func test_rejected_refresh_token_signs_out() -> void:
	_nakama.next_result = _failure(
		"Refresh token invalid or expired.",
		401,
		_GRPC_UNAUTHENTICATED,
	)

	_client._check_auto_refresh()

	assert_eq(_nakama.refresh_calls, 1)
	assert_true(_store.jwt_token.is_empty(), "access token cleared")
	assert_true(
		_store.refresh_token.is_empty(), "refresh token cleared")
	assert_eq(_completions, [false], "failure reported once")


func test_rejected_refresh_token_emits_signed_out() -> void:
	# After auth_completed, so callers awaiting the refresh (the auth
	# screen, matchmaking) finish before the game reroutes the player.
	_nakama.next_result = _failure(
		"Refresh token invalid or expired.",
		401,
		_GRPC_UNAUTHENTICATED,
	)

	_client._check_auto_refresh()

	assert_eq(_signals, ["auth_completed", "signed_out"])


func test_rejected_refresh_token_is_not_retried() -> void:
	_nakama.next_result = _failure(
		"Refresh token invalid or expired.",
		401,
		_GRPC_UNAUTHENTICATED,
	)

	for _i in _REPEATED_TICKS:
		_client._check_auto_refresh()

	assert_eq(
		_nakama.refresh_calls, 1, "one request, then signed out")


func test_banned_account_signs_out() -> void:
	_nakama.next_result = _failure(
		"User account banned.", 403, _GRPC_PERMISSION_DENIED)

	_client._check_auto_refresh()
	_client._check_auto_refresh()

	assert_eq(_nakama.refresh_calls, 1)
	assert_true(_store.refresh_token.is_empty())


func test_late_rejection_keeps_newer_session() -> void:
	# A sign-in that completes while the refresh is in flight
	# replaces the stored tokens. The late rejection of the old
	# refresh token must not sign that new session out.
	var newer_refresh_token := _fake_jwt(
		int(Time.get_unix_time_from_system())
		+ _REFRESH_TOKEN_LIFETIME_SEC
	)
	_nakama.on_refresh = func() -> void:
		_store.refresh_token = newer_refresh_token
	_nakama.next_result = _failure(
		"Refresh token invalid or expired.",
		401,
		_GRPC_UNAUTHENTICATED,
	)

	_client._check_auto_refresh()

	assert_eq(_store.refresh_token, newer_refresh_token)
	assert_false(_store.jwt_token.is_empty())
	assert_eq(_completions, [false])
	assert_eq(_signals, ["auth_completed"], "the new session stays")


func test_unreadable_refresh_token_signs_out_without_request() -> void:
	# NakamaSession can't parse this, so the refresh used to fail
	# locally and be retried on every frame.
	_store.refresh_token = "not-a-jwt"

	for _i in _REPEATED_TICKS:
		_client._check_auto_refresh()

	assert_eq(_nakama.refresh_calls, 0)
	assert_true(_store.refresh_token.is_empty())
	assert_eq(_completions, [false])
	assert_eq(_signals, ["auth_completed", "signed_out"])


# ------------------------------------------------------------------
# Transient failures
# ------------------------------------------------------------------


func test_transient_failure_keeps_session() -> void:
	var refresh_token_before := _store.refresh_token
	_nakama.next_result = _failure(
		"HTTPRequest failed!", HTTPRequest.RESULT_CANT_CONNECT, -1)

	_client._check_auto_refresh()

	assert_eq(_store.refresh_token, refresh_token_before)
	assert_false(_store.jwt_token.is_empty())
	assert_eq(_completions, [false], "failure reported")
	assert_eq(_signals, ["auth_completed"], "still signed in")


func test_transient_failure_holds_retries_until_backoff_ends() -> void:
	_nakama.next_result = _failure(
		"HTTPRequest failed!", HTTPRequest.RESULT_TIMEOUT, -1)

	for _i in _REPEATED_TICKS:
		_client._check_auto_refresh()
	assert_eq(_nakama.refresh_calls, 1, "held during backoff")
	assert_almost_eq(
		_seconds_until_retry(),
		_INITIAL_RETRY_DELAY_SEC,
		_TIME_TOLERANCE_SEC,
	)

	_end_backoff()
	_client._check_auto_refresh()
	assert_eq(_nakama.refresh_calls, 2, "retried after backoff")


func test_backoff_doubles_up_to_cap() -> void:
	_nakama.next_result = _failure(
		"Service unavailable", 503, _GRPC_UNAVAILABLE)

	for i in _EXPECTED_RETRY_WAITS_SEC.size():
		_end_backoff()
		_client._check_auto_refresh()
		assert_almost_eq(
			_seconds_until_retry(),
			_EXPECTED_RETRY_WAITS_SEC[i],
			_TIME_TOLERANCE_SEC,
			"wait after failure %d" % (i + 1),
		)
	assert_eq(_nakama.refresh_calls, _EXPECTED_RETRY_WAITS_SEC.size())


func test_explicit_refresh_skips_backoff() -> void:
	# Callers of refresh_token() await auth_completed (the auth
	# screen, matchmaking), so the automatic backoff must not
	# swallow their call.
	_nakama.next_result = _failure(
		"HTTPRequest failed!", HTTPRequest.RESULT_CANT_CONNECT, -1)
	_client._check_auto_refresh()

	_client.refresh_token()

	assert_eq(_nakama.refresh_calls, 2)
	assert_eq(_completions, [false, false])


# ------------------------------------------------------------------
# Refresh waits out link and delete flows (SP43, LK-1)
# ------------------------------------------------------------------


func test_auto_refresh_waits_while_linking() -> void:
	var jwt_before := _store.jwt_token
	_nakama.next_result = _success()
	_client._is_linking = true
	_client._link_provider_name = "google"

	_client._check_auto_refresh()

	assert_eq(_nakama.refresh_calls, 0, "no refresh sent")
	assert_true(_client._is_linking, "link still pending")
	assert_eq(_store.jwt_token, jwt_before, "session kept")
	assert_true(_completions.is_empty(), "nothing reported")


func test_auto_refresh_waits_while_deleting() -> void:
	_nakama.next_result = _success()
	_client._is_deleting = true

	_client._check_auto_refresh()

	assert_eq(_nakama.refresh_calls, 0, "no refresh sent")
	assert_true(_client._is_deleting, "delete still pending")
	assert_true(_completions.is_empty(), "nothing reported")


func test_refresh_runs_once_the_link_finishes() -> void:
	_nakama.next_result = _success()
	_client._is_linking = true
	_client._check_auto_refresh()
	assert_eq(_nakama.refresh_calls, 0)

	_client._is_linking = false
	_client._check_auto_refresh()

	assert_eq(_nakama.refresh_calls, 1, "refresh follows")
	assert_eq(_completions, [true])


# ------------------------------------------------------------------
# Success
# ------------------------------------------------------------------


func test_success_stores_session_and_resets_backoff() -> void:
	_nakama.next_result = _failure(
		"HTTPRequest failed!", HTTPRequest.RESULT_TIMEOUT, -1)
	_client._check_auto_refresh()
	_end_backoff()
	var fresh := _success()
	_nakama.next_result = fresh

	_client._check_auto_refresh()

	assert_eq(_nakama.refresh_calls, 2)
	assert_eq(_store.refresh_token, fresh.refresh_token)
	assert_true(_store.is_token_valid())
	assert_eq(_completions, [false, true])
	assert_eq(_client._refresh_retry_time, 0.0, "no retry pending")
	assert_eq(
		_client._refresh_retry_delay_sec,
		_INITIAL_RETRY_DELAY_SEC,
		"next failure waits the initial delay again",
	)


func test_refresh_runs_again_after_success() -> void:
	# _is_refreshing used to stay set after a successful refresh,
	# so no later refresh ever ran in that process.
	_nakama.next_result = _success()
	_client._check_auto_refresh()
	assert_false(_client._is_refreshing)

	# The new access token comes due, and the post-success
	# cooldown is over.
	_store.expires_at = int(Time.get_unix_time_from_system())
	_client._last_refresh_time = 0.0
	_nakama.next_result = _success()
	_client._check_auto_refresh()

	assert_eq(_nakama.refresh_calls, 2)


# ------------------------------------------------------------------
# Linked providers
# ------------------------------------------------------------------


func test_success_keeps_linked_providers() -> void:
	# The refresh response dict held the store's own list, which the
	# store cleared before copying from it.
	_store.linked_providers.assign(_LINKED_PROVIDERS)
	_nakama.next_result = _success()

	_client._check_auto_refresh()

	assert_eq(_completions, [true])
	assert_eq(Array(_store.linked_providers), _LINKED_PROVIDERS)


func test_success_saves_linked_providers() -> void:
	_store.linked_providers.assign(_LINKED_PROVIDERS)
	_nakama.next_result = _success()

	_client._check_auto_refresh()

	var reloaded := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	assert_eq(Array(reloaded.linked_providers), _LINKED_PROVIDERS)


func test_store_from_response_keeps_its_own_list() -> void:
	_store.linked_providers.assign(_LINKED_PROVIDERS)

	_store.store_from_response({
		"jwt_token": _store.jwt_token,
		"refresh_token": _store.refresh_token,
		"linked_providers": _store.linked_providers,
	})

	assert_eq(Array(_store.linked_providers), _LINKED_PROVIDERS)


# ------------------------------------------------------------------
# Refresh results take their own route (SP89)
# ------------------------------------------------------------------


func test_explicit_refresh_is_not_the_link_result() -> void:
	# A link waits for its browser flow while matchmaking asks
	# for a refresh. The refresh result belongs to the refresh:
	# it is stored and reported as auth, and the link stays
	# pending for its own result.
	var fresh := _success()
	_nakama.next_result = fresh
	_client._is_linking = true
	_client._link_provider_name = "google"

	_client.refresh_token()

	assert_eq(_nakama.refresh_calls, 1)
	assert_eq(_completions, [true], "refresh reported as auth")
	assert_true(_link_results.is_empty(), "link not completed")
	assert_true(_client._is_linking, "link still pending")
	assert_eq(
		_store.refresh_token, fresh.refresh_token,
		"refreshed session stored")


func test_in_flight_refresh_is_not_the_link_result() -> void:
	# The link starts while the refresh request is in flight
	# (the fake begins the link from inside the request).
	# The landing refresh is still the refresh's result.
	var fresh := _success()
	_nakama.on_refresh = func() -> void:
		_client._is_linking = true
		_client._link_provider_name = "google"
	_nakama.next_result = fresh

	_client.refresh_token()

	assert_eq(_completions, [true], "refresh reported as auth")
	assert_true(_link_results.is_empty(), "link not completed")
	assert_true(_client._is_linking, "link still pending")
	assert_eq(_store.refresh_token, fresh.refresh_token)


func test_refresh_landing_after_delete_is_dropped() -> void:
	# The delete clears the store while the refresh is in
	# flight. The refresh result must not write the session
	# back: the store stays cleared and the waiting callers
	# are told the result was superseded.
	_nakama.on_refresh = func() -> void:
		_store.clear_tokens()
	_nakama.next_result = _success()

	_client.refresh_token()

	assert_true(_store.jwt_token.is_empty(), "no session restored")
	assert_true(
		_store.refresh_token.is_empty(), "no refresh token restored")
	assert_eq(_completions, [false], "reported as not completed")
	assert_eq(_completion_errors, ["superseded"])


func test_refresh_landing_after_sign_out_is_dropped() -> void:
	# Signing out clears the session (consent kept) while the
	# refresh is in flight; the landing refresh must not sign
	# the player back in.
	_nakama.on_refresh = func() -> void:
		_store.clear_session()
	_nakama.next_result = _success()

	_client.refresh_token()

	assert_true(_store.jwt_token.is_empty(), "still signed out")
	assert_eq(_completions, [false])
	assert_eq(_completion_errors, ["superseded"])


func test_refresh_landing_after_new_sign_in_is_dropped() -> void:
	# A different account's sign-in lands while the refresh is
	# in flight. The old account's refresh result must not
	# replace the new session.
	var other_refresh := _fake_jwt(
		int(Time.get_unix_time_from_system())
		+ _REFRESH_TOKEN_LIFETIME_SEC)
	var other_jwt := _store.jwt_token
	_nakama.on_refresh = func() -> void:
		_store.refresh_token = other_refresh
	_nakama.next_result = _success()

	_client.refresh_token()

	assert_eq(
		_store.refresh_token, other_refresh, "new session kept")
	assert_eq(_store.jwt_token, other_jwt, "new session kept")
	assert_eq(_completions, [false])
	assert_eq(_completion_errors, ["superseded"])


# ------------------------------------------------------------------
# _is_refresh_token_rejected
# ------------------------------------------------------------------


func test_nakama_rejections_are_definitive() -> void:
	assert_true(_is_rejected(
		"Refresh token invalid or expired.",
		401,
		_GRPC_UNAUTHENTICATED,
	))
	assert_true(_is_rejected(
		"User account banned.", 403, _GRPC_PERMISSION_DENIED))
	assert_true(_is_rejected(
		"User account not found.", 404, _GRPC_NOT_FOUND))


func test_other_failures_are_transient() -> void:
	assert_false(
		_is_rejected(
			"HTTPRequest failed!", HTTPRequest.RESULT_CANT_CONNECT, -1),
		"network error",
	)
	assert_false(
		_is_rejected(
			"HTTPRequest failed!", HTTPRequest.RESULT_TIMEOUT, -1),
		"timeout",
	)
	assert_false(
		_is_rejected(
			"Error finding user account.", 500, _GRPC_INTERNAL),
		"Nakama 5xx",
	)
	assert_false(
		_is_rejected("Failed to decode JSON response", 502, -1),
		"proxy error page",
	)
	assert_false(
		_is_rejected("Failed to decode JSON response", 401, -1),
		"401 that did not come from Nakama",
	)
	assert_false(
		_is_rejected(
			"unknown game_id: x", 400, _GRPC_INVALID_ARGUMENT),
		"BeforeSessionRefresh hook's game_id check",
	)
	assert_false(
		_is_rejected("Request cancelled", -1, -1), "cancelled")
	assert_false(
		PlatformAuthApiClient._is_refresh_token_rejected(null),
		"no exception",
	)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


func _on_auth_completed(success: bool, error: String) -> void:
	_completions.append(success)
	_completion_errors.append(error)
	_signals.append("auth_completed")


func _on_link_completed(
	success: bool, error: String, provider: String,
) -> void:
	_link_results.append([success, error, provider])


func _on_signed_out(_error: String) -> void:
	_signals.append("signed_out")


## Pretends the scheduled retry time has passed.
func _end_backoff() -> void:
	_client._refresh_retry_time = Time.get_unix_time_from_system() - 1.0


func _seconds_until_retry() -> float:
	return (
		_client._refresh_retry_time - Time.get_unix_time_from_system())


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


func _is_rejected(
	message: String,
	status_code: int,
	grpc_status_code: int,
) -> bool:
	return PlatformAuthApiClient._is_refresh_token_rejected(
		NakamaException.new(message, status_code, grpc_status_code))


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
