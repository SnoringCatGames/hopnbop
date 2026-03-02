class_name Fish
extends Node2D
## A small fish that swims back-and-forth within
## water tiles. Reverses direction when approaching
## a non-water tile. Flees from nearby players.
##
## When flee pushes the fish into a boundary, it
## enters surface-following evade mode: sliding
## along the wall, navigating concave corners,
## until the player leaves proximity.
## Client-side only, no collision geometry.


enum _MoveMode {SWIMMING, EVADING}

## Horizontal margin from non-water tile edges
## (pixels).
const HORIZONTAL_MARGIN_PX := 3.0

## Vertical margin from the top of water
## (pixels).
const VERTICAL_MARGIN_TOP_PX := 1.0

## Vertical margin from the bottom of water
## (pixels).
const VERTICAL_MARGIN_BOTTOM_PX := 3.0

## Uniform margin from non-water boundaries
## during evade (pixels).
const EVADE_MARGIN_PX := 3.0

## Horizontal swim speed (pixels/sec).
const HORIZONTAL_SPEED := 12.0

## Vertical bob speed (pixels/sec).
const VERTICAL_SPEED := 4.0

## Player avoidance radius (pixels).
const PLAYER_FLEE_RADIUS := 40.0

## Minimum seconds since last disturbance before
## a new one can register.
const DISTURB_COOLDOWN_SEC := 0.8

## Emitted when a player disturbs this fish.
signal disturbed(player_id: int)

## Player avoidance force strength (pixels/sec).
const PLAYER_FLEE_SPEED := 21.0

## Per-frame decay for flee velocity.
const FLEE_DECAY := 0.92

## Initial burst speed when entering evade
## (pixels/sec).
const EVADE_INITIAL_SPEED := 60.0

## Minimum evade speed after deceleration
## (pixels/sec).
const EVADE_MIN_SPEED := 20.0

## Per-frame interpolation weight toward
## EVADE_MIN_SPEED (0 = no decay, 1 = instant).
const EVADE_SPEED_DECAY := 0.03

## Minimum flee component toward a wall to
## trigger evade mode instead of a simple
## direction reversal.
const _EVADE_FLEE_THRESHOLD := 0.5

## Minimum distance fish try to keep from each
## other (pixels).
const FISH_SEPARATION_DIST := 5.0

## Separation steering strength (pixels/sec).
const FISH_SEPARATION_WEIGHT := 20.0

## Available color variant texture paths.
const _COLOR_PATHS: Array[String] = [
	"res://assets/images/yellow_fish.png",
	"res://assets/images/purple_fish.png",
	"res://assets/images/blue_fish.png",
	"res://assets/images/orange_fish.png",
]

var _h_direction := 1.0
var _v_direction := 1.0
var _flee_velocity := Vector2.ZERO
var _collision_tiles: TileMapLayer

var _move_mode: int = _MoveMode.SWIMMING

## Unit vector along the surface the fish is
## sliding on while evading.
var _evade_slide_dir := Vector2.ZERO

## Unit normal pointing away from the wall
## (into the water) while evading.
var _evade_wall_normal := Vector2.ZERO

## Current evade speed, starts high and decays
## toward EVADE_MIN_SPEED.
var _evade_speed := 0.0

## Seconds since this fish was last disturbed.
var _time_since_disturbed := INF

@onready var _sprite: AnimatedSprite2D = (
	$AnimatedSprite2D)


## Call after instantiation, before add_child.
## color_path: one of _COLOR_PATHS, or pass
## "" to pick a random color.
func setup(
	tiles: TileMapLayer,
	color_path: String = "",
) -> void:
	_collision_tiles = tiles
	if color_path.is_empty():
		color_path = _COLOR_PATHS.pick_random()
	_recolor_sprite_frames(color_path)


