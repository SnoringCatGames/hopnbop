class_name JoinByCodePanel
extends SidePanel
## Sub-panel for joining a party via the 6-character
## invite code another player shared. Modeled on
## AddFriendPanel's text-input-row + send-button pattern;
## the Send action calls the party_join_by_code RPC and
## pops back to the lobby panel on success.


@export var _back_row_scene: PackedScene
@export var _text_input_row_scene: PackedScene
@export var _join_icon: Texture2D

## Codes are exactly partyInviteCodeLength chars on the
## server side (see snoringcat-platform/runtime/party.go).
## The runtime rejects shorter/longer codes; mirror that
## here so the Join button gates on the obvious length
## before round-tripping.
const _CODE_LENGTH := 6

var _code_input: TextInputRow
var _join_row: ActionRow


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

	# Hint label so the panel isn't just a blank text
	# field on first entry.
	var hint := Label.new()
	hint.text = tr("PARTY.JOIN_BY_CODE_HINT")
	hint.add_theme_color_override(
		"font_color", Color(0.7, 0.7, 0.7))
	hint.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART)
	hint.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	_row_container.add_child(hint)

	# Invite code text input row.
	_code_input = (
		_text_input_row_scene.instantiate())
	_code_input.setup(
		tr("PARTY.ENTER_CODE"),
		_CODE_LENGTH)
	_code_input.text_changed.connect(
		_on_code_changed)
	_code_input.submitted.connect(
		_on_join_pressed)
	_row_container.add_child(_code_input)
	_connect_row_clicked(_code_input)

	# Small spacer.
	var input_spacer := Control.new()
	input_spacer.custom_minimum_size = (
		Vector2(0, 8))
	_row_container.add_child(input_spacer)

	# Join row. Disabled until the input has the right
	# number of characters.
	_join_row = ActionRow.new()
	_join_row.setup_actions(
		_on_join_pressed, _on_join_pressed)
	_join_row.setup_label(
		tr("PARTY.JOIN_BY_CODE"),
		_join_icon)
	_join_row.disabled = true
	_row_container.add_child(_join_row)
	_connect_row_clicked(_join_row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)

	# Connect API signals.
	G.party_api_client\
		.party_invite_code_redeemed.connect(
			_on_invite_code_redeemed)
	G.party_api_client.request_failed.connect(
		_on_request_failed)


func _exit_tree() -> void:
	var client := G.party_api_client
	if not is_instance_valid(client):
		return
	if client.party_invite_code_redeemed.is_connected(
			_on_invite_code_redeemed):
		client.party_invite_code_redeemed.disconnect(
			_on_invite_code_redeemed)
	if client.request_failed.is_connected(
			_on_request_failed):
		client.request_failed.disconnect(
			_on_request_failed)


func _on_code_changed(text: String) -> void:
	if not is_instance_valid(_join_row):
		return
	# Whitespace-tolerant: people copy-paste with
	# surrounding spaces all the time.
	var trimmed := text.strip_edges()
	_join_row.disabled = trimmed.length() != _CODE_LENGTH


func _on_join_pressed() -> void:
	if not is_instance_valid(_code_input):
		return
	if not is_instance_valid(_join_row):
		return
	if _join_row.disabled:
		return
	var code := (
		_code_input.get_text()
			.strip_edges()
			.to_upper())
	if code.length() != _CODE_LENGTH:
		return
	_join_row.disabled = true
	G.party_manager.join_party_by_code(code)


func _on_invite_code_redeemed(data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("PARTY.JOINED_VIA_CODE"))
	# Drop back to the party lobby — the joined party
	# is now the visible one, so leaving this panel
	# returns the user to the right surface.
	if is_instance_valid(manager):
		manager.pop_panel()
	# Suppress "unused" warning on data; the panel doesn't
	# need to read party_id because PartyManager already
	# wired the join via the party_joined signal.
	if data.is_empty():
		return


func _on_request_failed(_error: String) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(_join_row):
		_join_row.disabled = false
