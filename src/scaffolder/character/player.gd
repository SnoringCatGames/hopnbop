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


func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		return
	if G.network.is_client:
		# On clients, wait for multiplayer_id to be replicated before adding
		# to level's players_by_id dictionary.
		state_from_server.multiplayer_id_changed.connect(
			_on_multiplayer_id_replicated,
			CONNECT_ONE_SHOT,
		)
	else:
		# Server sets multiplayer_id before adding to tree, so add immediately.
		G.level.on_player_added(self)


func _on_multiplayer_id_replicated() -> void:
	G.level.on_player_added(self)


func _exit_tree() -> void:
	super._exit_tree()
	if Engine.is_editor_hint():
		return
	if is_instance_valid(G.level):
		G.level.on_player_removed(self)


func _ready() -> void:
	super._ready()
	update_configuration_warnings()


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()


func get_is_player_control_active() -> bool:
	return is_instance_valid(input_from_client) and input_from_client.is_multiplayer_authority()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_instance_valid(input_from_client):
		warnings.append("input_from_client is not set")
	if not is_instance_valid(forwarded_input_from_server):
		warnings.append("forwarded_input_from_server is not set")
	return warnings
