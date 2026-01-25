@tool
class_name Player
extends Character


@export var input_from_client: PlayerInputFromClient:
	set(value):
		input_from_client = value
		update_configuration_warnings()

@export var forwarded_input_from_server: ForwardedPlayerInputFromServer:
	set(value):
		forwarded_input_from_server = value
		update_configuration_warnings()

var player_id: int:
	set(value):
		state_from_server.player_id = value
	get:
		return state_from_server.player_id


func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		return
	if G.network.is_client:
		# On clients, wait for player_id to be replicated before adding
		# to level's players_by_id dictionary.
		state_from_server.player_id_changed.connect(
			_client_on_player_id_replicated,
			CONNECT_ONE_SHOT,
		)
	else:
		# Server sets player_id before adding to tree, so add immediately.
		G.level.register_player(self)


func _client_on_player_id_replicated(new_player_id: int) -> void:
	player_id = new_player_id
	G.level.register_player(self)


func _exit_tree() -> void:
	super._exit_tree()
	if Engine.is_editor_hint():
		return
	if is_instance_valid(G.level):
		G.level.deregister_player(self)


func _ready() -> void:
	super._ready()
	update_configuration_warnings()


func on_match_state_ready(_player_match_state: PlayerMatchState) -> void:
	_set_up_action_sources()


func _set_up_action_sources() -> void:
	if not _action_sources.is_empty():
		return

	var player_match_state := G.get_player_match_state(player_id)
	if not is_instance_valid(player_match_state):
		# Player state not replicated yet.
		return

	var device_config := G.input_device_manager.get_device_for_player(
		player_match_state.local_player_index)
	if not G.ensure(is_instance_valid(device_config),
			"DeviceConfig not registered for player"):
		return

	var player_action_source := PlayerActionSource.new(
		self,
		true,
		device_config)
	_action_sources.append(player_action_source)


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()


func get_is_player_control_active() -> bool:
	return (
		is_instance_valid(input_from_client) and
		input_from_client.is_multiplayer_authority()
	)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_instance_valid(input_from_client):
		warnings.append("input_from_client is not set")
	if not is_instance_valid(forwarded_input_from_server):
		warnings.append("forwarded_input_from_server is not set")
	return warnings
