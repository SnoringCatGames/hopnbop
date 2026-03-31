class_name AuthScreen
extends Screen
## Authentication screen with provider login
## buttons. Supports keyboard/controller navigation
## via ScreenFocusNavigator.
##
## On platforms with implied auth (Steam, Epic),
## this screen auto-logs-in without showing any
## buttons. On web and desktop, it shows Google,
## Facebook, and anonymous options.

@export_group("Provider Icons")
@export var icon_google: Texture2D
@export var icon_facebook: Texture2D

var _is_authenticating := false
var _navigator := ScreenFocusNavigator.new()


func _enter_tree() -> void:
	super._enter_tree()
	G.auth_screen = self


func on_open() -> void:
	super.on_open()

	%StatusLabel.text = ""
	%ErrorLabel.text = ""
	_show_buttons()

	# In preview mode, force secondary clients to
	# use anonymous login so each gets a unique
	# player identity for matchmaking. Clear any
	# cached tokens first so they start fresh.
	if _should_force_anonymous():
		G.auth_token_store.clear_tokens()
		G.profile_image_cache.clear()
		G.friends_notification_poller.reset()
		G.friends_api_client.cached_friends.clear()
		G.friends_api_client\
			.cached_sent_requests.clear()
		G.friends_api_client\
			.cached_incoming_requests.clear()
		G.friends_api_client\
			.cached_online_ids.clear()
		G.party_manager.current_party.clear()
		G.party_manager.pending_invites.clear()
		G.client_session.clear_latest_state()
		_start_login(
			AuthClient.Provider.ANONYMOUS)
		return

	# Anonymous players have a local-only identity.
	# No network call is needed to enter the lobby.
	if G.auth_token_store.is_anonymous_ready():
		_navigate_to_lobby()
		return

	# Check cached token.
	if G.auth_token_store.is_token_valid():
		_navigate_to_lobby()
		return

	# Try auto-refresh.
	if G.auth_token_store.needs_refresh():
		_show_loading(tr("AUTH.RESUMING_SESSION"))
		G.auth_client.auth_completed.connect(
			_on_auto_refresh_completed,
			CONNECT_ONE_SHOT,
		)
		G.auth_client.refresh_token()
		return

	# On platforms with implied auth, auto-login.
	var platform_provider := (
		AuthClient.get_platform_provider()
	)
	if platform_provider >= 0:
		_start_login(
			platform_provider
			as AuthClient.Provider)
		return

	_build_focusable_list()
	_navigator.prime()


func on_close() -> void:
	super.on_close()
	_disconnect_signals()


func _process(_delta: float) -> void:
	if (not visible
			or not %ButtonsContainer.visible):
		return

	if _navigator.poll(_delta):
		_activate_focused()


func _build_focusable_list() -> void:
	var items: Array[Control] = []
	if %GoogleButton.visible:
		items.append(%GoogleButton)
	if %FacebookButton.visible:
		items.append(%FacebookButton)
	if %AnonButton.visible:
		items.append(%AnonButton)
	_navigator.set_focusable_list(items)


func _activate_focused() -> void:
	var focused := _navigator.get_focused()
	if focused == null:
		return
	if focused == %GoogleButton:
		_on_google_pressed()
	elif focused == %FacebookButton:
		_on_facebook_pressed()
	elif focused == %AnonButton:
		_on_anonymous_pressed()


func _show_buttons() -> void:
	_is_authenticating = false
	%ButtonsContainer.visible = true
	%LoadingContainer.visible = false

	# Set button icons.
	_apply_button_icon(
		%GoogleButton, icon_google)
	_apply_button_icon(
		%FacebookButton, icon_facebook)
	_apply_button_icon(
		%AnonButton, G.settings.anonymous_texture)

	# Hide buttons not relevant to this platform.
	var has_platform := (
		AuthClient.get_platform_provider() >= 0
	)
	%OAuthRow.visible = not has_platform
	%AnonButton.visible = not has_platform


func _show_loading(status: String) -> void:
	_is_authenticating = true
	%ButtonsContainer.visible = false
	%LoadingContainer.visible = true
	%StatusLabel.text = status
	%ErrorLabel.text = ""


func _show_error(message: String) -> void:
	_show_buttons()
	%ErrorLabel.text = message
	_build_focusable_list()
	_navigator.prime()


func _navigate_to_lobby() -> void:
	G.screens.client_open_screen(
		ScreensMain.ScreenType.LOBBY,
	)


# --- Button handlers ---


func _on_google_pressed() -> void:
	_start_login(AuthClient.Provider.GOOGLE)


func _on_facebook_pressed() -> void:
	_start_login(AuthClient.Provider.FACEBOOK)


func _on_anonymous_pressed() -> void:
	_start_login(AuthClient.Provider.ANONYMOUS)


func _start_login(
	provider: AuthClient.Provider,
) -> void:
	if _is_authenticating:
		return

	_show_loading(tr("AUTH.SIGNING_IN"))

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
		G.profile_image_cache.clear()
		G.friends_notification_poller.reset()
		G.friends_api_client.cached_friends.clear()
		G.friends_api_client\
			.cached_sent_requests.clear()
		G.friends_api_client\
			.cached_incoming_requests.clear()
		G.friends_api_client\
			.cached_online_ids.clear()
		G.party_manager.current_party.clear()
		G.party_manager.pending_invites.clear()
		G.client_session.clear_latest_state()
		_show_buttons()
		_build_focusable_list()
		_navigator.prime()


func _on_status_changed(status: String) -> void:
	%StatusLabel.text = status


func _disconnect_signals() -> void:
	_disconnect_status_signal()
	if G.auth_client.auth_completed.is_connected(
		_on_login_completed,
	):
		G.auth_client.auth_completed.disconnect(
			_on_login_completed,
		)
	if G.auth_client.auth_completed.is_connected(
		_on_auto_refresh_completed,
	):
		G.auth_client.auth_completed.disconnect(
			_on_auto_refresh_completed,
		)


func _should_force_anonymous() -> bool:
	return (
		Netcode.is_preview
		and Netcode.is_client
		and Netcode.preview_client_number > 1
	)


func _disconnect_status_signal() -> void:
	if G.auth_client.auth_status_changed.is_connected(
		_on_status_changed,
	):
		G.auth_client.auth_status_changed.disconnect(
			_on_status_changed,
		)


func _apply_button_icon(
	button: Button,
	tex: Texture2D,
) -> void:
	if tex == null:
		return
	button.icon = tex
	button.expand_icon = true
