class_name PartyManager
extends Node
## Manages party state and polls for updates.
## Child of Global autoload. Starts idle polling
## on authentication to discover pending invites.
## Switches to active polling when in a party.


signal party_updated(party_data: Dictionary)
signal party_disbanded
signal matchmaking_started(ticket_id: String)
signal invite_received(invite_data: Dictionary)

const _ACTIVE_POLL_INTERVAL_SEC := 3.0
const _IDLE_POLL_INTERVAL_SEC := 10.0

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
var _current_poll_interval := _IDLE_POLL_INTERVAL_SEC
var _known_invite_ids: Dictionary = {}


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


func _process(delta: float) -> void:
	if not _is_polling:
		return
	if not G.auth_token_store.is_token_valid():
		return

	_poll_timer += delta
	if _poll_timer >= _current_poll_interval:
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


## Whether the player is currently in a party.
func is_in_party() -> bool:
	return not current_party.is_empty()


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


## Invite a friend to the current party.
func invite_friend(
	friend_player_id: String,
) -> void:
	if not is_in_party():
		# Create party first, then invite.
		G.party_api_client.create_party()
		# Queue the invite after creation.
		var connection: Callable = func(
			data: Dictionary,
		) -> void:
			var party: Dictionary = data.get(
				"party", {})
			var party_id: String = party.get(
				"party_id", "")
			if not party_id.is_empty():
				G.party_api_client\
					.invite_to_party(
						party_id,
						friend_player_id)
		G.party_api_client.party_created.connect(
			connection, CONNECT_ONE_SHOT)
		return

	G.party_api_client.invite_to_party(
		get_party_id(), friend_player_id)


## Accept an invite.
func accept_invite(party_id: String) -> void:
	G.party_api_client.join_party(party_id)


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
	_current_poll_interval = (
		_IDLE_POLL_INTERVAL_SEC)
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
	_current_poll_interval = (
		_IDLE_POLL_INTERVAL_SEC)
	start_polling()


func _on_party_created(
	data: Dictionary,
) -> void:
	var party: Dictionary = data.get("party", {})
	current_party = party
	_current_poll_interval = (
		_ACTIVE_POLL_INTERVAL_SEC)
	_known_invite_ids.clear()
	start_polling()
	party_updated.emit(party)


func _on_party_invited(
	data: Dictionary,
) -> void:
	var party: Dictionary = data.get("party", {})
	current_party = party
	party_updated.emit(party)


func _on_party_joined(
	data: Dictionary,
) -> void:
	var party: Dictionary = data.get("party", {})
	current_party = party
	_current_poll_interval = (
		_ACTIVE_POLL_INTERVAL_SEC)
	_known_invite_ids.clear()
	start_polling()
	party_updated.emit(party)


func _on_party_left(data: Dictionary) -> void:
	var disbanded: bool = data.get(
		"disbanded", false)
	if disbanded:
		current_party.clear()
		_current_poll_interval = (
			_IDLE_POLL_INTERVAL_SEC)
		_known_invite_ids.clear()
		party_disbanded.emit()
	else:
		var party: Dictionary = data.get(
			"party", {})
		current_party = party
		party_updated.emit(party)


func _on_party_kicked(
	data: Dictionary,
) -> void:
	var party: Dictionary = data.get("party", {})
	current_party = party
	party_updated.emit(party)


func _on_party_status_received(
	data: Dictionary,
) -> void:
	var party = data.get("party")
	if party == null or (
		party is Dictionary and party.is_empty()
	):
		# No active party. Check invites.
		if not current_party.is_empty():
			current_party.clear()
			_current_poll_interval = (
				_IDLE_POLL_INTERVAL_SEC)
			party_disbanded.emit()
		var invites: Array = data.get(
			"pending_invites", [])
		pending_invites = invites
		for inv in invites:
			var pid: String = inv.get(
				"party_id", "")
			if (not pid.is_empty()
					and not _known_invite_ids
						.has(pid)):
				_known_invite_ids[pid] = true
				invite_received.emit(inv)
		return

	if party is Dictionary:
		current_party = party

		# Check if matchmaking started.
		var status: String = party.get(
			"status", "")
		if status == "matchmaking":
			var ticket_id: String = party.get(
				"matchmaking_ticket_id", "")
			if not ticket_id.is_empty():
				matchmaking_started.emit(
					ticket_id)

		party_updated.emit(party)


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
