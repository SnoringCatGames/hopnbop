class_name LogOutRow
extends SettingsRow
## A row that logs the player out via a
## ConfirmOverlay modal dialog.


const _ConfirmOverlayScene := preload(
	"res://src/ui/confirm_overlay/"
	+ "confirm_overlay.tscn")

var _panel: SettingsPanel
var _device_config: DeviceConfig
var _is_busy := false

@onready var _label: Label = %Label


func setup(
	panel: SettingsPanel,
	device_config: DeviceConfig,
) -> void:
	_panel = panel
	_device_config = device_config


func _ready() -> void:
	super()
	_label.text = "Log Out"


func on_left() -> void:
	_activate()


func on_right() -> void:
	_activate()


func _activate() -> void:
	if _is_busy:
		return

	_panel.is_input_blocked = true

	var dialog: ConfirmOverlay = (
		_ConfirmOverlayScene.instantiate())
	dialog.tree_exiting.connect(
		func() -> void:
			if is_instance_valid(_panel):
				_panel.is_input_blocked = false)
	get_tree().root.add_child(dialog)
	dialog.open(
		"Log out?",
		"Log Out",
		_do_logout,
		"Cancel",
		func() -> void: pass,
		_device_config,
	)


func _do_logout() -> void:
	_is_busy = true

	if is_instance_valid(_panel):
		_panel.close()

	G.auth_token_store.clear_tokens()

	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			"Logged out",
			ToastOverlay.Type.INFO,
		)

	G.screens.client_open_screen(
		ScreensMain.ScreenType.CONSENT,
	)
