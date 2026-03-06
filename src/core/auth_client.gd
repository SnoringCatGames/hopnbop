class_name AuthClient
extends Node
## HTTP client for backend authentication endpoints.
##
## Handles login (OAuth + anonymous), token refresh, and
## account linking. Supports three OAuth flows:
## - Loopback: Desktop clients open browser, local TCP
##   server captures redirect (Google, Facebook).
## - Popup: Web builds open a popup window, static
##   callback page sends code via postMessage.
## - Platform: Steam/Epic provide tokens via their SDK.

## Emitted on successful authentication.
signal auth_completed(success: bool, error: String)

## Emitted when account linking completes.
signal link_completed(
	success: bool,
	error: String,
	provider: String,
)

## Emitted when account unlinking completes.
signal unlink_completed(
	success: bool,
	error: String,
	provider: String,
)

## Emitted when account deletion completes.
signal delete_completed(success: bool, error: String)

## Status updates for UI feedback.
signal auth_status_changed(status: String)

## Emitted when backend reports a game version mismatch.
signal version_mismatch(
	client_version: String,
	server_version: String,
)

enum Provider {
	STEAM,
	EPIC,
	GOOGLE,
	FACEBOOK,
	APPLE,
	ANONYMOUS,
}

## Platforms where auth is implied (SDK provides token).
const PLATFORM_PROVIDERS := [
	Provider.STEAM,
	Provider.EPIC,
]

const _LOOPBACK_PORT := 9876
const _LOOPBACK_HOST := "127.0.0.1"
const _REFRESH_COOLDOWN_SEC := 60.0
const _AUTH_ENDPOINT := "/auth/login"
const _ANON_ENDPOINT := "/auth/anon"
const _REFRESH_ENDPOINT := "/auth/refresh"
const _LINK_ENDPOINT := "/auth/link"
const _UNLINK_ENDPOINT := "/auth/unlink"
const _DELETE_ACCOUNT_ENDPOINT := "/auth/account"
const _POPUP_TIMEOUT_SEC := 300.0

## Maps Provider enum to string name sent to backend.
const _PROVIDER_NAMES := {
	Provider.STEAM: "steam",
	Provider.EPIC: "epic",
	Provider.GOOGLE: "google",
	Provider.FACEBOOK: "facebook",
	Provider.APPLE: "apple",
	Provider.ANONYMOUS: "anonymous",
}

## Providers that use browser-based OAuth flow.
const _BROWSER_PROVIDERS := [
	Provider.GOOGLE,
	Provider.FACEBOOK,
]

var _http_request: HTTPRequest
var _tcp_server: TCPServer
var _oauth_state: String
var _oauth_provider: Provider
var _is_awaiting_oauth := false
var _last_refresh_time := 0.0
var _is_refreshing := false

# Account linking state.
var _is_linking := false
var _link_provider_name := ""

# Account unlinking state.
var _is_unlinking := false
var _unlink_provider_name := ""

# Account deletion state.
var _is_deleting := false

# Popup OAuth state (web platform).
var _js_message_callback: JavaScriptObject
var _popup_timeout_timer: Timer


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 30.0
	add_child(_http_request)


func _process(_delta: float) -> void:
	if _is_awaiting_oauth and _tcp_server != null:
		_poll_oauth_redirect()

	_check_auto_refresh()


## Returns true if running in a web browser.
static func is_web_platform() -> bool:
	return OS.has_feature("web")


## Returns the implied platform provider, or -1 if none.
static func get_platform_provider() -> int:
	if OS.has_feature("steam"):
		return Provider.STEAM
	# Epic detection would go here.
	return -1


## Start login flow for the given provider.
func login_with_provider(provider: Provider) -> void:
	if provider == Provider.ANONYMOUS:
		login_anonymous()
		return

	if provider in _BROWSER_PROVIDERS:
		if is_web_platform():
			_start_web_oauth(provider)
		else:
			_start_browser_oauth(provider)
	else:
		# Steam and Epic send platform tokens directly.
		auth_status_changed.emit(
			"Waiting for %s token..."
			% _PROVIDER_NAMES[provider]
		)


## Submit a platform token (Steam ticket or Epic
## access token) directly.
func submit_platform_token(
	provider: Provider,
	token: String,
) -> void:
	auth_status_changed.emit("Authenticating...")
	var body := {
		"provider": _PROVIDER_NAMES[provider],
		"auth_code": token,
	}
	_send_auth_request(_AUTH_ENDPOINT, body)


