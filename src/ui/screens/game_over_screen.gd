class_name GameOverScreen
extends Screen


## Fixed width for the Add Friend button column
## and its balancing spacer on the opposite side.
const _FRIEND_BUTTON_WIDTH := 48
const _ROW_PADDING := 8
const _STRIPE_COLOR := Color(1.0, 1.0, 1.0, 0.06)

@export var _add_friend_icon: Texture2D
@export var _request_sent_icon: Texture2D
@export var _checkmark_icon: Texture2D

## Set of backend player IDs that have been acted
## on this session (to avoid duplicate actions).
var _acted_friend_ids: Dictionary = {}
## Friend action buttons collected during result
## population for inclusion in the focusable list.
var _friend_action_buttons: Array[Control] = []

var _navigator := ScreenFocusNavigator.new()


func _enter_tree() -> void:
	super._enter_tree()
	G.game_over_screen = self


func _ready() -> void:
	var icon_width := int(
		G.settings.get_icon_display_width())
	for button: Button in [
		%PlayAgainButton,
		%ReturnToLobbyButton,
	]:
		button.expand_icon = true
		button.add_theme_constant_override(
			"icon_max_width", icon_width)


func _exit_tree() -> void:
	var client: PlatformFriendsApiClient = Platform.friends
	if not is_instance_valid(client):
		return
	if client.friends_received.is_connected(
			_on_friends_data_refreshed):
		client.friends_received.disconnect(
			_on_friends_data_refreshed)
	if client.friend_request_sent.is_connected(
			_on_friend_request_result):
		client.friend_request_sent.disconnect(
			_on_friend_request_result)
	if (client.friend_request_accepted
			.is_connected(
				_on_friend_accept_result)):
		client.friend_request_accepted.disconnect(
			_on_friend_accept_result)
	if client.request_failed.is_connected(
			_on_friend_action_failed):
		client.request_failed.disconnect(
			_on_friend_action_failed)


func _unhandled_input(
	event: InputEvent,
) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"close_menu"):
		get_viewport().set_input_as_handled()
		_on_return_to_lobby_pressed()


func _process(_delta: float) -> void:
	if not visible:
		return

	if _navigator.poll(_delta):
		_activate_focused()


func on_open() -> void:
	super.on_open()
	_acted_friend_ids.clear()

	# Display server message if present.
	if not (G.client_session
			.latest_server_message.is_empty()):
		%MessageLabel.text = (
			G.client_session
				.latest_server_message)
		%MessageLabel.visible = true
	else:
		%MessageLabel.visible = false

	# Refresh cached relationship data so buttons
	# reflect current state. The fetch is async,
	# so we populate immediately with cached data
	# and re-populate when fresh data arrives.
	if not Platform.friends.is_busy():
		Platform.friends.fetch_friends()
	if not (Platform.friends
			.friends_received
			.is_connected(
				_on_friends_data_refreshed)):
		Platform.friends\
			.friends_received.connect(
				_on_friends_data_refreshed,
				CONNECT_ONE_SHOT)

	_populate_results()
	_build_focusable_list()
	_navigator.prime()


func _build_focusable_list() -> void:
	var items: Array[Control] = []
	for button in _friend_action_buttons:
		items.append(button)
	items.append(%PlayAgainButton)
	items.append(%ReturnToLobbyButton)
	_navigator.set_focusable_list(items)


func _activate_focused() -> void:
	var focused := _navigator.get_focused()
	if focused == null:
		return
	if focused == %PlayAgainButton:
		_on_play_again_pressed()
	elif focused == %ReturnToLobbyButton:
		_on_return_to_lobby_pressed()
	elif focused is Button:
		# Friend action button. Trigger its
		# existing pressed callback.
		(focused as Button).pressed.emit()


func _populate_results() -> void:
	_friend_action_buttons.clear()

	# Clear previous results.
	for child in %ResultsContainer.get_children():
		child.queue_free()

	var match_state: GameMatchState = (
		G.client_session.latest_match_state
		as GameMatchState)
	if match_state == null:
		return
	if match_state.players_by_id.is_empty():
		return

	# Ensure scores and ranks are calculated from
	# the replicated kills/bumps arrays.
	match_state.update_scores()

	# Build lookup of participants with backend IDs.
	var participants := (
		G.client_session
			.latest_match_participants)

	# Sort players by rank.
	var sorted_players: Array = (
		match_state.players_by_id.values())
	sorted_players.sort_custom(
		func(a: GamePlayerState,
			b: GamePlayerState) -> bool:
			return a.rank < b.rank)

	# Check if any row will show an Add Friend
	# button so we can reserve balanced space.
	# Anonymous participants have no backend ID,
	# so they never show a button. Players we
	# are already friends with are hidden.
	var client: PlatformFriendsApiClient = Platform.friends
	var own_id: String = Platform.token_store.player_id
	var has_any_friend_button: bool = (
		not Platform.token_store.is_anonymous
		and participants.any(
			func(p: Dictionary) -> bool:
				var bid: String = p.get(
					"backend_player_id", "")
				return (
					not p.get(
						"is_anonymous", true)
					and not bid.is_empty()
					and bid != own_id
					and not client.is_friend(
						bid))))

	for i in sorted_players.size():
		var ps: GamePlayerState = sorted_players[i]
		var stats: PlayerMatchStats = (
			match_state.get_player_stats(
				ps.player_id))
		var backend_id := (
			_find_backend_id(
				ps.player_id, participants))
		var is_anon := (
			_find_participant_bool(
				ps.player_id,
				participants,
				"is_anonymous",
				true))
		_add_result_row(
			ps, stats, backend_id,
			is_anon,
			has_any_friend_button,
			i % 2 == 1)


