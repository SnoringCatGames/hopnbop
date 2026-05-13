class_name AccountPanel
extends SidePanel
## Account sub-panel containing OAuth linking,
## delete account, export data, and log out rows.


@export var _back_row_scene: PackedScene
@export var _link_account_row_scene: PackedScene
@export var _delete_account_row_scene: PackedScene
@export var _export_data_row_scene: PackedScene
@export var _log_out_row_scene: PackedScene

@export_group("Provider Icons")
@export var icon_google: Texture2D
@export var icon_facebook: Texture2D

@export_group("Row Icons")
@export var icon_delete_account: Texture2D
@export var icon_export_data: Texture2D
@export var icon_logout: Texture2D


func build_ui() -> void:
	# Top padding.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(top_spacer)

	# Back row.
	var back_row: BackRow = (
		_back_row_scene.instantiate())
	back_row.setup(self)
	_row_container.add_child(back_row)
	_connect_row_clicked(back_row)

	# Spacer below back button.
	var back_spacer := Control.new()
	back_spacer.custom_minimum_size = (
		Vector2(0, 20))
	_row_container.add_child(back_spacer)

	# Profile header (non-focusable).
	_add_profile_header()

	# Account linking section.
	_add_link_account_rows()

	# Delete account row.
	_add_delete_account_row()

	# Export data row.
	_add_export_data_row()

	# Log out row.
	_add_log_out_row()

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)


func _add_profile_header() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(
		"separation", 12)

	var profile_image := ProfileImageDisplay.new()
	profile_image.image_size = 48
	row.add_child(profile_image)

	var store: PlatformAuthTokenStore = Platform.token_store
	if store.is_anonymous:
		# ProfileImageDisplay defaults to the
		# anonymous icon. No extra setup needed.
		pass
	else:
		var url := store.profile_image_url
		if not url.is_empty():
			profile_image.set_from_url(
				store.player_id.hash(),
				url,
				Color.GRAY,
			)

	var name_label := Label.new()
	if store.is_anonymous:
		name_label.text = tr("ACCOUNT.ANONYMOUS")
	else:
		name_label.text = store.display_name
	row.add_child(name_label)

	_row_container.add_child(row)

	# Spacer below profile header.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_row_container.add_child(spacer)


func _add_link_account_rows() -> void:
	# Show sign-in options for anonymous users too,
	# so they can upgrade to a persistent account.
	if (
		not Platform.token_store.is_token_valid()
		and not Platform.token_store.is_anonymous
	):
		return

	var linked: Array[String] = (
		Platform.token_store.linked_providers
	)

	# Google link row.
	var google_row: LinkAccountRow = (
		_link_account_row_scene.instantiate()
	)
	if icon_google != null:
		google_row.set_icon(icon_google, 1)
	google_row.setup(
		AuthClient.Provider.GOOGLE,
		"Google",
		"google" in linked,
		self,
	)
	_row_container.add_child(google_row)
	_connect_row_clicked(google_row)

	# Facebook link row.
	var fb_row: LinkAccountRow = (
		_link_account_row_scene.instantiate()
	)
	if icon_facebook != null:
		fb_row.set_icon(icon_facebook, 1)
	fb_row.setup(
		AuthClient.Provider.FACEBOOK,
		"Facebook",
		"facebook" in linked,
		self,
	)
	_row_container.add_child(fb_row)
	_connect_row_clicked(fb_row)


func _add_delete_account_row() -> void:
	# Only show when authenticated.
	if not Platform.token_store.is_token_valid():
		return

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	_row_container.add_child(spacer)

	var row: DeleteAccountRow = (
		_delete_account_row_scene.instantiate()
	)
	if icon_delete_account != null:
		row.set_icon(icon_delete_account)
	row.setup(self)
	_row_container.add_child(row)
	_connect_row_clicked(row)


func _add_export_data_row() -> void:
	if not Platform.token_store.is_token_valid():
		return

	var row: ExportDataRow = (
		_export_data_row_scene.instantiate()
	)
	if icon_export_data != null:
		row.set_icon(icon_export_data)
	row.setup(self)
	_row_container.add_child(row)
	_connect_row_clicked(row)


func _add_log_out_row() -> void:
	if not Platform.token_store.is_token_valid():
		return
	if AuthClient.get_platform_provider() >= 0:
		return

	var row: LogOutRow = (
		_log_out_row_scene.instantiate()
	)
	if icon_logout != null:
		row.set_icon(icon_logout)
	row.setup(self)
	_row_container.add_child(row)
	_connect_row_clicked(row)
