class_name LeaderboardPanel
extends CanvasLayer
## Full-screen overlay showing leaderboard and
## player stats. Follows the same CanvasLayer
## overlay pattern as SettingsPanel.


signal closed


enum Tab {
	LEADERBOARD,
	MY_STATS,
}

var _current_tab := Tab.LEADERBOARD
var _is_loading := false

@onready var _tab_label: Label = %TabLabel
@onready var _content_container: VBoxContainer = (
	%ContentContainer)
@onready var _status_label: Label = %StatusLabel
@onready var _close_hint: Label = %CloseHint


func _ready() -> void:
	(G.backend_api_client.leaderboard_received
		.connect(_on_leaderboard_received))
	(G.backend_api_client.player_stats_received
		.connect(_on_player_stats_received))
	(G.backend_api_client.request_failed
		.connect(_on_request_failed))

	_close_hint.text = "Press ESC to close"
	_show_tab(Tab.LEADERBOARD)


func close() -> void:
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")
	closed.emit()
	queue_free()


func _unhandled_input(
	event: InputEvent,
) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return

	if event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_switch_tab(-1)
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_switch_tab(1)


func _switch_tab(direction: int) -> void:
	if _is_loading:
		return
	var new_tab := wrapi(
		_current_tab + direction,
		0,
		Tab.size())
	if new_tab != _current_tab:
		_show_tab(new_tab as Tab)


func _show_tab(tab: Tab) -> void:
	_current_tab = tab
	_clear_content()

	match tab:
		Tab.LEADERBOARD:
			_tab_label.text = (
				"< Leaderboard >")
			_set_loading(true)
			(G.backend_api_client
				.fetch_leaderboard())
		Tab.MY_STATS:
			_tab_label.text = (
				"< My Stats >")
			_set_loading(true)
			var player_id := (
				G.auth_token_store
					.player_id)
			if player_id.is_empty():
				_set_loading(false)
				_status_label.text = (
					"Not logged in")
				_status_label.show()
				return
			(G.backend_api_client
				.fetch_player_stats(
					player_id))


func _on_leaderboard_received(
	data: Dictionary,
) -> void:
	_set_loading(false)
	if _current_tab != Tab.LEADERBOARD:
		return

	_clear_content()

	# Show player's own rank.
	var your_rank: int = data.get("your_rank", 0)
	var your_rating: int = data.get(
		"your_rating", 1500)
	if your_rank > 0:
		var header := Label.new()
		header.text = "Your rank: #%d (%d)" % [
			your_rank, your_rating]
		header.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER)
		_content_container.add_child(header)

		var sep := HSeparator.new()
		_content_container.add_child(sep)

	# Show leaderboard entries.
	var board: Array = data.get(
		"leaderboard", [])
	if board.is_empty():
		_status_label.text = "No players yet"
		_status_label.show()
		return

	for entry in board:
		_add_leaderboard_row(entry)


func _on_player_stats_received(
	data: Dictionary,
) -> void:
	_set_loading(false)
	if _current_tab != Tab.MY_STATS:
		return

	_clear_content()

	var player: Dictionary = data.get(
		"player", {})
	if player.is_empty():
		_status_label.text = "No data"
		_status_label.show()
		return

	# Profile summary.
	_add_stat_row(
		"Rating",
		str(player.get("rating", 1500)))
	_add_stat_row(
		"Rank",
		"#%d" % player.get("rank", 0))
	_add_stat_row(
		"Matches",
		str(player.get("matches_played", 0)))
	_add_stat_row(
		"Wins",
		str(player.get("wins", 0)))
	_add_stat_row(
		"Losses",
		str(player.get("losses", 0)))
	_add_stat_row(
		"Win Rate",
		"%.1f%%" % player.get("win_rate", 0.0))

	# Recent matches.
	var matches: Array = data.get(
		"recent_matches", [])
	if not matches.is_empty():
		var sep := HSeparator.new()
		_content_container.add_child(sep)

		var header := Label.new()
		header.text = "Recent Matches"
		header.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER)
		_content_container.add_child(header)

		for m in matches:
			_add_match_row(m)


func _on_request_failed(error: String) -> void:
	_set_loading(false)
	_status_label.text = error
	_status_label.show()


func _add_leaderboard_row(
	entry: Dictionary,
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", 12)
	_content_container.add_child(row)

	var rank_label := Label.new()
	rank_label.text = "#%d" % entry.get(
		"rank", 0)
	rank_label.custom_minimum_size.x = 40
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = str(
		entry.get("display_name", ""))
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	row.add_child(name_label)

	var rating_label := Label.new()
	rating_label.text = str(
		entry.get("rating", 1500))
	rating_label.custom_minimum_size.x = 50
	rating_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(rating_label)

	var wl_label := Label.new()
	wl_label.text = "%d/%d" % [
		entry.get("wins", 0),
		entry.get("losses", 0),
	]
	wl_label.custom_minimum_size.x = 60
	wl_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(wl_label)


func _add_stat_row(
	label_text: String,
	value_text: String,
) -> void:
	var row := HBoxContainer.new()
	_content_container.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(value)


func _add_match_row(m: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", 8)
	_content_container.add_child(row)

	var result_label := Label.new()
	if m.get("is_win", false):
		result_label.text = "W"
		result_label.modulate = (
			Color(0.6, 1.0, 0.6))
	else:
		result_label.text = "L"
		result_label.modulate = (
			Color(1.0, 0.4, 0.4))
	result_label.custom_minimum_size.x = 20
	row.add_child(result_label)

	var level_label := Label.new()
	level_label.text = str(
		m.get("level_id", ""))
	level_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	row.add_child(level_label)

	var rank_label := Label.new()
	rank_label.text = "%d/%d" % [
		m.get("rank", 0),
		m.get("player_count", 0),
	]
	rank_label.custom_minimum_size.x = 40
	rank_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(rank_label)

	var kd_label := Label.new()
	kd_label.text = "%d/%d" % [
		m.get("kill_count", 0),
		m.get("death_count", 0),
	]
	kd_label.custom_minimum_size.x = 40
	kd_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(kd_label)


func _clear_content() -> void:
	for child in _content_container.get_children():
		child.queue_free()
	_status_label.hide()


func _set_loading(loading: bool) -> void:
	_is_loading = loading
	if loading:
		_status_label.text = "Loading..."
		_status_label.show()
	else:
		_status_label.hide()
