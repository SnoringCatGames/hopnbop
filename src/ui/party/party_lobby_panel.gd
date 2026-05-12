class_name PartyLobbyPanel
extends SidePanel
## Party sub-panel. Renders the viewer's active party
## (members, leader controls) and any pending invites
## with accept/decline rows. Reachable from the main
## settings menu; relies on PartyManager's polling for
## live updates.


@export var _back_row_scene: PackedScene
@export var _friends_panel_scene: PackedScene
@export var _join_by_code_panel_scene: PackedScene
@export var _chat_panel_scene: PackedScene
@export var _accept_icon: Texture2D
@export var _decline_icon: Texture2D
@export var _start_match_icon: Texture2D
@export var _invite_icon: Texture2D
@export var _leave_icon: Texture2D
@export var _kick_icon: Texture2D
@export var _open_friends_icon: Texture2D
@export var _ready_icon: Texture2D
@export var _not_ready_icon: Texture2D
@export var _share_code_icon: Texture2D
@export var _join_by_code_icon: Texture2D
@export var _chat_icon: Texture2D
@export var _transfer_leadership_icon: Texture2D

var _status_label: Label
var _bottom_spacer: Control
var _dynamic_nodes: Array[Node] = []
var _cached_invite_code := ""
var _is_fetching_invite_code := false


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

	# Status label (non-focusable).
	_status_label = Label.new()
	_status_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.add_theme_color_override(
		"font_color", Color(0.7, 0.7, 0.7))
	_status_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART)
	_row_container.add_child(_status_label)

	# Bottom padding. Repositioned after dynamic
	# content on each refresh.
	_bottom_spacer = Control.new()
	_bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(_bottom_spacer)

	# Connect to party signals.
	G.party_manager.party_updated.connect(
		_on_party_updated)
	G.party_manager.party_disbanded.connect(
		_on_party_disbanded)
	G.party_manager.matchmaking_started.connect(
		_on_matchmaking_started)
	G.party_api_client.party_invited.connect(
		_on_party_invited)
	G.party_api_client.party_joined.connect(
		_on_party_joined)
	G.party_api_client.party_left.connect(
		_on_party_left)
	G.party_api_client.party_kicked.connect(
		_on_party_kicked)
	G.party_api_client.party_invite_code_received\
		.connect(_on_invite_code_received)
	G.party_api_client.party_invite_code_redeemed\
		.connect(_on_invite_code_redeemed)
	G.party_api_client.party_leader_transferred\
		.connect(_on_leader_transferred)
	G.party_api_client.request_failed.connect(
		_on_request_failed)

	# Ensure polling is active and fire an immediate
	# fetch so the panel doesn't sit empty for up to
	# 10 seconds while the existing poll timer winds
	# down.
	G.party_manager.start_polling()
	if not G.party_api_client.is_busy():
		G.party_api_client.fetch_party_status()

	_refresh()


func _exit_tree() -> void:
	var pm := G.party_manager
	if is_instance_valid(pm):
		if pm.party_updated.is_connected(
				_on_party_updated):
			pm.party_updated.disconnect(
				_on_party_updated)
		if pm.party_disbanded.is_connected(
				_on_party_disbanded):
			pm.party_disbanded.disconnect(
				_on_party_disbanded)
		if pm.matchmaking_started.is_connected(
				_on_matchmaking_started):
			pm.matchmaking_started.disconnect(
				_on_matchmaking_started)

	var pac := G.party_api_client
	if is_instance_valid(pac):
		if pac.party_invited.is_connected(
				_on_party_invited):
			pac.party_invited.disconnect(
				_on_party_invited)
		if pac.party_joined.is_connected(
				_on_party_joined):
			pac.party_joined.disconnect(
				_on_party_joined)
		if pac.party_left.is_connected(
				_on_party_left):
			pac.party_left.disconnect(
				_on_party_left)
		if pac.party_kicked.is_connected(
				_on_party_kicked):
			pac.party_kicked.disconnect(
				_on_party_kicked)
		if pac.party_invite_code_received.is_connected(
				_on_invite_code_received):
			pac.party_invite_code_received.disconnect(
				_on_invite_code_received)
		if pac.party_invite_code_redeemed.is_connected(
				_on_invite_code_redeemed):
			pac.party_invite_code_redeemed.disconnect(
				_on_invite_code_redeemed)
		if pac.party_leader_transferred.is_connected(
				_on_leader_transferred):
			pac.party_leader_transferred.disconnect(
				_on_leader_transferred)
		if pac.request_failed.is_connected(
				_on_request_failed):
			pac.request_failed.disconnect(
				_on_request_failed)


