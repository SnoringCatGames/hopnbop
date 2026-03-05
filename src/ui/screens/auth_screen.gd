class_name AuthScreen
extends Screen
## Authentication screen with provider login buttons.
##
## Shows sign-in options (6 OAuth providers + anonymous).
## Checks for cached tokens on open and auto-navigates
## to lobby if valid.

var _is_authenticating := false


func _enter_tree() -> void:
	super._enter_tree()
	G.auth_screen = self


func on_open() -> void:
	super.on_open()

	_show_buttons()
	%StatusLabel.text = ""
	%ErrorLabel.text = ""

	# Check cached token.
	if G.auth_token_store.is_token_valid():
		_navigate_to_lobby()
		return

	# Try auto-refresh.
	if G.auth_token_store.needs_refresh():
		_show_loading("Resuming session...")
		G.auth_client.auth_completed.connect(
			_on_auto_refresh_completed,
			CONNECT_ONE_SHOT,
		)
		G.auth_client.refresh_token()
		return


func on_close() -> void:
	super.on_close()
	_disconnect_signals()


func _show_buttons() -> void:
	_is_authenticating = false
	%ButtonsContainer.visible = true
	%LoadingContainer.visible = false


func _show_loading(status: String) -> void:
	_is_authenticating = true
	%ButtonsContainer.visible = false
	%LoadingContainer.visible = true
	%StatusLabel.text = status
	%ErrorLabel.text = ""


func _show_error(message: String) -> void:
	_show_buttons()
	%ErrorLabel.text = message


func _navigate_to_lobby() -> void:
	G.screens.client_open_screen(
		ScreensMain.ScreenType.LOBBY
	)


# --- Button handlers ---


func _on_steam_pressed() -> void:
	_start_login(AuthClient.Provider.STEAM)


func _on_epic_pressed() -> void:
	_start_login(AuthClient.Provider.EPIC)


func _on_google_pressed() -> void:
	_start_login(AuthClient.Provider.GOOGLE)


func _on_apple_pressed() -> void:
	_start_login(AuthClient.Provider.APPLE)


func _on_discord_pressed() -> void:
	_start_login(AuthClient.Provider.DISCORD)


func _on_twitch_pressed() -> void:
	_start_login(AuthClient.Provider.TWITCH)


func _on_anonymous_pressed() -> void:
	_start_login(AuthClient.Provider.ANONYMOUS)


func _start_login(provider: AuthClient.Provider) -> void:
	if _is_authenticating:
		return

	_show_loading("Signing in...")

	G.auth_client.auth_completed.connect(
		_on_login_completed,
		CONNECT_ONE_SHOT,
	)
	G.auth_client.auth_status_changed.connect(
		_on_status_changed,
	)
	G.auth_client.login_with_provider(provider)


func _on_login_completed(
	success: bool,
	error: String,
) -> void:
	_disconnect_status_signal()
	if success:
		_navigate_to_lobby()
	else:
		_show_error(error)


func _on_auto_refresh_completed(
	success: bool,
	_error: String,
) -> void:
	if success:
		_navigate_to_lobby()
	else:
		# Refresh failed. Show login buttons.
		G.auth_token_store.clear_tokens()
		_show_buttons()


func _on_status_changed(status: String) -> void:
	%StatusLabel.text = status


func _disconnect_signals() -> void:
	_disconnect_status_signal()
	if G.auth_client.auth_completed.is_connected(
		_on_login_completed
	):
		G.auth_client.auth_completed.disconnect(
			_on_login_completed
		)
	if G.auth_client.auth_completed.is_connected(
		_on_auto_refresh_completed
	):
		G.auth_client.auth_completed.disconnect(
			_on_auto_refresh_completed
		)


func _disconnect_status_signal() -> void:
	if G.auth_client.auth_status_changed.is_connected(
		_on_status_changed
	):
		G.auth_client.auth_status_changed.disconnect(
			_on_status_changed
		)
