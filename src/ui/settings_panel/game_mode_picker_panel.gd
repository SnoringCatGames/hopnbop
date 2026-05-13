class_name GameModePickerPanel
extends SidePanel
## Sub-panel for selecting the active matchmaker game mode
## (Stage 4.7 solo path). Renders one ActionRow per server-
## known mode (from `BackendApiClient.server_matchmaker_modes`,
## sourced from game.yaml `matchmaker_rules.modes` via
## `version_check`). Tapping a row persists the choice to
## `LocalSettings.set_selected_game_mode` and refreshes the
## panel so the checkmark moves.
##
## Hidden from the main menu when no modes are declared (single-
## mode game; `server_matchmaker_modes.is_empty()`).
##
## Party flow (Stage 5.7) is separate: in a party, the leader's
## choice wins for everyone in that party, and the picker is
## opened from `PartyLobbyPanel` rather than the main menu.


@export var _back_row_scene: PackedScene
@export var _selected_icon: Texture2D


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
	back_spacer.custom_minimum_size = Vector2(0, 20)
	_row_container.add_child(back_spacer)

	# Description label.
	var header := Label.new()
	header.text = tr("GAME_MODE.PICKER_HEADER")
	header.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_color_override(
		"font_color", Color(1, 1, 1, 0.7))
	_row_container.add_child(header)

	var header_spacer := Control.new()
	header_spacer.custom_minimum_size = Vector2(0, 12)
	_row_container.add_child(header_spacer)

	_build_mode_rows()

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(bottom_spacer)


## Refreshes the rendered rows from the current server modes
## list and the current device pick. Called on first build and
## after every selection so the checkmark moves.
func _build_mode_rows() -> void:
	var modes: Array = []
	if is_instance_valid(G.backend_api_client):
		modes = G.backend_api_client.server_matchmaker_modes
	var selected_id := ""
	if is_instance_valid(G.local_settings):
		selected_id = G.local_settings.get_selected_game_mode()
	# Empty selection falls back to the server's default-flagged
	# entry so the checkmark visibly highlights *something* on
	# first open. The matchmaker resolves the same way.
	if selected_id.is_empty():
		for m in modes:
			if (m is Dictionary
					and bool(m.get("is_default", false))):
				selected_id = str(m.get("id", ""))
				break

	if modes.is_empty():
		var empty := Label.new()
		empty.text = tr("GAME_MODE.EMPTY")
		empty.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER)
		empty.add_theme_color_override(
			"font_color", Color(1, 1, 1, 0.55))
		_row_container.add_child(empty)
		return

	for mode in modes:
		if not (mode is Dictionary):
			continue
		var mode_id := str(mode.get("id", ""))
		if mode_id.is_empty():
			continue
		var display_key := str(
			mode.get("display_name_key", ""))
		var label := (
			tr(display_key) if not display_key.is_empty()
			else mode_id.capitalize())
		var row := ActionRow.new()
		var description_key := str(
			mode.get("description_key", ""))
		if not description_key.is_empty():
			var subtitle := tr(description_key)
			if not subtitle.is_empty():
				label = "%s\n%s" % [label, subtitle]
		var is_selected := mode_id == selected_id
		row.setup_label(
			label,
			_selected_icon if is_selected else null)
		row.setup_actions(
			_make_select_callable(mode_id),
			_make_select_callable(mode_id))
		_row_container.add_child(row)
		_connect_row_clicked(row)


## Returns a parameterless Callable that selects `mode_id`. Used
## by the ActionRow primary/secondary action slots which both
## expect zero-arg Callables. Stage 4.7.
func _make_select_callable(mode_id: String) -> Callable:
	return func() -> void: _on_mode_selected(mode_id)


func _on_mode_selected(mode_id: String) -> void:
	if not is_instance_valid(G.local_settings):
		return
	if G.local_settings.get_selected_game_mode() == mode_id:
		return
	G.local_settings.set_selected_game_mode(mode_id)
	# Rebuild rows so the checkmark moves to the newly-selected
	# entry. _clear_rows preserves the back row + header so the
	# navigation focus doesn't reset to the top of the panel.
	_rebuild()


func _rebuild() -> void:
	for child in _row_container.get_children():
		child.queue_free()
	build_ui()
	rebuild_row_list()
