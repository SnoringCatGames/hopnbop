class_name MyStatsScreen
extends Screen
## Full-screen personal stats: the player's best score and rank on
## the public leaderboard, their match totals, and their latest
## matches (BackendApiClient.fetch_my_stats). The main menu offers it
## to signed-in players only.
##
## Until 2026-10-12 it read the account profile (fetch_player_profile,
## which carries the friend code, not stats) under a key that reply
## never had, so it always said "No data".
##
## Up and down scroll. Trigger, left, right, Escape, and the close
## row all go back.


const _FONT_SIZE := 28
const _SCROLL_STEP := 120
const _ROW_SEPARATION := 8
const _RESULT_COLUMN_WIDTH := 140
const _NUMBER_COLUMN_WIDTH := 120
const _HEADER_ALPHA := 0.7
const _WIN_COLOR := Color(0.6, 1.0, 0.6)
const _LOSS_COLOR := Color(1.0, 0.4, 0.4)
## What a value with no data shows (no score yet, not ranked).
const _NO_VALUE := "-"

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat
@export var _x_icon: Texture2D

var _return_screen_type := (
	ScreensMain.ScreenType.UNKNOWN)
var _poller := AnyDeviceInputPoller.new()


func _enter_tree() -> void:
	super._enter_tree()
	G.my_stats_screen = self


func _ready() -> void:
	(G.backend_api_client.my_stats_received
		.connect(_on_my_stats_received))
	(G.backend_api_client.my_stats_failed
		.connect(_on_my_stats_failed))
	_setup_close_row()


func _exit_tree() -> void:
	var client := G.backend_api_client
	if not is_instance_valid(client):
		return
	if client.my_stats_received.is_connected(
			_on_my_stats_received):
		client.my_stats_received.disconnect(
			_on_my_stats_received)
	if client.my_stats_failed.is_connected(
			_on_my_stats_failed):
		client.my_stats_failed.disconnect(
			_on_my_stats_failed)


func on_open() -> void:
	super.on_open()
	_clear_content()
	%ScrollContainer.scroll_vertical = 0
	_poller.prime()
	if not Platform.token_store.is_token_valid():
		_show_status(tr("STATS.SIGN_IN_REQUIRED"))
		return
	_set_loading(true)
	G.backend_api_client.fetch_my_stats()


func _process(delta: float) -> void:
	if not visible:
		return
	_poller.poll(delta)
	if _poller.up_just:
		_scroll(-_SCROLL_STEP)
	elif _poller.down_just:
		_scroll(_SCROLL_STEP)
	elif (_poller.trigger_just
			or _poller.left_just
			or _poller.right_just):
		on_back()


func on_back() -> void:
	_on_close_pressed()


## Set where the back button navigates to.
## Call before opening this screen.
func set_return_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	_return_screen_type = screen_type


## Shows a my_stats_received payload.
func show_stats(stats: Dictionary) -> void:
	_set_loading(false)
	_clear_content()
	%ScrollContainer.show()

	var best_score: int = stats.get("best_score", -1)
	var rank: int = stats.get("rank", 0)
	_add_stat_row(
		tr("LEADERBOARD.BEST_SCORE"),
		str(best_score) if best_score >= 0 else _NO_VALUE)
	_add_stat_row(
		tr("STATS.RANK"),
		"#%d" % rank if rank > 0 else _NO_VALUE)
	_add_stat_row(tr("STATS.MATCHES"), str(stats.get("matches", 0)))
	_add_stat_row(tr("STATS.WINS"), str(stats.get("wins", 0)))
	_add_stat_row(tr("STATS.KILLS"), str(stats.get("kills", 0)))
	_add_stat_row(tr("STATS.BUMPS"), str(stats.get("bumps", 0)))

	%ContentContainer.add_child(HSeparator.new())
	var header := _make_label(
		tr("STATS.RECENT_MATCHES"), 0.0, HORIZONTAL_ALIGNMENT_CENTER)
	%ContentContainer.add_child(header)

	var matches: Array = stats.get("recent_matches", [])
	if matches.is_empty():
		var empty := _make_label(
			tr("STATS.NO_MATCHES"), 0.0, HORIZONTAL_ALIGNMENT_CENTER)
		empty.modulate.a = _HEADER_ALPHA
		%ContentContainer.add_child(empty)
		return
	var columns := _add_match_row(
		"",
		tr("STATS.SCORE"),
		tr("STATS.KILLS"),
		tr("STATS.BUMPS"),
	)
	columns.modulate.a = _HEADER_ALPHA
	for match_entry: Variant in matches:
		if match_entry is Dictionary:
			_add_result_row(match_entry)


