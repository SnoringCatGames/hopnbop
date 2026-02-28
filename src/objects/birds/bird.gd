class_name Bird
extends Node2D
## A single bird that flies across the level in a
## near-horizontal line with a gentle curve.
## Client-side only, purely decorative.


## Flight speed in pixels per second.
const FLIGHT_SPEED := 90.0

## Max random deviation from horizontal (degrees).
const MAX_ANGLE_DEVIATION_DEG := 3.0

## Angular drift per second (degrees) for gentle
## arc curvature.
const CURVE_RATE_DEG := 0.5

## Distance beyond camera edge before despawning.
const OFFSCREEN_MARGIN := 30.0

var _direction := Vector2.RIGHT
var _curve_rate_rad := 0.0
var _camera: Camera2D
var _viewport_size := Vector2.ZERO

@onready var _sprite: Sprite2D = $Sprite2D


func setup(
	camera: Camera2D,
	viewport_size: Vector2,
	direction: Vector2,
	curve_rate_rad: float,
) -> void:
	_camera = camera
	_viewport_size = viewport_size
	_direction = direction.normalized()
	_curve_rate_rad = curve_rate_rad


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Flip sprite when flying leftward.
	if _direction.x < 0.0:
		_sprite.flip_h = true


func _process(delta: float) -> void:
	# Rotate direction for gentle curve.
	_direction = _direction.rotated(
		_curve_rate_rad * delta)

	# Move along direction.
	position += _direction * FLIGHT_SPEED * delta

	# Despawn when past the opposite edge.
	if _is_past_opposite_edge():
		queue_free()


func _is_past_opposite_edge() -> bool:
	if not is_instance_valid(_camera):
		return true
	var visible_size: Vector2 = (
		_viewport_size / _camera.zoom)
	var half_w: float = visible_size.x / 2.0
	var cam_x: float = _camera.global_position.x

	# Check against the edge the bird is flying
	# toward.
	if _direction.x > 0.0:
		return position.x > (
			cam_x + half_w + OFFSCREEN_MARGIN)
	else:
		return position.x < (
			cam_x - half_w - OFFSCREEN_MARGIN)
