class_name LogOutRow
extends SettingsRow
## A row that logs the player out via a
## ConfirmOverlay modal dialog.


@export var _confirm_overlay_scene: PackedScene

var _panel: SidePanel
var _device_config: DeviceConfig
var _is_busy := false

@onready var _label: Label = %Label


func setup(
	panel: SidePanel,
	device_config: DeviceConfig,
) -> void:
	_panel = panel
	_device_config = device_config


func _ready() -> void:
	super()
	_label.text = tr("SETTINGS.LOG_OUT")


func on_left() -> void:
	_activate()


func on_right() -> void:
	_activate()


func _activate() -> void:
	if _is_busy:
		return

	_panel.is_input_active = false

	var dialog: ConfirmOverlay = (
		_confirm_overlay_scene.instantiate())
	dialog.tree_exiting.connect(
		func() -> void:
			if is_instance_valid(_panel):
				_panel.is_input_active = true)
	get_tree().root.add_child(dialog)
	dialog.open(
		tr("CONFIRM.LOG_OUT"),
		tr("SETTINGS.LOG_OUT"),
		_do_logout,
		tr("CONFIRM.CANCEL"),
		func() -> void: pass,
		_device_config,
	)


func _do_logout() -> void:
	_is_busy = true

	if (is_instance_valid(_panel)
			and is_instance_valid(_panel.manager)):
		_panel.manager.close_all()

	G.auth_token_store.clear_tokens()

	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.LOGGED_OUT"),
			ToastOverlay.Type.INFO,
		)

	G.screens.client_open_screen(
		ScreensMain.ScreenType.CONSENT,
	)
