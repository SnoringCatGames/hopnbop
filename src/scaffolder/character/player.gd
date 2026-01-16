class_name Player
extends Character


# FIXME: LEFT OFF HERE: ACTUALLY: Input collection.
# - Make sure we only collect input when
#   input_from_client.is_multiplayer_authority().
@export var input_from_client: PlayerStateFromClient


func _enter_tree() -> void:
    super._enter_tree()
    G.level.on_player_added(self)


func _exit_tree() -> void:
    super._exit_tree()
    if is_instance_valid(G.level):
        G.level.on_player_removed(self)


func _ready() -> void:
    super._ready()


func _network_process() -> void:
    super._network_process()


func _update_actions() -> void:
    # FIXME: LEFT OFF HERE: ACTUALLY: Input collection.
    if is_multiplayer_authority():
        super._update_actions()
    else:
        # Don't update actions per-frame. Instead, actions are updated when
        # networked state is replicated.
        pass


func get_is_player_control_active() -> bool:
    return is_instance_valid(input_from_client) and \
        input_from_client.is_multiplayer_authority()
