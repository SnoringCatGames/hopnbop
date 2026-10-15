extends GutTest
## H37 phase 2b probe (h37-verify2, item 3, DEL-2 UI half): what the
## Delete Account confirm panel does when the delete RPC fails. Drives the
## real DeleteAccountConfirmPanel handlers and the real
## PlatformAuthApiClient against a fake Nakama client whose RPC fails; no
## network. Fake and setup: h37-account's test_h37_account_probe.gd.


const _TEST_AUTH_FILE := "user://h37v2_del2_panel_probe.cfg"
const _GRPC_UNAVAILABLE := 14
const _HTTP_SERVICE_UNAVAILABLE := 503
const _VERIFY_WORD := "DELETE"


class FakeNakamaClient extends NakamaClient:
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

	func rpc_async(
		_p_session: NakamaSession,
		p_id: String,
		_p_payload = null,
	):
		rpc_ids.append(p_id)
		if next_rpc_exception != null:
			return NakamaAPI.ApiRpc.new(next_rpc_exception)
		return NakamaAPI.ApiRpc.new()


var _client: PlatformAuthApiClient
var _nakama: FakeNakamaClient
var _store: PlatformAuthTokenStore
var _panel: DeleteAccountConfirmPanel
var _original_auth
var _original_token_store
var _original_nakama_client
var _was_original_auth_processing := false
var _was_live_poller_processing := false


func _fake_jwt(expires_at: int) -> String:
	var claims := JSON.stringify({"exp": expires_at, "uid": "test-player"})
	var payload := (
		Marshalls.utf8_to_base64(claims)
		.replace("+", "-")
		.replace("/", "_")
		.replace("=", "")
	)
	return "probe-header.%s.probe-signature" % payload


func before_each() -> void:
	_original_auth = Platform.auth
	_original_token_store = Platform.token_store
	_original_nakama_client = Platform.nakama_client
	_was_original_auth_processing = _original_auth.is_processing()
	_original_auth.set_process(false)
	_was_live_poller_processing = (
		G.friends_notification_poller.is_processing())
	G.friends_notification_poller.set_process(false)

	var now := int(Time.get_unix_time_from_system())
	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store.provider = "google"
	_store.player_id = "test-player"
	_store.display_name = "Player"
	_store.expires_at = now + 600
	_store.jwt_token = _fake_jwt(_store.expires_at)
	_store.refresh_token = _fake_jwt(now + 604800)
	_store.save_tokens()
	Platform.token_store = _store
	_nakama = FakeNakamaClient.new()
	Platform.nakama_client = _nakama
	_client = PlatformAuthApiClient.new()
	Platform.register_subsystem("auth", _client)

	# The panel's state after build_ui() and a matching verify word; never
	# added to the tree, so no manager and no scene rows are needed.
	_panel = DeleteAccountConfirmPanel.new()
	_panel._confirm_row = ActionRow.new()
	_panel._verify_word = _VERIFY_WORD
	_panel._on_input_changed(_VERIFY_WORD)


func after_each() -> void:
	_panel._confirm_row.free()
	_panel.free()
	Platform.register_subsystem("auth", _original_auth)
	_original_auth.set_process(_was_original_auth_processing)
	G.friends_notification_poller.set_process(_was_live_poller_processing)
	_client.free()
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client


# DEL-2, UI half: the delete fails, the panel never hears of it, stays busy
# with the confirm row disabled, and cannot be retried until it is closed.
func test_del2_panel_stuck_after_failed_delete() -> void:
	assert_false(_panel._confirm_row.disabled, "confirm enabled before")
	_nakama.next_rpc_exception = NakamaException.new(
		"Service unavailable",
		_HTTP_SERVICE_UNAVAILABLE,
		_GRPC_UNAVAILABLE,
	)
	watch_signals(_client)

	_panel._on_confirm_pressed()

	assert_eq(_nakama.rpc_ids, ["delete_account"], "the RPC was sent")
	assert_signal_not_emitted(_client, "delete_completed", "DEL-2")
	assert_signal_emitted(_client, "auth_completed", "reported as auth")
	assert_true(
		_panel._is_busy,
		"DEL-2: _on_delete_completed never ran, the panel stays busy",
	)
	assert_true(_panel._confirm_row.disabled, "confirm row stays disabled")

	# The player retypes the word and presses confirm again.
	_panel._on_input_changed(_VERIFY_WORD)
	assert_true(
		_panel._confirm_row.disabled,
		"DEL-2: still disabled while busy",
	)
	_panel._confirm_row.disabled = false
	_panel._on_confirm_pressed()
	assert_eq(
		_nakama.rpc_ids.size(), 1,
		"DEL-2: a second press sends nothing",
	)
	assert_true(_store.jwt_token != "", "player still signed in")
