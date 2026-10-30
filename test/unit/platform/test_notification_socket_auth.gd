extends GutTest
## H23: the notification socket stopped on any failed auth
## result, transient refresh failures included, until the next
## successful refresh. It must stop only on a real sign-out and
## keep its connection state through a transient failure. The
## GUT case the H37 social audit asked for (F6).


const _TEST_AUTH_FILE := "user://test_notification_socket_auth.cfg"
const _SESSION_LIFETIME_SEC := 7200


var _auth: PlatformAuthApiClient
var _socket: PlatformNotificationSocketClient
var _store: PlatformAuthTokenStore
var _original_auth
var _original_token_store
var _was_original_auth_processing := false


func before_each() -> void:
	_original_auth = Platform.auth
	_original_token_store = Platform.token_store
	_was_original_auth_processing = _original_auth.is_processing()
	_original_auth.set_process(false)

	_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	_store_provider_session()
	Platform.token_store = _store

	# Never added to the tree, so its own _process never runs.
	_auth = PlatformAuthApiClient.new()
	Platform.register_subsystem("auth", _auth)

	# In the tree so _ready connects it to the fake auth client.
	_socket = PlatformNotificationSocketClient.new()
	add_child_autofree(_socket)
	_socket.set_process(false)
	# As after a successful start, without opening a connection.
	_socket._wants_connection = true


func after_each() -> void:
	Platform.register_subsystem("auth", _original_auth)
	_original_auth.set_process(_was_original_auth_processing)
	_auth.free()
	_store.clear_tokens()
	Platform.token_store = _original_token_store


func test_transient_failure_keeps_the_socket() -> void:
	_auth.auth_completed.emit(false, "HTTPRequest failed!")

	assert_true(
		_socket._wants_connection, "still wants the connection")


func test_cleared_session_stops_the_socket() -> void:
	_store.clear_tokens()

	_auth.auth_completed.emit(false, "Refresh token invalid")

	assert_false(
		_socket._wants_connection, "stopped with the session")


func test_signed_out_stops_the_socket() -> void:
	_auth.signed_out.emit("Refresh token invalid")

	assert_false(
		_socket._wants_connection, "stopped on sign-out")


func _store_provider_session() -> void:
	_store.is_anonymous = false
	_store.provider = "google"
	_store.player_id = "test-player"
	_store.jwt_token = "test-access-token"
	_store.refresh_token = "test-refresh-token"
	_store.expires_at = (
		int(Time.get_unix_time_from_system())
		+ _SESSION_LIFETIME_SEC)
