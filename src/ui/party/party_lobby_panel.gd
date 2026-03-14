class_name PartyLobbyPanel
extends CanvasLayer
## Overlay panel showing the current party state.
## Displays members, invite button, and start match
## button (leader only). Polls for status updates.


signal closed

var _members_container: VBoxContainer
var _invite_button: Button
var _start_button: Button
var _leave_button: Button
var _status_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.7)
	background.set_anchors_preset(
		Control.PRESET_FULL_RECT)
	background.mouse_filter = (
		Control.MOUSE_FILTER_STOP)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(
		Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 200)
	center.add_child(panel)

	var main_box := VBoxContainer.new()
	main_box.add_theme_constant_override(
		"separation", 12)
	panel.add_child(main_box)

	# Title.
	var title := Label.new()
	title.text = tr("PARTY.TITLE")
	title.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	main_box.add_child(title)

	# Status label.
	_status_label = Label.new()
	_status_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.add_theme_color_override(
		"font_color", Color(0.7, 0.7, 0.7))
	_status_label.visible = false
	main_box.add_child(_status_label)

	# Members list.
	_members_container = VBoxContainer.new()
	_members_container.add_theme_constant_override(
		"separation", 4)
	main_box.add_child(_members_container)

	# Button row.
	var button_box := HBoxContainer.new()
	button_box.alignment = (
		BoxContainer.ALIGNMENT_CENTER)
	button_box.add_theme_constant_override(
		"separation", 8)
	main_box.add_child(button_box)

	_invite_button = Button.new()
	_invite_button.text = tr("PARTY.INVITE")
	_invite_button.pressed.connect(
		_on_invite_pressed)
	button_box.add_child(_invite_button)

	_start_button = Button.new()
	_start_button.text = tr("PARTY.START_MATCH")
	_start_button.pressed.connect(
		_on_start_pressed)
	button_box.add_child(_start_button)

	_leave_button = Button.new()
	_leave_button.text = tr("PARTY.LEAVE")
	_leave_button.pressed.connect(
		_on_leave_pressed)
	button_box.add_child(_leave_button)

	# Close button.
	var close_button := Button.new()
	close_button.text = tr("PARTY.CLOSE")
	close_button.pressed.connect(_on_close_pressed)
	button_box.add_child(close_button)

	# Connect to party updates.
	G.party_manager.party_updated.connect(
		_on_party_updated)
	G.party_manager.party_disbanded.connect(
		_on_party_disbanded)
	G.party_manager.matchmaking_started.connect(
		_on_matchmaking_started)

	# Start polling and refresh.
	G.party_manager.start_polling()
	_refresh_ui()


func _exit_tree() -> void:
	if is_instance_valid(G.party_manager):
		if G.party_manager.party_updated\
				.is_connected(_on_party_updated):
			G.party_manager.party_updated\
				.disconnect(_on_party_updated)
		if G.party_manager.party_disbanded\
				.is_connected(_on_party_disbanded):
			G.party_manager.party_disbanded\
				.disconnect(_on_party_disbanded)
		if G.party_manager.matchmaking_started\
				.is_connected(
					_on_matchmaking_started):
			G.party_manager.matchmaking_started\
				.disconnect(
					_on_matchmaking_started)


func _refresh_ui() -> void:
	var party := G.party_manager.current_party
	if party.is_empty():
		_status_label.text = (
			tr("PARTY.WAITING_FOR_CREATE"))
		_status_label.visible = true
		_start_button.visible = false
		_invite_button.visible = false
		return

	_status_label.visible = false
	var is_leader := G.party_manager.is_leader()
	_start_button.visible = is_leader
	_invite_button.visible = is_leader

	# Check member count for start button.
	var members: Array = party.get("members", [])
	_start_button.disabled = members.size() < 2

	var status: String = party.get("status", "")
	if status == "matchmaking":
		_status_label.text = (
			tr("PARTY.MATCHMAKING"))
		_status_label.visible = true
		_start_button.disabled = true
		_invite_button.disabled = true

	# Populate members.
	for child in (
		_members_container.get_children()
	):
		child.queue_free()

	for member_id in members:
		var member_label := Label.new()
		# Show player_id for now. Could resolve
		# display names via profile API.
		var is_current := (
			member_id
			== G.auth_token_store.player_id)
		var prefix := (
			"★ " if member_id
			== party.get("leader_id", "")
			else "  ")
		var suffix := (
			" (" + tr("PARTY.YOU") + ")"
			if is_current else "")
		member_label.text = (
			prefix + str(member_id) + suffix)
		_members_container.add_child(member_label)

	# Show invited players.
	var invited: Array = party.get("invited", [])
	for invitee_id in invited:
		var invite_label := Label.new()
		invite_label.text = (
			"  " + str(invitee_id) + " ("
			+ tr("PARTY.PENDING") + ")")
		invite_label.add_theme_color_override(
			"font_color", Color(0.6, 0.6, 0.6))
		_members_container.add_child(invite_label)


func _on_party_updated(
	party_data: Dictionary,
) -> void:
	_refresh_ui()


func _on_party_disbanded() -> void:
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("PARTY.DISBANDED"))
	_close()


func _on_matchmaking_started(
	ticket_id: String,
) -> void:
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("PARTY.MATCHMAKING"))
	_close()


func _on_invite_pressed() -> void:
	# Open friends panel would go here. For now,
	# show a toast directing to the friends panel.
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("PARTY.USE_FRIENDS_TO_INVITE"))


func _on_start_pressed() -> void:
	G.party_manager.start_party_matchmaking()
	_start_button.disabled = true


func _on_leave_pressed() -> void:
	G.party_manager.leave_current_party()


func _on_close_pressed() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_pause"):
		_close()
		get_viewport().set_input_as_handled()
