class_name FriendsPanel
extends SidePanel
## Friends sub-panel. Displays the player's friend
## code, an add-friend input, and three sections:
## incoming requests, accepted friends, and sent
## requests. All interactive elements are ActionRow
## instances for U/D + L/R navigation.


@export var _back_row_scene: PackedScene
@export var _loading_spinner_scene: PackedScene
@export var _add_friend_icon: Texture2D
@export var _remove_friend_icon: Texture2D
@export var _block_icon: Texture2D
@export var _copy_icon: Texture2D
@export var _sub_panel_trigger_row_scene: PackedScene
@export var _add_friend_panel_scene: PackedScene
@export var _friend_request_panel_scene: PackedScene
@export var _friend_details_panel_scene: PackedScene
@export var _blocked_users_panel_scene: PackedScene

var _friend_code_label: Label
var _is_loading := false
var _loading_spinner: LoadingSpinner
var _bottom_spacer: Control
var _dynamic_nodes: Array[Node] = []


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

	# Friend code display row.
	_build_friend_code_section()

	# Spacer.
	var code_spacer := Control.new()
	code_spacer.custom_minimum_size = (
		Vector2(0, 16))
	_row_container.add_child(code_spacer)

	# Add friend trigger row — opens sub-panel.
	var add_row: SubPanelTriggerRow = (
		_sub_panel_trigger_row_scene.instantiate())
	add_row.set_icon(_add_friend_icon)
	add_row.setup(
		tr("FRIENDS.ADD"),
		_add_friend_panel_scene,
		self)
	_row_container.add_child(add_row)
	_connect_row_clicked(add_row)

	# Blocked users trigger row — opens sub-panel (Stage 7.4).
	var blocked_row: SubPanelTriggerRow = (
		_sub_panel_trigger_row_scene.instantiate())
	blocked_row.set_icon(_block_icon)
	blocked_row.setup(
		tr("FRIENDS.BLOCKED_USERS"),
		_blocked_users_panel_scene,
		self)
	_row_container.add_child(blocked_row)
	_connect_row_clicked(blocked_row)

	# Spacer.
	var list_spacer := Control.new()
	list_spacer.custom_minimum_size = (
		Vector2(0, 16))
	_row_container.add_child(list_spacer)

	# Loading spinner. Shown while fetching
	# friends, hidden when data arrives.
	_loading_spinner = (
		_loading_spinner_scene.instantiate())
	_loading_spinner.visible = false
	_row_container.add_child(_loading_spinner)

	# Bottom padding. Repositioned after dynamic
	# content on each refresh.
	_bottom_spacer = Control.new()
	_bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(_bottom_spacer)

	# Connect API signals.
	Platform.friends.friends_received.connect(
		_on_friends_received)
	Platform.friends\
		.friend_request_sent.connect(
			_on_friend_request_sent)
	Platform.friends\
		.friend_request_accepted.connect(
			_on_friend_request_accepted)
	Platform.friends\
		.friend_request_rejected.connect(
			_on_friend_request_rejected)
	Platform.friends\
		.friend_request_cancelled.connect(
			_on_friend_request_cancelled)
	Platform.friends.friend_removed.connect(
		_on_friend_removed)
	Platform.friends.request_failed.connect(
		_on_request_failed)
	Platform.presence.presence_received.connect(
		_on_presence_received)

	# Fetch friends list. mark_seen is called after
	# the list loads to avoid blocking the shared
	# HTTPRequest node.
	_refresh_friends()


func _exit_tree() -> void:
	var client: PlatformFriendsApiClient = Platform.friends
	var presence: PlatformPresenceApiClient = (
		Platform.presence)
	if not is_instance_valid(client):
		return
	var signals_to_disconnect: Array[Signal] = [
		client.friends_received,
		client.friend_request_sent,
		client.friend_request_accepted,
		client.friend_request_rejected,
		client.friend_request_cancelled,
		client.friend_removed,
		client.request_failed,
		presence.presence_received,
	]
	var callbacks: Array[Callable] = [
		_on_friends_received,
		_on_friend_request_sent,
		_on_friend_request_accepted,
		_on_friend_request_rejected,
		_on_friend_request_cancelled,
		_on_friend_removed,
		_on_request_failed,
		_on_presence_received,
	]
	for i in signals_to_disconnect.size():
		if signals_to_disconnect[i].is_connected(
				callbacks[i]):
			signals_to_disconnect[i].disconnect(
				callbacks[i])