## Clone the scene's SpriteFrames and swap
## every AtlasTexture's atlas to the chosen
## color variant.
func _recolor_sprite_frames(
	texture_path: String,
) -> void:
	var sprite: AnimatedSprite2D = (
		$AnimatedSprite2D)
	var base: SpriteFrames = (
		sprite.sprite_frames)
	var new_atlas: Texture2D = load(
		texture_path)
	var frames := base.duplicate()

	for anim_name in frames.get_animation_names():
		var count: int = (
			frames.get_frame_count(anim_name))
		for i in count:
			var tex: AtlasTexture = (
				frames.get_frame_texture(
					anim_name, i).duplicate())
			tex.atlas = new_atlas
			frames.set_frame(
				anim_name, i, tex)

	sprite.sprite_frames = frames


## Place fish at center of the given water tile.
## Pick random directions and a random start
## frame.
func initialize(cell: Vector2i) -> void:
	var local_pos := (
		_collision_tiles.map_to_local(cell))
	global_position = (
		_collision_tiles.to_global(local_pos))
	_h_direction = [-1.0, 1.0].pick_random()
	_v_direction = [-1.0, 1.0].pick_random()
	_update_sprite_flip()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Random start frame within the swim
	# animation.
	var frame_count := (
		_sprite.sprite_frames
			.get_frame_count(&"swim"))
	if frame_count > 1:
		_sprite.frame = randi() % frame_count
	_sprite.play(&"swim")

	CritterWrapGhost.create_ghosts(
		self, _sprite)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_collision_tiles):
		return

	_time_since_disturbed += delta

	match _move_mode:
		_MoveMode.SWIMMING:
			_process_swimming(delta)
		_MoveMode.EVADING:
			_process_evading(delta)

	# Wrap position for toroidal level bounds.
	var level := G.level
	if level is NetworkedLevel:
		level.wrap_node(self)


func _process_swimming(delta: float) -> void:
	_update_flee_velocity()
	_probe_boundaries()

	# Probing may have entered evade mode.
	if _move_mode == _MoveMode.EVADING:
		return

	var base := Vector2(
		HORIZONTAL_SPEED * _h_direction,
		VERTICAL_SPEED * _v_direction,
	)
	var sep := _calc_separation()
	var prev_pos := global_position
	global_position += (
		(base + _flee_velocity + sep) * delta)

	# Safety clamp: if we left water, snap back.
	# Only revert position — direction is managed
	# by _probe_boundaries().
	if not _is_current_cell_water():
		global_position = prev_pos


func _process_evading(delta: float) -> void:
	# Keep flee velocity up-to-date so the fish
	# continues fleeing after exiting evade.
	_update_flee_velocity()

	# Re-burst when flee pressure is strong,
	# otherwise decay toward minimum speed.
	var flee_strength := _flee_velocity.length()
	if flee_strength > PLAYER_FLEE_SPEED * 0.3:
		_evade_speed = lerpf(
			_evade_speed,
			EVADE_INITIAL_SPEED,
			0.1)
	else:
		_evade_speed = lerpf(
			_evade_speed,
			EVADE_MIN_SPEED,
			EVADE_SPEED_DECAY)

	# Exit evade when no player is nearby.
	if not _is_any_player_nearby():
		_exit_evade()
		return

	# Move along the surface.
	var prev_pos := global_position
	global_position += (
		_evade_slide_dir * _evade_speed * delta)

	# If we breached the margin, revert and pick
	# a new random direction. Defer the sprite
	# flip until the fish successfully moves, to
	# prevent rapid left-right flicking in tight
	# corners.
	if not _is_within_evade_margin():
		global_position = prev_pos
		_pick_random_evade_dir()
	else:
		_update_evade_sprite_flip()


