@tool
class_name CharacterStateFromServer
extends ReconcilableNetworkedState


# FIXME: Override configuration warnings to check this is set.
@export var character: Character

var _state_from_client: PlayerStateFromClient:
    get:
        if is_instance_valid(_partner_state):
            return _partner_state as PlayerStateFromClient
        else:
            return null

var position: Vector2
var velocity: Vector2
## A bitmask representing the player's surface state.
var surfaces: int

const _synced_properties_and_rollback_diff_thresholds := {
    position = DEFAULT_POSITION_DIFF_ROLLBACK_THRESHELD,
    velocity = DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHELD,
    surfaces = 0,
}


func _network_process() -> void:
    if not G.ensure_valid(character):
        return

    if:
        pass
    
    super._network_process()


func _sync_to_scene_state() -> void:
    if not G.ensure_valid(character):
        return

    # FIXME: LEFT OFF HERE: ACTUALLY: Character process.

    character.position = position
    character.velocity = velocity
    character.surfaces.bitmask = surfaces

    # FIXME: LEFT OFF HERE: ACTUALLY, ACTUALLY: ----------
    # - Also sync surface state.
    # - Also sync _previous_ state for all of these properties.
    # - Also remove all previous logic that used to update previous state.
    character.actions.previous_bitmask
    character.surfaces.previous_bitmask

    # FIXME: LEFT OFF HERE: ACTUALLY: Add a utility for accessing previous frame
    #        state (get_previous(property_name: String)).

    character.previous_position = position


func _sync_from_scene_state() -> void:
    if not G.ensure_valid(character):
        return

    # FIXME: LEFT OFF HERE: ACTUALLY: Character process.

    pass