func _build_friend_code_section() -> void:
	var code_row := ActionRow.new()
	code_row.setup_actions(
		_on_copy_code_pressed,
		_on_copy_code_pressed)

	var code_container := HBoxContainer.new()
	code_container.alignment = (
		BoxContainer.ALIGNMENT_CENTER)
	code_container.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	code_row.add_child(code_container)

	var code_header := Label.new()
	code_header.text = (
		tr("FRIENDS.YOUR_CODE") + ": ")
	code_container.add_child(code_header)

	_friend_code_label = Label.new()
	_friend_code_label.text = "..."
	_friend_code_label.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	code_container.add_child(_friend_code_label)

	var copy_button := Button.new()
	copy_button.icon = _copy_icon
	copy_button.expand_icon = true
	copy_button.pressed.connect(
		_on_copy_code_pressed)
	code_container.add_child(copy_button)

	_row_container.add_child(code_row)
	_connect_row_clicked(code_row)

	# Fetch profile to get friend code.
	if not G.backend_api_client.profile_received\
			.is_connected(_on_profile_received):
		G.backend_api_client.profile_received\
			.connect(_on_profile_received)
	G.backend_api_client.fetch_player_profile()



func _refresh_friends() -> void:
	var client: PlatformFriendsApiClient = Platform.friends
	var has_cache := (
		not client.cached_friends.is_empty()
		or not client.cached_sent_requests.is_empty()
		or not client.cached_incoming_requests
			.is_empty()
	)
	if has_cache:
		# Show cached data immediately; the server
		# response will re-populate silently.
		_populate_all_sections(
			client.cached_friends,
			client.cached_sent_requests,
			client.cached_incoming_requests,
		)
	else:
		_is_loading = true
		if is_instance_valid(_loading_spinner):
			_loading_spinner.visible = true
	# Skip the fetch if the client is already
	# handling a request. This panel is connected
	# to friends_received, so the in-flight
	# response will arrive when it completes.
	if not client.is_busy():
		client.fetch_friends()


func _on_profile_received(
	data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	var player: Dictionary = data.get("player", {})
	var code: String = player.get("friend_code", "")
	if not code.is_empty():
		_friend_code_label.text = code
	if G.backend_api_client.profile_received\
			.is_connected(_on_profile_received):
		G.backend_api_client.profile_received\
			.disconnect(_on_profile_received)


func _on_copy_code_pressed() -> void:
	var code: String = _friend_code_label.text
	if code == "...":
		return
	DisplayServer.clipboard_set(code)
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("FRIENDS.CODE_COPIED"))