## Pick a new random evade direction after
## hitting a boundary. Probes candidate
## directions and picks a valid one that
## leads into water.
func _pick_random_evade_dir() -> void:
	var dirs: Array[Vector2] = [
		Vector2.RIGHT, Vector2.LEFT,
		Vector2.DOWN, Vector2.UP,
		Vector2(1, 1).normalized(),
		Vector2(1, -1).normalized(),
		Vector2(-1, 1).normalized(),
		Vector2(-1, -1).normalized(),
	]
	var candidates: Array[Vector2] = []
	for dir in dirs:
		# Skip directions similar to current.
		if dir.dot(_evade_slide_dir) > 0.7:
			continue
		var probe := (
			global_position
			+ dir * Level.TILE_SIZE / 2.0)
		if _is_water_at(probe):
			candidates.append(dir)

	if candidates.is_empty():
		_evade_slide_dir = - _evade_slide_dir
	else:
		_evade_slide_dir = (
			candidates.pick_random())


func _exit_evade() -> void:
	_move_mode = _MoveMode.SWIMMING
	# Clear residual flee velocity so
	# _probe_boundaries() does not immediately
	# re-enter evade on the next swimming frame.
	_flee_velocity = Vector2.ZERO
	# Align swim directions to continue
	# smoothly from the evade trajectory.
	if absf(_evade_slide_dir.x) > 0.01:
		_h_direction = signf(_evade_slide_dir.x)
	if absf(_evade_slide_dir.y) > 0.01:
		_v_direction = signf(_evade_slide_dir.y)
	_update_sprite_flip()
	if is_instance_valid(_sprite):
		_sprite.play(&"swim")


## Check ahead in each axis and reverse if
## approaching a non-water tile. If the flee
## velocity pushes the fish toward a detected
## wall, enter evade mode.
func _probe_boundaries() -> void:
	# Horizontal: check both directions so flee
	# can trigger evade even when _h_direction
	# faces away from the wall.
	var right_probe := (
		global_position + Vector2(
			Level.TILE_SIZE / 2.0
			+ HORIZONTAL_MARGIN_PX,
			0.0))
	var left_probe := (
		global_position + Vector2(
			- (Level.TILE_SIZE / 2.0
			+ HORIZONTAL_MARGIN_PX),
			0.0))
	var right_wall := not _is_water_at(
		right_probe)
	var left_wall := not _is_water_at(
		left_probe)

	# Evade: flee pushes toward a detected wall.
	if (
		right_wall
		and _flee_velocity.x
			> _EVADE_FLEE_THRESHOLD
	):
		_h_direction = 1.0
		_enter_evade_h()
		return
	if (
		left_wall
		and -_flee_velocity.x
			> _EVADE_FLEE_THRESHOLD
	):
		_h_direction = -1.0
		_enter_evade_h()
		return

	# Simple reversal when no flee pressure.
	if _h_direction > 0.0 and right_wall:
		_h_direction = -1.0
		_update_sprite_flip()
	elif _h_direction < 0.0 and left_wall:
		_h_direction = 1.0
		_update_sprite_flip()

	# Vertical: check both directions.
	var down_probe := (
		global_position + Vector2(
			0.0,
			Level.TILE_SIZE / 2.0
			+ VERTICAL_MARGIN_BOTTOM_PX))
	var up_probe := (
		global_position + Vector2(
			0.0,
			- (Level.TILE_SIZE / 2.0
			+ VERTICAL_MARGIN_TOP_PX)))
	var down_wall := not _is_water_at(
		down_probe)
	var up_wall := not _is_water_at(up_probe)

	if (
		down_wall
		and _flee_velocity.y
			> _EVADE_FLEE_THRESHOLD
	):
		_v_direction = 1.0
		_enter_evade_v()
		return
	if (
		up_wall
		and -_flee_velocity.y
			> _EVADE_FLEE_THRESHOLD
	):
		_v_direction = -1.0
		_enter_evade_v()
		return

	if _v_direction > 0.0 and down_wall:
		_v_direction = -1.0
	elif _v_direction < 0.0 and up_wall:
		_v_direction = 1.0


