class_name LeaderboardScreen
extends Screen
## Full-screen leaderboard viewer. Shows ranked
## player scores with a collapsible filter row.
## Opened from game-over or the side panel.


const _TYPE_LABELS: Array[String] = [
	"All Time", "Weekly",
]
const _TYPE_PARAMS: Array[String] = [
	"alltime", "weekly",
]
const _FONT_SIZE := 28
const _FILTER_FONT_SIZE := 22
const _ROW_PADDING := 8
const _STRIPE_COLOR := Color(1.0, 1.0, 1.0, 0.06)

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat
@export var _x_icon: Texture2D
@export var _filter_icon: Texture2D
@export var _checkmark_icon: Texture2D
@export var _binary_toggle_scene: PackedScene

var _return_screen_type := (
	ScreensMain.ScreenType.UNKNOWN)
var _default_type_param := "weekly"
var _default_scope := "global"
var _is_loading := false
var _is_filter_expanded := false
## Index into _TYPE_PARAMS. Default: Weekly.
var _type_index := 1
## Index into _scope_options. Default: global.
var _scope_index := 0
## Cached scope IDs: ["global", level_id, ...].
var _scope_options: Array[String] = []
var _scope_labels: Array[String] = []

var _navigator := ScreenFocusNavigator.new()
## Maps filter sub-row PanelContainers to their
## selection callables.
var _filter_row_actions: Dictionary = {}
## The type binary toggle (All Time / Weekly).
var _type_toggle: BinaryToggle = null


func _enter_tree() -> void:
	super._enter_tree()
	G.leaderboard_screen = self


func _ready() -> void:
	(G.backend_api_client.leaderboard_received
		.connect(_on_leaderboard_received))
	(G.backend_api_client.request_failed
		.connect(_on_request_failed))
	_setup_filter_master_row()
	_setup_close_row()


func on_open() -> void:
	super.on_open()
	_apply_default_filter()
	_build_scope_options()
	_is_filter_expanded = false
	_build_filter_rows()
	_update_filter_sub_rows_visibility()
	_fetch_leaderboard()
	_build_focusable_list(true)
	_navigator.prime()


func _process(delta: float) -> void:
	if not visible:
		return
	if _navigator.poll(delta):
		# Left on a non-horizontal-consumer control routes
		# to the screen's `on_back()` (close). The type
		# toggle consumes Left/Right (cycles between All
		# Time / Weekly), so when focused on it, fall
		# through to `_activate_focused` which routes the
		# direction to the toggle's on_left/on_right.
		var focused := _navigator.get_focused()
		var direction := _navigator.last_activation_direction
		if (direction == -1
				and not _focused_consumes_horizontal(focused)):
			on_back()
		else:
			_activate_focused()


## True iff the focused control wants Left/Right
## input itself (e.g., the All-Time/Weekly
## BinaryToggle). Other focused controls let Left
## fall through to `on_back()`.
func _focused_consumes_horizontal(
	focused: Control,
) -> bool:
	if focused == null:
		return false
	if (is_instance_valid(_type_toggle)
			and focused == _type_toggle):
		return true
	return false


## Close the leaderboard and return to the screen
## set via `set_return_screen()`. Triggered by Left
## input on non-type-toggle rows, by close_menu /
## ui_cancel (Escape / B-button), and by the
## CloseRow at the bottom of the list.
func on_back() -> void:
	_on_close_pressed()


## Set where the back button navigates to.
## Call before opening this screen.
func set_return_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	_return_screen_type = screen_type


## Set the default filter applied on open.
## Call before opening this screen.
func set_default_filter(
	type_param: String,
	scope: String,
) -> void:
	_default_type_param = type_param
	_default_scope = scope


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


func _apply_default_filter() -> void:
	var type_idx := _TYPE_PARAMS.find(
		_default_type_param)
	_type_index = (
		type_idx if type_idx >= 0 else 1)


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
			if (info
					and not info.display_name
					.is_empty()):
				_scope_labels.append(
					info.display_name)
			else:
				_scope_labels.append(
					String(id))
	# Map default scope to index.
	var scope_idx := _scope_options.find(
		_default_scope)
	_scope_index = (
		scope_idx if scope_idx >= 0 else 0)


func _fetch_leaderboard() -> void:
	_clear_content()
	_update_scope_label()
	_set_loading(true)
	G.backend_api_client.fetch_leaderboard(
		_TYPE_PARAMS[_type_index],
		_scope_options[_scope_index],
	)


func _update_scope_label() -> void:
	%ScopeLabel.text = "Leaderboard"


