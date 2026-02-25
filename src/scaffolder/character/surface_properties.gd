class_name SurfaceProperties
extends RefCounted

# TODO:
# - Add some way of checking fall-through/walk-through state.
#   - And add a way to validate that this matches the normal TileSet encoding.

const KEYS := ["can_attach", "friction_multiplier", "speed_multiplier", "clockwise_speed_offset"]

var name: StringName

var can_attach := true

var friction_multiplier := 1.0

## -   This affects the character's speed while moving along the surface.[br]
## -   This does not affect jump start/end velocities or in-air velocities.[br]
## -   This will modify both acceleration and max-speed.[br]
var speed_multiplier := 1.0

## Multiplier for walk acceleration only (does not
## affect max speed). Used for ice surfaces where
## acceleration is reduced but max speed is not.
var acceleration_multiplier := 1.0

var is_ice := false


func reset() -> void:
	friction_multiplier = 1.0
	speed_multiplier = 1.0
	acceleration_multiplier = 1.0
	is_ice = false
