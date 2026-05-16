class_name PartyChatPanel
extends SidePanel
## Live chat for the current party. Messages stream from
## PartyManager.chat_message_received; history is seeded
## from PartyManager.chat_history (which PartyManager
## populates by calling list_channel_messages_async right
## after the chat-join handshake).
##
## Layout: back row, message list (one row per message),
## text input + send row, bottom padding. All in the
## SidePanel base's scrollable VBox so input gamepad
## navigation just works (U/D moves focus, L/R triggers).


@export var _back_row_scene: PackedScene
@export var _text_input_row_scene: PackedScene
@export var _send_icon: Texture2D

## Cap user-visible message length. The actual on-the-wire
## cap is enforced by PartyManager, but the LineEdit's
## `max_length` also gates this so the user gets immediate
## feedback when they hit it.
const _MESSAGE_MAX_LENGTH := 500

var _message_input: TextInputRow
var _send_row: ActionRow
var _messages_anchor_index := -1
var _message_row_nodes: Array[Control] = []


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

	# Header.
	var header := Label.new()
	header.text = tr("PARTY.CHAT_HEADER")
	header.add_theme_color_override(
		"font_color", Color(1.0, 1.0, 1.0))
	header.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	_row_container.add_child(header)

	# Track where to insert message rows so we can wipe
	# and re-render history without disturbing the
	# back/header/input scaffolding.
	_messages_anchor_index = (
		_row_container.get_child_count())

	# Text input row.
	_message_input = (
		_text_input_row_scene.instantiate())
	_message_input.setup(
		tr("PARTY.CHAT_PLACEHOLDER"),
		_MESSAGE_MAX_LENGTH)
	_message_input.text_changed.connect(
		_on_message_changed)
	_message_input.submitted.connect(
		_on_send_pressed)
	_row_container.add_child(_message_input)
	_connect_row_clicked(_message_input)

	# Send action row.
	_send_row = ActionRow.new()
	_send_row.setup_action(_on_send_pressed)
	_send_row.setup_label(
		tr("PARTY.CHAT_SEND"),
		_send_icon)
	_send_row.disabled = true
	_row_container.add_child(_send_row)
	_connect_row_clicked(_send_row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)

	# Wire signals.
	G.party_manager.chat_message_received.connect(
		_on_chat_message_received)
	G.party_manager.chat_history_reset.connect(
		_on_chat_history_reset)
	G.party_manager.party_disbanded.connect(
		_on_party_disbanded)

	_render_history()


func _exit_tree() -> void:
	var pm := G.party_manager
	if not is_instance_valid(pm):
		return
	if pm.chat_message_received.is_connected(
			_on_chat_message_received):
		pm.chat_message_received.disconnect(
			_on_chat_message_received)
	if pm.chat_history_reset.is_connected(
			_on_chat_history_reset):
		pm.chat_history_reset.disconnect(
			_on_chat_history_reset)
	if pm.party_disbanded.is_connected(
			_on_party_disbanded):
		pm.party_disbanded.disconnect(
			_on_party_disbanded)


func _render_history() -> void:
	for node in _message_row_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_message_row_nodes.clear()

	if G.party_manager.chat_history.is_empty():
		_append_empty_placeholder()
	else:
		for message in G.party_manager.chat_history:
			_append_message_row(message)

	rebuild_row_list()
	_scroll_to_bottom()


func _append_empty_placeholder() -> void:
	var placeholder := Label.new()
	placeholder.text = tr("PARTY.CHAT_EMPTY")
	placeholder.add_theme_color_override(
		"font_color", Color(0.6, 0.6, 0.6))
	placeholder.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	placeholder.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART)
	_row_container.add_child(placeholder)
	_row_container.move_child(
		placeholder, _messages_anchor_index)
	_message_row_nodes.append(placeholder)


