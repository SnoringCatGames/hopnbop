extends GutTest
## H37 phase 2b probe (h37-verify2, item 3, AN-1): what the guest
## "upgrade" to Google does to the guest's server account. Drives the real
## settings row (LinkAccountRow) and the real PlatformAuthApiClient against
## a fake Nakama client that records every call; no network. Only the
## browser step and Google's code exchange are stubbed. Fake pattern:
## h37-account's probe and test/unit/platform/test_consent_retention.gd.


const _TEST_AUTH_FILE := "user://h37v2_guest_upgrade_probe.cfg"
const _GUEST_ACCOUNT := "guest-device-account"
const _GOOGLE_ACCOUNT := "google-identity-account"


## Stands in for Platform.nakama_client, without network I/O.
class FakeNakamaClient extends NakamaClient:
	var calls: Array = []
	var device_account := ""
	var google_account := ""
	var _serial := 0

	func _init() -> void:
		super(
			Nakama.get_client_adapter(),
			"",
			"https",
			"fake.invalid",
			443,
			Nakama.DEFAULT_TIMEOUT,
		)

	func fake_jwt(user_id: String, expires_at: int) -> String:
		_serial += 1
		var claims := JSON.stringify({
			"exp": expires_at,
			"uid": user_id,
			"tid": "probe-token-%d" % _serial,
		})
		var payload := (
			Marshalls.utf8_to_base64(claims)
			.replace("+", "-")
			.replace("/", "_")
			.replace("=", "")
		)
		return "probe-header.%s.probe-signature" % payload

	func _session_for(user_id: String) -> NakamaSession:
		var now := int(Time.get_unix_time_from_system())
		return NakamaSession.new(
			fake_jwt(user_id, now + 7200),
			false,
			fake_jwt(user_id, now + 604800),
		)

	func authenticate_device_async(
		p_id: String,
		_p_username = null,
		p_create: bool = true,
		_p_vars = null,
	) -> NakamaSession:
		calls.append(["authenticate_device", p_id, p_create])
		return _session_for(device_account)

	func authenticate_google_async(
		_p_token: String,
		_p_username = null,
		p_create: bool = true,
		_p_vars = null,
	) -> NakamaSession:
		calls.append(["authenticate_google", p_create])
		return _session_for(google_account)

	func link_google_async(
		p_session: NakamaSession,
		_p_token: String,
	) -> NakamaAsyncResult:
		calls.append(["link_google", p_session.user_id])
		return NakamaAsyncResult.new()

	func link_device_async(
		p_session: NakamaSession,
		p_id: String,
	) -> NakamaAsyncResult:
		calls.append(["link_device", p_session.user_id, p_id])
		return NakamaAsyncResult.new()

	func get_account_async(p_session: NakamaSession):
		calls.append(["get_account", p_session.user_id])
		return NakamaAPI.ApiAccount.create(NakamaAPI, {
			"user": {"id": p_session.user_id, "google_id": "google-sub"},
		})

	func update_account_async(
		p_session: NakamaSession,
		_p_username = null,
		_p_display_name = null,
		_p_avatar_url = null,
		_p_lang_tag = null,
		_p_location = null,
		_p_timezone = null,
	) -> NakamaAsyncResult:
		calls.append(["update_account", p_session.user_id])
		return NakamaAsyncResult.new()

	func rpc_async(
		p_session: NakamaSession,
		p_id: String,
		_p_payload = null,
	):
		calls.append(["rpc", p_id, p_session.user_id])
		return NakamaAPI.ApiRpc.create(
			NakamaAPI, {"id": p_id, "payload": "{}"})

	func names() -> Array:
		var out: Array = []
		for call in calls:
			out.append(call[0])
		return out


## The real client with the browser step and Google's code exchange
## stubbed out.
class ProbeAuth extends PlatformAuthApiClient:
	var browser_calls: Array = []
	var google_id_token := ""

	func _start_browser_oauth(provider: Provider, _is_link := false) -> void:
		browser_calls.append([provider, _is_link])
		_oauth_provider = provider

	func _exchange_google_code_for_id_token(
		_code: String,
		_redirect_uri: String,
	) -> String:
		return google_id_token


