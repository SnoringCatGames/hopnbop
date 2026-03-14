class_name LogOutRow
extends SettingsRow
## A row that logs the player out via a
## ConfirmOverlay modal dialog.


@export var _confirm_overlay_scene: PackedScene

var _panel: SidePanel
var _device_config: DeviceConfig
var _is_busy := false
var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label


## Set an icon to display before the label. Call
## before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


func setup(
	panel: SidePanel,
	device_config: DeviceConfig,
) -> void:
	_panel = panel
	_device_config = device_config


func _ready() -> void:
	super()
	_label.text = tr("SETTINGS.LOG_OUT")
	if _icon_texture != null:
		_icon.texture = _icon_texture
		_icon.custom_minimum_size = (
			_icon_texture.get_size()
			* G.settings.icon_scale)
		_icon.show()
	else:
		_icon.hide()


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

	G.local_settings.clear_user_state()
	G.auth_token_store.clear_tokens()

	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.LOGGED_OUT"),
			ToastOverlay.Type.INFO,
		)

	G.screens.client_open_screen(
		ScreensMain.ScreenType.CONSENT,
	)