func _on_friend_request_sent(
	_data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	# Toast and button handling are in
	# AddFriendPanel. Refresh the list here so it
	# is up to date when the sub-panel pops.
	_refresh_friends()


func _on_friend_request_accepted(
	_data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("FRIENDS.ADDED"))
	_refresh_friends()


func _on_friend_request_rejected(
	_data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("FRIENDS.REMOVED"))
	_refresh_friends()


func _on_friend_request_cancelled(
	_data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	_refresh_friends()


func _on_friend_removed(
	_data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("FRIENDS.REMOVED"))
	_refresh_friends()


func _on_friends_received(
	data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	_is_loading = false
	if is_instance_valid(_loading_spinner):
		_loading_spinner.visible = false
	var friends: Array = data.get("friends", [])
	var sent: Array = data.get(
		"sent_requests", [])
	var incoming: Array = data.get(
		"incoming_requests", [])
	_populate_all_sections(
		friends, sent, incoming)
	# Mark notifications as seen now that the list
	# has loaded and the HTTPRequest node is free.
	if not Platform.friends.is_busy():
		Platform.friends.mark_seen()


func _on_request_failed(error: String) -> void:
	if is_queued_for_deletion():
		return
	_is_loading = false
	if is_instance_valid(_loading_spinner):
		_loading_spinner.visible = false
	# "Request in progress" is expected during
	# rapid panel navigation and not actionable.
	if error == "Request in progress":
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			error, G.toast_overlay.Type.ERROR)


func _on_presence_received(
	_online_ids: Array[String],
) -> void:
	if is_queued_for_deletion():
		return
	if _is_loading:
		return
	_populate_all_sections(
		Platform.friends.cached_friends,
		Platform.friends.cached_sent_requests,
		Platform.friends.cached_incoming_requests,
	)


func _populate_all_sections(
	friends: Array,
	sent: Array,
	incoming: Array,
) -> void:
	# Clear previous dynamic rows.
	for node in _dynamic_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_dynamic_nodes.clear()

	# Remove bottom spacer so dynamic content is
	# added before it.
	_row_container.remove_child(_bottom_spacer)

	var has_any := (
		not friends.is_empty()
		or not sent.is_empty()
		or not incoming.is_empty()
	)

	if not has_any:
		var empty_label := Label.new()
		empty_label.text = tr("FRIENDS.EMPTY")
		empty_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER)
		empty_label.autowrap_mode = (
			TextServer.AUTOWRAP_WORD_SMART)
		empty_label.add_theme_color_override(
			"font_color", Color(0.6, 0.6, 0.6))
		_row_container.add_child(empty_label)
		_dynamic_nodes.append(empty_label)
	else:
		# Incoming requests section.
		if not incoming.is_empty():
			_add_section_header(
				tr("FRIENDS.INCOMING_REQUESTS"),
				Color(1.0, 0.85, 0.3),
				incoming.size())
			for entry in incoming:
				_add_incoming_row(entry)
			_add_section_spacer()

		# Friends section.
		if not friends.is_empty():
			_add_section_header(
				tr("FRIENDS.FRIENDS_LIST"),
				Color(1.0, 1.0, 1.0))
			for entry in friends:
				_add_friend_row(entry)
			_add_section_spacer()

		# Sent requests section.
		if not sent.is_empty():
			_add_section_header(
				tr("FRIENDS.SENT_REQUESTS"),
				Color(0.6, 0.6, 0.6))
			for entry in sent:
				_add_sent_row(entry)

	# Re-add bottom spacer at the end.
	_row_container.add_child(_bottom_spacer)

	rebuild_row_list()


func _add_section_header(
	text: String,
	color: Color,
	count: int = -1,
) -> void:
	var header := Label.new()
	if count >= 0:
		header.text = "%s (%d)" % [text, count]
	else:
		header.text = text
	header.add_theme_color_override(
		"font_color", color)
	_row_container.add_child(header)
	_dynamic_nodes.append(header)


func _add_section_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_row_container.add_child(spacer)
	_dynamic_nodes.append(spacer)


func _add_incoming_row(
	entry: Dictionary,
) -> void:
	var friend_id: String = entry.get(
		"player_id", "")
	var display_name: String = entry.get(
		"display_name", "Unknown")

	var row := ActionRow.new()

	var open_action := func() -> void:
		var panel: FriendRequestPanel = (
			_friend_request_panel_scene
				.instantiate())
		panel.set_friend_data(
			friend_id, display_name)
		manager.push_panel(panel)

	row.setup_actions(open_action, open_action)

	var content := HBoxContainer.new()
	content.add_theme_constant_override(
		"separation", 8)
	content.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	row.add_child(content)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	content.add_child(name_label)

	var arrow := TextureRect.new()
	arrow.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE)
	arrow.stretch_mode = (
		TextureRect
			.STRETCH_KEEP_ASPECT_CENTERED)
	arrow.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	content.add_child(arrow)
	row._setup_chevron(arrow)

	_row_container.add_child(row)
	_connect_row_clicked(row)
	_dynamic_nodes.append(row)


