@tool
class_name PlayerStateFromServer
extends NetworkedState


var position: Vector2
var velocity: Vector2
var is_facing_right: bool

var attachment_side: int
var attachment_position: Vector2
var attachment_normal: Vector2

const _property_diff_rollback_thresholds := {
    position = DEFAULT_POSITION_DIFF_ROLLBACK_THRESHELD,
    velocity = DEFAULT_VELOCITY_DIFF_ROLLBACK_THRESHELD,
    is_facing_right = 0,

    attachment_side = 0,
    attachment_position = DEFAULT_POSITION_DIFF_ROLLBACK_THRESHELD,
    attachment_normal = DEFAULT_NORMAL_DIFF_ROLLBACK_THRESHELD,
}
