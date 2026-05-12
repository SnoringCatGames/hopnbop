class_name PartyManager
extends Node
## Manages party state. Real-time updates flow over the long-lived
## Nakama notification socket (NotificationSocketClient) via the
## `party_state_changed` subject the platform runtime emits on every
## group lifecycle hook (invite / join / leave / kick). A slow
## catch-up HTTP poll runs alongside as a fallback for windows when
## the socket is down or transient notifications were dropped before
## the client reconnected.
##
## Stage 5.4: replaced the previous 3 s active / 10 s idle polling
## cadence. The poll cadence is now a single ~60 s catch-up regardless
## of in-party state because the socket carries the latency-sensitive
## events.


signal party_updated(party_data: Dictionary)
signal party_disbanded
signal matchmaking_started(ticket_id: String)
signal invite_received(invite_data: Dictionary)

## Catch-up cadence when the socket is healthy. Long enough that
## it's not a meaningful drain in steady state; short enough that
## a hung socket recovers within a minute.
const _CATCH_UP_POLL_INTERVAL_SEC := 60.0

## Subject the runtime fans out on every party group hook. Mirrors
## third_party/snoringcat-platform/runtime/party.go
## :partyStateChangedSubject.
const _PARTY_STATE_CHANGED_SUBJECT := "party_state_changed"

var current_party: Dictionary = {}
var pending_invites: Array = []

## Set when party_start_matchmaking succeeds (leader path) or when
## a `party_matchmaking_start` notification arrives (follower path).
## Consumed by `GamePanel._client_client_request_session_ids` so the
## resulting matchmaker ticket carries the shared `party_id`. Keys:
## `party_id`, `game_mode`, `matchmaker_properties`.
var pending_party_match_context: Dictionary = {}

var _poll_timer := 0.0
var _is_polling := false
var _known_invite_ids: Dictionary = {}
## Dedup transient-notification deliveries. Most party_state_changed
## notifications are unique by id, but the matchmaker socket
## (NakamaMatchmakerClient) and the notification socket can both
## receive the same id when matchmaking is also active.
var _known_state_changed_ids: Dictionary = {}


func _ready() -> void:
	G.party_api_client.party_created.connect(
		_on_party_created)
	G.party_api_client.party_invited.connect(
		_on_party_invited)
	G.party_api_client.party_joined.connect(
		_on_party_joined)
	G.party_api_client.party_left.connect(
		_on_party_left)
	G.party_api_client.party_kicked.connect(
		_on_party_kicked)
	G.party_api_client.party_status_received\
		.connect(_on_party_status_received)
	G.party_api_client\
		.party_matchmaking_started.connect(
			_on_matchmaking_started)
	invite_received.connect(
		_show_invite_dialog)
	G.auth_client.auth_completed.connect(
		_on_auth_completed)
	# Stage 5.4: real-time updates over the long-lived notification
	# socket. The catch-up poll below handles socket-down windows.
	G.notification_socket_client\
		.notification_received.connect(
			_on_socket_notification)
	G.notification_socket_client\
		.socket_connected.connect(_on_socket_connected)


func _process(delta: float) -> void:
	if not _is_polling:
		return
	if not G.auth_token_store.is_token_valid():
		return

	_poll_timer += delta
	if _poll_timer >= _CATCH_UP_POLL_INTERVAL_SEC:
		_poll_timer = 0.0
		if not G.party_api_client.is_busy():
			G.party_api_client.fetch_party_status()


## Start polling for party status updates.
func start_polling() -> void:
	_is_polling = true
	_poll_timer = 0.0


## Stop polling.
func stop_polling() -> void:
	_is_polling = false


## Whether the player is an accepted member of a party.
## Pending invites (Nakama state=3) live in
## `pending_invites` instead, not in `current_party`.
func is_in_party() -> bool:
	return not current_party.is_empty()


## Whether the player currently has at least one
## pending party invite they haven't accepted or
## declined. Nakama exposes a closed-group invite as
## the user being associated with the group in state=3;
## `PartyApiClient.fetch_party_status` separates those
## from active membership.
func has_pending_invite() -> bool:
	return not pending_invites.is_empty()


## Whether the player is the party leader.
func is_leader() -> bool:
	if current_party.is_empty():
		return false
	return (
		current_party.get("leader_id", "")
		== G.auth_token_store.player_id
	)


## Get the current party ID.
func get_party_id() -> String:
	return current_party.get("party_id", "")


## Create a new party.
func create_party() -> void:
	G.party_api_client.create_party()


