class_name Fly
extends CharacterBody2D
## A single fly in a fly swarm. Uses move_and_slide
## for collision with level and player geometry.
## Client-side only.


# Random sprite offsets applied each render frame
# to simulate wing flutter.
const _SPRITE_OFFSETS: Array[Vector2] = [
	Vector2(0, 0),
	Vector2(-1, 0),
	Vector2(0, -1),
	Vector2(-1, -1),
]

var _sprite: Sprite2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Nothing collides with the fly.
	collision_layer = 0
	# Fly collides against normal_surfaces (bit 0)
	# and player bodies (bit 3).
	collision_mask = (1 << 0) | (1 << 3)
	up_direction = Vector2.UP
	floor_stop_on_slope = false
	_sprite = $Sprite2D


func _process(_delta: float) -> void:
	# Assign random sprite offset each render
	# frame for jittery 1px appearance.
	_sprite.offset = _SPRITE_OFFSETS[
		randi() % _SPRITE_OFFSETS.size()]
