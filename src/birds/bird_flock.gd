class_name BirdFlock
extends Node2D
## Periodically spawns birds that fly across the
## level. Client-side only, purely decorative.


## Minimum seconds between bird spawns.
const SPAWN_INTERVAL_MIN := 4.0

## Maximum seconds between bird spawns.
const SPAWN_INTERVAL_MAX := 9.0

## Maximum simultaneous birds on screen.
const MAX_BIRDS := 3

const _BIRD_SCENE_PATH := \
	"res://src/birds/bird.tscn"

## Fraction of camera height for vertical spawn
## range (0.0 to 1.0).
var flight_band_height := 0.5

## Vertical offset of the flight band as a fraction
## of camera height. Negative = upward.
var flight_band_vertical_offset := 0.0

var _camera: Camera2D
var _viewport_size := Vector2.ZERO
var _spawn_timer := 0.0
var _bird_scene: PackedScene


func setup(camera: Camera2D) -> void:
	_camera = camera


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bird_scene = preload(_BIRD_SCENE_PATH)
	_viewport_size = get_viewport() \
		.get_visible_rect().size
	_spawn_timer = randf_range(
		SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)


func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = randf_range(
			SPAWN_INTERVAL_MIN,
			SPAWN_INTERVAL_MAX)
		if _get_bird_count() < MAX_BIRDS:
			_spawn_bird()


func _spawn_bird() -> void:
	if not is_instance_valid(_camera):
		return

	var visible_size: Vector2 = (
		_viewport_size / _camera.zoom)
	var cam_pos: Vector2 = \
		_camera.global_position
	var half_w: float = visible_size.x / 2.0
	var half_h: float = visible_size.y / 2.0

	# Calculate vertical flight band.
	var band_center_y: float = cam_pos.y + (
		flight_band_vertical_offset * visible_size.y)
	var band_half: float = (
		flight_band_height * visible_size.y / 2.0)
	var spawn_y: float = randf_range(
		band_center_y - band_half,
		band_center_y + band_half)

	# Pick random side.
	var from_left: bool = randi() % 2 == 0
	var spawn_x: float
	if from_left:
		spawn_x = cam_pos.x - half_w \
			- Bird.OFFSCREEN_MARGIN
	else:
		spawn_x = cam_pos.x + half_w \
			+ Bird.OFFSCREEN_MARGIN

	# Base direction toward opposite side.
	var base_dir := Vector2.RIGHT if from_left \
		else Vector2.LEFT

	# Random angle deviation.
	var angle_dev: float = deg_to_rad(
		randf_range(
			-Bird.MAX_ANGLE_DEVIATION_DEG,
			Bird.MAX_ANGLE_DEVIATION_DEG))
	var direction: Vector2 = \
		base_dir.rotated(angle_dev)

	# Random curve direction.
	var curve_rate: float = deg_to_rad(
		Bird.CURVE_RATE_DEG)
	if randi() % 2 == 0:
		curve_rate = -curve_rate

	# Instantiate bird.
	var bird: Bird = _bird_scene.instantiate()
	bird.position = Vector2(spawn_x, spawn_y)
	bird.setup(
		_camera, _viewport_size,
		direction, curve_rate)
	add_child(bird)


func _get_bird_count() -> int:
	var count := 0
	for child in get_children():
		if child is Bird:
			count += 1
	return count
