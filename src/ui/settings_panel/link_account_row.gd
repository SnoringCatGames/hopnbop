class_name LinkAccountRow
extends SettingsRow
## A row for linking or unlinking an OAuth provider.
## Shows provider name and linked status. Left/right
## triggers the link flow when not yet linked, or the
## unlink flow (with confirmation) when already linked.


var _provider: AuthClient.Provider
var _provider_name: String
var _is_linked := false
var _is_busy := false
var _icon_texture: Texture2D
var _icon_scale := -1
var _panel: SidePanel

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label
@onready var _status_label: Label = %StatusLabel


## Set an icon to display before the label. Call
## before add_child().
func set_icon(
	tex: Texture2D,
	scale: int = -1,
) -> void:
	_icon_texture = tex
	_icon_scale = scale


func setup(
	provider: AuthClient.Provider,
	display_name: String,
	is_linked: bool,
	panel: SidePanel,
) -> void:
	_provider = provider
	_provider_name = display_name
	_is_linked = is_linked
	_panel = panel


func _ready() -> void:
	super()
	_label.text = _provider_name
	_apply_icon(_icon, _icon_texture, _icon_scale)
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
		_status_label.text = tr("LINK.LOGGING_IN")
		G.auth_client.auth_completed.connect(
			_on_login_completed, CONNECT_ONE_SHOT
		)
		G.auth_client.login_with_provider(_provider)
	else:
		_status_label.text = tr("LINK.LINKING")
		G.auth_client.link_completed.connect(
			_on_link_completed, CONNECT_ONE_SHOT
		)
		G.auth_client.link_provider(_provider)


func _try_unlink() -> void:
	if not is_instance_valid(_panel):
		return

	_panel.open_confirm_dialog(
		tr("CONFIRM.UNLINK_ACCOUNT")
			% _provider_name,
		tr("LINK.UNLINK"),
		_do_unlink,
		tr("CONFIRM.CANCEL"),
	)


func _do_unlink() -> void:
	_is_busy = true
	_status_label.text = tr("LINK.UNLINKING")

	G.auth_client.unlink_completed.connect(
		_on_unlink_completed, CONNECT_ONE_SHOT
	)
	G.auth_client.unlink_provider(_provider)


func _on_login_completed(
	success: bool,
	error: String,
) -> void:
	G.log.print(
		"[LinkAccountRow] Login completed for %s:"
		% _provider_name
		+ " success=%s error='%s'"
		% [success, error]
	)
	if success:
		_is_busy = false
		if (
			is_instance_valid(_panel)
			and is_instance_valid(_panel.manager)
		):
			_panel.manager.close_all()
		return

	_is_busy = false
	push_warning(
		"Login failed for %s: %s"
		% [_provider_name, error]
	)
	_update_status()


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
	if success:
		_is_busy = false
		_is_linked = true
		if (
			is_instance_valid(_panel)
			and is_instance_valid(_panel.manager)
		):
			_panel.manager.close_all()
		return

	if error == "PROVIDER_CONFLICT":
		# Keep _is_busy true while the dialog is shown.
		_offer_merge()
		return

	_is_busy = false
	push_warning(
		"Link failed for %s: %s"
		% [_provider_name, error]
	)
	_update_status()


func _offer_merge() -> void:
	if not is_instance_valid(_panel):
		_is_busy = false
		_update_status()
		return
	_panel.open_confirm_dialog(
		tr("CONFIRM.MERGE_ACCOUNT") % _provider_name,
		tr("LINK.MERGE"),
		_do_merge,
		tr("CONFIRM.CANCEL"),
		_on_merge_cancelled,
	)


func _do_merge() -> void:
	_status_label.text = tr("LINK.MERGING")
	G.auth_client.merge_completed.connect(
		_on_merge_completed, CONNECT_ONE_SHOT
	)
	G.auth_client.confirm_merge()


func _on_merge_cancelled() -> void:
	_is_busy = false
	G.auth_client.cancel_merge()
	_update_status()


func _on_merge_completed(
	success: bool,
	_error: String,
	_provider_str: String,
) -> void:
	_is_busy = false
	if success:
		_is_linked = true
		if (
			is_instance_valid(_panel)
			and is_instance_valid(_panel.manager)
		):
			_panel.manager.close_all()
		return
	_update_status()


func _on_unlink_completed(
	success: bool,
	_error: String,
	_provider_str: String,
) -> void:
	_is_busy = false
	if success:
		_is_linked = false
		if (
			is_instance_valid(_panel)
			and is_instance_valid(_panel.manager)
		):
			_panel.manager.close_all()
		return
	_update_status()


func _update_status() -> void:
	if _is_linked:
		_status_label.text = tr("LINK.LINKED")
		_status_label.modulate = Color(0.6, 1.0, 0.6)
	elif G.auth_token_store.is_anonymous:
		_status_label.text = tr("LINK.LOG_IN")
		_status_label.modulate = Color.WHITE
	else:
		_status_label.text = tr("LINK.LINK")
		_status_label.modulate = Color.WHITE
