@tool
class_name PlayerInputFromClient
extends PlayerInputNetworkState


@export var player: Player:
	set(value):
		player = value
		update_configuration_warnings()


func _get_is_server_authoritative() -> bool:
	return false


func _ready() -> void:
	super._ready()
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super._get_configuration_warnings()
	if not is_instance_valid(player):
		warnings.append("player is not set")

	# Validate that ForwardedPlayerInputFromServer sibling is present.
	if forwarded_input_from_server == null:
		warnings.append("PlayerInputFromClient requires a ForwardedPlayerInputFromServer sibling node")
	else:
		# Validate that synced properties match.
		var property_mismatch := _validate_synced_properties_match(forwarded_input_from_server)
		if not property_mismatch.is_empty():
			warnings.append(property_mismatch)

	return warnings


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if is_multiplayer_authority():
		Netcode.local_authority_removed.emit(self)


func update_authority() -> void:
	var was_multiplayer_authority := is_multiplayer_authority()
	super.update_authority()
	if is_multiplayer_authority() and not was_multiplayer_authority:
		Netcode.local_authority_added.emit(self)


func _network_process() -> void:
	# CharacterStateFromServer handles _network_process for itself and any
	# corresponding PlayerInputFromClient.
	pass


func _post_network_process() -> void:
	super._post_network_process()


func _sync_to_scene_state(previous_state: Array) -> void:
	if not G.ensure_valid(player):
		return

	# Only sync to scene state if this is the locally-controlled player.
	# Remote players get their input state from ForwardedPlayerInputFromServer.
	if not is_multiplayer_authority():
		return

	player.actions.bitmask = actions

	player.actions.previous_bitmask = previous_state[_property_name_to_pack_index.actions]


func _sync_from_scene_state() -> void:
	if not G.ensure_valid(player):
		return

	# Only sync from scene state if this client has authority.
	if not is_multiplayer_authority():
		return

	actions = player.actions.bitmask

	# Record jump interaction when jump is triggered.
	if player.last_triggered_jump_frame_index >= 0:
		record_interaction(
			ClientInteractionType.JUMP,
			player.last_triggered_jump_frame_index,
			player.global_position,
			Vector2.ZERO
		)


func _find_forwarded_input_sibling() -> ForwardedPlayerInputFromServer:
	if not is_node_ready():
		return null
	for child in get_parent().get_children():
		if child is ForwardedPlayerInputFromServer:
			return child as ForwardedPlayerInputFromServer
	return null


func _validate_synced_properties_match(
	forwarded_input: ForwardedPlayerInputFromServer
) -> String:
	var input_properties: Dictionary = (
		_synced_properties_and_rollback_diff_thresholds
	)
	var forwarded_properties: Dictionary = (
		forwarded_input._synced_properties_and_rollback_diff_thresholds
	)

	# Check if property names match.
	var input_keys := input_properties.keys()
	var forwarded_keys := forwarded_properties.keys()

	input_keys.sort()
	forwarded_keys.sort()

	if input_keys != forwarded_keys:
		return (
			"PlayerInputFromClient and ForwardedPlayerInputFromServer " +
			"must have matching _synced_properties_and_rollback_diff_thresholds " +
			"keys. Expected: %s, Got: %s"
		) % [input_keys, forwarded_keys]

	return ""