## Invite a friend to the current party. Creates a
## party on demand if the caller isn't in one yet.
func invite_friend(
	friend_player_id: String,
) -> void:
	if is_in_party():
		G.party_api_client.invite_to_party(
			get_party_id(), friend_player_id)
		return
	if has_pending_invite():
		# Auto-creating a new party would silently
		# leave the user's existing invite stranded.
		# Surface a hint so they decline (or accept)
		# the invite first.
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("PARTY.HANDLE_INVITE_FIRST"))
		return
	# Create party first, then invite.
	G.party_api_client.create_party()
	# Queue the invite after creation. `party_created`
	# now emits `{party_id, name}` per the wider event-
	# shape cleanup, so read party_id off the top
	# level (not under a nested "party" key).
	var connection: Callable = func(
		data: Dictionary,
	) -> void:
		var party_id: String = data.get(
			"party_id", "")
		if not party_id.is_empty():
			G.party_api_client.invite_to_party(
				party_id, friend_player_id)
	G.party_api_client.party_created.connect(
		connection, CONNECT_ONE_SHOT)


## Accept a pending invite. The actual party_joined
## signal arrives via the join_group_async callback.
## Optimistically removes the invite from the local
## list so the UI refreshes without waiting for the
## next 3 s poll cycle to confirm the server state.
func accept_invite(party_id: String) -> void:
	G.party_api_client.join_party(party_id)
	_remove_pending_invite(party_id)


## Decline a pending invite. Nakama exposes the
## "decline" operation as leaving the (state=3) group;
## wrapped in a named helper so the UI call site reads
## correctly and the local list updates optimistically.
func decline_invite(party_id: String) -> void:
	G.party_api_client.leave_party(party_id)
	_remove_pending_invite(party_id)


func _remove_pending_invite(party_id: String) -> void:
	var i := 0
	while i < pending_invites.size():
		var inv: Dictionary = pending_invites[i]
		if inv.get("party_id", "") == party_id:
			pending_invites.remove_at(i)
		else:
			i += 1
	_known_invite_ids.erase(party_id)
	# party_updated covers both "active party content
	# changed" and "pending-invite list changed" for the
	# UI's purposes — the panel reads both surfaces on
	# refresh.
	party_updated.emit(current_party)


## Leave the current party.
func leave_current_party() -> void:
	if not is_in_party():
		return
	G.party_api_client.leave_party(get_party_id())


## Kick a member from the party (leader only).
func kick_member(
	target_player_id: String,
) -> void:
	if not is_leader():
		return
	G.party_api_client.kick_from_party(
		get_party_id(), target_player_id)


## Toggle the viewer's own ready state for the current
## party. No-op when the viewer isn't in a party.
##
## Optimistically patches the local `current_party.members`
## entry so the UI reflects the change immediately rather
## than waiting for the catch-up fetch the server-side
## party_state_changed notification triggers.
func set_ready(ready: bool) -> void:
	if not is_in_party():
		return
	var self_id := G.auth_token_store.player_id
	_patch_member_ready(self_id, ready)
	party_updated.emit(current_party)
	G.party_api_client.set_ready(
		get_party_id(), ready)


## Whether the viewer is currently marked ready in this
## party. False when not in a party.
func is_self_ready() -> bool:
	if not is_in_party():
		return false
	var self_id := G.auth_token_store.player_id
	for m in current_party.get("members", []):
		if m is Dictionary and m.get("user_id", "") == self_id:
			return bool(m.get("ready", false))
	return false


## Whether every active (non-invited) member of the
## current party is marked ready. Used by the leader to
## gate the Start Match button.
##
## Returns false when there are no active members so the
## leader doesn't see Start Match enabled in a 1-member
## degenerate party (the start-button enable threshold
## elsewhere already requires >= 2 active members, but
## this method is also called from the gate condition).
func all_active_members_ready() -> bool:
	if not is_in_party():
		return false
	var active_count := 0
	for m in current_party.get("members", []):
		if not (m is Dictionary):
			continue
		if m.get("role", "") == "invited":
			continue
		active_count += 1
		if not bool(m.get("ready", false)):
			return false
	return active_count > 0


func _patch_member_ready(
	user_id: String,
	ready: bool,
) -> void:
	for m in current_party.get("members", []):
		if m is Dictionary and m.get("user_id", "") == user_id:
			m["ready"] = ready
			return


## Start matchmaking for the party.
func start_party_matchmaking() -> void:
	if not is_leader():
		return
	G.party_api_client.start_matchmaking(
		get_party_id())


