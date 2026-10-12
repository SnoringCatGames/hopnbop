class_name SignOutRouter
extends Node
## Ends a signed-in session on this device: when the player logs out,
## when they delete their account, and when the platform SDK signs them
## out mid-session.
##
## PlatformAuthApiClient signs the player out on its own when Nakama
## rejects the stored refresh token (an expired or revoked session, a
## banned or deleted account), and emits signed_out. The player used
## to stay where they were, typically the lobby, with no session, so
## everything online failed. A fresh launch shows the auth screen in
## that state, and so does this:
## - In the lobby, or on a screen opened over it (leaderboard, stats,
##   credits, ...), the auth screen opens at once. The lobby is torn
##   down, as on log-out, so the next sign-in starts clean.
## - During a match, local or online, nothing is interrupted. Local
##   play needs no session, and an online match talks to its game
##   server, not to Nakama. Matchmaking already in progress is left to
##   finish or fail. The results screen still shows. After that, the
##   auth screen opens instead of the lobby, and instead of any new
##   online match (GamePanel asks is_sign_in_required).
## - On the splash, consent, or auth screens, the boot flow reaches the
##   auth screen by itself.
##
## Every way out clears what the old session left on this device the
## same way (clear_session_state), so the next sign-in, as anyone,
## starts clean: no friend caches or profile pictures, no party, and no
## friends poller or realtime notification socket still working for
## the old account. Only log-out and account deletion forget the
## player's consent. The SDK keeps it through a sign-out the player did
## not ask for.
##
## ScreensMain owns this node on clients and passes every screen switch
## through resolve_screen().


## True from the sign-out until the auth screen opens.
var is_sign_in_required := false


func _ready() -> void:
	(Platform.auth as PlatformAuthApiClient).signed_out.connect(
		_on_signed_out)


## Returns the screen to open when screen_type is requested. While
## sign-in is required, the lobby gives way to the auth screen.
## Opening the auth screen settles the requirement: it clears what the
## old session left behind and tells the player why they are there.
func resolve_screen(
	screen_type: ScreensMain.ScreenType,
) -> ScreensMain.ScreenType:
	if not is_sign_in_required:
		return screen_type
	if screen_type == ScreensMain.ScreenType.LOBBY:
		screen_type = ScreensMain.ScreenType.AUTH
	if screen_type == ScreensMain.ScreenType.AUTH:
		is_sign_in_required = false
		clear_session_state()
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.SIGNED_OUT"),
				ToastOverlay.Type.ERROR,
			)
	return screen_type


## Logs the player out because they asked to (Settings, Log Out).
## Forgets everything this device holds for them, their consent
## included, so whoever plays next starts at the consent screen.
func log_out() -> void:
	# Tell the platform we're going offline before dropping the token:
	# announce_offline needs a live session to write the row as. Without
	# it the player lingers on friends' lists until the runtime's
	# staleness window expires.
	await Platform.presence.announce_offline()
	Platform.token_store.clear_tokens()
	_forget_account(tr("TOAST.LOGGED_OUT"), ToastOverlay.Type.INFO)


## Finishes an account deletion that the platform SDK reports done. The
## SDK has already cleared the stored credentials, consent included.
func finish_account_deletion() -> void:
	_forget_account(
		tr("TOAST.ACCOUNT_DELETE_QUEUED"),
		ToastOverlay.Type.SUCCESS,
	)


## Drops what the old session left behind on this device, and closes
## the menus and dialogs that would act on it. Every sign-out runs it:
## log-out, account deletion, an automatic sign-out when the auth
## screen opens, and the auth screen's own boot-time rejection.
func clear_session_state() -> void:
	if is_instance_valid(G.side_panel_layer):
		for child in G.side_panel_layer.get_children():
			if child is SidePanelManager:
				child.close_all()
	if is_instance_valid(G.confirm_layer):
		for child in G.confirm_layer.get_children():
			if child is ConfirmOverlay:
				child.queue_free()
	G.profile_image_cache.clear()
	# Stopped until the next sign-in, which starts it again.
	G.friends_notification_poller.stop_polling()
	G.friends_notification_poller.reset()
	# The socket is authenticated as the old account, and would keep
	# delivering its notifications. The next provider sign-in opens one
	# for the new account.
	Platform.notification_socket.stop()
	G.party_manager.reset()
	if G.client_session != null:
		G.client_session.clear_latest_state()
	Platform.friends.cached_friends.clear()
	Platform.friends.cached_sent_requests.clear()
	Platform.friends.cached_incoming_requests.clear()
	# clear_cache() drops cached_online_friends too. Clearing only
	# cached_online_ids left the rich-presence map behind, so the next
	# user to sign in on this device inherited the previous user's
	# friends' presence text.
	Platform.presence.clear_cache()


func _on_signed_out(_error: String) -> void:
	if (
		is_instance_valid(G.screens)
		and G.screens.current_screen == ScreensMain.ScreenType.AUTH
	):
		return
	is_sign_in_required = true
	if G.is_lobby_active:
		# The lobby's bunnies carry the old account's name and picture.
		G.game_panel.client_clear_all_levels()
		G.screens.client_open_screen(ScreensMain.ScreenType.AUTH)


## Ends the session for good after a log-out or an account deletion and
## opens the consent screen.
func _forget_account(message: String, toast_type: ToastOverlay.Type) -> void:
	G.local_settings.clear_user_state()
	clear_session_state()
	# Tear down the live lobby or game level too, otherwise the next
	# user inherits the previous user's spawned bunnies. Their profile
	# images and display names are captured into the lobby player nodes
	# at spawn, so clearing client_session is not enough on its own.
	if is_instance_valid(G.game_panel):
		G.game_panel.client_clear_all_levels()
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(message, toast_type)
	if is_instance_valid(G.screens):
		G.screens.client_open_screen(ScreensMain.ScreenType.CONSENT)