## Anonymous login using device ID.
func login_anonymous() -> void:
	auth_status_changed.emit("Signing in...")
	var device_id := OS.get_unique_id()
	if device_id.is_empty():
		device_id = _generate_fallback_device_id()
	var body := {"device_id": device_id}
	_send_auth_request(_ANON_ENDPOINT, body)


## Refresh the current JWT using the stored refresh
## token.
func refresh_token() -> void:
	if _is_refreshing:
		return

	var store := G.auth_token_store
	if store.refresh_token.is_empty():
		auth_completed.emit(false, "No refresh token")
		return

	_is_refreshing = true
	auth_status_changed.emit("Refreshing session...")
	var body := {
		"player_id": store.player_id,
		"refresh_token": store.refresh_token,
	}
	_send_auth_request(_REFRESH_ENDPOINT, body)


## Link a new OAuth provider to the current account.
func link_provider(provider: Provider) -> void:
	_is_linking = true
	_link_provider_name = _PROVIDER_NAMES[provider]
	if provider in _BROWSER_PROVIDERS:
		if is_web_platform():
			_start_web_oauth(provider)
		else:
			_start_browser_oauth(provider, true)
	else:
		auth_status_changed.emit(
			"Use submit_platform_link() for %s"
			% _PROVIDER_NAMES[provider]
		)


## Submit a platform token for account linking.
func submit_platform_link(
	provider: Provider,
	token: String,
) -> void:
	_is_linking = true
	_link_provider_name = _PROVIDER_NAMES[provider]
	auth_status_changed.emit("Linking account...")
	var body := {
		"provider": _PROVIDER_NAMES[provider],
		"auth_code": token,
	}
	_send_auth_request(
		_LINK_ENDPOINT, body, true
	)


## Unlink a provider from the current account.
func unlink_provider(provider: Provider) -> void:
	_is_unlinking = true
	_unlink_provider_name = _PROVIDER_NAMES[provider]
	auth_status_changed.emit("Unlinking account...")
	var body := {
		"provider": _PROVIDER_NAMES[provider],
	}
	_send_auth_request(
		_UNLINK_ENDPOINT, body, true
	)


## Delete the current account and all associated data.
func delete_account() -> void:
	if _is_deleting:
		return
	_is_deleting = true
	auth_status_changed.emit("Deleting account...")
	_send_delete_request()


# =============================================================
# Desktop loopback OAuth flow
# =============================================================


func _start_browser_oauth(
	provider: Provider,
	_is_link := false,
) -> void:
	_oauth_provider = provider
	_oauth_state = _generate_state_nonce()

	# Start loopback TCP server.
	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(
		_LOOPBACK_PORT, _LOOPBACK_HOST
	)
	if err != OK:
		_emit_failure(
			"Failed to start loopback server"
		)
		return

	_is_awaiting_oauth = true
	var redirect_uri := (
		"http://%s:%d" % [_LOOPBACK_HOST, _LOOPBACK_PORT]
	)

	var auth_url := _build_oauth_url(
		provider, redirect_uri, _oauth_state
	)
	auth_status_changed.emit(
		"Opening browser for %s..."
		% _PROVIDER_NAMES[provider]
	)
	OS.shell_open(auth_url)


func _poll_oauth_redirect() -> void:
	if not _tcp_server.is_connection_available():
		return

	var connection := _tcp_server.take_connection()
	if connection == null:
		return

	# Wait briefly for data.
	var data := ""
	var start := Time.get_ticks_msec()
	while (
		connection.get_status()
			== StreamPeerTCP.STATUS_CONNECTED
		and Time.get_ticks_msec() - start < 2000
	):
		if connection.get_available_bytes() > 0:
			data += connection.get_utf8_string(
				connection.get_available_bytes()
			)
			if "\r\n\r\n" in data:
				break
		await get_tree().process_frame

	# Send response HTML.
	var html := (
		"HTTP/1.1 200 OK\r\n"
		+ "Content-Type: text/html\r\n\r\n"
		+ "<html><body><h2>Authentication"
		+ " complete</h2><p>You can close this"
		+ " window.</p></body></html>"
	)
	connection.put_data(html.to_utf8_buffer())
	connection.disconnect_from_host()

	_cleanup_tcp_server()
	_is_awaiting_oauth = false

	# Parse auth code from request.
	var code := _parse_query_param(data, "code")
	var state := _parse_query_param(data, "state")

	if code.is_empty():
		_emit_failure("No auth code received")
		return

	if state != _oauth_state:
		_emit_failure("OAuth state mismatch")
		return

	var redirect_uri := (
		"http://%s:%d" % [_LOOPBACK_HOST, _LOOPBACK_PORT]
	)

	auth_status_changed.emit("Authenticating...")
	var body := {
		"provider": _PROVIDER_NAMES[_oauth_provider],
		"auth_code": code,
		"redirect_uri": redirect_uri,
	}

	# Determine endpoint.
	var endpoint := _AUTH_ENDPOINT
	if _is_linking:
		endpoint = _LINK_ENDPOINT

	_send_auth_request(
		endpoint, body, endpoint == _LINK_ENDPOINT
	)


