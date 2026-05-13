class_name FriendRequestPanel
extends SidePanel
## Sub-panel for handling an incoming friend
## request. Shows the sender's name with separate
## accept and reject action rows.


@export var _back_row_scene: PackedScene
@export var _accept_icon: Texture2D
@export var _reject_icon: Texture2D

var _friend_id: String
var _display_name: String
var _accept_row: ActionRow
var _reject_row: ActionRow


func set_friend_data(
	friend_id: String,
	display_name: String,
) -> void:
	_friend_id = friend_id
	_display_name = display_name


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

	# Player name header.
	var name_label := Label.new()
	name_label.text = _display_name
	name_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	name_label.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	_row_container.add_child(name_label)

	# Spacer.
	var name_spacer := Control.new()
	name_spacer.custom_minimum_size = (
		Vector2(0, 8))
	_row_container.add_child(name_spacer)

	# Accept row.
	_accept_row = ActionRow.new()
	_accept_row.setup_actions(
		_on_accept_pressed, _on_accept_pressed)
	_accept_row.setup_label(
		tr("FRIENDS.ACCEPT"), _accept_icon)
	_row_container.add_child(_accept_row)
	_connect_row_clicked(_accept_row)

	# Reject row.
	_reject_row = ActionRow.new()
	_reject_row.setup_actions(
		_on_reject_pressed, _on_reject_pressed)
	_reject_row.setup_label(
		tr("FRIENDS.REJECT"), _reject_icon)
	_row_container.add_child(_reject_row)
	_connect_row_clicked(_reject_row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)

	# Connect API signals to pop panel on response.
	Platform.friends\
		.friend_request_accepted.connect(
			_on_response)
	Platform.friends\
		.friend_request_rejected.connect(
			_on_response)
	Platform.friends.request_failed.connect(
		_on_request_failed)


func _exit_tree() -> void:
	var client: PlatformFriendsApiClient = Platform.friends
	if not is_instance_valid(client):
		return
	if client.friend_request_accepted.is_connected(
			_on_response):
		client.friend_request_accepted.disconnect(
			_on_response)
	if client.friend_request_rejected.is_connected(
			_on_response):
		client.friend_request_rejected.disconnect(
			_on_response)
	if client.request_failed.is_connected(
			_on_request_failed):
		client.request_failed.disconnect(
			_on_request_failed)


func _on_accept_pressed() -> void:
	if is_instance_valid(_accept_row):
		_accept_row.disabled = true
	if is_instance_valid(_reject_row):
		_reject_row.disabled = true
	Platform.friends.accept_request(
		_friend_id)


func _on_reject_pressed() -> void:
	if is_instance_valid(_accept_row):
		_accept_row.disabled = true
	if is_instance_valid(_reject_row):
		_reject_row.disabled = true
	Platform.friends.reject_request(
		_friend_id)


func _on_response(
	_data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(manager):
		manager.pop_panel()


func _on_request_failed(
	_error: String,
) -> void:
	if is_queued_for_deletion():
		return
	# Re-enable rows so the user can retry.
	if is_instance_valid(_accept_row):
		_accept_row.disabled = false
	if is_instance_valid(_reject_row):
		_reject_row.disabled = false
