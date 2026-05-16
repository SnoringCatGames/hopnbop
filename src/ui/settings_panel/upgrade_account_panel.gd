class_name UpgradeAccountPanel
extends SidePanel
## Anonymous-only entry point that explains the benefits of
## upgrading to a permanent account and exposes Google / Facebook
## upgrade actions. Authenticated callers are routed straight back
## (defensive — main menu only opens this panel for anonymous
## users). Stage 7.9.


@export var _back_row_scene: PackedScene
@export var _link_account_row_scene: PackedScene

@export_group("Provider Icons")
@export var icon_google: Texture2D
@export var icon_facebook: Texture2D


func build_ui() -> void:
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(top_spacer)

	var back_row: BackRow = _back_row_scene.instantiate()
	back_row.setup(self)
	_row_container.add_child(back_row)
	_connect_row_clicked(back_row)

	var back_spacer := Control.new()
	back_spacer.custom_minimum_size = Vector2(0, 20)
	_row_container.add_child(back_spacer)

	_add_header()
	_add_benefits_body()

	if Platform.token_store.is_anonymous:
		_add_link_account_rows()
		_add_maybe_later_row()

	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(bottom_spacer)


func _add_header() -> void:
	var header := Label.new()
	header.text = tr("UPGRADE.HEADER")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	_row_container.add_child(header)

	var header_spacer := Control.new()
	header_spacer.custom_minimum_size = Vector2(0, 12)
	_row_container.add_child(header_spacer)


func _add_benefits_body() -> void:
	var body := Label.new()
	body.text = tr("UPGRADE.BENEFITS_BODY")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row_container.add_child(body)

	var body_spacer := Control.new()
	body_spacer.custom_minimum_size = Vector2(0, 20)
	_row_container.add_child(body_spacer)


func _add_link_account_rows() -> void:
	# Linked providers are always empty for anonymous users; the
	# argument is required by setup() so we pass false.
	var google_row: LinkAccountRow = (
		_link_account_row_scene.instantiate())
	if icon_google != null:
		google_row.set_icon(icon_google, 1)
	google_row.setup(
		PlatformAuthApiClient.Provider.GOOGLE,
		"Google",
		false,
		self,
	)
	_row_container.add_child(google_row)
	_connect_row_clicked(google_row)

	var fb_row: LinkAccountRow = (
		_link_account_row_scene.instantiate())
	if icon_facebook != null:
		fb_row.set_icon(icon_facebook, 1)
	fb_row.setup(
		PlatformAuthApiClient.Provider.FACEBOOK,
		"Facebook",
		false,
		self,
	)
	_row_container.add_child(fb_row)
	_connect_row_clicked(fb_row)


func _add_maybe_later_row() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_row_container.add_child(spacer)

	var later_row := ActionRow.new()
	later_row.setup_action(_on_maybe_later_pressed)
	later_row.setup_label(tr("UPGRADE.MAYBE_LATER"))
	_row_container.add_child(later_row)
	_connect_row_clicked(later_row)


func _on_maybe_later_pressed() -> void:
	if not is_instance_valid(manager):
		return
	manager.pop_panel()
