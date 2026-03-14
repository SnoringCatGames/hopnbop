class_name PartyManager
extends Node
## Manages party state and polls for updates.
## Child of Global autoload.


signal party_updated(party_data: Dictionary)
signal party_disbanded
signal matchmaking_started(ticket_id: String)
signal invite_received(invite_data: Dictionary)

const _POLL_INTERVAL_SEC := 3.0

var current_party: Dictionary = {}
var pending_invites: Array = []

var _poll_timer := 0.0
var _is_polling := false


func _ready() -> void:
	G.party_api_client.party_created.connect(
		_on_party_created)
	G.party_api_client.party_invited.connect(
		_on_party_invited)
	G.party_api_client.party_joined.connect(
		_on_party_joined)
	G.party_api_client.party_left.connect(
		_on_party_left)
	G.party_api_client.party_status_received\
		.connect(_on_party_status_received)
	G.party_api_client\
		.party_matchmaking_started.connect(
			_on_matchmaking_started)


func _process(delta: float) -> void:
	if not _is_polling:
		return
	if not G.auth_token_store.is_token_valid():
		return

	_poll_timer += delta
	if _poll_timer >= _POLL_INTERVAL_SEC:
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
func invite_friend(friend_player_id: String) -> void:
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


## Start matchmaking for the party.
func start_party_matchmaking() -> void:
	if not is_leader():
		return
	G.party_api_client.start_matchmaking(
		get_party_id())


func _on_party_created(data: Dictionary) -> void:
	var party: Dictionary = data.get("party", {})
	current_party = party
	start_polling()
	party_updated.emit(party)


func _on_party_invited(data: Dictionary) -> void:
	var party: Dictionary = data.get("party", {})
	current_party = party
	party_updated.emit(party)


func _on_party_joined(data: Dictionary) -> void:
	var party: Dictionary = data.get("party", {})
	current_party = party
	start_polling()
	party_updated.emit(party)


func _on_party_left(data: Dictionary) -> void:
	var disbanded: bool = data.get(
		"disbanded", false)
	if disbanded:
		current_party.clear()
		stop_polling()
		party_disbanded.emit()
	else:
		var party: Dictionary = data.get(
			"party", {})
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
			party_disbanded.emit()
		var invites: Array = data.get(
			"pending_invites", [])
		if not invites.is_empty():
			pending_invites = invites
			for inv in invites:
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
	var ticket_id: String = data.get(
		"ticket_id", "")
	var party_id: String = data.get(
		"party_id", "")
	if not ticket_id.is_empty():
		matchmaking_started.emit(ticket_id)