## Shows why the stats couldn't be loaded.
func show_failure(reason: String) -> void:
	_set_loading(false)
	_clear_content()
	if reason == BackendApiClient.NOT_SIGNED_IN:
		_show_status(tr("STATS.SIGN_IN_REQUIRED"))
	else:
		_show_status(tr("LOADING.CONNECTION_FAILED"))


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


func _on_my_stats_received(stats: Dictionary) -> void:
	if is_queued_for_deletion() or not visible:
		return
	show_stats(stats)


func _on_my_stats_failed(reason: String) -> void:
	if is_queued_for_deletion() or not visible:
		return
	if reason != BackendApiClient.NOT_SIGNED_IN:
		Netcode.warning(
			"My Stats fetch failed: %s" % reason,
			NetworkLogger.CATEGORY_CONNECTIONS,
		)
	show_failure(reason)


func _on_close_pressed() -> void:
	G.audio.play_sound("click")
	G.screens.client_open_screen(
		_return_screen_type)


func _add_stat_row(
	label_text: String,
	value_text: String,
) -> void:
	var row := HBoxContainer.new()
	%ContentContainer.add_child(row)
	var label := _make_label(
		label_text, 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(_make_label(
		value_text, 0.0, HORIZONTAL_ALIGNMENT_RIGHT))


## Adds one recent match: the result, colored, then its numbers.
func _add_result_row(match_entry: Dictionary) -> void:
	var is_winner: bool = match_entry.get("is_winner", false)
	var row := _add_match_row(
		tr("STATS.WIN") if is_winner else tr("STATS.LOSS"),
		str(match_entry.get("score", 0)),
		str(match_entry.get("kills", 0)),
		str(match_entry.get("bumps", 0)),
	)
	var result_label: Label = row.get_child(0)
	result_label.add_theme_color_override(
		"font_color", _WIN_COLOR if is_winner else _LOSS_COLOR)


## Adds a four-column row (result, score, kills, bumps) and returns
## it.
func _add_match_row(
	result_text: String,
	score_text: String,
	kills_text: String,
	bumps_text: String,
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", _ROW_SEPARATION)
	%ContentContainer.add_child(row)
	var result_label := _make_label(
		result_text, _RESULT_COLUMN_WIDTH, HORIZONTAL_ALIGNMENT_LEFT)
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(result_label)
	for text in [score_text, kills_text, bumps_text]:
		row.add_child(_make_label(
			text, _NUMBER_COLUMN_WIDTH, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


func _make_label(
	text: String,
	min_width: float,
	alignment: HorizontalAlignment,
) -> Label:
	var label := Label.new()
	label.text = text
	# Already translated, or data.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.custom_minimum_size.x = min_width
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", _FONT_SIZE)
	return label


func _scroll(amount: int) -> void:
	%ScrollContainer.scroll_vertical = (
		%ScrollContainer.scroll_vertical + amount)


func _setup_close_row() -> void:
	# The close row is the screen's one action, so it always looks
	# focused.
	%CloseRow.add_theme_stylebox_override(
		"panel", _focus_style)
	(%CloseRow.gui_input
		.connect(_on_close_row_gui_input))
	if _x_icon != null:
		%CloseIcon.texture = _x_icon
		%CloseIcon.custom_minimum_size = (
			_x_icon.get_size() * 2.0)
		%CloseIcon.show()


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
