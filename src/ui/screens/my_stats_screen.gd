class_name MyStatsScreen
extends Screen
## Full-screen personal stats viewer. Shows the
## local player's rating, match history, and
## lifetime stats. Hidden for anonymous players.


const _FONT_SIZE := 28
const _RETRY_DELAY_SEC := 0.5
const _MAX_RETRIES := 6

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat
@export var _x_icon: Texture2D

var _return_screen_type := (
	ScreensMain.ScreenType.UNKNOWN)
var _navigator := ScreenFocusNavigator.new()
var _retry_count := 0


func _enter_tree() -> void:
	super._enter_tree()
	G.my_stats_screen = self


func _ready() -> void:
	(G.backend_api_client.profile_received
		.connect(_on_profile_received))
	(G.backend_api_client.request_failed
		.connect(_on_request_failed))
	_setup_close_row()


func _exit_tree() -> void:
	var client := G.backend_api_client
	if not is_instance_valid(client):
		return
	if client.profile_received.is_connected(
			_on_profile_received):
		client.profile_received.disconnect(
			_on_profile_received)
	if client.request_failed.is_connected(
			_on_request_failed):
		client.request_failed.disconnect(
			_on_request_failed)


func on_open() -> void:
	super.on_open()
	_clear_content()
	%ScrollContainer.scroll_vertical = 0
	var items: Array[Control] = [%CloseRow]
	_navigator.set_focusable_list(items)
	_navigator.prime()
	if not Platform.token_store.is_token_valid():
		_show_status("Not logged in")
		return
	_retry_count = 0
	_set_loading(true)
	G.backend_api_client.fetch_player_profile()


## Set where the back button navigates to.
## Call before opening this screen.
func set_return_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	_return_screen_type = screen_type


func _process(_delta: float) -> void:
	if not visible:
		return
	if _navigator.poll(_delta):
		_on_close_pressed()


func _unhandled_input(
	event: InputEvent,
) -> void:
	if not visible:
		return
	if (event.is_action_pressed("ui_cancel")
			or event.is_action_pressed(
				&"close_menu")):
		get_viewport().set_input_as_handled()
		_on_close_pressed()


func _on_close_pressed() -> void:
	G.audio.play_sound("click")
	G.screens.client_open_screen(
		_return_screen_type)


func _on_profile_received(
	data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	if not visible:
		return
	_set_loading(false)
	_clear_content()

	var profile: Dictionary = data.get(
		"profile", {})
	if profile.is_empty():
		_show_status("No data")
		return

	%ScrollContainer.show()

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

	# Lifetime combat stats.
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
		%ContentContainer.add_child(sep)
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
		%ContentContainer.add_child(sep2)

		var header := Label.new()
		header.text = "Recent Matches"
		header.add_theme_font_size_override(
			"font_size", _FONT_SIZE)
		header.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER)
		%ContentContainer.add_child(header)

		for m in matches:
			_add_match_row(m)


func _on_request_failed(
	error: String,
) -> void:
	if is_queued_for_deletion():
		return
	if not visible:
		return
	if (error == error_string(ERR_BUSY)
			and _retry_count < _MAX_RETRIES):
		_retry_count += 1
		(get_tree()
			.create_timer(_RETRY_DELAY_SEC)
			.timeout
			.connect(
				_retry_fetch, CONNECT_ONE_SHOT))
		return
	_set_loading(false)
	_show_status(error)


func _retry_fetch() -> void:
	if not visible:
		return
	G.backend_api_client.fetch_player_profile()


func _add_stat_row(
	label_text: String,
	value_text: String,
) -> void:
	var row := HBoxContainer.new()
	%ContentContainer.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	label.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
	value.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(value)


func _add_match_row(m: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", 8)
	%ContentContainer.add_child(row)

	var result_label := Label.new()
	if m.get("is_win", false):
		result_label.text = "W"
		result_label.modulate = (
			Color(0.6, 1.0, 0.6))
	else:
		result_label.text = "L"
		result_label.modulate = (
			Color(1.0, 0.4, 0.4))
	result_label.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
	result_label.custom_minimum_size.x = 28
	row.add_child(result_label)

	var level_label := Label.new()
	level_label.text = str(
		m.get("level_id", ""))
	level_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	level_label.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
	row.add_child(level_label)

	var rank_label := Label.new()
	rank_label.text = "%d/%d" % [
		m.get("rank", 0),
		m.get("player_count", 0),
	]
	rank_label.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
	rank_label.custom_minimum_size.x = 56
	rank_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(rank_label)

	var kd_label := Label.new()
	kd_label.text = "%d/%d" % [
		m.get("kill_count", 0),
		m.get("death_count", 0),
	]
	kd_label.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
	kd_label.custom_minimum_size.x = 56
	kd_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(kd_label)


func _setup_close_row() -> void:
	_update_close_row_style()
	(%CloseRow.gui_input
		.connect(_on_close_row_gui_input))
	(%CloseRow.focus_entered
		.connect(_update_close_row_style))
	(%CloseRow.focus_exited
		.connect(_update_close_row_style))
	if _x_icon != null:
		%CloseIcon.texture = _x_icon
		%CloseIcon.custom_minimum_size = (
			_x_icon.get_size() * 2.0)
		%CloseIcon.show()


func _update_close_row_style() -> void:
	if %CloseRow.has_focus():
		%CloseRow.add_theme_stylebox_override(
			"panel", _focus_style)
	else:
		%CloseRow.add_theme_stylebox_override(
			"panel", _unfocused_style)


func _on_close_row_gui_input(
	event: InputEvent,
) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if (mb.pressed
				and mb.button_index
				== MOUSE_BUTTON_LEFT):
			_on_close_pressed()


func _show_status(text: String) -> void:
	%ScrollContainer.hide()
	%StatusLabel.text = text
	%StatusLabel.show()


func _clear_content() -> void:
	for child in (
		%ContentContainer.get_children()
	):
		child.queue_free()
	%StatusLabel.hide()
	%ScrollContainer.hide()


func _set_loading(loading: bool) -> void:
	%LoadingSpinner.visible = loading
	if loading:
		%ScrollContainer.hide()
		%StatusLabel.hide()
