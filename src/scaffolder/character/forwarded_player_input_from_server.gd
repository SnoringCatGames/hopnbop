@tool
class_name ForwardedPlayerInputFromServer
extends PlayerInputNetworkState


@export var player: Player:
	set(value):
		player = value
		update_configuration_warnings()

var is_authority_for_forwarded_input: bool:
	get:
		return is_multiplayer_authority()


func _get_is_server_authoritative() -> bool:
	return true


func _should_accept_predicted_states() -> bool:
	# ForwardedPlayerInputFromServer must accept PREDICTED states because
	# remote clients have no local input to predict with - the server's
	# predicted input (based on extrapolation) is the only source available.
	return true


func _should_create_debug_buffer() -> bool:
	return true


func _ready() -> void:
	super._ready()
	update_configuration_warnings()
	if Engine.is_editor_hint():
		return
	add_visibility_filter(_visibility_filter)
	record_initial_state(false)


func _visibility_filter(p_peer_id: int) -> bool:
	# Hide from the originating player (they already have local input).
	return p_peer_id != peer_id


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super._get_configuration_warnings()
	if not is_instance_valid(player):
		warnings.append("player is not set")

	# Validate that PlayerInputFromClient sibling is present.
	if input_from_client == null:
		warnings.append("ForwardedPlayerInputFromServer requires a PlayerInputFromClient sibling node")
	else:
		# Validate that synced properties match by calling the validation on
		# PlayerInputFromClient (avoids duplicating logic).
		var property_mismatch := input_from_client._validate_synced_properties_match(self )
		if not property_mismatch.is_empty():
			warnings.append(property_mismatch)

	return warnings


func _network_process() -> void:
	# CharacterStateFromServer handles forwarding during _post_network_process.
	pass


func _sync_to_scene_state(previous_state: Array) -> void:
	# Only sync to scene state for remote players. Local player already has
	# their own input through PlayerInputFromClient.
	if is_instance_valid(player) and is_instance_valid(player.input_from_client):
		# Player has local input source, don't override with forwarded input.
		if not G.is_networked_level_active:
			# In local mode, input_from_client presence means local control.
			return
		if player.input_from_client.is_multiplayer_authority():
			# In networked mode, check multiplayer authority.
			return

	if not Netcode.ensure_valid(player):
		return

	player.actions.bitmask = actions

	player.actions.previous_bitmask = previous_state[_property_name_to_pack_index.actions]

	match last_interaction_type:
		ClientInteractionType.NONE:
			pass
		ClientInteractionType.JUMP:
			player.last_triggered_jump_frame_index = last_interaction_frame_index
		_:
			Netcode.fatal()


func _sync_from_scene_state() -> void:
	# Don't sync from scene state. This node is server-authoritative and gets
	# its data from CharacterStateFromServer._network_process(), not from
	# the player's scene state.
	pass


func _reconcile_client_interaction() -> void:
	# Only reconcile client interactions for remote players. The local player
	# uses PlayerInputFromClient for client interaction reconciliation.
	if is_instance_valid(player) and is_instance_valid(player.input_from_client):
		# Player has local input source, don't reconcile via forwarded input.
		if not G.is_networked_level_active:
			# In local mode, input_from_client presence means local control.
			return
		if player.input_from_client.is_multiplayer_authority():
			# In networked mode, check multiplayer authority.
			return

	super._reconcile_client_interaction()
