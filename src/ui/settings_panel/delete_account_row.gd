class_name DeleteAccountRow
extends SettingsRow
## A row that triggers account deletion via a
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
	_label.text = tr("SETTINGS.DELETE_ACCOUNT")
	_apply_icon(_icon, _icon_texture)


func on_left() -> void:
	_activate()


func on_right() -> void:
	_activate()


func _activate() -> void:
	if _is_busy:
		return
	if not is_instance_valid(_panel):
		return

	_panel.open_confirm_dialog(
		tr("CONFIRM.DELETE_ACCOUNT"),
		tr("CONFIRM.DELETE"),
		_do_delete,
		tr("CONFIRM.CANCEL"),
	)


func _do_delete() -> void:
	_is_busy = true

	G.auth_client.delete_completed.connect(
		_on_delete_completed, CONNECT_ONE_SHOT,
	)
	G.auth_client.delete_account()


func _on_delete_completed(
	success: bool,
	error: String,
) -> void:
	_is_busy = false

	if (is_instance_valid(_panel)
			and is_instance_valid(_panel.manager)):
		_panel.manager.close_all()

	if success:
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.ACCOUNT_DELETED"),
				ToastOverlay.Type.SUCCESS,
			)
		G.screens.client_open_screen(
			ScreensMain.ScreenType.CONSENT,
		)
	else:
		G.log.error(
			"Account deletion failed: %s"
			% error,
		)
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.DELETE_FAILED") % error,
				ToastOverlay.Type.ERROR,
			)