func _append_message_row(
	message: Dictionary,
) -> void:
	# If the placeholder is showing, clear it before adding
	# the first real message.
	if (_message_row_nodes.size() == 1
			and _message_row_nodes[0] is Label
			and (_message_row_nodes[0] as Label).text
				== tr("PARTY.CHAT_EMPTY")):
		_message_row_nodes[0].queue_free()
		_message_row_nodes.clear()

	var sender_id: String = message.get("sender_id", "")
	var self_id: String = Platform.token_store.player_id
	var display_name := _resolve_sender_display_name(message)
	var body: String = ""
	var content_dict: Variant = message.get("content", {})
	if content_dict is Dictionary:
		body = content_dict.get("text", "")
	if body.is_empty():
		# Fallback for messages whose content didn't parse as
		# a dict — show the raw string so debugging stays
		# possible.
		body = message.get("content_raw", "")

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var header := Label.new()
	header.text = (
		"%s (%s)" % [display_name, tr("PARTY.YOU")]
		if sender_id == self_id and sender_id != ""
		else display_name)
	header.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	row.add_child(header)

	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART)
	body_label.add_theme_color_override(
		"font_color", Color(0.95, 0.95, 0.95))
	row.add_child(body_label)

	_row_container.add_child(row)
	# Place the new row just before the input scaffold. The
	# anchor is the position where the input row was
	# originally inserted; appending at that index pushes
	# the input down to remain at the bottom of the message
	# stack.
	_row_container.move_child(row, _messages_anchor_index)
	_messages_anchor_index += 1
	_message_row_nodes.append(row)


## Look up the sender's friendly name. Prefer the username
## the message carries (Nakama populates it on send), fall
## back to the party member list, and finally to "Someone".
func _resolve_sender_display_name(
	message: Dictionary,
) -> String:
	var sender_id: String = message.get(
		"sender_id", "")
	if sender_id == Platform.token_store.player_id:
		# Self — display the local username if we have it,
		# else the literal "You" fallback handled by the
		# caller.
		var self_name := _lookup_member_display_name(
			sender_id)
		if not self_name.is_empty():
			return self_name
	# Live socket messages carry the sender's username
	# verbatim.
	var username: String = message.get("username", "")
	if not username.is_empty():
		return username
	var name := _lookup_member_display_name(sender_id)
	if not name.is_empty():
		return name
	return tr("PARTY.SOMEONE")


func _lookup_member_display_name(
	user_id: String,
) -> String:
	if user_id.is_empty():
		return ""
	var party: Dictionary = G.party_manager.current_party
	for m in party.get("members", []):
		if m is Dictionary and m.get("user_id", "") == user_id:
			var dn: String = m.get("display_name", "")
			if not dn.is_empty():
				return dn
			return m.get("username", "")
	return ""


func _scroll_to_bottom() -> void:
	# Wait two frames for the VBox to relayout after row
	# insertions, then snap the scroll bar to the bottom.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_scroll_container):
		return
	var bar: ScrollBar = (
		_scroll_container.get_v_scroll_bar())
	if bar != null:
		_scroll_container.scroll_vertical = (
			int(bar.max_value))


# --- Signal handlers ---


func _on_message_changed(text: String) -> void:
	if not is_instance_valid(_send_row):
		return
	_send_row.disabled = (
		text.strip_edges().is_empty())


func _on_send_pressed() -> void:
	if not is_instance_valid(_message_input):
		return
	if not is_instance_valid(_send_row):
		return
	if _send_row.disabled:
		return
	var text := _message_input.get_text().strip_edges()
	if text.is_empty():
		return
	_send_row.disabled = true
	# Best-effort: clear the input immediately so the user
	# can keep typing. If the send fails the message is just
	# gone — Discord-style.
	_message_input.clear_text()
	var ok = await G.party_manager.send_party_chat_message(
		text)
	if not ok and is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("PARTY.CHAT_SEND_FAILED"),
			G.toast_overlay.Type.ERROR)
	# Leave send disabled until the user types again.


func _on_chat_message_received(
	message: Dictionary,
) -> void:
	if is_queued_for_deletion():
		return
	_append_message_row(message)
	rebuild_row_list()
	_scroll_to_bottom()


func _on_chat_history_reset() -> void:
	if is_queued_for_deletion():
		return
	_render_history()


func _on_party_disbanded() -> void:
	if is_queued_for_deletion():
		return
	# Party gone — close the panel.
	if is_instance_valid(manager):
		manager.pop_panel()