## Reset all party state. Called on logout.
func reset() -> void:
	current_party.clear()
	pending_invites.clear()
	pending_party_match_context.clear()
	_known_invite_ids.clear()
	_known_state_changed_ids.clear()
	stop_polling()


func _on_auth_completed(
	success: bool, _error: String,
) -> void:
	if not success:
		return
	if not G.auth_token_store.is_token_valid():
		return
	if G.auth_token_store.is_anonymous:
		return
	start_polling()


# party_api_client only emits the operation ack
# (`{party_id, ...}`) on these signals — not the full
# party dict. Each handler now patches local state with
# what it knows and triggers an immediate fetch_party_
# status so the next tick repopulates members /
# leader_id / etc. Pre-fix the code did
# `current_party = data.get("party", {})` which
# silently cleared current_party on every party event
# (data has no "party" key) and relied on broken
# polling to restore it.


func _on_party_created(
	data: Dictionary,
) -> void:
	var party_id: String = data.get("party_id", "")
	current_party = {
		"party_id": party_id,
		"name": data.get("name", ""),
		"leader_id": G.auth_token_store.player_id,
		"members": [],
		"viewer_role": "leader",
	}
	_known_invite_ids.clear()
	start_polling()
	_request_immediate_fetch()
	party_updated.emit(current_party)


func _on_party_invited(
	_data: Dictionary,
) -> void:
	# Leader perspective: their `add_group_users_async`
	# call landed. The invited member shows up on the
	# next fetch.
	_request_immediate_fetch()


func _on_party_joined(
	data: Dictionary,
) -> void:
	var party_id: String = data.get("party_id", "")
	# Seed a minimal current_party so is_in_party()
	# flips true immediately and the panel transitions
	# to the joined-member view. Real member data lands
	# on the next fetch.
	current_party = {
		"party_id": party_id,
		"members": [],
		"viewer_role": "member",
	}
	_known_invite_ids.clear()
	start_polling()
	_request_immediate_fetch()
	party_updated.emit(current_party)


func _on_party_left(data: Dictionary) -> void:
	var disbanded: bool = data.get(
		"disbanded", false)
	if disbanded:
		current_party.clear()
		_known_invite_ids.clear()
		party_disbanded.emit()
	else:
		current_party.clear()
		party_updated.emit({})


func _on_party_kicked(
	_data: Dictionary,
) -> void:
	# Leader kicked a member. Refetch to remove them
	# from the local list.
	_request_immediate_fetch()


func _request_immediate_fetch() -> void:
	if (is_instance_valid(G.party_api_client)
			and not G.party_api_client.is_busy()):
		G.party_api_client.fetch_party_status()


func _on_party_status_received(
	data: Dictionary,
) -> void:
	# Always refresh pending_invites — a user can be in
	# one party AND have outstanding invites to another,
	# so this surface is independent of active-party
	# state.
	var invites: Array = data.get(
		"pending_invites", [])
	pending_invites = invites
	var current_ids: Dictionary = {}
	for inv in invites:
		var pid: String = inv.get("party_id", "")
		current_ids[pid] = true
		if (not pid.is_empty()
				and not _known_invite_ids.has(pid)):
			_known_invite_ids[pid] = true
			invite_received.emit(inv)
	# Drop dedup entries for invites the server no
	# longer reports (declined locally or accepted from
	# a different device).
	for known_id in _known_invite_ids.keys():
		if not current_ids.has(known_id):
			_known_invite_ids.erase(known_id)

	var party_raw: Variant = data.get("party")
	var has_active_party := (
		party_raw is Dictionary
		and not (party_raw as Dictionary).is_empty()
	)

	if not has_active_party:
		if not current_party.is_empty():
			current_party.clear()
			party_disbanded.emit()
		else:
			# Pending invites can still have changed —
			# notify the panel so it re-renders.
			party_updated.emit({})
		return

	current_party = party_raw as Dictionary

	# Check if matchmaking started.
	var status: String = current_party.get(
		"status", "")
	if status == "matchmaking":
		var ticket_id: String = current_party.get(
			"matchmaking_ticket_id", "")
		if not ticket_id.is_empty():
			matchmaking_started.emit(ticket_id)

	party_updated.emit(current_party)


