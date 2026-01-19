@tool
class_name Player
extends Character

@export var input_from_client: PlayerInputFromClient:
    set(value):
        input_from_client = value
        update_configuration_warnings()


func _enter_tree() -> void:
    super._enter_tree()
    if Engine.is_editor_hint():
        return
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


func _network_process() -> void:
    super._network_process()


func get_is_player_control_active() -> bool:
    return is_instance_valid(input_from_client) and input_from_client.is_multiplayer_authority()


func _get_configuration_warnings() -> PackedStringArray:
    var warnings := PackedStringArray()
    if not is_instance_valid(input_from_client):
        warnings.append("input_from_client is not set")
    return warnings
