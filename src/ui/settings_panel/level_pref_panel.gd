class_name LevelPrefPanel
extends SidePanel
## Level preferences sub-panel. Shows one row per
## level with exclude/include/prefer tri-toggle.


@export var _back_row_scene: PackedScene
@export var _level_pref_row_scene: PackedScene

var _level_pref_rows: Array[LevelPrefRow] = []


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

	# Load persisted level preferences.
	var saved_prefs: LevelPreferences = (
		G.local_settings.load_level_preferences())

	# Level preference rows.
	for level_info: LevelInfo in (
			G.level_registry._levels):
		var initial_state := (
			LevelPrefRow.LevelPrefState.INCLUDED)
		if saved_prefs != null:
			if (level_info.id
					== saved_prefs.preferred_level):
				initial_state = (
					LevelPrefRow.LevelPrefState
						.PREFERRED)
			elif (level_info.id
					in saved_prefs.exclusion_list):
				initial_state = (
					LevelPrefRow.LevelPrefState
						.EXCLUDED)

		var level_row: LevelPrefRow = (
			_level_pref_row_scene.instantiate())
		level_row.setup(
			level_info.id,
			level_info.display_name,
			self,
			initial_state,
			level_info.thumbnail)
		_row_container.add_child(level_row)
		_connect_row_clicked(level_row)
		_level_pref_rows.append(level_row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)


## Enforce heart exclusivity: only one level can
## have PREFERRED state at a time.
func on_level_preferred(
	preferred_row: LevelPrefRow,
) -> void:
	for row in _level_pref_rows:
		if (row != preferred_row
				and row.get_state()
				== LevelPrefRow.LevelPrefState
					.PREFERRED):
			row.set_state(
				LevelPrefRow.LevelPrefState
					.INCLUDED)


func save_level_preferences() -> void:
	var prefs := LevelPreferences.new()
	for row in _level_pref_rows:
		match row.get_state():
			LevelPrefRow.LevelPrefState.EXCLUDED:
				prefs.exclude_level(
					row.get_level_id())
			LevelPrefRow.LevelPrefState.INCLUDED:
				prefs.include_level(
					row.get_level_id())
			LevelPrefRow.LevelPrefState.PREFERRED:
				prefs.set_preferred(
					row.get_level_id())
	G.local_settings.save_level_preferences(prefs)
