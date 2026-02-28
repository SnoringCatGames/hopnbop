class_name CheatGroupRow
extends ToggleRow
## Toggle for are_cheats_enabled that shows/hides
## nested cheat sub-rows.


var _sub_rows: Array[SettingsRow] = []
var _panel: SettingsPanel


func set_sub_rows(
	sub_rows: Array[SettingsRow],
	panel: SettingsPanel,
) -> void:
	_sub_rows = sub_rows
	_panel = panel
	_update_sub_row_visibility()


func _toggle() -> void:
	super._toggle()
	_update_sub_row_visibility()
	# Rebuild the panel's row list to include/
	# exclude sub-rows from navigation.
	_panel.rebuild_row_list()


func _update_sub_row_visibility() -> void:
	for row in _sub_rows:
		row.visible = _value
