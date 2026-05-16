class_name BlockedUsersPanel
extends SidePanel
## Sub-panel that lists the player's blocked users with an
## unblock action per row. Backed by Platform.friends's
## cached_blocked_users + fetch_blocked_users RPC (Stage 7.4).


@export var _back_row_scene: PackedScene
@export var _loading_spinner_scene: PackedScene
@export var _unblock_icon: Texture2D

var _loading_spinner: LoadingSpinner
var _bottom_spacer: Control
var _dynamic_nodes: Array[Node] = []
var _is_loading := false


func build_ui() -> void:
	# Top padding.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(top_spacer)

	# Back row.
	var back_row: BackRow = _back_row_scene.instantiate()
	back_row.setup(self)
	_row_container.add_child(back_row)
	_connect_row_clicked(back_row)

	# Spacer below back button.
	var back_spacer := Control.new()
	back_spacer.custom_minimum_size = Vector2(0, 20)
	_row_container.add_child(back_spacer)

	# Header.
	var header := Label.new()
	header.text = tr("FRIENDS.BLOCKED_USERS")
	header.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	header.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	_row_container.add_child(header)

	# Spacer.
	var header_spacer := Control.new()
	header_spacer.custom_minimum_size = Vector2(0, 16)
	_row_container.add_child(header_spacer)

	# Loading spinner.
	_loading_spinner = _loading_spinner_scene.instantiate()
	_loading_spinner.visible = false
	_row_container.add_child(_loading_spinner)

	# Bottom padding. Repositioned after dynamic content
	# on each refresh.
	_bottom_spacer = Control.new()
	_bottom_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(_bottom_spacer)

	# Connect API signals.
	Platform.friends.blocked_users_received.connect(
		_on_blocked_users_received)
	Platform.friends.user_unblocked.connect(
		_on_user_unblocked)
	Platform.friends.request_failed.connect(
		_on_request_failed)

	_refresh()


func _exit_tree() -> void:
	var client: PlatformFriendsApiClient = Platform.friends
	if not is_instance_valid(client):
		return
	if client.blocked_users_received.is_connected(
			_on_blocked_users_received):
		client.blocked_users_received.disconnect(
			_on_blocked_users_received)
	if client.user_unblocked.is_connected(
			_on_user_unblocked):
		client.user_unblocked.disconnect(
			_on_user_unblocked)
	if client.request_failed.is_connected(
			_on_request_failed):
		client.request_failed.disconnect(
			_on_request_failed)


func _refresh() -> void:
	var client: PlatformFriendsApiClient = Platform.friends
	if not client.cached_blocked_users.is_empty():
		# Show cached data immediately; the response
		# re-populates silently.
		_populate(client.cached_blocked_users)
	else:
		_is_loading = true
		if is_instance_valid(_loading_spinner):
			_loading_spinner.visible = true
	if not client.is_blocked_users_busy():
		client.fetch_blocked_users()


func _on_blocked_users_received(data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	_is_loading = false
	if is_instance_valid(_loading_spinner):
		_loading_spinner.visible = false
	var entries: Array = data.get("blocked_users", [])
	_populate(entries)


func _on_user_unblocked(_data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.USER_UNBLOCKED"))
	_populate(Platform.friends.cached_blocked_users)


func _on_request_failed(error: String) -> void:
	if is_queued_for_deletion():
		return
	_is_loading = false
	if is_instance_valid(_loading_spinner):
		_loading_spinner.visible = false
	if error == "Request in progress":
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			error, G.toast_overlay.Type.ERROR)


func _populate(entries: Array) -> void:
	for node in _dynamic_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_dynamic_nodes.clear()

	_row_container.remove_child(_bottom_spacer)

	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = tr("FRIENDS.NO_BLOCKED_USERS")
		empty_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER)
		empty_label.autowrap_mode = (
			TextServer.AUTOWRAP_WORD_SMART)
		empty_label.add_theme_color_override(
			"font_color", Color(0.6, 0.6, 0.6))
		_row_container.add_child(empty_label)
		_dynamic_nodes.append(empty_label)
	else:
		for entry in entries:
			_add_row(entry)

	_row_container.add_child(_bottom_spacer)
	rebuild_row_list()


func _add_row(entry: Dictionary) -> void:
	var blocked_id: String = entry.get("player_id", "")
	var display_name: String = entry.get("display_name", "")
	if display_name.is_empty():
		display_name = entry.get("username", blocked_id)

	var row := ActionRow.new()

	var unblock_action := func() -> void:
		row.disabled = true
		Platform.friends.unblock_user(blocked_id)

	row.setup_action(unblock_action)
	row.setup_label(
		"%s — %s" % [display_name, tr("FRIENDS.UNBLOCK")],
		_unblock_icon)
	_row_container.add_child(row)
	_connect_row_clicked(row)
	_dynamic_nodes.append(row)
