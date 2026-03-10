class_name SettingsPage
extends SidePanelPage
## Top-level settings page. Contains only a close
## row and trigger rows for sub-panels.


@export var _close_row_scene: PackedScene
@export var _sub_panel_trigger_row_scene: PackedScene
@export var _preferences_page_scene: PackedScene
@export var _level_pref_page_scene: PackedScene
@export var _language_page_scene: PackedScene
@export var _account_page_scene: PackedScene
@export var _info_page_scene: PackedScene


func build_ui() -> void:
	# Top padding.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(top_spacer)

	# Close row.
	var close_row: CloseRow = (
		_close_row_scene.instantiate())
	close_row.setup(self)
	_row_container.add_child(close_row)
	_connect_row_clicked(close_row)

	# Spacer below close button.
	var close_spacer := Control.new()
	close_spacer.custom_minimum_size = (
		Vector2(0, 20))
	_row_container.add_child(close_spacer)

	# Settings trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.SETTINGS"),
		_preferences_page_scene)

	# Levels trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.LEVELS"),
		_level_pref_page_scene)

	# Language trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.LANGUAGE"),
		_language_page_scene)

	# Account trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.ACCOUNT"),
		_account_page_scene)

	# Info trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.INFO"),
		_info_page_scene)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)


func _add_sub_panel_trigger_row(
	display_name: String,
	page_scene: PackedScene,
) -> void:
	var row: SubPanelTriggerRow = (
		_sub_panel_trigger_row_scene.instantiate())
	row.setup(display_name, page_scene, self)
	_row_container.add_child(row)
	_connect_row_clicked(row)