## Enter evade after hitting a horizontal wall
## (left or right boundary).
func _enter_evade_h() -> void:
	# Wall is in the _h_direction; normal
	# points back into the water.
	_evade_wall_normal = Vector2(
		- _h_direction, 0.0)
	# Slide vertically, prefer the flee's
	# vertical component.
	if absf(_flee_velocity.y) > 0.1:
		_evade_slide_dir = Vector2(
			0.0, signf(_flee_velocity.y))
	else:
		_evade_slide_dir = Vector2(
			0.0, _v_direction)
	_evade_speed = EVADE_INITIAL_SPEED
	_move_mode = _MoveMode.EVADING
	# Nudge away from the wall to ensure
	# safe margin for sliding.
	_clamp_axis_margin(
		Vector2(_h_direction, 0.0),
		HORIZONTAL_MARGIN_PX)
	_update_evade_sprite_flip()
	if is_instance_valid(_sprite):
		_sprite.play(&"evade")


## Enter evade after hitting a vertical wall
## (floor or ceiling boundary).
func _enter_evade_v() -> void:
	_evade_wall_normal = Vector2(
		0.0, -_v_direction)
	if absf(_flee_velocity.x) > 0.1:
		_evade_slide_dir = Vector2(
			signf(_flee_velocity.x), 0.0)
	else:
		_evade_slide_dir = Vector2(
			_h_direction, 0.0)
	_evade_speed = EVADE_INITIAL_SPEED
	_move_mode = _MoveMode.EVADING
	# Nudge away from the wall to ensure
	# safe margin for sliding.
	var v_margin: float
	if _v_direction > 0.0:
		v_margin = VERTICAL_MARGIN_BOTTOM_PX
	else:
		v_margin = VERTICAL_MARGIN_TOP_PX
	_clamp_axis_margin(
		Vector2(0.0, _v_direction), v_margin)
	_update_evade_sprite_flip()
	if is_instance_valid(_sprite):
		_sprite.play(&"evade")


func _update_flee_velocity() -> void:
	_flee_velocity *= FLEE_DECAY

	var level: Level = G.level
	if not is_instance_valid(level):
		return

	var nearest_dist := INF
	var nearest_pid := -1
	for player in level.players:
		if not is_instance_valid(player):
			continue
		if not player.surfaces.is_in_water:
			continue
		var diff := (
			global_position
			- player.global_position)
		var dist := diff.length()
		if (
			dist > 0.0
			and dist < PLAYER_FLEE_RADIUS
		):
			var ratio := (
				1.0
				- dist / PLAYER_FLEE_RADIUS)
			_flee_velocity += (
				diff.normalized()
				* PLAYER_FLEE_SPEED * ratio)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_pid = player.player_id

	# Emit disturbance if cooldown expired.
	if (
		nearest_pid >= 0
		and _time_since_disturbed
			>= DISTURB_COOLDOWN_SEC
	):
		_time_since_disturbed = 0.0
		disturbed.emit(nearest_pid)


func _is_any_player_nearby() -> bool:
	var level: Level = G.level
	if not is_instance_valid(level):
		return false
	for player in level.players:
		if not is_instance_valid(player):
			continue
		if not player.surfaces.is_in_water:
			continue
		var dist := global_position.distance_to(
			player.global_position)
		if dist < PLAYER_FLEE_RADIUS:
			return true
	return false


func _calc_separation() -> Vector2:
	var sep := Vector2.ZERO
	var parent_node := get_parent()
	if parent_node == null:
		return sep
	for node in parent_node.get_children():
		if node == self or not (node is Fish):
			continue
		var diff: Vector2 = (
			global_position
			- node.global_position)
		var dist := diff.length()
		if (
			dist > 0.0
			and dist < FISH_SEPARATION_DIST
		):
			var ratio := (
				1.0
				- dist / FISH_SEPARATION_DIST)
			sep += (
				diff.normalized()
				* FISH_SEPARATION_WEIGHT
				* ratio)
	return sep


