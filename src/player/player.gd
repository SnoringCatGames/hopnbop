class_name Player
extends Character


@export var state_from_server: PlayerStateFromServer
@export var input_from_client: PlayerStateFromClient

# FIXME: LEFT OFF HERE: ACTUALLY: Input collection.
# - Make sure we only collect input when
#   input_from_client.is_multiplayer_authority().
var multiplayer_id: int:
    set(value):
        state_from_server.multiplayer_id = value
        input_from_client.multiplayer_id = value
    get:
        return state_from_server.multiplayer_id


func _enter_tree() -> void:
    G.level.on_player_added(self)


func _exit_tree() -> void:
    G.level.on_player_removed(self)


func _physics_process(delta: float) -> void:
    super._physics_process(delta)


func _network_process() -> void:
    # FIXME: [Rollback]
    pass


func _update_actions() -> void:
    if is_multiplayer_authority():
        super._update_actions()
    else:
        # Don't update actions per-frame. Instead, actions are updated when
        # networked state is replicated.
        pass


func play_sound(sound_name: String) -> void:
    # TODO: Implement sounds.
    match sound_name:
        "jump":
            pass
        "land":
            pass
