class_name PlayerNetworkedState
extends Node


var actions := NetworkedProperty.new(NetworkedProperty.NetworkedDataType.INT)

var position := NetworkedProperty.new(NetworkedProperty.NetworkedDataType.VECTOR2)
var velocity := NetworkedProperty.new(NetworkedProperty.NetworkedDataType.VECTOR2)
var is_facing_right := NetworkedProperty.new(NetworkedProperty.NetworkedDataType.BOOL)

var attachment_side := NetworkedProperty.new(NetworkedProperty.NetworkedDataType.INT)
var attachment_position := NetworkedProperty.new(NetworkedProperty.NetworkedDataType.VECTOR2)
var attachment_normal := NetworkedProperty.new(NetworkedProperty.NetworkedDataType.VECTOR2)


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

    actions.name = "Actions"
    position.name = "Position"
    velocity.name = "Velocity"
    is_facing_right.name = "IsFacingRight"
    attachment_side.name = "AttachmentSide"
    attachment_position.name = "AttachmentPosition"
    attachment_normal.name = "AttachmentNormal"

    for property in _get_all_properties():
        add_child(property)


func update(player: Player) -> void:
    _sync_local_simulation_values_from_player(player)
    _sync_networked_values_to_player(player)


func _sync_local_simulation_values_from_player(player: Player) -> void:
    actions.update_local_value(player.actions.current_actions_bitmask)
    position.update_local_value(player.global_position)
    velocity.update_local_value(player.velocity)
    is_facing_right.update_local_value(player.surface_state.is_facing_right)
    attachment_side.update_local_value(player.surface_state.attachment_side)
    attachment_position.update_local_value(player.surface_state.attachment_position)
    attachment_normal.update_local_value(player.surface_state.attachment_normal)


func _sync_networked_values_to_player(player: Player) -> void:
    player.actions.current_actions_bitmask = actions.local_value
    player.global_position = position.local_value
    player.velocity = velocity.local_value
    player.surface_state.is_facing_right = is_facing_right.local_value
    player.surface_state.attachment_side = attachment_side.local_value
    player.surface_state.attachment_position = attachment_position.local_value
    player.surface_state.attachment_normal = attachment_normal.local_value


func set_has_authority(has_authority: bool) -> void:
    for property in _get_all_properties():
        property.has_authority = has_authority


func _get_all_properties() -> Array:
    return [
        actions,
        position,
        velocity,
        is_facing_right,
        attachment_side,
        attachment_position,
        attachment_normal,
    ]