func _refresh() -> void:
	# Clear previous dynamic rows.
	for node in _dynamic_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_dynamic_nodes.clear()

	# Lift the bottom spacer so freshly built sections
	# sit above it.
	_row_container.remove_child(_bottom_spacer)

	var in_party := G.party_manager.is_in_party()
	var has_invites := (
		G.party_manager.has_pending_invite())

	# Drop a stale invite code if the party changed
	# (e.g. user left and joined a different party in
	# the same panel session).
	if not in_party:
		_cached_invite_code = ""

	if has_invites:
		_render_pending_invites()

	if in_party:
		_render_active_party()

	if not in_party and not has_invites:
		_render_empty_state()

	_row_container.add_child(_bottom_spacer)
	rebuild_row_list()


func _render_empty_state() -> void:
	_status_label.text = (
		tr("PARTY.EMPTY_STATE_HINT"))
	_status_label.visible = true

	var open_friends_row := ActionRow.new()
	open_friends_row.setup_actions(
		_on_open_friends_pressed,
		_on_open_friends_pressed)
	open_friends_row.setup_label(
		tr("SETTINGS.FRIENDS"),
		_open_friends_icon)
	_row_container.add_child(open_friends_row)
	_connect_row_clicked(open_friends_row)
	_dynamic_nodes.append(open_friends_row)

	# Join-by-code path. Lets a player paste a 6-char
	# code from a teammate without sending a friend
	# request first — the simplest way to set up a
	# party with someone you're meeting in a Discord
	# voice channel.
	if _join_by_code_panel_scene != null:
		var join_row := ActionRow.new()
		join_row.setup_actions(
			_on_join_by_code_pressed,
			_on_join_by_code_pressed)
		join_row.setup_label(
			tr("PARTY.JOIN_BY_CODE"),
			_join_by_code_icon)
		_row_container.add_child(join_row)
		_connect_row_clicked(join_row)
		_dynamic_nodes.append(join_row)


func _render_pending_invites() -> void:
	if not G.party_manager.is_in_party():
		_status_label.text = (
			tr("PARTY.HAS_PENDING_INVITES"))
		_status_label.visible = true
	else:
		# Hide status label; the active-party section
		# below has its own header.
		_status_label.visible = false

	var section_label := Label.new()
	section_label.text = (
		tr("PARTY.PENDING_INVITES_HEADER"))
	section_label.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	_row_container.add_child(section_label)
	_dynamic_nodes.append(section_label)

	for invite in G.party_manager.pending_invites:
		_add_invite_row(invite)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_row_container.add_child(spacer)
	_dynamic_nodes.append(spacer)


