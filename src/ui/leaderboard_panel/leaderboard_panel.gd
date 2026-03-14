class_name LeaderboardPanel
extends CanvasLayer
## Full-screen overlay showing leaderboard and
## player stats. Follows the same CanvasLayer
## overlay pattern as SidePanelManager.


signal closed


enum Tab {
	LEADERBOARD,
	MY_STATS,
}

const _TYPE_LABELS: Array[String] = [
	"All Time", "Weekly",
]
const _TYPE_PARAMS: Array[String] = [
	"alltime", "weekly",
]

var _current_tab := Tab.LEADERBOARD
var _is_loading := false
var _type_index := 0
var _scope_index := 0
## Cached scope list: ["global", level_id, ...].
var _scope_options: Array[String] = []
var _scope_labels: Array[String] = []

@onready var _tab_label: Label = %TabLabel
@onready var _content_container: VBoxContainer = (
	%ContentContainer)
@onready var _status_label: Label = %StatusLabel
@onready var _close_hint: Label = %CloseHint


func _ready() -> void:
	(G.backend_api_client.leaderboard_received
		.connect(_on_leaderboard_received))
	(G.backend_api_client.profile_received
		.connect(_on_profile_received))
	(G.backend_api_client.request_failed
		.connect(_on_request_failed))

	_build_scope_options()
	_close_hint.text = (
		"ESC close | Left/Right tab"
		+ " | Up/Down filter")
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
	elif event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		_cycle_filter(-1)
	elif event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		_cycle_filter(1)


func _switch_tab(direction: int) -> void:
	if _is_loading:
		return
	var new_tab := wrapi(
		_current_tab + direction,
		0,
		Tab.size())
	if new_tab != _current_tab:
		_show_tab(new_tab as Tab)


func _cycle_filter(direction: int) -> void:
	if _is_loading:
		return
	if _current_tab != Tab.LEADERBOARD:
		return
	# Up/down cycles through all type+scope
	# combinations as a flat list.
	var scope_count := _scope_options.size()
	var total := (
		_TYPE_LABELS.size() * scope_count)
	var combined := (
		_type_index * scope_count
		+ _scope_index)
	combined = wrapi(
		combined + direction, 0, total)
	var new_type := combined / scope_count
	var new_scope := combined % scope_count
	if (new_type != _type_index
			or new_scope != _scope_index):
		_type_index = new_type
		_scope_index = new_scope
		_fetch_leaderboard()


func _build_scope_options() -> void:
	_scope_options = ["global"]
	_scope_labels = ["Global"]
	if G.level_registry != null:
		for id in (
			G.level_registry
				.get_enabled_level_ids()
		):
			_scope_options.append(String(id))
			var info := (
				G.level_registry
					.get_level_by_id(id))
			if info and not info.display_name.is_empty():
				_scope_labels.append(
					info.display_name)
			else:
				_scope_labels.append(String(id))


func _fetch_leaderboard() -> void:
	_clear_content()
	_update_leaderboard_header()
	_set_loading(true)
	G.backend_api_client.fetch_leaderboard(
		_TYPE_PARAMS[_type_index],
		_scope_options[_scope_index],
	)


func _update_leaderboard_header() -> void:
	var filter_text := "%s - %s" % [
		_TYPE_LABELS[_type_index],
		_scope_labels[_scope_index],
	]
	_tab_label.text = (
		"< Leaderboard: %s >" % filter_text)


func _show_tab(tab: Tab) -> void:
	_current_tab = tab
	_clear_content()

	match tab:
		Tab.LEADERBOARD:
			_update_leaderboard_header()
			_set_loading(true)
			G.backend_api_client.fetch_leaderboard(
				_TYPE_PARAMS[_type_index],
				_scope_options[_scope_index],
			)
		Tab.MY_STATS:
			_tab_label.text = (
				"< My Stats >")
			_set_loading(true)
			if not (
				G.auth_token_store
					.is_token_valid()
			):
				_set_loading(false)
				_status_label.text = (
					"Not logged in")
				_status_label.show()
				return
			(G.backend_api_client
				.fetch_player_profile())


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


func _on_profile_received(
	data: Dictionary,
) -> void:
	_set_loading(false)
	if _current_tab != Tab.MY_STATS:
		return

	_clear_content()

	var profile: Dictionary = data.get(
		"profile", {})
	if profile.is_empty():
		_status_label.text = "No data"
		_status_label.show()
		return

	# Profile summary.
	_add_stat_row(
		"Rating",
		str(profile.get("rating", 1500)))
	var rank: int = data.get("rank", 0)
	if rank > 0:
		_add_stat_row("Rank", "#%d" % rank)
	_add_stat_row(
		"Matches",
		str(profile.get("matches_played", 0)))
	_add_stat_row(
		"Wins",
		str(profile.get("wins", 0)))

	# Lifetime stats.
	var kills: int = profile.get(
		"total_kills", 0)
	var deaths: int = profile.get(
		"total_deaths", 0)
	var bumps: int = profile.get(
		"total_bumps", 0)
	var crown_sec: float = profile.get(
		"total_crown_time_sec", 0.0)
	if kills > 0 or deaths > 0:
		var sep := HSeparator.new()
		_content_container.add_child(sep)
		_add_stat_row("Kills", str(kills))
		_add_stat_row("Deaths", str(deaths))
		_add_stat_row("Bumps", str(bumps))
		if crown_sec > 0:
			_add_stat_row(
				"Crown Time",
				"%.0fs" % crown_sec)

	# Recent matches.
	var matches: Array = data.get(
		"recent_matches", [])
	if not matches.is_empty():
		var sep2 := HSeparator.new()
		_content_container.add_child(sep2)

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

	# Profile image.
	var profile_image := ProfileImageDisplay.new()
	profile_image.image_size = 32
	row.add_child(profile_image)
	var image_url: String = entry.get(
		"profile_image_url", "")
	var pid: String = entry.get(
		"player_id", "")
	var cache_key: int = pid.hash()
	profile_image.set_from_url(
		cache_key, image_url, Color.GRAY)

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
