class_name PlayerStatePanel
extends PanelContainer


@export var toast_scene: PackedScene
@export var toast_fade_duration := 0.5
@export var toast_fade_delay := 1.5

var player: Player


func clear() -> void:
    %Actions.text = ""
    %Position.text = ""
    %Velocity.text = ""
    %AttachmentSide.text = ""
    %AttachmentPosition.text = ""
    %AttachmentNormal.text = ""


func _process(_delta: float) -> void:
    # FIXME: Update this to use whichever player is relevant.
    if not is_instance_valid(G.level) or G.level.players.is_empty():
        clear()
        return
    if not is_instance_valid(player):
        player = G.level.players[0]
        player.connect("physics_processed", _on_player_physics_processed)

    %Actions.text = CharacterActionState.get_debug_label_from_actions_bitmask(player.actions.current_actions_bitmask)
    %Position.text = G.utils.get_vector_string(player.position, 1)
    %Velocity.text = G.utils.get_vector_string(player.velocity, 1)
    %AttachmentSide.text = SurfaceSide.get_string(player.surface_state.attachment_side)
    %AttachmentPosition.text = G.utils.get_vector_string(player.surface_state.attachment_position, 1)
    %AttachmentNormal.text = G.utils.get_vector_string(player.surface_state.attachment_normal, 1)


func _on_player_physics_processed() -> void:
    #if player.just_triggered_jump:
        #add_toast("Jumped")
    if player.surface_state.just_changed_attachment_side:
        add_toast("Attached to %s" % SurfaceSide.get_string(player.surface_state.attachment_side))


func add_toast(text: String) -> void:
    var toast: PlayerStatePanelToast = toast_scene.instantiate()
    toast.text = text
    %Toasts.add_child(toast)
    %Toasts.move_child(toast, 0)
    
    var tween = get_tree().create_tween()
    tween.tween_property(toast, "modulate:a", 0, toast_fade_duration).set_delay(toast_fade_delay)
    await tween.step_finished
    toast.queue_free()