func _add_invite_row(invite: Dictionary) -> void:
	var party_id: String = invite.get("party_id", "")
	var leader_id: String = invite.get("leader_id", "")
	var leader_name := _resolve_friend_display_name(
		leader_id)
	if leader_name.is_empty():
		leader_name = tr("PARTY.SOMEONE")

	# Accept row.
	var accept_row := ActionRow.new()
	var accept_action := _on_accept_pressed.bind(
		party_id)
	accept_row.setup_actions(
		accept_action, accept_action)
	accept_row.setup_label(
		tr("PARTY.ACCEPT_INVITE") % leader_name,
		_accept_icon)
	_row_container.add_child(accept_row)
	_connect_row_clicked(accept_row)
	_dynamic_nodes.append(accept_row)

	# Decline row.
	var decline_row := ActionRow.new()
	var decline_action := _on_decline_pressed.bind(
		party_id, leader_name)
	decline_row.setup_actions(
		decline_action, decline_action)
	decline_row.setup_label(
		tr("PARTY.DECLINE_INVITE"),
		_decline_icon)
	_row_container.add_child(decline_row)
	_connect_row_clicked(decline_row)
	_dynamic_nodes.append(decline_row)


func _render_active_party() -> void:
	var party := G.party_manager.current_party
	var status: String = party.get("status", "")
	var is_matchmaking := status == "matchmaking"
	var is_leader := G.party_manager.is_leader()
	var members: Array = party.get("members", [])

	if is_matchmaking:
		_status_label.text = tr("PARTY.MATCHMAKING")
		_status_label.visible = true
	elif not G.party_manager.has_pending_invite():
		# Suppress the status label when invites
		# already populate it.
		_status_label.visible = false

	var active_count := 0
	for m in members:
		if m is Dictionary and m.get("role", "") != "invited":
			active_count += 1

	var header := Label.new()
	header.text = "%s (%d)" % [
		tr("PARTY.MEMBERS"), active_count]
	header.add_theme_color_override(
		"font_color", Color(1.0, 1.0, 1.0))
	_row_container.add_child(header)
	_dynamic_nodes.append(header)

	for member in members:
		_add_member_row(member, is_leader)

	# Leader-only "promote member to leader" section. Rendered as a
	# row per eligible target so the user can transfer in one tap
	# without an intermediate picker. Parties cap at 4 members, so
	# at most 3 rows here.
	if is_leader and not is_matchmaking:
		for member in members:
			if not (member is Dictionary):
				continue
			if member.get("role", "") == "invited":
				continue
			var mid: String = member.get("user_id", "")
			if (mid.is_empty()
					or mid == G.auth_token_store.player_id):
				continue
			_add_transfer_leadership_row(member)

	var actions_spacer := Control.new()
	actions_spacer.custom_minimum_size = (
		Vector2(0, 12))
	_row_container.add_child(actions_spacer)
	_dynamic_nodes.append(actions_spacer)

	# Self-ready toggle (visible to every viewer, not
	# just the leader). Hidden while matchmaking is in
	# flight because changing ready state mid-queue
	# doesn't do anything — the ticket is already
	# enqueued.
	if not is_matchmaking:
		var is_ready := G.party_manager.is_self_ready()
		var ready_row := ActionRow.new()
		var ready_action := _on_ready_toggle_pressed.bind(
			not is_ready)
		ready_row.setup_actions(
			ready_action, ready_action)
		var ready_label := (
			tr("PARTY.MARK_NOT_READY")
			if is_ready
			else tr("PARTY.MARK_READY"))
		var ready_icon := (
			_not_ready_icon
			if is_ready
			else _ready_icon)
		ready_row.setup_label(ready_label, ready_icon)
		_row_container.add_child(ready_row)
		_connect_row_clicked(ready_row)
		_dynamic_nodes.append(ready_row)

	if is_leader and not is_matchmaking:
		var start_row := ActionRow.new()
		start_row.setup_actions(
			_on_start_match_pressed,
			_on_start_match_pressed)
		var all_ready := (
			G.party_manager.all_active_members_ready())
		var start_label := (
			tr("PARTY.START_MATCH")
			if all_ready
			else tr("PARTY.WAITING_FOR_READY"))
		start_row.setup_label(
			start_label, _start_match_icon)
		start_row.disabled = (
			active_count < 2 or not all_ready)
		_row_container.add_child(start_row)
		_connect_row_clicked(start_row)
		_dynamic_nodes.append(start_row)

		var invite_row := ActionRow.new()
		invite_row.setup_actions(
			_on_open_friends_pressed,
			_on_open_friends_pressed)
		invite_row.setup_label(
			tr("PARTY.INVITE"),
			_invite_icon)
		_row_container.add_child(invite_row)
		_connect_row_clicked(invite_row)
		_dynamic_nodes.append(invite_row)

	# Chat row. Available to every active member while not in
	# matchmaking. Drops into a sub-panel that streams the party's
	# group channel.
	if not is_matchmaking and _chat_panel_scene != null:
		var chat_row := ActionRow.new()
		chat_row.setup_actions(
			_on_open_chat_pressed,
			_on_open_chat_pressed)
		chat_row.setup_label(
			tr("PARTY.OPEN_CHAT"),
			_chat_icon)
		_row_container.add_child(chat_row)
		_connect_row_clicked(chat_row)
		_dynamic_nodes.append(chat_row)

	# Share invite code row. Available to every active member, not
	# just the leader — invitations are a social action and any
	# member should be able to bring a friend in. The label flips
	# between "Show invite code" (before fetching) and the literal
	# 6-char code (once resolved); pressing while the code is shown
	# copies it to the clipboard.
	if not is_matchmaking:
		var share_label: String
		var share_action: Callable
		if _cached_invite_code.is_empty():
			share_label = (
				tr("PARTY.SHOW_INVITE_CODE")
				if not _is_fetching_invite_code
				else tr("PARTY.FETCHING_INVITE_CODE"))
			share_action = _on_show_invite_code_pressed
		else:
			share_label = (
				tr("PARTY.INVITE_CODE_LABEL")
				% _cached_invite_code)
			share_action = _on_copy_invite_code_pressed
		var share_row := ActionRow.new()
		share_row.setup_actions(share_action, share_action)
		share_row.setup_label(share_label, _share_code_icon)
		share_row.disabled = _is_fetching_invite_code
		_row_container.add_child(share_row)
		_connect_row_clicked(share_row)
		_dynamic_nodes.append(share_row)

	var leave_row := ActionRow.new()
	leave_row.setup_actions(
		_on_leave_pressed,
		_on_leave_pressed)
	leave_row.setup_label(
		tr("PARTY.LEAVE"),
		_leave_icon)
	_row_container.add_child(leave_row)
	_connect_row_clicked(leave_row)
	_dynamic_nodes.append(leave_row)


