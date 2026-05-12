class_name FriendDetailsPanel
extends SidePanel
## Sub-panel for a friend's details. Shows profile
## info and actions: invite to party, kick from
## party, and remove friend.


@export var _back_row_scene: PackedScene
@export var _invite_icon: Texture2D
@export var _kick_icon: Texture2D
@export var _remove_icon: Texture2D

var _friend_id: String
var _display_name: String
var _is_online: bool
var _invite_row: ActionRow
var _kick_row: ActionRow
var _remove_row: ActionRow


func set_friend_data(
	friend_id: String,
	display_name: String,
	is_online: bool,
) -> void:
	_friend_id = friend_id
	_display_name = display_name
	_is_online = is_online


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

	# Profile info row (non-focusable).
	var profile_container := HBoxContainer.new()
	profile_container.add_theme_constant_override(
		"separation", 8)
	profile_container.alignment = (
		BoxContainer.ALIGNMENT_CENTER)

	var dot_label := Label.new()
	dot_label.text = "●"
	if _is_online:
		dot_label.add_theme_color_override(
			"font_color", Color(0.3, 0.9, 0.3))
	else:
		dot_label.add_theme_color_override(
			"font_color", Color(0.5, 0.5, 0.5))
	profile_container.add_child(dot_label)

	var name_label := Label.new()
	name_label.text = _display_name
	name_label.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	profile_container.add_child(name_label)

	_row_container.add_child(profile_container)

	# Spacer.
	var name_spacer := Control.new()
	name_spacer.custom_minimum_size = (
		Vector2(0, 8))
	_row_container.add_child(name_spacer)

	# Invite to party row.
	_invite_row = ActionRow.new()
	_invite_row.setup_actions(
		_on_invite_pressed, _on_invite_pressed)
	_invite_row.setup_label(
		tr("PARTY.INVITE_TO_PARTY"), _invite_icon)
	_invite_row.disabled = not _is_online
	_row_container.add_child(_invite_row)
	_connect_row_clicked(_invite_row)

	# Kick from party row (conditional).
	_kick_row = ActionRow.new()
	_kick_row.setup_actions(
		_on_kick_pressed, _on_kick_pressed)
	_kick_row.setup_label(
		tr("PARTY.KICK"), _kick_icon)
	_kick_row.visible = _is_friend_in_party()
	_row_container.add_child(_kick_row)
	_connect_row_clicked(_kick_row)

	# Remove friend row.
	_remove_row = ActionRow.new()
	_remove_row.setup_actions(
		_on_remove_pressed, _on_remove_pressed)
	_remove_row.setup_label(
		tr("FRIENDS.REMOVE"), _remove_icon)
	_row_container.add_child(_remove_row)
	_connect_row_clicked(_remove_row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)

	# Connect API signals.
	G.party_api_client.party_invited.connect(
		_on_invite_response)
	G.party_api_client.party_kicked.connect(
		_on_kick_response)
	G.friends_api_client.friend_removed.connect(
		_on_remove_response)
	G.party_api_client.request_failed.connect(
		_on_party_request_failed)
	G.friends_api_client.request_failed.connect(
		_on_friends_request_failed)


func _exit_tree() -> void:
	var party_client := G.party_api_client
	if is_instance_valid(party_client):
		if party_client.party_invited\
				.is_connected(
					_on_invite_response):
			party_client.party_invited\
				.disconnect(_on_invite_response)
		if party_client.party_kicked\
				.is_connected(
					_on_kick_response):
			party_client.party_kicked\
				.disconnect(_on_kick_response)
		if party_client.request_failed\
				.is_connected(
					_on_party_request_failed):
			party_client.request_failed\
				.disconnect(
					_on_party_request_failed)

	var friends_client := G.friends_api_client
	if is_instance_valid(friends_client):
		if friends_client.friend_removed\
				.is_connected(
					_on_remove_response):
			friends_client.friend_removed\
				.disconnect(_on_remove_response)
		if friends_client.request_failed\
				.is_connected(
					_on_friends_request_failed):
			friends_client.request_failed\
				.disconnect(
					_on_friends_request_failed)


func _is_friend_in_party() -> bool:
	if not G.party_manager.is_in_party():
		return false
	if not G.party_manager.is_leader():
		return false
	var members: Array = (
		G.party_manager.current_party
			.get("members", []))
	for m in members:
		if m is Dictionary and m.get("user_id", "") == _friend_id:
			return true
	return false


func _on_invite_pressed() -> void:
	_invite_row.disabled = true
	G.party_manager.invite_friend(_friend_id)
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("PARTY.INVITE_SENT")
			% _display_name)


func _on_kick_pressed() -> void:
	open_confirm_dialog(
		tr("CONFIRM.KICK") % _display_name,
		tr("PARTY.KICK"),
		func() -> void:
			_kick_row.disabled = true
			G.party_manager.kick_member(
				_friend_id),
		tr("CONFIRM.CANCEL"),
	)


func _on_remove_pressed() -> void:
	open_confirm_dialog(
		tr("CONFIRM.REMOVE_FRIEND")
		% _display_name,
		tr("FRIENDS.REMOVE"),
		func() -> void:
			_remove_row.disabled = true
			G.friends_api_client.remove_friend(
				_friend_id),
		tr("CONFIRM.CANCEL"),
	)


func _on_invite_response(
	_data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(manager):
		manager.pop_panel()


func _on_kick_response(
	_data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(manager):
		manager.pop_panel()


func _on_remove_response(
	_data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(manager):
		manager.pop_panel()


func _on_party_request_failed(
	_error: String,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(_invite_row):
		_invite_row.disabled = not _is_online
	if is_instance_valid(_kick_row):
		_kick_row.disabled = false


func _on_friends_request_failed(
	_error: String,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(_remove_row):
		_remove_row.disabled = false