func _find_backend_id(
	player_id: int,
	participants: Array[Dictionary],
) -> String:
	for entry in participants:
		if entry.get("player_id", -1) == player_id:
			return entry.get(
				"backend_player_id", "")
	return ""


func _find_participant_bool(
	player_id: int,
	participants: Array[Dictionary],
	field: String,
	default_value: bool,
) -> bool:
	for entry in participants:
		if entry.get("player_id", -1) == player_id:
			return entry.get(field, default_value)
	return default_value


func _add_result_row(
	ps: GamePlayerState,
	stats: PlayerMatchStats,
	backend_player_id: String,
	is_anonymous: bool,
	reserve_friend_column: bool,
	is_striped: bool,
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", 16)
	row.alignment = (
		BoxContainer.ALIGNMENT_CENTER)
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
		%ResultsContainer.add_child(panel)
		panel.add_child(margin)
	else:
		%ResultsContainer.add_child(margin)

	# Left spacer to balance the Add Friend
	# button on the right, keeping the core
	# content centered.
	if reserve_friend_column:
		var left_spacer := Control.new()
		left_spacer.custom_minimum_size.x = (
			_FRIEND_BUTTON_WIDTH)
		row.add_child(left_spacer)

	# Profile image.
	var profile_image := ProfileImageDisplay.new()
	profile_image.image_size = 48
	row.add_child(profile_image)
	profile_image.set_player(
		ps.player_id,
		G.get_peer_anonymous_color(ps.peer_id))

	# Rank label.
	var rank_label := Label.new()
	rank_label.text = _ordinal(ps.rank)
	rank_label.custom_minimum_size.x = 40
	row.add_child(rank_label)

	# Player name (colored). Prefer auth display
	# name over procedural in-game name.
	var auth_name: String = (
		G.client_session.auth_display_names
			.get(ps.player_id, ""))
	var name_label := Label.new()
	name_label.text = (
		auth_name
		if not auth_name.is_empty()
		else String(ps.full_name))
	name_label.modulate = ps.label_color
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	row.add_child(name_label)

	# Score.
	var score_label := Label.new()
	score_label.text = str(ps.score)
	score_label.custom_minimum_size.x = 50
	score_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(score_label)

	# K/D.
	if stats != null:
		var kd_label := Label.new()
		kd_label.text = "%d/%d" % [
			stats.kill_count,
			stats.death_count,
		]
		kd_label.custom_minimum_size.x = 50
		kd_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_RIGHT)
		row.add_child(kd_label)

	# Friend action button or spacer.
	if reserve_friend_column:
		var show_button: bool = (
			not is_anonymous
			and not backend_player_id.is_empty()
			and not Platform.token_store.is_anonymous
			and backend_player_id
				!= Platform.token_store.player_id)
		if show_button:
			_add_friend_button(
				row, backend_player_id)
		else:
			var right_spacer := Control.new()
			right_spacer.custom_minimum_size.x = (
				_FRIEND_BUTTON_WIDTH)
			row.add_child(right_spacer)


func _ordinal(n: int) -> String:
	match n:
		1:
			return tr("ORDINAL.1ST")
		2:
			return tr("ORDINAL.2ND")
		3:
			return tr("ORDINAL.3RD")
		_:
			return tr("ORDINAL.NTH") % n


