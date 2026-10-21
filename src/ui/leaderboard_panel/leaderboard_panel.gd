class_name LeaderboardScreen
extends Screen
## Full-screen leaderboard: the game's public leaderboard, the same
## players, ranks, and listing rules as hopnbop.net/leaderboard/,
## read from the platform runtime's unauthenticated route (see
## BackendApiClient.fetch_leaderboard). Opening it never creates a
## guest account. A signed-in player also sees their own rank; an
## anonymous player sees why they aren't listed.
##
## Up and down scroll the list. Trigger, left, right, Escape, and the
## close row all go back.


const _FONT_SIZE := 28
const _ROW_PADDING := 8
const _ROW_SEPARATION := 12
const _SCROLL_STEP := 120
const _STRIPE_COLOR := Color(1.0, 1.0, 1.0, 0.06)
## Rank colors for the top three (gold, silver, bronze), as on the
## website.
const _PODIUM_COLORS: Array[Color] = [
	Color(0.949, 0.788, 0.298),
	Color(0.788, 0.82, 0.851),
	Color(0.831, 0.58, 0.353),
]

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat
@export var _x_icon: Texture2D

var _return_screen_type := (
	ScreensMain.ScreenType.UNKNOWN)
var _poller := AnyDeviceInputPoller.new()


func _enter_tree() -> void:
	super._enter_tree()
	G.leaderboard_screen = self


func _ready() -> void:
	(G.backend_api_client.leaderboard_received
		.connect(_on_leaderboard_received))
	(G.backend_api_client.leaderboard_failed
		.connect(_on_leaderboard_failed))
	(G.backend_api_client.own_standing_received
		.connect(_on_own_standing_received))
	%ScopeLabel.text = tr("SETTINGS.LEADERBOARD")
	_setup_close_row()


func _exit_tree() -> void:
	var client := G.backend_api_client
	if not is_instance_valid(client):
		return
	if client.leaderboard_received.is_connected(
			_on_leaderboard_received):
		client.leaderboard_received.disconnect(
			_on_leaderboard_received)
	if client.leaderboard_failed.is_connected(
			_on_leaderboard_failed):
		client.leaderboard_failed.disconnect(
			_on_leaderboard_failed)
	if client.own_standing_received.is_connected(
			_on_own_standing_received):
		client.own_standing_received.disconnect(
			_on_own_standing_received)


func on_open() -> void:
	super.on_open()
	_clear_content()
	%ScrollContainer.scroll_vertical = 0
	%RankLabel.hide()
	_poller.prime()
	_set_loading(true)
	G.backend_api_client.fetch_leaderboard()
	if Platform.token_store.is_anonymous:
		# Anonymous accounts have no display name, so they're never
		# listed. Say so instead of asking for a rank.
		%RankLabel.text = tr("LEADERBOARD.GUEST_HINT")
		%RankLabel.show()
	else:
		G.backend_api_client.fetch_own_standing()


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


## Close the leaderboard and return to the screen set via
## `set_return_screen()`.
func on_back() -> void:
	_on_close_pressed()


## Set where the back button navigates to.
## Call before opening this screen.
func set_return_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	_return_screen_type = screen_type


## Shows a leaderboard_received payload: one row per entry, in order.
func show_leaderboard(data: Dictionary) -> void:
	_set_loading(false)
	_clear_content()
	var entries: Array = data.get("entries", [])
	if entries.is_empty():
		_show_status(tr("LEADERBOARD.NO_SCORES"))
		return
	%ScrollContainer.show()
	for index in entries.size():
		_add_leaderboard_row(entries[index], index % 2 == 1)


## Shows that the leaderboard couldn't be loaded.
func show_failure() -> void:
	_set_loading(false)
	_clear_content()
	_show_status(tr("LOADING.CONNECTION_FAILED"))


## Shows an own_standing_received payload: the player's rank when
## they're on the leaderboard.
func show_own_standing(standing: Dictionary) -> void:
	var rank: int = standing.get("rank", 0)
	if rank <= 0:
		%RankLabel.hide()
		return
	%RankLabel.text = tr("LEADERBOARD.YOUR_RANK") % rank
	%RankLabel.show()


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


func _on_leaderboard_received(data: Dictionary) -> void:
	if not visible:
		return
	show_leaderboard(data)


func _on_leaderboard_failed(reason: String) -> void:
	if not visible:
		return
	Netcode.warning(
		"Leaderboard fetch failed: %s" % reason,
		NetworkLogger.CATEGORY_CONNECTIONS,
	)
	show_failure()


func _on_own_standing_received(standing: Dictionary) -> void:
	if not visible or Platform.token_store.is_anonymous:
		return
	show_own_standing(standing)


func _on_close_pressed() -> void:
	G.audio.play_sound("click")
	G.screens.client_open_screen(
		_return_screen_type)


func _add_leaderboard_row(
	entry: Dictionary,
	is_striped: bool,
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", _ROW_SEPARATION)
	var margin := MarginContainer.new()
	for key in [
		"margin_top", "margin_bottom",
		"margin_left", "margin_right",
	]:
		margin.add_theme_constant_override(
			key, _ROW_PADDING)
	margin.add_child(row)
	if is_striped:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = _STRIPE_COLOR
		panel.add_theme_stylebox_override(
			"panel", style)
		%ContentContainer.add_child(panel)
		panel.add_child(margin)
	else:
		%ContentContainer.add_child(margin)

	var rank: int = entry.get("rank", 0)
	var rank_label := _make_label(
		str(rank),
		%RankHeader.custom_minimum_size.x,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	if rank >= 1 and rank <= _PODIUM_COLORS.size():
		rank_label.add_theme_color_override(
			"font_color", _PODIUM_COLORS[rank - 1])
	row.add_child(rank_label)

	# The bunny name from the match that set the score when the
	# entry carries one (H59), else the account's generated name.
	# A plain Label never parses markup, and the TextServer lays
	# out right-to-left names on its own.
	var player_name: String = (
		DynamicAdjectiveConfig
			.localized_full_name_from_spawn(
				entry.get("spawn_name", {})))
	if player_name.is_empty():
		player_name = str(entry.get("display_name", ""))
	var name_label := _make_label(
		player_name,
		0.0,
		HORIZONTAL_ALIGNMENT_LEFT,
	)
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	name_label.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS)
	row.add_child(name_label)

	row.add_child(_make_label(
		str(entry.get("score", 0)),
		%ScoreHeader.custom_minimum_size.x,
		HORIZONTAL_ALIGNMENT_RIGHT,
	))


func _make_label(
	text: String,
	min_width: float,
	alignment: HorizontalAlignment,
) -> Label:
	var label := Label.new()
	label.text = text
	# Data, not translation keys: a name like "Leaderboard" must not
	# be translated.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.custom_minimum_size.x = min_width
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
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
	%ScrollContainer.show()
	%StatusLabel.hide()


func _set_loading(loading: bool) -> void:
	%LoadingSpinner.visible = loading
	if loading:
		%ScrollContainer.hide()
		%StatusLabel.hide()
