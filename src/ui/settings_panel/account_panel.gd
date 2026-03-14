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


func _add_link_account_rows() -> void:
	# Only show linking when authenticated.
	if not G.auth_token_store.is_token_valid():
		return

	var linked: Array[String] = (
		G.auth_token_store.linked_providers
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
	if not G.auth_token_store.is_token_valid():
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
	if not G.auth_token_store.is_token_valid():
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
	if not G.auth_token_store.is_token_valid():
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