var _client: ProbeAuth
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _row: LinkAccountRow
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

	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	Platform.token_store = _store
	_nakama = FakeNakamaClient.new()
	_nakama.device_account = _GUEST_ACCOUNT
	_nakama.google_account = _GOOGLE_ACCOUNT
	Platform.nakama_client = _nakama
	# Never added to the tree, so its own _process never runs.
	_client = ProbeAuth.new()
	_client.google_id_token = _nakama.fake_jwt("google-sub", 0)
	Platform.register_subsystem("auth", _client)
	_row = null


func after_each() -> void:
	if _row != null:
		_row._status_label.free()
		_row.free()
	Platform.register_subsystem("auth", _original_auth)
	_original_auth.set_process(_was_original_auth_processing)
	G.friends_notification_poller.set_process(_was_live_poller_processing)
	_client.free()
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client


## A guest who has played online: the local identity from "Play as
## guest", then the device session get_guest_jwt() takes for matchmaking.
func _become_guest_who_played_online() -> String:
	_client.login_anonymous()
	var device_id := _store.local_player_id
	await _client.get_guest_jwt()
	return device_id


## The OAuth callback's endpoint choice (auth_api_client.gd:641-643 for
## the desktop loopback, 795-797 for web), then its dispatch.
func _deliver_oauth_code() -> void:
	var endpoint: String = _client._AUTH_ENDPOINT
	if _client._is_linking:
		endpoint = _client._LINK_ENDPOINT
	await _client._send_auth_request(endpoint, {
		"provider": "google",
		"auth_code": "probe-code",
		"redirect_uri": "http://127.0.0.1:1",
	})


# AN-1: the guest presses Google on the "Keep Your Progress" panel. The row
# signs in with create=true; nothing links or migrates the guest account.
func test_an1_guest_upgrade_signs_in_to_another_account() -> void:
	var device_id: String = await _become_guest_who_played_online()
	assert_eq(_store.player_id, _GUEST_ACCOUNT, "guest has a server account")
	assert_true(_store.is_anonymous, "guest")
	assert_eq(
		_nakama.calls[0], ["authenticate_device", device_id, true],
		"the guest account is the device account",
	)

	_row = LinkAccountRow.new()
	_row._status_label = Label.new()
	_row.setup(PlatformAuthApiClient.Provider.GOOGLE, "Google", false, null)
	_row._try_link()
	assert_eq(
		_client.browser_calls,
		[[PlatformAuthApiClient.Provider.GOOGLE, false]],
		"AN-1: the row starts a sign-in, not a link",
	)
	assert_false(_client._is_linking, "AN-1: not in link mode")

	watch_signals(_client)
	await _deliver_oauth_code()
	assert_signal_emitted_with_parameters(_client, "auth_completed", [true, ""])
	assert_signal_not_emitted(_client, "link_completed")
	assert_eq(
		_nakama.names(),
		["authenticate_device", "authenticate_google", "get_account"],
		"AN-1: no link_google, no link_device, no RPC moves anything",
	)
	assert_eq(_nakama.calls[1], ["authenticate_google", true], "create=true")
	assert_eq(
		_store.player_id, _GOOGLE_ACCOUNT,
		"AN-1: now the Google identity's own account",
	)
	assert_false(_store.is_anonymous, "no longer a guest")
	assert_eq(
		_store.local_player_id, device_id,
		"the device id is still on disk until log-out",
	)

	# What sign-out does (sign_out_router.gd:77).
	_store.clear_tokens()
	assert_eq(
		_store.local_player_id, "",
		"AN-1: after log-out nothing on the device names the guest account",
	)


# Control: the link path from the same guest session keeps the account.
# This is the call the upgrade should make (Nakama LinkGoogle on the
# guest's device session).
func test_link_from_guest_session_keeps_the_account() -> void:
	await _become_guest_who_played_online()
	_client.link_provider(PlatformAuthApiClient.Provider.GOOGLE)
	assert_true(_client._is_linking, "link mode")
	watch_signals(_client)
	await _deliver_oauth_code()
	assert_signal_emitted(_client, "link_completed")
	assert_true(
		_nakama.calls.has(["link_google", _GUEST_ACCOUNT]),
		"link_google on the guest's own session",
	)
	assert_false(_nakama.names().has("authenticate_google"), "no sign-in")
	assert_eq(_store.player_id, _GUEST_ACCOUNT, "same account kept")
	# Residual for the fix: the store still calls this player a guest.
	assert_true(_store.is_anonymous, "link path leaves is_anonymous set")
