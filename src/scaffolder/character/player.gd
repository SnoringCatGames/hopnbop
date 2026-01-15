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
    super._enter_tree()
    G.level.on_player_added(self)


func _exit_tree() -> void:
    super._exit_tree()
    if is_instance_valid(G.level):
        G.level.on_player_removed(self)


func _ready() -> void:
    super._ready()
    if is_instance_valid(state_from_server):
        state_from_server.connect("network_processed", _network_process)


func _physics_process(delta: float) -> void:
    super._physics_process(delta)


func _network_process() -> void:
    super._network_process()


func _update_actions() -> void:
    # FIXME: LEFT OFF HERE:
    if is_multiplayer_authority():
        super._update_actions()
    else:
        # Don't update actions per-frame. Instead, actions are updated when
        # networked state is replicated.
        pass