func _cleanup_tcp_server() -> void:
	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null


# =============================================================
# Web popup OAuth flow (postMessage)
# =============================================================


func _start_web_oauth(
	provider: Provider,
) -> void:
	_oauth_provider = provider
	_oauth_state = _generate_state_nonce()

	var redirect_uri := G.settings.oauth_callback_url
	var auth_url := _build_oauth_url(
		provider, redirect_uri, _oauth_state
	)

	auth_status_changed.emit(
		"Opening %s login..."
		% _PROVIDER_NAMES[provider]
	)

	# Register JS message listener for the callback.
	_setup_js_message_listener()

	# Open popup. Must happen synchronously from user
	# interaction to avoid popup blockers.
	var js_code := (
		"window.open('%s', 'oauth_popup',"
		+ " 'width=500,height=700')"
	) % auth_url.replace("'", "\\'")
	var popup: JavaScriptObject = (
		JavaScriptBridge.eval(js_code)
	)

	if popup == null:
		_cleanup_js_message_listener()
		_emit_failure(
			"Popup blocked. Please allow popups."
		)
		return

	auth_status_changed.emit(
		"Complete sign-in in the popup..."
	)

	# Start a timeout timer.
	_start_popup_timeout()


func _setup_js_message_listener() -> void:
	_cleanup_js_message_listener()

	_js_message_callback = (
		JavaScriptBridge.create_callback(
			_on_js_message
		)
	)
	JavaScriptBridge.eval(
		"window._hopnbop_oauth_cb = null;"
	)
	var window: JavaScriptObject = (
		JavaScriptBridge.get_interface("window")
	)
	window.addEventListener(
		"message", _js_message_callback
	)


func _cleanup_js_message_listener() -> void:
	if _js_message_callback != null:
		var window: JavaScriptObject = (
			JavaScriptBridge.get_interface("window")
		)
		window.removeEventListener(
			"message", _js_message_callback
		)
		_js_message_callback = null

	if _popup_timeout_timer != null:
		_popup_timeout_timer.stop()
		_popup_timeout_timer.queue_free()
		_popup_timeout_timer = null


func _start_popup_timeout() -> void:
	if _popup_timeout_timer != null:
		_popup_timeout_timer.queue_free()

	_popup_timeout_timer = Timer.new()
	_popup_timeout_timer.wait_time = _POPUP_TIMEOUT_SEC
	_popup_timeout_timer.one_shot = true
	_popup_timeout_timer.timeout.connect(
		_on_popup_timeout
	)
	add_child(_popup_timeout_timer)
	_popup_timeout_timer.start()


func _on_popup_timeout() -> void:
	_cleanup_js_message_listener()
	_emit_failure("Sign-in timed out")