func _add_friend_row(
	entry: Dictionary,
) -> void:
	var friend_id: String = entry.get(
		"player_id", "")
	var display_name: String = entry.get(
		"display_name", "Unknown")

	var is_online: bool = (
		Platform.presence.cached_online_ids
		.has(friend_id))

	# Rich presence (game_id, status, rich_presence string)
	# is opportunistically populated by PlatformPresenceApiClient when
	# the platform stack returns the rich response shape. Pre-
	# rich-rollout deploys leave this as an empty Dictionary.
	var rich: Dictionary = (
		Platform.presence.cached_online_friends
			.get(friend_id, {})
	)
	var friend_game_id: String = rich.get(
		"game_id", "")
	var friend_rich_text: String = rich.get(
		"rich_presence", "")
	# Compare against the addon-resolved Platform.game_id
	# (Stage 3.4) so a friend in a different game gets the
	# "in another game" badge color. Falls back to "" when the
	# Platform autoload hasn't initialized yet — in that case
	# every same-game friend would render as "other game",
	# which is preferable to mis-rendering as same-game.
	var is_in_other_game: bool = (
		is_online
		and not friend_game_id.is_empty()
		and friend_game_id != Platform.game_id
	)

	var row := ActionRow.new()

	var open_action := func() -> void:
		var panel: FriendDetailsPanel = (
			_friend_details_panel_scene
				.instantiate())
		panel.set_friend_data(
			friend_id, display_name, is_online)
		manager.push_panel(panel)

	row.setup_actions(open_action, open_action)

	var content := HBoxContainer.new()
	content.add_theme_constant_override(
		"separation", 8)
	content.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	row.add_child(content)

	var dot_label := Label.new()
	dot_label.text = "●"
	if is_in_other_game:
		# Cyan: online but in a different game on the
		# platform. Party invites to this friend will be
		# rejected by the backend with CROSS_GAME_INVITE.
		dot_label.add_theme_color_override(
			"font_color", Color(0.3, 0.7, 1.0))
	elif is_online:
		dot_label.add_theme_color_override(
			"font_color", Color(0.3, 0.9, 0.3))
	else:
		dot_label.add_theme_color_override(
			"font_color", Color(0.5, 0.5, 0.5))
	content.add_child(dot_label)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	content.add_child(name_label)

	# Subtitle: rich_presence string ("In lobby", "In match")
	# or the other-game label. Falls back to nothing for
	# friends online in our game with no rich text.
	var subtitle_text := ""
	if is_in_other_game:
		# Show the friend's current game_id until the
		# games-config download lands; that will let us
		# substitute the friendly display name.
		subtitle_text = (
			tr("PRESENCE.IN_OTHER_GAME")
			% friend_game_id
		)
	elif is_online and not friend_rich_text.is_empty():
		subtitle_text = friend_rich_text
	if not subtitle_text.is_empty():
		var subtitle := Label.new()
		subtitle.text = subtitle_text
		subtitle.add_theme_color_override(
			"font_color", Color(0.6, 0.6, 0.6))
		content.add_child(subtitle)

	var arrow := TextureRect.new()
	arrow.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE)
	arrow.stretch_mode = (
		TextureRect
			.STRETCH_KEEP_ASPECT_CENTERED)
	arrow.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	content.add_child(arrow)
	row._setup_chevron(arrow)

	_row_container.add_child(row)
	_connect_row_clicked(row)
	_dynamic_nodes.append(row)


func _add_sent_row(
	entry: Dictionary,
) -> void:
	var friend_id: String = entry.get(
		"player_id", "")
	var display_name: String = entry.get(
		"display_name", "Unknown")

	var row := ActionRow.new()

	var content := HBoxContainer.new()
	content.add_theme_constant_override(
		"separation", 8)
	content.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	row.add_child(content)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	content.add_child(name_label)

	var cancel_button := Button.new()
	cancel_button.text = (
		tr("FRIENDS.CANCEL_REQUEST"))
	content.add_child(cancel_button)

	var cancel_action := func() -> void:
		cancel_button.disabled = true
		Platform.friends.cancel_request(
			friend_id)

	cancel_button.pressed.connect(cancel_action)
	row.setup_actions(cancel_action, cancel_action)

	_row_container.add_child(row)
	_connect_row_clicked(row)
	_dynamic_nodes.append(row)
