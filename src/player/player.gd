class_name Player
extends Character


var has_authority: bool:
    get: return get_multiplayer_authority() == multiplayer.get_unique_id()

var networked_state := PlayerNetworkedState.new()


func _ready() -> void:
    networked_state.name = "NetworkedState"
    add_child(networked_state)


func _physics_process(delta: float) -> void:
    super._physics_process(delta)
    
    networked_state.update(self)


func _update_actions() -> void:
    if has_authority:
        super._update_actions()
    else:
        # Don't update actions per-frame. Instead, actions are updated when
        # networked state is replicated.
        pass


# FIXME: LEFT OFF HERE: CALL THIS
func _on_has_authority_changed(has_authority: bool) -> void:
    networked_state.set_has_authority(has_authority)


func play_sound(sound_name: String) -> void:
    # FIXME: Implement sounds.
    match sound_name:
        "jump":
            pass
        "land":
            pass
