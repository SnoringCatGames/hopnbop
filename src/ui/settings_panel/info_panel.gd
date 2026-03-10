class_name InfoPanel
extends SidePanel
## Info sub-panel containing legal links and
## credits access.


@export var _back_row_scene: PackedScene
@export var _legal_link_row_scene: PackedScene


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
	terms_row.setup(
		tr("CONSENT.TERMS_OF_SERVICE"),
		"https://hopnbop.net/terms",
	)
	_row_container.add_child(terms_row)
	_connect_row_clicked(terms_row)

	var privacy_row: LegalLinkRow = (
		_legal_link_row_scene.instantiate()
	)
	privacy_row.setup(
		tr("CONSENT.PRIVACY_POLICY"),
		"https://hopnbop.net/privacy",
	)
	_row_container.add_child(privacy_row)
	_connect_row_clicked(privacy_row)

	var deletion_row: LegalLinkRow = (
		_legal_link_row_scene.instantiate()
	)
	deletion_row.setup(
		tr("SETTINGS.DATA_DELETION_POLICY"),
		"https://hopnbop.net/data-deletion",
	)
	_row_container.add_child(deletion_row)
	_connect_row_clicked(deletion_row)


func _add_credits_row() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	_row_container.add_child(spacer)

	var row: CreditsRow = (
		CreditsRow.new_row(
			tr("SETTINGS.CREDITS"), self))
	_row_container.add_child(row)
	_connect_row_clicked(row)
