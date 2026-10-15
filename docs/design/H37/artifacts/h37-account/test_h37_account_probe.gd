extends GutTest
## H37 account audit probe (h37-account). Not part of the suite.
##
## Reproduces account findings with the fake Nakama client pattern of
## test/unit/platform/test_consent_retention.gd:
## - DEL-2: a failed delete_account is reported through auth_completed,
##   and delete_completed never fires.
## - LK-1: a background refresh that completes while a link is waiting
##   for the browser is taken for the link's result.
## - PI-1: the avatar cache takes any URL, and its downloads have no
##   size limit or timeout.
## - PI-2: the avatar cache keeps an old image for a reused player id.
## - SO-1 (H15): log-out leaves the matchmaking socket open, and the
##   next ensure_socket() reuses it.
## Each test asserts the CURRENT (buggy) behavior, so a pass means the
## bug reproduced.


const _TEST_AUTH_FILE := "user://h37_account_probe.cfg"
const _TEST_PLAYER_ID := "test-player"
const _ACCESS_TOKEN_LIFETIME_LEFT_SEC := 600
const _NEW_ACCESS_TOKEN_LIFETIME_SEC := 7200
const _REFRESH_TOKEN_LIFETIME_SEC := 604800
const _GRPC_UNAVAILABLE := 14
const _HTTP_SERVICE_UNAVAILABLE := 503


## Stands in for Platform.nakama_client, without network I/O.
class FakeNakamaClient extends NakamaClient:
	var next_refresh: NakamaSession
	var next_rpc_exception: NakamaException
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
		if next_rpc_exception != null:
			return NakamaAPI.ApiRpc.new(next_rpc_exception)
		return NakamaAPI.ApiRpc.new()


## Reports an open connection, without network I/O.
class ConnectedSocketAdapter extends NakamaSocketAdapter:
	func is_connected_to_host():
		return true


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

	# A signed-in Google player whose access token is still valid but
	# inside the SDK's one-hour refresh window.
	var now := int(Time.get_unix_time_from_system())
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.provider = "google"
	_store.player_id = _TEST_PLAYER_ID
	_store.display_name = "Player"
	_store.expires_at = now + _ACCESS_TOKEN_LIFETIME_LEFT_SEC
	_store.jwt_token = _fake_jwt(_store.expires_at)
	_store.refresh_token = _fake_jwt(now + _REFRESH_TOKEN_LIFETIME_SEC)
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
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client


func test_del2_failed_delete_is_reported_as_auth_failure() -> void:
	_nakama.next_rpc_exception = NakamaException.new(
		"Service unavailable",
		_HTTP_SERVICE_UNAVAILABLE,
		_GRPC_UNAVAILABLE,
	)
	watch_signals(_client)

	_client.delete_account()

	assert_eq(_nakama.rpc_ids, ["delete_account"], "the RPC was sent")
	assert_signal_not_emitted(
		_client, "delete_completed", "DEL-2: delete_completed never fires")
	assert_signal_emitted(
		_client, "auth_completed", "DEL-2: reported as auth_completed")
	var parameters: Array = get_signal_parameters(_client, "auth_completed")
	assert_eq(parameters[0], false, "as a failure")
	assert_false(_client._is_deleting, "delete state cleared")
	assert_false(_store.jwt_token.is_empty(), "player still signed in")


func test_lk1_refresh_during_link_is_taken_for_the_link() -> void:
	var jwt_before := _store.jwt_token
	var now := int(Time.get_unix_time_from_system())
	_nakama.next_refresh = NakamaSession.new(
		_fake_jwt(now + _NEW_ACCESS_TOKEN_LIFETIME_SEC),
		false,
		_fake_jwt(now + _REFRESH_TOKEN_LIFETIME_SEC),
	)
	# The state link_provider(GOOGLE) leaves while the browser is open.
	_client._is_linking = true
	_client._link_provider_name = "google"
	watch_signals(_client)

	_client._check_auto_refresh()

	# LK-1: the refresh is reported as a successful link. (GUT's fourth
	# parameter here is a call index, not a message.)
	assert_signal_emitted_with_parameters(
		_client, "link_completed", [true, "", "google"])
	assert_signal_not_emitted(
		_client, "auth_completed", "LK-1: the refresh itself is not reported")
	assert_false(_client._is_linking, "LK-1: the real link is forgotten")
	assert_eq(_store.jwt_token, jwt_before, "LK-1: refreshed token dropped")


## PI-2: the avatar cache is keyed by the match player id, which
## restarts at 1 on every game server, and a cached id ignores any new
## URL. So a later match's player 1 keeps an earlier player 1's image.
func test_pi2_cached_avatar_ignores_a_new_url_for_the_same_id() -> void:
	var cache := ProfileImageCache.new()
	var earlier_match_avatar := ImageTexture.new()
	cache._textures[1] = earlier_match_avatar

	cache.request_image(1, "https://example.invalid/other-player.png")

	assert_eq(
		cache.get_texture(1),
		earlier_match_avatar,
		"PI-2: the earlier player's avatar is kept for id 1",
	)
	assert_eq(cache._queue.size(), 0, "PI-2: the new URL is never queued")
	cache.free()


## PI-1: any avatar URL is accepted, plain http on any host included,
## and the pooled downloads have no body size limit and no timeout.
func test_pi1_any_avatar_url_is_accepted_without_limits() -> void:
	# Outside the tree it has no download slots, so nothing is fetched
	# and the accepted URL stays queued.
	var detached_cache := ProfileImageCache.new()
	detached_cache.request_image(2, "http://tracker.invalid/pixel.png")
	assert_eq(
		detached_cache._queue.size(),
		1,
		"PI-1: a plain-http URL on any host is queued",
	)
	detached_cache.free()

	# In the tree, _ready builds the download slots. No URL is requested.
	var cache := ProfileImageCache.new()
	add_child_autofree(cache)
	assert_eq(cache._request_pool.size(), 3, "three download slots")
	for request in cache._request_pool:
		assert_eq(request.body_size_limit, -1, "PI-1: no size limit")
		assert_eq(request.timeout, 0.0, "PI-1: no timeout")


## SO-1 (H15): log-out stops the notification socket but not the
## matchmaking socket, and ensure_socket() accepts any connected socket
## without checking whose session it carries. So the next account's
## tickets and party operations would go out on the old account's
## socket.
func test_so1_log_out_leaves_the_matchmaking_socket_open() -> void:
	var original_matchmaking = Platform.matchmaking
	var matchmaking := PlatformMatchmakingClient.new()
	Platform.register_subsystem("matchmaking", matchmaking)
	var adapter := ConnectedSocketAdapter.new()
	var old_account_socket := NakamaSocket.new(
		adapter,
		"fake.invalid",
		443,
		"wss",
	)
	matchmaking._socket = old_account_socket
	var router := SignOutRouter.new()
	add_child_autofree(router)

	await router.log_out()

	assert_true(_store.refresh_token.is_empty(), "logged out")
	assert_eq(
		matchmaking._socket,
		old_account_socket,
		"SO-1: the old account's socket survives log-out",
	)
	var is_socket_ready: bool = await matchmaking.ensure_socket()
	assert_true(is_socket_ready, "SO-1: ensure_socket() accepts it")
	assert_eq(
		matchmaking._socket,
		old_account_socket,
		"SO-1: the next account would reuse it",
	)

	matchmaking._socket = null
	Platform.register_subsystem("matchmaking", original_matchmaking)
	matchmaking.free()
	adapter.free()
	G.friends_notification_poller.start_polling()


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