func _add_member_row(
	member: Dictionary,
	is_viewer_leader: bool,
) -> void:
	var member_id: String = member.get(
		"user_id", "")
	var display: String = member.get(
		"display_name", "")
	if display.is_empty():
		display = member.get("username", "")
	if display.is_empty():
		display = member_id
	var role: String = member.get(
		"role", "member")
	var is_pending := role == "invited"
	var is_self := (
		member_id == G.auth_token_store.player_id)
	# Leader can revoke a pending invite or kick a
	# member via the same Nakama group-kick endpoint.
	var is_kickable := (
		is_viewer_leader
		and not is_self
	)

	var row := ActionRow.new()
	if is_kickable:
		var kick_action := _on_kick_pressed.bind(
			member_id, display)
		row.setup_actions(kick_action, kick_action)
	else:
		row.disabled = true

	var content := HBoxContainer.new()
	content.add_theme_constant_override(
		"separation", 8)
	content.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	row.add_child(content)

	if role == "leader":
		var crown := Label.new()
		crown.text = "★"
		crown.add_theme_color_override(
			"font_color", Color(1.0, 0.85, 0.3))
		crown.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE)
		content.add_child(crown)

	var name_label := Label.new()
	name_label.text = display
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	name_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	if is_pending:
		name_label.add_theme_color_override(
			"font_color", Color(0.6, 0.6, 0.6))
	content.add_child(name_label)

	var suffix_text := ""
	if is_pending:
		suffix_text = "(%s)" % tr("PARTY.PENDING")
	elif is_self:
		suffix_text = "(%s)" % tr("PARTY.YOU")
	if not suffix_text.is_empty():
		var suffix := Label.new()
		suffix.text = suffix_text
		suffix.add_theme_color_override(
			"font_color", Color(0.6, 0.6, 0.6))
		suffix.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE)
		content.add_child(suffix)

	# Ready badge for accepted members. Pending invitees
	# can't ready up; everyone else carries a small green
	# "Ready" tag once they've toggled.
	if not is_pending and bool(member.get("ready", false)):
		var badge := Label.new()
		badge.text = "[%s]" % tr("PARTY.READY")
		badge.add_theme_color_override(
			"font_color", Color(0.5, 1.0, 0.5))
		badge.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE)
		content.add_child(badge)

	if is_kickable:
		var chevron := TextureRect.new()
		chevron.expand_mode = (
			TextureRect.EXPAND_IGNORE_SIZE)
		chevron.stretch_mode = (
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		chevron.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE)
		content.add_child(chevron)
		row._setup_chevron(chevron)

	_row_container.add_child(row)
	_connect_row_clicked(row)
	_dynamic_nodes.append(row)


