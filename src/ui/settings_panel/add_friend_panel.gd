class_name AddFriendPanel
extends SidePanel
## Sub-panel for sending a friend request by
## friend code. Contains a text input row for
## entering the code and a send-request button
## that enables only when the code is long enough.


@export var _back_row_scene: PackedScene
@export var _text_input_row_scene: PackedScene
@export var _add_friend_icon: Texture2D

const _MIN_CODE_LENGTH := 6

var _code_input: TextInputRow
var _send_row: ActionRow


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

	# Friend code text input row.
	_code_input = (
		_text_input_row_scene.instantiate())
	_code_input.setup(
		tr("FRIENDS.ENTER_CODE"),
		_MIN_CODE_LENGTH)
	_code_input.text_changed.connect(
		_on_code_changed)
	_code_input.submitted.connect(
		_on_send_pressed)
	_row_container.add_child(_code_input)
	_connect_row_clicked(_code_input)

	# Small spacer.
	var input_spacer := Control.new()
	input_spacer.custom_minimum_size = (
		Vector2(0, 8))
	_row_container.add_child(input_spacer)

	# Send request row. Disabled until code is
	# long enough.
	_send_row = ActionRow.new()
	_send_row.setup_action(_on_send_pressed)
	_send_row.setup_label(
		tr("FRIENDS.SEND_REQUEST"),
		_add_friend_icon)
	_send_row.disabled = true
	_row_container.add_child(_send_row)
	_connect_row_clicked(_send_row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)

	# Connect API signals.
	Platform.friends\
		.friend_request_sent.connect(
			_on_friend_request_sent)
	Platform.friends.request_failed.connect(
		_on_request_failed)


func _exit_tree() -> void:
	var client: PlatformFriendsApiClient = Platform.friends
	if not is_instance_valid(client):
		return
	if client.friend_request_sent.is_connected(
			_on_friend_request_sent):
		client.friend_request_sent.disconnect(
			_on_friend_request_sent)
	if client.request_failed.is_connected(
			_on_request_failed):
		client.request_failed.disconnect(
			_on_request_failed)


func _on_code_changed(text: String) -> void:
	if not is_instance_valid(_send_row):
		return
	_send_row.disabled = (
		text.strip_edges().length()
		< _MIN_CODE_LENGTH)


func _on_send_pressed() -> void:
	if not is_instance_valid(_code_input):
		return
	if not is_instance_valid(_send_row):
		return
	if _send_row.disabled:
		return
	var code := (
		_code_input.get_text()
			.strip_edges()
			.to_upper())
	if code.length() < _MIN_CODE_LENGTH:
		return
	_send_row.disabled = true
	Platform.friends.send_request_by_code(
		code)


func _on_friend_request_sent(
	data: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(G.toast_overlay):
		var result: String = (
			data.get("result", ""))
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
	if is_instance_valid(manager):
		manager.pop_panel()


func _on_request_failed(
	_error: String,
) -> void:
	if is_queued_for_deletion():
		return
	# Re-enable the send row so the user can try
	# again. FriendsPanel below in the stack
	# handles showing the error toast.
	if is_instance_valid(_send_row):
		_send_row.disabled = false
