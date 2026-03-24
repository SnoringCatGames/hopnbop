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

var _friend_code_label: Label
var _add_input: LineEdit
var _add_button: Button
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

	# Add friend section.
	_build_add_friend_section()

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
	G.friends_api_client.friends_received.connect(
		_on_friends_received)
	G.friends_api_client\
		.friend_request_sent.connect(
			_on_friend_request_sent)
	G.friends_api_client\
		.friend_request_accepted.connect(
			_on_friend_request_accepted)
	G.friends_api_client\
		.friend_request_rejected.connect(
			_on_friend_request_rejected)
	G.friends_api_client\
		.friend_request_cancelled.connect(
			_on_friend_request_cancelled)
	G.friends_api_client.friend_removed.connect(
		_on_friend_removed)
	G.friends_api_client.request_failed.connect(
		_on_request_failed)

	# Fetch friends list. mark_seen is called after
	# the list loads to avoid blocking the shared
	# HTTPRequest node.
	_refresh_friends()


func _exit_tree() -> void:
	var client := G.friends_api_client
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
	]
	var callbacks: Array[Callable] = [
		_on_friends_received,
		_on_friend_request_sent,
		_on_friend_request_accepted,
		_on_friend_request_rejected,
		_on_friend_request_cancelled,
		_on_friend_removed,
		_on_request_failed,
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
	copy_button.text = " [+] "
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


func _build_add_friend_section() -> void:
	var add_row := ActionRow.new()
	add_row.setup_actions(
		_on_add_friend_pressed,
		_on_add_friend_pressed)

	var add_container := HBoxContainer.new()
	add_container.add_theme_constant_override(
		"separation", 8)
	add_container.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	add_row.add_child(add_container)

	_add_input = LineEdit.new()
	_add_input.placeholder_text = (
		tr("FRIENDS.ENTER_CODE"))
	_add_input.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	_add_input.max_length = 6
	add_container.add_child(_add_input)

	_add_button = Button.new()
	_add_button.text = tr("FRIENDS.ADD")
	_add_button.icon = _add_friend_icon
	_add_button.expand_icon = true
	_add_button.pressed.connect(
		_on_add_friend_pressed)
	add_container.add_child(_add_button)

	_row_container.add_child(add_row)
	_connect_row_clicked(add_row)


func _refresh_friends() -> void:
	_is_loading = true
	if is_instance_valid(_loading_spinner):
		_loading_spinner.visible = true
	G.friends_api_client.fetch_friends()


func _on_profile_received(
	data: Dictionary,
) -> void:
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


func _on_add_friend_pressed() -> void:
	var code := (
		_add_input.text.strip_edges().to_upper())
	if code.is_empty():
		return
	_add_button.disabled = true
	G.friends_api_client.send_request_by_code(code)


func _on_friend_request_sent(
	data: Dictionary,
) -> void:
	_add_button.disabled = false
	_add_input.text = ""
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
	_refresh_friends()


func _on_friend_request_accepted(
	_data: Dictionary,
) -> void:
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("FRIENDS.ADDED"))
	_refresh_friends()


func _on_friend_request_rejected(
	_data: Dictionary,
) -> void:
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("FRIENDS.REMOVED"))
	_refresh_friends()


func _on_friend_request_cancelled(
	_data: Dictionary,
) -> void:
	_refresh_friends()


func _on_friend_removed(
	_data: Dictionary,
) -> void:
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("FRIENDS.REMOVED"))
	_refresh_friends()


func _on_friends_received(
	data: Dictionary,
) -> void:
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
	G.friends_api_client.mark_seen()


func _on_request_failed(error: String) -> void:
	_is_loading = false
	if is_instance_valid(_loading_spinner):
		_loading_spinner.visible = false
	if is_instance_valid(_add_button):
		_add_button.disabled = false
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			error, G.toast_overlay.Type.ERROR)


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

	var accept_button := Button.new()
	accept_button.text = tr("FRIENDS.ACCEPT")
	content.add_child(accept_button)

	var reject_button := Button.new()
	reject_button.text = tr("FRIENDS.REJECT")
	content.add_child(reject_button)

	var accept_action := func() -> void:
		accept_button.disabled = true
		G.friends_api_client.accept_request(
			friend_id)

	var reject_action := func() -> void:
		reject_button.disabled = true
		G.friends_api_client.reject_request(
			friend_id)

	accept_button.pressed.connect(accept_action)
	reject_button.pressed.connect(reject_action)
	row.setup_actions(
		accept_action, reject_action)

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

	# Invite to party button.
	var invite_button := Button.new()
	invite_button.text = (
		tr("FRIENDS.INVITE_TO_PARTY"))
	content.add_child(invite_button)

	var remove_button := Button.new()
	remove_button.icon = _remove_friend_icon
	remove_button.expand_icon = true
	content.add_child(remove_button)

	var invite_action := func() -> void:
		invite_button.disabled = true
		G.party_manager.invite_friend(friend_id)
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("PARTY.INVITE"))

	var remove_action := func() -> void:
		G.friends_api_client.remove_friend(
			friend_id)

	invite_button.pressed.connect(invite_action)
	remove_button.pressed.connect(remove_action)
	# Right/trigger invites. Left removes.
	row.setup_actions(
		invite_action, remove_action)

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
		G.friends_api_client.cancel_request(
			friend_id)

	cancel_button.pressed.connect(cancel_action)
	row.setup_actions(cancel_action, cancel_action)

	_row_container.add_child(row)
	_connect_row_clicked(row)
	_dynamic_nodes.append(row)
