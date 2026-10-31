extends GutTest
## DeleteAccountConfirmPanel when the delete RPC fails: the
## panel hears the failure through delete_completed, clears
## its busy state, and lets the player retry. (The H37
## verify2 probe asserted the stuck behavior; this is that
## probe flipped into the suite.)


const _TEST_AUTH_FILE := "user://test_delete_panel.cfg"
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
var _delete_results: Array = []
var _auth_results: Array = []
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
	_delete_results = []
	_auth_results = []
	_client.delete_completed.connect(_on_delete_completed)
	_client.auth_completed.connect(_on_auth_completed)

	# The panel's state after build_ui() and a matching
	# verify word; never added to the tree, so no manager
	# and no scene rows are needed.
	_panel = DeleteAccountConfirmPanel.new()
	_panel._confirm_row = ActionRow.new()
	_panel._verify_word = _VERIFY_WORD
	_panel._on_input_changed(_VERIFY_WORD)


func after_each() -> void:
	_panel._confirm_row.free()
	_panel.free()
	Platform.register_subsystem("auth", _original_auth)
	_original_auth.set_process(_was_original_auth_processing)
	G.friends_notification_poller.set_process(
		_was_live_poller_processing)
	_client.free()
	_store.clear_tokens()
	Platform.token_store = _original_token_store
	Platform.nakama_client = _original_nakama_client


func _on_delete_completed(success: bool, error: String) -> void:
	_delete_results.append([success, error])


func _on_auth_completed(success: bool, error: String) -> void:
	_auth_results.append([success, error])


func test_failed_delete_clears_busy_and_allows_retry() -> void:
	assert_false(
		_panel._confirm_row.disabled, "confirm enabled before")
	_nakama.next_rpc_exception = NakamaException.new(
		"Service unavailable",
		_HTTP_SERVICE_UNAVAILABLE,
		_GRPC_UNAVAILABLE,
	)

	_panel._on_confirm_pressed()

	assert_eq(_nakama.rpc_ids, ["delete_account"], "the RPC was sent")
	assert_eq(_delete_results.size(), 1, "failure reported to panel")
	if _delete_results.is_empty():
		return
	assert_false(_delete_results[0][0], "delete failed")
	assert_ne(_delete_results[0][1], "", "error text present")
	assert_true(
		_auth_results.is_empty(), "not reported as a sign-in failure")
	assert_false(_panel._is_busy, "busy cleared")
	assert_false(_store.jwt_token.is_empty(), "still signed in")

	# The player retypes the word: the row enables again and
	# a second press sends a second RPC.
	_panel._on_input_changed(_VERIFY_WORD)
	assert_false(
		_panel._confirm_row.disabled, "confirm enabled for retry")
	_panel._on_confirm_pressed()
	assert_eq(_nakama.rpc_ids.size(), 2, "retry sent")
	assert_eq(_delete_results.size(), 2, "retry reported")
	assert_false(_panel._is_busy, "busy cleared after retry")


func _fake_jwt(expires_at: int) -> String:
	var claims := JSON.stringify(
		{"exp": expires_at, "uid": "test-player"})
	var payload := (
		Marshalls.utf8_to_base64(claims)
		.replace("+", "-")
		.replace("/", "_")
		.replace("=", "")
	)
	return "test-header.%s.test-signature" % payload