## Clamp position to maintain margins from
## all non-water boundaries.
func _enforce_water_margins() -> void:
	_clamp_axis_margin(
		Vector2.DOWN,
		VERTICAL_MARGIN_BOTTOM_PX)
	_clamp_axis_margin(
		Vector2.UP,
		VERTICAL_MARGIN_TOP_PX)
	_clamp_axis_margin(
		Vector2.RIGHT,
		HORIZONTAL_MARGIN_PX)
	_clamp_axis_margin(
		Vector2.LEFT,
		HORIZONTAL_MARGIN_PX)


func _clamp_axis_margin(
	dir: Vector2,
	margin: float,
) -> void:
	var probe := (
		global_position
		+ dir
		* (Level.TILE_SIZE / 2.0 + margin))
	if _is_water_at(probe):
		return
	var local := (
		_collision_tiles.to_local(probe))
	var cell := (
		_collision_tiles.local_to_map(local))
	var cell_center := (
		_collision_tiles.to_global(
			_collision_tiles.map_to_local(cell)))
	# Boundary: edge of non-water cell
	# closest to the fish.
	var boundary := (
		cell_center
		- dir * Level.TILE_SIZE / 2.0)
	# Fish must stay margin + half a tile from
	# the boundary. Extra 0.5 px clearance
	# prevents local_to_map boundary rounding
	# from misclassifying probe points.
	var safe := margin + 0.5
	if absf(dir.x) > 0.5:
		global_position.x = (
			boundary.x
			- dir.x
			* (Level.TILE_SIZE / 2.0 + safe))
	else:
		global_position.y = (
			boundary.y
			- dir.y
			* (Level.TILE_SIZE / 2.0 + safe))


## Returns the appropriate margin constant for
## the given direction vector.
func _margin_for_dir(dir: Vector2) -> float:
	if absf(dir.x) > 0.5:
		return HORIZONTAL_MARGIN_PX
	if dir.y > 0.0:
		return VERTICAL_MARGIN_BOTTOM_PX
	return VERTICAL_MARGIN_TOP_PX


func _update_sprite_flip() -> void:
	if is_instance_valid(_sprite):
		_sprite.flip_h = _h_direction < 0.0


## Updates sprite facing during evade. When
## sliding horizontally, face the slide
## direction. When sliding vertically, face
## away from the wall (into the water).
func _update_evade_sprite_flip() -> void:
	if not is_instance_valid(_sprite):
		return
	if absf(_evade_slide_dir.x) > 0.01:
		_sprite.flip_h = _evade_slide_dir.x < 0.0
	elif absf(_evade_wall_normal.x) > 0.01:
		_sprite.flip_h = (
			_evade_wall_normal.x < 0.0)


func _is_water_at(
	global_pos: Vector2,
) -> bool:
	var local_pos := (
		_collision_tiles.to_local(global_pos))
	var cell := (
		_collision_tiles.local_to_map(local_pos))
	return _is_cell_water(cell)


func _is_current_cell_water() -> bool:
	return _is_water_at(global_position)


## Returns true if the fish is at least
## EVADE_MARGIN_PX from all non-water
## boundaries.
func _is_within_evade_margin() -> bool:
	if not _is_current_cell_water():
		return false
	for dir in [
		Vector2.RIGHT, Vector2.LEFT,
		Vector2.DOWN, Vector2.UP,
	]:
		var probe: Vector2 = (
			global_position
			+ dir * EVADE_MARGIN_PX)
		if not _is_water_at(probe):
			return false
	return true


func _is_cell_water(cell: Vector2i) -> bool:
	var tile_data := (
		_collision_tiles
			.get_cell_tile_data(cell))
	if tile_data == null:
		return false
	return (tile_data.get_terrain_set()
		== Level.TERRAIN_SET_WATER)
