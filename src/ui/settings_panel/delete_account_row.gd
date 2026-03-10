class_name DeleteAccountRow
extends SettingsRow
## A row that triggers account deletion via a
## ConfirmOverlay modal dialog.


@export var _confirm_overlay_scene: PackedScene

var _page: SidePanelPage
var _device_config: DeviceConfig
var _is_busy := false

@onready var _label: Label = %Label


func setup(
	page: SidePanelPage,
	device_config: DeviceConfig,
) -> void:
	_page = page
	_device_config = device_config


func _ready() -> void:
	super()
	_label.text = tr("SETTINGS.DELETE_ACCOUNT")


func on_left() -> void:
	_activate()


func on_right() -> void:
	_activate()


func _activate() -> void:
	if _is_busy:
		return

	_page.is_input_active = false

	var dialog: ConfirmOverlay = (
		_confirm_overlay_scene.instantiate())
	dialog.tree_exiting.connect(
		func() -> void:
			if is_instance_valid(_page):
				_page.is_input_active = true)
	get_tree().root.add_child(dialog)
	dialog.open(
		tr("CONFIRM.DELETE_ACCOUNT"),
		tr("CONFIRM.DELETE"),
		_do_delete,
		tr("CONFIRM.CANCEL"),
		func() -> void: pass,
		_device_config,
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

	if (is_instance_valid(_page)
			and is_instance_valid(_page.manager)):
		_page.manager.close_all()

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
