class_name AuthClient
extends Node
## HTTP client for backend authentication endpoints.
##
## Handles login (OAuth + anonymous), token refresh, and
## account linking. For browser-based OAuth providers
## (Google, Apple, Discord, Twitch), opens a browser and
## runs a local TCP loopback server to capture the auth
## code redirect.

## Emitted on successful authentication.
signal auth_completed(success: bool, error: String)

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
	APPLE,
	DISCORD,
	TWITCH,
	ANONYMOUS,
}

const _LOOPBACK_PORT := 9876
const _LOOPBACK_HOST := "127.0.0.1"
const _REFRESH_COOLDOWN_SEC := 60.0
const _AUTH_ENDPOINT := "/auth/login"
const _ANON_ENDPOINT := "/auth/anon"
const _REFRESH_ENDPOINT := "/auth/refresh"
const _LINK_ENDPOINT := "/auth/link"

## Maps Provider enum to string name sent to backend.
const _PROVIDER_NAMES := {
	Provider.STEAM: "steam",
	Provider.EPIC: "epic",
	Provider.GOOGLE: "google",
	Provider.APPLE: "apple",
	Provider.DISCORD: "discord",
	Provider.TWITCH: "twitch",
	Provider.ANONYMOUS: "anonymous",
}

## Providers that use browser-based OAuth flow.
const _BROWSER_PROVIDERS := [
	Provider.GOOGLE,
	Provider.APPLE,
	Provider.DISCORD,
	Provider.TWITCH,
]

var _http_request: HTTPRequest
var _tcp_server: TCPServer
var _oauth_state: String
var _oauth_provider: Provider
var _is_awaiting_oauth := false
var _last_refresh_time := 0.0
var _is_refreshing := false


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 30.0
	add_child(_http_request)


func _process(delta: float) -> void:
	if _is_awaiting_oauth and _tcp_server != null:
		_poll_oauth_redirect()

	_check_auto_refresh()


## Start login flow for the given provider.
func login_with_provider(provider: Provider) -> void:
	if provider == Provider.ANONYMOUS:
		login_anonymous()
		return

	if provider in _BROWSER_PROVIDERS:
		_start_browser_oauth(provider)
	else:
		# Steam and Epic send platform tokens directly.
		# The game client must obtain the token from
		# the platform SDK first, then call
		# submit_platform_token().
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
	if provider in _BROWSER_PROVIDERS:
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
	auth_status_changed.emit("Linking account...")
	var body := {
		"provider": _PROVIDER_NAMES[provider],
		"auth_code": token,
	}
	_send_auth_request(
		_LINK_ENDPOINT, body, true
	)


# --- Browser OAuth flow ---


func _start_browser_oauth(
	provider: Provider,
	is_link := false,
) -> void:
	_oauth_provider = provider
	_oauth_state = _generate_state_nonce()

	# Start loopback TCP server.
	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(
		_LOOPBACK_PORT, _LOOPBACK_HOST
	)
	if err != OK:
		auth_completed.emit(
			false,
			"Failed to start loopback server",
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
		auth_completed.emit(
			false, "No auth code received"
		)
		return

	if state != _oauth_state:
		auth_completed.emit(
			false, "OAuth state mismatch"
		)
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

	var is_link := false
	# Determine endpoint. If we have a valid token,
	# this might be a link request.
	var endpoint := _AUTH_ENDPOINT
	if (
		G.auth_token_store.is_token_valid()
		and not G.auth_token_store.is_anonymous
	):
		endpoint = _LINK_ENDPOINT
		is_link = true
	elif G.auth_token_store.is_token_valid():
		# Anonymous upgrading to full account.
		endpoint = _LINK_ENDPOINT
		is_link = true

	_send_auth_request(endpoint, body, is_link)


func _cleanup_tcp_server() -> void:
	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null


# --- HTTP requests ---


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
		auth_completed.emit(
			false, "HTTP request failed: %d" % err
		)


func _on_auth_response(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	_is_refreshing = false

	if result != HTTPRequest.RESULT_SUCCESS:
		auth_completed.emit(
			false, "Request failed: %d" % result
		)
		return

	var json := JSON.new()
	var parse_err := json.parse(
		body.get_string_from_utf8()
	)
	if parse_err != OK:
		auth_completed.emit(
			false, "Invalid server response"
		)
		return

	var data: Dictionary = json.data

	if response_code != 200:
		var msg: String = data.get(
			"message", "Authentication failed"
		)
		auth_completed.emit(false, msg)
		return

	if data.get("status") != "success":
		auth_completed.emit(
			false,
			data.get("message", "Unknown error"),
		)
		return

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

	# Store tokens.
	if data.has("jwt_token"):
		G.auth_token_store.store_from_response(data)
		_last_refresh_time = (
			Time.get_unix_time_from_system()
		)

	auth_status_changed.emit("Authenticated")
	auth_completed.emit(true, "")


# --- Auto-refresh ---


func _check_auto_refresh() -> void:
	if not G.auth_token_store.needs_refresh():
		return
	if _is_refreshing:
		return
	var now := Time.get_unix_time_from_system()
	if now - _last_refresh_time < _REFRESH_COOLDOWN_SEC:
		return
	refresh_token()


# --- OAuth URL builders ---


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
		Provider.DISCORD:
			return _build_discord_auth_url(
				redirect_uri, state
			)
		Provider.TWITCH:
			return _build_twitch_auth_url(
				redirect_uri, state
			)
		Provider.APPLE:
			return _build_apple_auth_url(
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


func _build_discord_auth_url(
	redirect_uri: String,
	state: String,
) -> String:
	var client_id := G.settings.discord_oauth_client_id
	return (
		"https://discord.com/api/oauth2/authorize"
		+ "?client_id=%s" % client_id
		+ "&redirect_uri=%s" % redirect_uri.uri_encode()
		+ "&response_type=code"
		+ "&scope=identify"
		+ "&state=%s" % state
	)


func _build_twitch_auth_url(
	redirect_uri: String,
	state: String,
) -> String:
	var client_id := G.settings.twitch_oauth_client_id
	return (
		"https://id.twitch.tv/oauth2/authorize"
		+ "?client_id=%s" % client_id
		+ "&redirect_uri=%s" % redirect_uri.uri_encode()
		+ "&response_type=code"
		+ "&scope=user:read:email"
		+ "&state=%s" % state
	)


func _build_apple_auth_url(
	redirect_uri: String,
	state: String,
) -> String:
	var client_id := G.settings.apple_oauth_client_id
	return (
		"https://appleid.apple.com/auth/authorize"
		+ "?client_id=%s" % client_id
		+ "&redirect_uri=%s" % redirect_uri.uri_encode()
		+ "&response_type=code"
		+ "&scope=name%%20email"
		+ "&response_mode=query"
		+ "&state=%s" % state
	)


# --- Utilities ---


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