func _on_js_message(args: Array) -> void:
	# args[0] is the MessageEvent.
	var event: JavaScriptObject = args[0]

	# Verify origin matches our callback URL.
	var origin: String = event.origin
	var expected_origin := (
		G.settings.oauth_callback_url
			.get_base_dir()
			.trim_suffix("/")
	)
	# get_base_dir on a URL strips the filename, giving
	# the origin. But we need just scheme + host.
	# Use a simpler check: the callback URL must start
	# with the event origin.
	if not G.settings.oauth_callback_url.begins_with(
		origin
	):
		return

	var data: JavaScriptObject = event.data
	if data == null:
		return

	var msg_type: String = data.type
	if msg_type != "oauth_callback":
		return

	var code: String = data.code
	var state: String = data.state

	_cleanup_js_message_listener()

	if code.is_empty():
		_emit_failure("No auth code received")
		return

	if state != _oauth_state:
		_emit_failure("OAuth state mismatch")
		return

	var redirect_uri := G.settings.oauth_callback_url

	auth_status_changed.emit("Authenticating...")
	var body := {
		"provider": _PROVIDER_NAMES[_oauth_provider],
		"auth_code": code,
		"redirect_uri": redirect_uri,
	}

	# Determine endpoint.
	var endpoint := _AUTH_ENDPOINT
	if _is_linking:
		endpoint = _LINK_ENDPOINT

	_send_auth_request(
		endpoint, body, endpoint == _LINK_ENDPOINT
	)


# =============================================================
# HTTP requests
# =============================================================


func _send_auth_request(
	endpoint: String,
	body: Dictionary,
	include_auth_header := false,
) -> void:
	var url := (
		G.settings.gamelift_backend_api_url + endpoint
	)
	var json_body := JSON.stringify(body)

	var headers := [
		"Content-Type: application/json",
	]
	if include_auth_header:
		headers.append(
			"Authorization: Bearer %s"
			% G.auth_token_store.jwt_token
		)

	# Disconnect previous signal if any.
	if _http_request.request_completed.is_connected(
		_on_auth_response
	):
		_http_request.request_completed.disconnect(
			_on_auth_response
		)

	_http_request.request_completed.connect(
		_on_auth_response, CONNECT_ONE_SHOT
	)

	var err := _http_request.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		json_body,
	)
	if err != OK:
		_is_refreshing = false
		_emit_failure("HTTP request failed: %d" % err)


func _send_delete_request() -> void:
	var url := (
		G.settings.gamelift_backend_api_url
		+ _DELETE_ACCOUNT_ENDPOINT
	)

	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s"
		% G.auth_token_store.jwt_token,
	]

	if _http_request.request_completed.is_connected(
		_on_auth_response
	):
		_http_request.request_completed.disconnect(
			_on_auth_response
		)

	_http_request.request_completed.connect(
		_on_auth_response, CONNECT_ONE_SHOT
	)

	var err := _http_request.request(
		url,
		headers,
		HTTPClient.METHOD_DELETE,
	)
	if err != OK:
		_is_deleting = false
		_emit_failure("HTTP request failed: %d" % err)


