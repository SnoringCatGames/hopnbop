class_name InfoPanel
extends SidePanel
## Info sub-panel containing legal links and
## credits access.


@export var _back_row_scene: PackedScene
@export var _legal_link_row_scene: PackedScene

@export_group("Row Icons")
@export var icon_terms: Texture2D
@export var icon_privacy: Texture2D
@export var icon_data_deletion: Texture2D
@export var icon_discord: Texture2D
@export var icon_credits: Texture2D


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

	# Legal links.
	_add_legal_section()

	# Credits row.
	_add_credits_row()

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)


func _add_legal_section() -> void:
	var terms_row: LegalLinkRow = (
		_legal_link_row_scene.instantiate()
	)
	if icon_terms != null:
		terms_row.set_icon(icon_terms)
	terms_row.setup(
		tr("CONSENT.TERMS_OF_SERVICE"),
		"https://hopnbop.net/terms",
	)
	_row_container.add_child(terms_row)
	_connect_row_clicked(terms_row)

	var privacy_row: LegalLinkRow = (
		_legal_link_row_scene.instantiate()
	)
	if icon_privacy != null:
		privacy_row.set_icon(icon_privacy)
	privacy_row.setup(
		tr("CONSENT.PRIVACY_POLICY"),
		"https://hopnbop.net/privacy",
	)
	_row_container.add_child(privacy_row)
	_connect_row_clicked(privacy_row)

	var deletion_row: LegalLinkRow = (
		_legal_link_row_scene.instantiate()
	)
	if icon_data_deletion != null:
		deletion_row.set_icon(icon_data_deletion)
	deletion_row.setup(
		tr("SETTINGS.DATA_DELETION_POLICY"),
		"https://hopnbop.net/data-deletion",
	)
	_row_container.add_child(deletion_row)
	_connect_row_clicked(deletion_row)

	# Spacer before community link.
	var discord_spacer := Control.new()
	discord_spacer.custom_minimum_size = (
		Vector2(0, 20))
	_row_container.add_child(discord_spacer)

	var discord_row: LegalLinkRow = (
		_legal_link_row_scene.instantiate()
	)
	if icon_discord != null:
		discord_row.set_icon(icon_discord, 1)
	discord_row.setup(
		"Discord",
		G.settings.discord_url,
	)
	_row_container.add_child(discord_row)
	_connect_row_clicked(discord_row)


func _add_credits_row() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	_row_container.add_child(spacer)

	var row: CreditsRow = (
		CreditsRow.new_row(
			tr("SETTINGS.CREDITS"),
			self,
			icon_credits,
		)
	)
	_row_container.add_child(row)
	_connect_row_clicked(row)
