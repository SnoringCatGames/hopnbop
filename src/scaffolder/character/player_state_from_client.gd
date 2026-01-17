@tool
class_name PlayerStateFromClient
extends ReconcilableNetworkedState


# FIXME: Override configuration warnings to check this is set.
@export var player: Player

var _state_from_server: CharacterStateFromServer:
    get:
        if is_instance_valid(_partner_state):
            return _partner_state as CharacterStateFromServer
        else:
            return null

## A bitmask representing which of the player's actions are active.
var actions := 0

const _synced_properties_and_rollback_diff_thresholds := {
    actions = 0,
}


func _get_default_values() -> Array:
    return [
        0,
    ]


func _exit_tree() -> void:
    if is_multiplayer_authority():
        G.network.local_authority_removed.emit(self)


func update_authority() -> void:
    var was_multiplayer_authority := is_multiplayer_authority()
    super.update_authority()
    if is_multiplayer_authority() and not was_multiplayer_authority:
        G.network.local_authority_added.emit(self)


func _network_process() -> void:
    # CharacterStateFromServer handles _network_process for itself and any
    # corresponding PlayerStateFromClient.
    pass


func _sync_to_scene_state() -> void:
    if not G.ensure_valid(player):
        return

    # FIXME: LEFT OFF HERE: ACTUALLY: Character process.

    player.actions.bitmask = actions

    pass


func _sync_from_scene_state() -> void:
    if not G.ensure_valid(player):
        return

    # FIXME: LEFT OFF HERE: ACTUALLY: Character process.

    pass
