class_name PlayerStatePanel
extends PanelContainer


func _process(_delta: float) -> void:
    if not is_instance_valid(G.level) or G.level.players.is_empty():
        clear()
        return

    # FIXME: Update this to use whichever player is relevant.
    var player: Player = G.level.players[0]
    %Actions.text = CharacterActionState.get_debug_label_from_actions_bitmask(player.actions.current_actions_bitmask)
    %Position.text = G.utils.get_vector_string(player.position, 1)
    %Velocity.text = G.utils.get_vector_string(player.velocity, 1)
    %AttachmentSide.text = SurfaceSide.get_string(player.surface_state.attachment_side)
    %AttachmentPosition.text = G.utils.get_vector_string(player.surface_state.attachment_position, 1)
    %AttachmentNormal.text = G.utils.get_vector_string(player.surface_state.attachment_normal, 1)


func clear() -> void:
    %Actions.text = ""
    %Position.text = ""
    %Velocity.text = ""
    %AttachmentSide.text = ""
    %AttachmentPosition.text = ""
    %AttachmentNormal.text = ""