## Add a leader-only "Make %s the leader" action row for a single
## eligible target. The caller is expected to have already filtered
## down to non-self, non-pending members.
func _add_transfer_leadership_row(
	member: Dictionary,
) -> void:
	var target_id: String = member.get("user_id", "")
	var display: String = member.get("display_name", "")
	if display.is_empty():
		display = member.get("username", "")
	if display.is_empty():
		display = target_id
	var row := ActionRow.new()
	var action := _on_transfer_leadership_pressed.bind(
		target_id, display)
	row.setup_actions(action, action)
	row.setup_label(
		tr("PARTY.MAKE_LEADER") % display,
		_transfer_leadership_icon)
	_row_container.add_child(row)
	_connect_row_clicked(row)
	_dynamic_nodes.append(row)


## Resolve a player_id to a display name via the
## friends cache. Returns "" if not in cache; the
## caller falls back to PARTY.SOMEONE.
func _resolve_friend_display_name(
	player_id: String,
) -> String:
	if player_id.is_empty():
		return ""
	if not is_instance_valid(G.friends_api_client):
		return ""
	for entry in G.friends_api_client.cached_friends:
		if entry.get("player_id", "") == player_id:
			return entry.get("display_name", "")
	return ""


# --- Signal handlers ---


func _on_party_updated(_data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	_refresh()


func _on_party_disbanded() -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("PARTY.DISBANDED"))
	_refresh()


func _on_matchmaking_started(
	_ticket_id: String,
) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("PARTY.MATCHMAKING"))
	_refresh()