func _on_leaderboard_received(
	data: Dictionary,
) -> void:
	if not visible:
		return
	_set_loading(false)
	_clear_content()

	var your_rank: int = data.get(
		"your_rank", 0)
	var your_rating: int = data.get(
		"your_rating", 0)
	if your_rank > 0:
		%RankLabel.text = (
			"Your rank: #%d \u00b7 Rating: %d"
			% [your_rank, your_rating])
		%RankLabel.show()

	var board: Array = data.get(
		"leaderboard", [])
	# Filter out anonymous entries
	# (empty display_name).
	var filtered: Array = board.filter(
		func(e: Dictionary) -> bool:
			return not e.get(
				"display_name", "").is_empty())

	if filtered.is_empty():
		%ScrollContainer.hide()
		%StatusLabel.text = "No players yet"
		%StatusLabel.show()
		return

	for i in filtered.size():
		_add_leaderboard_row(
			filtered[i], i % 2 == 1)


func _on_request_failed(
	error: String,
) -> void:
	if not visible:
		return
	_set_loading(false)
	%ScrollContainer.hide()
	%StatusLabel.text = error
	%StatusLabel.show()


func _add_leaderboard_row(
	entry: Dictionary,
	is_striped: bool,
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", 12)
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

	var profile_image := ProfileImageDisplay.new()
	profile_image.image_size = 48
	row.add_child(profile_image)
	var image_url: String = entry.get(
		"profile_image_url", "")
	var pid: String = entry.get("player_id", "")
	profile_image.set_from_url(
		pid.hash(), image_url, Color.GRAY)

	var rank_label := Label.new()
	rank_label.text = "#%d" % entry.get(
		"rank", 0)
	rank_label.custom_minimum_size.x = 56
	rank_label.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = str(
		entry.get("display_name", ""))
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	name_label.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
	row.add_child(name_label)

	var rating_label := Label.new()
	rating_label.text = str(
		entry.get("score", entry.get("rating", 0)))
	rating_label.custom_minimum_size.x = 70
	rating_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	rating_label.add_theme_font_size_override(
		"font_size", _FONT_SIZE)
	row.add_child(rating_label)

	if entry.has("wins") or entry.has("losses"):
		var wl_label := Label.new()
		wl_label.text = "%d/%d" % [
			entry.get("wins", 0),
			entry.get("losses", 0),
		]
		wl_label.custom_minimum_size.x = 80
		wl_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_RIGHT)
		wl_label.add_theme_font_size_override(
			"font_size", _FONT_SIZE)
		row.add_child(wl_label)


func _build_focusable_list(
	focus_close: bool = false,
) -> void:
	var items: Array[Control] = []
	items.append(%FilterMasterRow)
	if _is_filter_expanded:
		if is_instance_valid(_type_toggle):
			items.append(_type_toggle)
		for child in (
			%FilterSubRows.get_children()
		):
			if child is PanelContainer:
				items.append(
					child as PanelContainer)
	items.append(%CloseRow)
	_navigator.set_focusable_list(items)
	if focus_close:
		_navigator.focus_index(
			items.size() - 1)


func _activate_focused() -> void:
	var focused := _navigator.get_focused()
	if focused == null:
		return
	if focused == %CloseRow:
		_on_close_pressed()
	elif focused == %FilterMasterRow:
		_toggle_filter()
	elif (is_instance_valid(_type_toggle)
			and focused == _type_toggle):
		var direction := (
			_navigator.last_activation_direction)
		if direction < 0:
			_type_toggle.on_left()
		elif direction > 0:
			_type_toggle.on_right()
	elif _filter_row_actions.has(focused):
		_filter_row_actions[focused].call()


func _setup_filter_master_row() -> void:
	_update_filter_row_style(false)
	(%FilterMasterRow.gui_input
		.connect(_on_filter_master_row_gui_input))
	(%FilterMasterRow.mouse_entered
		.connect(func() -> void:
			_update_filter_row_style(true)))
	(%FilterMasterRow.mouse_exited
		.connect(func() -> void:
			_update_filter_row_style(false)))
	(%FilterMasterRow.focus_entered
		.connect(func() -> void:
			_update_filter_row_style(true)))
	(%FilterMasterRow.focus_exited
		.connect(func() -> void:
			_update_filter_row_style(false)))
	%FilterLabel.add_theme_font_size_override(
		"font_size", _FILTER_FONT_SIZE)
	if _filter_icon != null:
		%FilterIcon.texture = _filter_icon
		%FilterIcon.custom_minimum_size = (
			_filter_icon.get_size()
			* G.settings.icon_scale)
		%FilterIcon.show()
	else:
		%FilterIcon.hide()


func _on_filter_master_row_gui_input(
	event: InputEvent,
) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if (mb.pressed
				and mb.button_index
				== MOUSE_BUTTON_LEFT):
			_toggle_filter()


func _toggle_filter() -> void:
	if _is_loading:
		return
	_is_filter_expanded = not _is_filter_expanded
	_update_filter_sub_rows_visibility()
	_build_focusable_list()


