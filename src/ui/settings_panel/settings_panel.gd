class_name SettingsPanel
extends SidePanel
## Settings sub-panel containing all gameplay,
## display, and audio toggles.


@export var _back_row_scene: PackedScene
@export var _toggle_row_scene: PackedScene
@export var _cheat_group_row_scene: PackedScene
@export var _sub_panel_trigger_row_scene: PackedScene
@export var _language_panel_scene: PackedScene

@export_group("Row Icons")
@export var icon_gore: Texture2D
@export var icon_critters: Texture2D
@export var icon_cheats: Texture2D
@export var icon_fullscreen: Texture2D
@export var icon_music: Texture2D
@export var icon_sfx: Texture2D
@export var icon_offline: Texture2D
@export var icon_language: Texture2D


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

	# Language trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.LANGUAGE"),
		_language_panel_scene,
		icon_language)

	# Gore toggle.
	_add_toggle_row(
		tr("SETTINGS.GORE"),
		&"is_gore_enabled",
		0, icon_gore)

	# Critters toggle.
	_add_toggle_row(
		tr("SETTINGS.CRITTERS"),
		&"are_critters_enabled",
		0, icon_critters)

	# Cheats group toggle.
	var cheats_row: CheatGroupRow = (
		_cheat_group_row_scene.instantiate())
	cheats_row.set_icon(icon_cheats)
	cheats_row.setup(
		tr("SETTINGS.CHEATS"),
		&"are_cheats_enabled")
	_row_container.add_child(cheats_row)
	_connect_row_clicked(cheats_row)

	# Cheat sub-rows.
	var cheat_sub_rows: Array[SettingsRow] = []

	var cheat_indent := 24
	cheat_sub_rows.append(
		_add_toggle_row(
			"jetpack",
			&"is_jetpack_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"bloodisthickerthanwater",
			&"is_bloodisthickerthanwater_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"lordoftheflies",
			&"is_lordoftheflies_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"pogostick",
			&"is_pogostick_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"bunniesinspace",
			&"is_bunniesinspace_enabled",
			cheat_indent))
	cheat_sub_rows.append(
		_add_toggle_row(
			"moregore",
			&"is_moregore_enabled",
			cheat_indent))

	cheats_row.set_sub_rows(
		cheat_sub_rows, self)

	# Full screen toggle.
	_add_toggle_row(
		tr("SETTINGS.FULL_SCREEN"),
		&"full_screen",
		0, icon_fullscreen)

	# Music toggle (inverted: checked = enabled).
	_add_toggle_row(
		tr("SETTINGS.MUSIC"), &"mute_music",
		0, icon_music, true)

	# SFX toggle (inverted: checked = enabled).
	_add_toggle_row(
		tr("SETTINGS.SFX"), &"mute_sfx",
		0, icon_sfx, true)

	# Offline mode toggle.
	_add_toggle_row(
		tr("SETTINGS.OFFLINE_MODE"),
		&"prefer_offline_mode",
		0, icon_offline)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)


func _add_sub_panel_trigger_row(
	display_name: String,
	panel_scene: PackedScene,
	icon: Texture2D = null,
) -> void:
	var row: SubPanelTriggerRow = (
		_sub_panel_trigger_row_scene.instantiate())
	if icon != null:
		row.set_icon(icon)
	row.setup(display_name, panel_scene, self)
	_row_container.add_child(row)
	_connect_row_clicked(row)


func _add_toggle_row(
	display_name: String,
	setting_key: StringName,
	indent_pixels := 0,
	icon: Texture2D = null,
	is_inverted := false,
) -> ToggleRow:
	var row: ToggleRow = (
		_toggle_row_scene.instantiate())
	if indent_pixels > 0:
		row.set_indent(indent_pixels)
	if icon != null:
		row.set_icon(icon)
	if is_inverted:
		row.set_inverted()
	row.setup(display_name, setting_key)
	_row_container.add_child(row)
	_connect_row_clicked(row)
	return row