func _on_party_invited(_data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	_refresh()


func _on_party_joined(_data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	_refresh()


func _on_party_left(_data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	_refresh()


func _on_party_kicked(_data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	_refresh()


func _on_request_failed(error: String) -> void:
	if is_queued_for_deletion():
		return
	if error == "Request in progress":
		return
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			error, G.toast_overlay.Type.ERROR)


# --- Actions ---


func _on_start_match_pressed() -> void:
	G.party_manager.start_party_matchmaking()


func _on_ready_toggle_pressed(ready: bool) -> void:
	G.party_manager.set_ready(ready)


func _on_leave_pressed() -> void:
	open_confirm_dialog(
		tr("CONFIRM.LEAVE_PARTY"),
		tr("PARTY.LEAVE"),
		func() -> void:
			G.party_manager.leave_current_party(),
		tr("CONFIRM.CANCEL"),
	)


func _on_kick_pressed(
	target_id: String,
	display_name: String,
) -> void:
	open_confirm_dialog(
		tr("CONFIRM.KICK") % display_name,
		tr("PARTY.KICK"),
		func() -> void:
			G.party_manager.kick_member(target_id),
		tr("CONFIRM.CANCEL"),
	)


func _on_transfer_leadership_pressed(
	target_id: String,
	display_name: String,
) -> void:
	open_confirm_dialog(
		tr("CONFIRM.TRANSFER_LEADERSHIP") % display_name,
		tr("PARTY.MAKE_LEADER_CONFIRM"),
		func() -> void:
			G.party_manager.transfer_leadership(target_id),
		tr("CONFIRM.CANCEL"),
	)


func _on_open_friends_pressed() -> void:
	if _friends_panel_scene == null:
		return
	if not is_instance_valid(manager):
		return
	var panel := _friends_panel_scene.instantiate()
	manager.push_panel(panel)


func _on_accept_pressed(party_id: String) -> void:
	G.party_manager.accept_invite(party_id)


func _on_decline_pressed(
	party_id: String,
	leader_name: String,
) -> void:
	open_confirm_dialog(
		tr("CONFIRM.DECLINE_INVITE") % leader_name,
		tr("PARTY.DECLINE_INVITE"),
		func() -> void:
			G.party_manager.decline_invite(party_id),
		tr("CONFIRM.CANCEL"),
	)


func _on_join_by_code_pressed() -> void:
	if _join_by_code_panel_scene == null:
		return
	if not is_instance_valid(manager):
		return
	var panel := _join_by_code_panel_scene.instantiate()
	manager.push_panel(panel)


func _on_open_chat_pressed() -> void:
	if _chat_panel_scene == null:
		return
	if not is_instance_valid(manager):
		return
	var panel := _chat_panel_scene.instantiate()
	manager.push_panel(panel)


func _on_show_invite_code_pressed() -> void:
	if _is_fetching_invite_code:
		return
	_is_fetching_invite_code = true
	_refresh()
	G.party_manager.request_invite_code()


func _on_copy_invite_code_pressed() -> void:
	if _cached_invite_code.is_empty():
		return
	DisplayServer.clipboard_set(_cached_invite_code)
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("PARTY.INVITE_CODE_COPIED"))


func _on_invite_code_received(data: Dictionary) -> void:
	if is_queued_for_deletion():
		return
	_is_fetching_invite_code = false
	var code: String = data.get("code", "")
	if not code.is_empty():
		_cached_invite_code = code
	_refresh()


func _on_leader_transferred(data: Dictionary) -> void:
	# The runtime's party_state_changed fan-out triggers an
	# immediate refetch in PartyManager, so the panel re-renders
	# with the new leader_id without anything to do here.  We do
	# show a toast so the (now-former) leader has visible
	# confirmation their transfer landed — the row they tapped
	# disappears on refresh, which is otherwise ambiguous.
	if is_queued_for_deletion():
		return
	if not is_instance_valid(G.toast_overlay):
		return
	var new_leader_id: String = data.get("leader_id", "")
	if new_leader_id.is_empty():
		return
	var display := _resolve_member_display_name(new_leader_id)
	if display.is_empty():
		display = _resolve_friend_display_name(new_leader_id)
	if display.is_empty():
		display = tr("PARTY.SOMEONE")
	G.toast_overlay.show_toast(
		tr("PARTY.LEADERSHIP_TRANSFERRED") % display)


## Look up a member's display name from the cached party members
## dict. Returns "" when the id isn't a known member.
func _resolve_member_display_name(
	player_id: String,
) -> String:
	if player_id.is_empty():
		return ""
	for m in G.party_manager.current_party.get("members", []):
		if not (m is Dictionary):
			continue
		if m.get("user_id", "") != player_id:
			continue
		var name: String = m.get("display_name", "")
		if not name.is_empty():
			return name
		return m.get("username", "")
	return ""


func _on_invite_code_redeemed(_data: Dictionary) -> void:
	# The redeem flow only fires for the joining client (PartyManager's
	# party_joined handler covers the rest of the state machine). This
	# panel doesn't react directly — the party_updated signal that
	# fires shortly after will trigger _refresh().
	pass
