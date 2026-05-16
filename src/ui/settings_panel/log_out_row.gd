class_name LogOutRow
extends MenuRow
## A row that logs the player out via a
## ConfirmOverlay modal dialog.


var _panel: SidePanel
var _is_busy := false
var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label


## Set an icon to display before the label. Call
## before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


func setup(panel: SidePanel) -> void:
	_panel = panel


func _ready() -> void:
	super()
	_label.text = tr("SETTINGS.LOG_OUT")
	_apply_icon(_icon, _icon_texture)


func on_trigger() -> void:
	_activate()


func _activate() -> void:
	if _is_busy:
		return
	if not is_instance_valid(_panel):
		return

	_panel.open_confirm_dialog(
		tr("CONFIRM.LOG_OUT"),
		tr("SETTINGS.LOG_OUT"),
		_do_logout,
		tr("CONFIRM.CANCEL"),
	)


func _do_logout() -> void:
	_is_busy = true

	if (is_instance_valid(_panel)
			and is_instance_valid(_panel.manager)):
		_panel.manager.close_all()

	G.local_settings.clear_user_state()
	Platform.token_store.clear_tokens()
	G.profile_image_cache.clear()
	G.friends_notification_poller.stop_polling()
	G.friends_notification_poller.reset()
	Platform.friends.cached_friends.clear()
	Platform.friends.cached_sent_requests.clear()
	Platform.friends.cached_incoming_requests\
		.clear()
	Platform.presence.cached_online_ids.clear()
	G.party_manager.reset()
	G.client_session.clear_latest_state()
	# Tear down the live lobby/game level too, otherwise
	# the next user inherits the previous user's spawned
	# bunnies (Profile-image / display-name attributes are
	# captured into the lobby player nodes at spawn, so
	# clearing client_session is not enough on its own).
	if is_instance_valid(G.game_panel):
		G.game_panel.client_clear_all_levels()

	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.LOGGED_OUT"),
			ToastOverlay.Type.INFO,
		)

	G.screens.client_open_screen(
		ScreensMain.ScreenType.CONSENT,
	)
