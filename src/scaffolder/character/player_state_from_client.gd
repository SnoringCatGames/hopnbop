@tool
class_name PlayerStateFromClient
extends ReconcilableNetworkedState


# FIXME: Override configuration warnings to check this is set.
@export var player: Player

## A bitmask representing which of the player's actions are active.
var actions: int

const _synced_properties_and_rollback_diff_thresholds := {
    actions = 0,
}


func _sync_to_scene_state() -> void:
    G.ensure(is_instance_valid(player))

    # FIXME: LEFT OFF HERE: ACTUALLY: Character process.

    player.actions.bitmask = actions

    pass


func _sync_from_scene_state() -> void:
    G.ensure(is_instance_valid(player))

    # FIXME: LEFT OFF HERE: ACTUALLY: Character process.

    pass
