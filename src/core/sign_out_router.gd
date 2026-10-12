class_name SignOutRouter
extends Node
## Sends the player to the auth screen after the platform SDK signs
## them out mid-session.
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
		_clear_signed_out_state()
	return screen_type


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


## Drops what the old session left behind, as the auth screen does
## when its boot-time refresh is rejected, and closes the menus and
## dialogs that would act on it.
func _clear_signed_out_state() -> void:
	if is_instance_valid(G.side_panel_layer):
		for child in G.side_panel_layer.get_children():
			if child is SidePanelManager:
				child.close_all()
	if is_instance_valid(G.confirm_layer):
		for child in G.confirm_layer.get_children():
			if child is ConfirmOverlay:
				child.queue_free()
	G.profile_image_cache.clear()
	G.friends_notification_poller.reset()
	G.party_manager.reset()
	if G.client_session != null:
		G.client_session.clear_latest_state()
	Platform.friends.cached_friends.clear()
	Platform.friends.cached_sent_requests.clear()
	Platform.friends.cached_incoming_requests.clear()
	Platform.presence.clear_cache()
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.SIGNED_OUT"),
			ToastOverlay.Type.ERROR,
		)