func _add_friend_button(
	row: HBoxContainer,
	backend_player_id: String,
) -> void:
	var client: PlatformFriendsApiClient = Platform.friends

	var icon_width := int(
		G.settings.get_icon_display_width())

	# Already friends. Hide the button entirely.
	if client.is_friend(backend_player_id):
		var spacer := Control.new()
		spacer.custom_minimum_size.x = (
			_FRIEND_BUTTON_WIDTH)
		row.add_child(spacer)
		return

	# Sent request already pending.
	if client.has_sent_request(
		backend_player_id,
	):
		var pending_button := Button.new()
		pending_button.icon = _request_sent_icon
		pending_button.expand_icon = true
		pending_button.add_theme_constant_override(
			"icon_max_width", icon_width)
		pending_button.disabled = true
		pending_button.custom_minimum_size.x = (
			_FRIEND_BUTTON_WIDTH)
		row.add_child(pending_button)
		return

	# Incoming request. Show Accept button.
	if client.has_incoming_request(
		backend_player_id,
	):
		var accept_button := Button.new()
		accept_button.text = (
			tr("FRIENDS.ACCEPT"))
		accept_button.custom_minimum_size.x = (
			_FRIEND_BUTTON_WIDTH)
		accept_button.pressed.connect(
			_on_accept_friend_pressed.bind(
				backend_player_id,
				accept_button))
		row.add_child(accept_button)
		_friend_action_buttons.append(
			accept_button)
		return

	# No relationship. Show Add Friend button.
	var add_button := Button.new()
	add_button.icon = _add_friend_icon
	add_button.expand_icon = true
	add_button.add_theme_constant_override(
		"icon_max_width", icon_width)
	add_button.custom_minimum_size.x = (
		_FRIEND_BUTTON_WIDTH)
	add_button.pressed.connect(
		_on_add_friend_pressed.bind(
			backend_player_id,
			add_button))
	row.add_child(add_button)
	_friend_action_buttons.append(add_button)


func _on_add_friend_pressed(
	backend_player_id: String,
	button: Button,
) -> void:
	if backend_player_id in _acted_friend_ids:
		return
	_acted_friend_ids[backend_player_id] = true
	button.disabled = true
	button.icon = _request_sent_icon

	Platform.friends\
		.send_request_by_player_id(
			backend_player_id, "recent_match")

	if not (Platform.friends
			.friend_request_sent
			.is_connected(
				_on_friend_request_result)):
		Platform.friends\
			.friend_request_sent.connect(
				_on_friend_request_result,
				CONNECT_ONE_SHOT)
		Platform.friends.request_failed\
			.connect(
				_on_friend_action_failed,
				CONNECT_ONE_SHOT)


func _on_accept_friend_pressed(
	backend_player_id: String,
	button: Button,
) -> void:
	if backend_player_id in _acted_friend_ids:
		return
	_acted_friend_ids[backend_player_id] = true
	button.disabled = true
	button.text = ""
	button.icon = _checkmark_icon
	button.expand_icon = true
	button.add_theme_constant_override(
		"icon_max_width",
		int(G.settings
			.get_icon_display_width()))

	Platform.friends.accept_request(
		backend_player_id)

	if not (Platform.friends
			.friend_request_accepted
			.is_connected(
				_on_friend_accept_result)):
		Platform.friends\
			.friend_request_accepted.connect(
				_on_friend_accept_result,
				CONNECT_ONE_SHOT)
		Platform.friends.request_failed\
			.connect(
				_on_friend_action_failed,
				CONNECT_ONE_SHOT)


func _on_friend_request_result(
	data: Dictionary,
) -> void:
	if (Platform.friends.request_failed
			.is_connected(
				_on_friend_action_failed)):
		Platform.friends.request_failed\
			.disconnect(_on_friend_action_failed)
	var result: String = data.get("result", "")
	if is_instance_valid(G.toast_overlay):
		match result:
			"request_sent":
				G.toast_overlay.show_toast(
					tr("FRIENDS.REQUEST_SENT"))
			"auto_accepted":
				G.toast_overlay.show_toast(
					tr("FRIENDS.ADDED"))
			"already_friends":
				G.toast_overlay.show_toast(
					tr("FRIENDS.ALREADY_FRIENDS"))
			"already_pending":
				G.toast_overlay.show_toast(
					tr("FRIENDS.ALREADY_PENDING"))


func _on_friend_accept_result(
	_data: Dictionary,
) -> void:
	if (Platform.friends.request_failed
			.is_connected(
				_on_friend_action_failed)):
		Platform.friends.request_failed\
			.disconnect(_on_friend_action_failed)
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("FRIENDS.ADDED"))


func _on_friend_action_failed(
	error: String,
) -> void:
	if (Platform.friends.friend_request_sent
			.is_connected(
				_on_friend_request_result)):
		Platform.friends.friend_request_sent\
			.disconnect(_on_friend_request_result)
	if (Platform.friends
			.friend_request_accepted
			.is_connected(
				_on_friend_accept_result)):
		Platform.friends\
			.friend_request_accepted\
			.disconnect(_on_friend_accept_result)
	# "Request in progress" is expected when the
	# friends API client is busy and not actionable.
	if error == "Request in progress":
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			error, G.toast_overlay.Type.ERROR)


func _on_friends_data_refreshed(
	_data: Dictionary,
) -> void:
	if not visible:
		return
	_populate_results()
	_build_focusable_list()
	_navigator.prime()


func _on_play_again_pressed() -> void:
	G.audio.play_sound("click")
	G.game_panel.client_play_again()


func _on_return_to_lobby_pressed() -> void:
	G.audio.play_sound("click")
	G.screens.client_open_screen(
		ScreensMain.ScreenType.LOBBY)