func _update_filter_row_style(
	is_hovered: bool,
) -> void:
	if is_hovered or %FilterMasterRow.has_focus():
		(%FilterMasterRow
			.add_theme_stylebox_override(
				"panel", _focus_style))
	else:
		(%FilterMasterRow
			.add_theme_stylebox_override(
				"panel", _unfocused_style))


func _update_filter_sub_rows_visibility() -> void:
	%FilterSubRows.visible = _is_filter_expanded
	_update_filter_label()
	_update_filter_row_style(false)


func _update_filter_label() -> void:
	var scope_text := (
		_scope_labels[_scope_index]
		if _scope_labels.size() > _scope_index
		else "Global")
	%FilterLabel.text = (
		"Filter: %s \u00b7 %s" % [
			_TYPE_LABELS[_type_index],
			scope_text,
		])


func _build_filter_rows() -> void:
	_filter_row_actions.clear()
	_type_toggle = null
	for child in %FilterSubRows.get_children():
		child.queue_free()

	# Time period binary toggle.
	if _binary_toggle_scene != null:
		_type_toggle = (
			_binary_toggle_scene.instantiate()
			as BinaryToggle)
		_type_toggle.setup(
			_TYPE_LABELS[0],
			_TYPE_LABELS[1],
			_type_index,
			_focus_style,
			_unfocused_style)
		_type_toggle.option_changed.connect(
			_select_type)
		%FilterSubRows.add_child(_type_toggle)

	var sep := HSeparator.new()
	%FilterSubRows.add_child(sep)

	# Scope options.
	for i in _scope_options.size():
		_add_filter_option_row(
			_scope_labels[i],
			i == _scope_index,
			_select_scope.bind(i))


func _add_filter_option_row(
	label_text: String,
	is_selected: bool,
	on_click: Callable,
) -> void:
	var row := PanelContainer.new()
	row.focus_mode = Control.FOCUS_ALL
	row.add_theme_stylebox_override(
		"panel", _unfocused_style)
	%FilterSubRows.add_child(row)
	_filter_row_actions[row] = on_click

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override(
		"separation", 6)
	row.add_child(hbox)

	if _checkmark_icon != null:
		var check := TextureRect.new()
		check.texture = (
			_checkmark_icon if is_selected
			else null)
		check.custom_minimum_size = Vector2(22, 22)
		check.stretch_mode = (
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		check.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE)
		hbox.add_child(check)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override(
		"font_size", _FILTER_FONT_SIZE)
	hbox.add_child(label)

	row.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb := (
					event as InputEventMouseButton)
				if (mb.pressed
						and mb.button_index
						== MOUSE_BUTTON_LEFT):
					on_click.call())
	row.mouse_entered.connect(
		func() -> void:
			row.add_theme_stylebox_override(
				"panel", _focus_style))
	row.mouse_exited.connect(
		func() -> void:
			row.add_theme_stylebox_override(
				"panel", _unfocused_style))
	row.focus_entered.connect(
		func() -> void:
			row.add_theme_stylebox_override(
				"panel", _focus_style))
	row.focus_exited.connect(
		func() -> void:
			row.add_theme_stylebox_override(
				"panel", _unfocused_style))


func _select_type(index: int) -> void:
	if _is_loading:
		return
	_type_index = index
	_update_filter_label()
	_fetch_leaderboard()


func _select_scope(index: int) -> void:
	if _is_loading:
		return
	_scope_index = index
	_build_filter_rows()
	_update_filter_label()
	_build_focusable_list()
	_fetch_leaderboard()


func _setup_close_row() -> void:
	_update_close_row_style(false)
	(%CloseRow.gui_input
		.connect(_on_close_row_gui_input))
	(%CloseRow.mouse_entered
		.connect(func() -> void:
			_update_close_row_style(true)))
	(%CloseRow.mouse_exited
		.connect(func() -> void:
			_update_close_row_style(false)))
	(%CloseRow.focus_entered
		.connect(func() -> void:
			_update_close_row_style(true)))
	(%CloseRow.focus_exited
		.connect(func() -> void:
			_update_close_row_style(false)))
	if _x_icon != null:
		%CloseIcon.texture = _x_icon
		%CloseIcon.custom_minimum_size = (
			_x_icon.get_size() * 2.0)
		%CloseIcon.show()


func _update_close_row_style(
	is_hovered: bool,
) -> void:
	if is_hovered:
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


func _clear_content() -> void:
	for child in (
		%ContentContainer.get_children()
	):
		child.queue_free()
	%ScrollContainer.show()
	%StatusLabel.hide()
	%RankLabel.hide()


func _set_loading(loading: bool) -> void:
	_is_loading = loading
	%LoadingSpinner.visible = loading
	if loading:
		%ScrollContainer.hide()