func _on_matchmaking_started(
	data: Dictionary,
) -> void:
	# Leader's RPC-response path. Server doesn't currently issue a
	# Nakama ticket on the caller's behalf (session presence isn't
	# available server-side), so `ticket_id` is usually empty.
	# Stash the matchmaker_properties echoed by the server and
	# trigger the existing client-side matchmaker enqueue flow.
	_start_party_matchmaking(data)
	var ticket_id: String = data.get(
		"ticket_id", "")
	if not ticket_id.is_empty():
		matchmaking_started.emit(ticket_id)
	else:
		matchmaking_started.emit(
			data.get("party_id", ""))


## Follower path: a `party_matchmaking_start` notification arrived
## via the friends_notification_poller. The payload mirrors the
## leader's RPC response, so we use the same kickoff path.
func on_party_matchmaking_notification(
	content: Dictionary,
) -> void:
	_start_party_matchmaking(content)
	matchmaking_started.emit(
		content.get("party_id", ""))


## Shared kickoff used by both leader and follower paths. Stores
## the party context so `GamePanel._client_client_request_session_ids`
## can pick up the `party_id` matchmaker property, then transitions
## the client into the same "playing online" flow a solo Play
## button would.
##
## Skips when a match is already loading or active so re-fetched
## persistent notifications (or a leader+follower race) don't double-
## trigger and don't stash a stale party_id that would attach to the
## next solo match.
func _start_party_matchmaking(
	data: Dictionary,
) -> void:
	if (G.client_session.is_game_loading
			or G.client_session.is_game_active):
		return
	pending_party_match_context = {
		"party_id": data.get("party_id", ""),
		"game_mode": data.get("game_mode", ""),
		"matchmaker_properties": data.get(
			"matchmaker_properties", {}),
	}
	if not is_instance_valid(G.game_panel):
		# Notification arrived before the game panel
		# was ready (e.g., during early bootstrap).
		# Context is stashed; whoever drives the next
		# match-start will pick it up.
		return
	G.game_panel.client_load_game()


func _show_invite_dialog(
	invite_data: Dictionary,
) -> void:
	if not is_instance_valid(G.toast_overlay):
		return
	var leader_name: String = invite_data.get(
		"leader_display_name", "")
	var party_id: String = invite_data.get(
		"party_id", "")
	if leader_name.is_empty():
		leader_name = tr("PARTY.SOMEONE")
	var message: String = (
		tr("PARTY.INVITE_RECEIVED")
		% leader_name)
	G.toast_overlay.show_toast(message)
	# Show confirm dialog for immediate
	# accept/decline.
	if not is_instance_valid(G.confirm_layer):
		return
	var dialog: ConfirmOverlay = (
		G.settings.confirm_overlay_scene
			.instantiate())
	G.confirm_layer.add_child(dialog)
	dialog.open(
		message,
		tr("PARTY.JOIN"),
		func() -> void:
			accept_invite(party_id),
		tr("CONFIRM.CANCEL"),
	)


## Real-time push from the platform runtime on every party group
## membership change. Triggers an immediate refetch; the actual
## state-applying logic is shared with the catch-up poll via
## `_on_party_status_received`.
##
## The notification is transient — Nakama doesn't store it — so we
## only see it while the socket is connected. Catch-up after a
## socket drop is handled by the periodic poll in `_process` plus
## the immediate fetch on `socket_connected`.
func _on_socket_notification(
	subject: String,
	content: Dictionary,
	notification_id: String,
) -> void:
	if subject != _PARTY_STATE_CHANGED_SUBJECT:
		return
	# Dedup. The matchmaker socket and the notification socket may
	# both deliver the same Nakama notification id while matchmaking
	# is in flight — only fan out the first one.
	if (not notification_id.is_empty()
			and _known_state_changed_ids.has(notification_id)):
		return
	if not notification_id.is_empty():
		_known_state_changed_ids[notification_id] = true
		# Trim the dedup map opportunistically so it doesn't grow
		# unbounded across long sessions. 64 is generous — party
		# events for any one viewer are sparse.
		if _known_state_changed_ids.size() > 64:
			var keys: Array = (
				_known_state_changed_ids.keys())
			for i in keys.size() - 64:
				_known_state_changed_ids.erase(keys[i])
	# `content.event` (invited / joined / left / kicked) is
	# unused today — we always refetch to get the canonical state.
	# Kept on the wire so a future UI can render a per-event toast
	# without a second roundtrip.
	_request_immediate_fetch()


## Refresh local state when the notification socket reconnects, so
## any party events that fired while we were disconnected get
## reflected. The catch-up poll would catch them too, just on the
## next ~60 s tick.
func _on_socket_connected() -> void:
	if not G.auth_token_store.is_token_valid():
		return
	_request_immediate_fetch()