func _on_auth_response(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	_is_refreshing = false

	if result != HTTPRequest.RESULT_SUCCESS:
		_emit_failure("Request failed: %d" % result)
		return

	var json := JSON.new()
	var parse_err := json.parse(
		body.get_string_from_utf8()
	)
	if parse_err != OK:
		_emit_failure("Invalid server response")
		return

	var data: Dictionary = json.data

	if response_code != 200:
		var msg: String = data.get(
			"message", "Authentication failed"
		)
		_emit_failure(msg)
		return

	if data.get("status") != "success":
		_emit_failure(
			data.get("message", "Unknown error")
		)
		return

	# Handle delete response separately.
	if _is_deleting:
		_handle_delete_success()
		return

	# Handle unlink response separately.
	if _is_unlinking:
		_handle_unlink_success(data)
		return

	_handle_auth_success(data)


func _handle_auth_success(data: Dictionary) -> void:
	# Check game version.
	var server_version: String = data.get(
		"game_version", ""
	)
	if not server_version.is_empty():
		var client_version: String = (
			ProjectSettings.get_setting(
				"application/config/version",
				"0.0.0",
			)
		)
		if server_version != client_version:
			version_mismatch.emit(
				client_version, server_version
			)

	# Update linked providers from response.
	if data.has("linked_providers"):
		G.auth_token_store.linked_providers.clear()
		var lp: Array = data.get("linked_providers", [])
		for p in lp:
			G.auth_token_store.linked_providers.append(
				str(p)
			)
		G.auth_token_store.save_tokens()

	if _is_linking:
		_is_linking = false
		var provider_name := _link_provider_name
		_link_provider_name = ""
		link_completed.emit(true, "", provider_name)
		return

	# Store tokens.
	if data.has("jwt_token"):
		G.auth_token_store.store_from_response(data)
		_last_refresh_time = (
			Time.get_unix_time_from_system()
		)

	auth_status_changed.emit("Authenticated")
	auth_completed.emit(true, "")


func _handle_unlink_success(data: Dictionary) -> void:
	_is_unlinking = false
	var provider_name := _unlink_provider_name
	_unlink_provider_name = ""

	# Update linked providers from response.
	if data.has("linked_providers"):
		G.auth_token_store.linked_providers.clear()
		var lp: Array = data.get("linked_providers", [])
		for p in lp:
			G.auth_token_store.linked_providers.append(
				str(p)
			)
		G.auth_token_store.save_tokens()

	unlink_completed.emit(true, "", provider_name)


func _handle_delete_success() -> void:
	_is_deleting = false
	G.auth_token_store.clear_tokens()
	delete_completed.emit(true, "")


func _emit_failure(error: String) -> void:
	if _is_linking:
		_is_linking = false
		var provider_name := _link_provider_name
		_link_provider_name = ""
		link_completed.emit(false, error, provider_name)
	elif _is_unlinking:
		_is_unlinking = false
		var provider_name := _unlink_provider_name
		_unlink_provider_name = ""
		unlink_completed.emit(false, error, provider_name)
	elif _is_deleting:
		_is_deleting = false
		delete_completed.emit(false, error)
	else:
		auth_completed.emit(false, error)


# =============================================================
# Auto-refresh
# =============================================================


func _check_auto_refresh() -> void:
	if not G.auth_token_store.needs_refresh():
		return
	if _is_refreshing:
		return
	var now := Time.get_unix_time_from_system()
	if now - _last_refresh_time < _REFRESH_COOLDOWN_SEC:
		return
	refresh_token()


# =============================================================
# OAuth URL builders
# =============================================================


func _build_oauth_url(
	provider: Provider,
	redirect_uri: String,
	state: String,
) -> String:
	match provider:
		Provider.GOOGLE:
			return _build_google_auth_url(
				redirect_uri, state
			)
		Provider.FACEBOOK:
			return _build_facebook_auth_url(
				redirect_uri, state
			)
		_:
			return ""


func _build_google_auth_url(
	redirect_uri: String,
	state: String,
) -> String:
	var client_id := G.settings.google_oauth_client_id
	return (
		"https://accounts.google.com/o/oauth2/v2/auth"
		+ "?client_id=%s" % client_id
		+ "&redirect_uri=%s" % redirect_uri.uri_encode()
		+ "&response_type=code"
		+ "&scope=openid%%20profile%%20email"
		+ "&state=%s" % state
	)


func _build_facebook_auth_url(
	redirect_uri: String,
	state: String,
) -> String:
	var client_id := G.settings.facebook_oauth_client_id
	return (
		"https://www.facebook.com/v19.0/dialog/oauth"
		+ "?client_id=%s" % client_id
		+ "&redirect_uri=%s" % redirect_uri.uri_encode()
		+ "&response_type=code"
		+ "&scope=public_profile"
		+ "&state=%s" % state
	)


# =============================================================
# Utilities
# =============================================================


func _generate_state_nonce() -> String:
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in bytes.size():
		bytes[i] = randi() % 256
	return bytes.hex_encode()


func _generate_fallback_device_id() -> String:
	# Persist a generated device ID for platforms
	# where OS.get_unique_id() is empty.
	var config := ConfigFile.new()
	var path := "user://device_id.cfg"
	if config.load(path) == OK:
		var stored: String = config.get_value(
			"device", "id", ""
		)
		if not stored.is_empty():
			return stored

	var device_id := _generate_state_nonce()
	config.set_value("device", "id", device_id)
	config.save(path)
	return device_id


func _parse_query_param(
	http_request_text: String,
	param_name: String,
) -> String:
	# Extract a query parameter from an HTTP GET
	# request line like "GET /?code=abc&state=xyz".
	var lines := http_request_text.split("\r\n")
	if lines.is_empty():
		return ""
	var first_line := lines[0]
	var parts := first_line.split(" ")
	if parts.size() < 2:
		return ""
	var path := parts[1]
	var query_start := path.find("?")
	if query_start < 0:
		return ""
	var query := path.substr(query_start + 1)
	var pairs := query.split("&")
	for pair in pairs:
		var kv := pair.split("=", true, 1)
		if kv.size() == 2 and kv[0] == param_name:
			return kv[1].uri_decode()
	return ""
