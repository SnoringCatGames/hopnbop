class_name RecentPlayersPanel
extends SidePanel
## Sub-panel that lists the player's recent opponents from
## non-synthetic matches. Each row offers a one-tap "Add Friend"
## action that fires Platform.friends.send_request_by_player_id.
## Players who are already friends or who have an in-flight
## friend request are filtered out so the list stays focused on
## actionable items. Backed by Platform.friends's
## cached_recent_players + fetch_recent_players RPC (Stage 7.6).


@export var _back_row_scene: PackedScene
@export var _loading_spinner_scene: PackedScene
@export var _add_friend_icon: Texture2D

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
	header.text = tr("FRIENDS.RECENT_PLAYERS")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

	# Bottom padding. Repositioned after dynamic content on
	# each refresh.
	_bottom_spacer = Control.new()
	_bottom_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(_bottom_spacer)

	# Connect API signals.
	Platform.friends.recent_players_received.connect(
		_on_recent_players_received)
	Platform.friends.friend_request_sent.connect(
		_on_friend_request_sent)
	Platform.friends.request_failed.connect(
		_on_request_failed)

	_refresh()


func _exit_tree() -> void:
	var client: PlatformFriendsApiClient = Platform.friends
	if not is_instance_valid(client):
		return
	if client.recent_players_received.is_connected(
			_on_recent_players_received):
		client.recent_players_received.disconnect(
			_on_recent_players_received)
	if client.friend_request_sent.is_connected(
			_on_friend_request_sent):
		client.friend_request_sent.disconnect(
			_on_friend_request_sent)
	if client.request_failed.is_connected(_on_request_failed):
		client.request_failed.disconnect(_on_request_failed)


func _refresh() -> void:
	var client: PlatformFriendsApiClient = Platform.friends
	if not client.cached_recent_players.is_empty():
		# Show cached data immediately; the response re-
		# populates silently.
		_populate(client.cached_recent_players)
	else:
		_is_loading = true
		if is_instance_valid(_loading_spinner):
			_loading_spinner.visible = true
	if not client.is_recent_players_busy():
		client.fetch_recent_players()


func _on_recent_players_received(data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	_is_loading = false
	if is_instance_valid(_loading_spinner):
		_loading_spinner.visible = false
	var entries: Array = data.get("recent_players", [])
	_populate(entries)


func _on_friend_request_sent(_data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(tr("FRIENDS.ADDED"))
	# Repaint so the just-added player drops out of the
	# actionable list. cached_recent_players doesn't change; the
	# add filter does (now there's a sent-request entry).
	_populate(Platform.friends.cached_recent_players)


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

	# Filter out players the user is already friends with, has a
	# pending outgoing request to, or has blocked. Those rows
	# would just bounce off the existing friends-add logic and
	# clutter the list. Already-incoming-request entries stay
	# visible — the "Add Friend" tap on those becomes an auto-
	# accept via Nakama's bidirectional add semantics.
	var client: PlatformFriendsApiClient = Platform.friends
	var actionable: Array = []
	for entry in entries:
		var pid: String = entry.get("player_id", "")
		if pid.is_empty():
			continue
		if client.is_friend(pid):
			continue
		if client.has_sent_request(pid):
			continue
		if client.is_blocked(pid):
			continue
		actionable.append(entry)

	if actionable.is_empty():
		var empty_label := Label.new()
		empty_label.text = tr("FRIENDS.NO_RECENT_PLAYERS")
		empty_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER)
		empty_label.autowrap_mode = (
			TextServer.AUTOWRAP_WORD_SMART)
		empty_label.add_theme_color_override(
			"font_color", Color(0.6, 0.6, 0.6))
		_row_container.add_child(empty_label)
		_dynamic_nodes.append(empty_label)
	else:
		for entry in actionable:
			_add_row(entry)

	_row_container.add_child(_bottom_spacer)
	rebuild_row_list()


func _add_row(entry: Dictionary) -> void:
	var player_id: String = entry.get("player_id", "")
	var display_name: String = entry.get("display_name", "")
	if display_name.is_empty():
		display_name = entry.get("username", player_id)

	var row := ActionRow.new()

	var add_action := func() -> void:
		row.disabled = true
		Platform.friends.send_request_by_player_id(player_id)

	row.setup_action(add_action)
	row.setup_label(
		"%s — %s" % [display_name, tr("FRIENDS.ADD")],
		_add_friend_icon)
	_row_container.add_child(row)
	_connect_row_clicked(row)
	_dynamic_nodes.append(row)
