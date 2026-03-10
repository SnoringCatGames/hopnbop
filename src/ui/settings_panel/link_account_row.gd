class_name LinkAccountRow
extends SettingsRow
## A row for linking or unlinking an OAuth provider.
## Shows provider name and linked status. Left/right
## triggers the link flow when not yet linked, or the
## unlink flow (with confirmation) when already linked.


@export var _confirm_overlay_scene: PackedScene

var _provider: AuthClient.Provider
var _provider_name: String
var _is_linked := false
var _is_busy := false
var _icon_texture: Texture2D
var _page: SidePanelPage

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label
@onready var _status_label: Label = %StatusLabel


## Set an icon to display before the label. Call
## before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


func setup(
	provider: AuthClient.Provider,
	display_name: String,
	is_linked: bool,
	page: SidePanelPage,
) -> void:
	_provider = provider
	_provider_name = display_name
	_is_linked = is_linked
	_page = page


func _ready() -> void:
	super()
	_label.text = _provider_name
	if _icon_texture != null:
		_icon.texture = _icon_texture
		_icon.custom_minimum_size = (
			_icon_texture.get_size())
		_icon.show()
	else:
		_icon.hide()
	_update_status()


func on_left() -> void:
	_toggle()


func on_right() -> void:
	_toggle()


func _toggle() -> void:
	if _is_busy:
		return

	if _is_linked:
		_try_unlink()
	else:
		_try_link()


func _try_link() -> void:
	G.log.print(
		"[LinkAccountRow] Starting link for %s"
		% _provider_name
	)
	_is_busy = true
	if G.auth_token_store.is_anonymous:
		_status_label.text = tr("LINK.CONNECTING")
	else:
		_status_label.text = tr("LINK.LINKING")

	G.auth_client.link_completed.connect(
		_on_link_completed, CONNECT_ONE_SHOT
	)
	G.auth_client.link_provider(_provider)


func _try_unlink() -> void:
	if not is_instance_valid(_page):
		return

	_page.is_input_active = false

	var device_config: DeviceConfig = null
	if is_instance_valid(_page.manager):
		device_config = (
			_page.manager.get_device_config())

	var dialog: ConfirmOverlay = (
		_confirm_overlay_scene.instantiate())
	dialog.tree_exiting.connect(
		func() -> void:
			if is_instance_valid(_page):
				_page.is_input_active = true)
	get_tree().root.add_child(dialog)
	dialog.open(
		tr("CONFIRM.UNLINK_ACCOUNT")
			% _provider_name,
		tr("LINK.UNLINK"),
		_do_unlink,
		tr("CONFIRM.CANCEL"),
		func() -> void: pass,
		device_config,
	)


func _do_unlink() -> void:
	_is_busy = true
	_status_label.text = tr("LINK.UNLINKING")

	G.auth_client.unlink_completed.connect(
		_on_unlink_completed, CONNECT_ONE_SHOT
	)
	G.auth_client.unlink_provider(_provider)


func _on_link_completed(
	success: bool,
	error: String,
	_provider_str: String,
) -> void:
	G.log.print(
		"[LinkAccountRow] Link completed for %s:"
		% _provider_name
		+ " success=%s error='%s'"
		% [success, error]
	)
	_is_busy = false
	if success:
		_is_linked = true
	else:
		push_warning(
			"Link failed for %s: %s"
			% [_provider_name, error]
		)
	_update_status()


func _on_unlink_completed(
	success: bool,
	_error: String,
	_provider_str: String,
) -> void:
	_is_busy = false
	if success:
		_is_linked = false
	_update_status()


func _update_status() -> void:
	if _is_linked:
		_status_label.text = tr("LINK.LINKED")
		_status_label.modulate = Color(0.6, 1.0, 0.6)
	elif G.auth_token_store.is_anonymous:
		_status_label.text = tr("LINK.CONNECT")
		_status_label.modulate = Color.WHITE
	else:
		_status_label.text = tr("LINK.LINK")
		_status_label.modulate = Color.WHITE
