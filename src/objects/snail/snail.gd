class_name Snail
extends Node2D
## A small creature that crawls along interior
## tile surfaces in match levels. Players can
## crush it by landing on it.
##
## Movement is frame-based, keyed to
## Netcode.server_frame_index, so server and
## client stay in sync regardless of pause
## state or clock corrections.


## Which face of a tile the snail is on.
enum Face {
	TOP = 0,
	RIGHT = 1,
	BOTTOM = 2,
	LEFT = 3,
}

## Movement speed in pixels per second.
const SPEED := 15.0

## Frames before the snail respawns after
## being crushed (~0.5s at 60fps).
const _RESPAWN_DELAY_FRAMES := 30

## How long the crunched remnant sprite stays
## visible after a crush.
const _CRUNCH_DISPLAY_SEC := 5.0

## Fade-out duration for the remnant after the
## display period.
const _CRUNCH_FADE_SEC := 1.0

const _TRAIL_ALPHA_MIN := 0.06
const _TRAIL_ALPHA_MAX := 0.6

## Seconds before each trail particle begins
## to fade out.
const _TRAIL_FADE_DELAY_SEC := 1.0

## Duration of the trail particle fade-out.
const _TRAIL_FADE_DURATION_SEC := 1.0

## Pixels to cut from each side of a concave
## corner to prevent sprite-tile overlap.
const _CONCAVE_CORNER_INSET := 2.0

## CW forward direction along each face.
const _CW_FORWARD := {
	Face.TOP: Vector2i(1, 0),
	Face.RIGHT: Vector2i(0, 1),
	Face.BOTTOM: Vector2i(-1, 0),
	Face.LEFT: Vector2i(0, -1),
}

## Normal for each face (points into empty
## space, away from the tile).
const _FACE_NORMALS := {
	Face.TOP: Vector2i(0, -1),
	Face.RIGHT: Vector2i(1, 0),
	Face.BOTTOM: Vector2i(0, 1),
	Face.LEFT: Vector2i(-1, 0),
}

## The next CW face when wrapping around a
## convex corner.
const _CW_NEXT_FACE := {
	Face.TOP: Face.RIGHT,
	Face.RIGHT: Face.BOTTOM,
	Face.BOTTOM: Face.LEFT,
	Face.LEFT: Face.TOP,
}

## Concave corner: the face to transition to
## on the diagonal tile.
const _CW_CONCAVE_FACE := {
	Face.TOP: Face.LEFT,
	Face.RIGHT: Face.TOP,
	Face.BOTTOM: Face.RIGHT,
	Face.LEFT: Face.BOTTOM,
}

## CCW forward direction along each face.
const _CCW_FORWARD := {
	Face.TOP: Vector2i(-1, 0),
	Face.RIGHT: Vector2i(0, -1),
	Face.BOTTOM: Vector2i(1, 0),
	Face.LEFT: Vector2i(0, 1),
}

## CCW convex corner: next face.
const _CCW_NEXT_FACE := {
	Face.TOP: Face.LEFT,
	Face.LEFT: Face.BOTTOM,
	Face.BOTTOM: Face.RIGHT,
	Face.RIGHT: Face.TOP,
}

## CCW concave corner: the face to transition
## to on the diagonal tile.
const _CCW_CONCAVE_FACE := {
	Face.TOP: Face.RIGHT,
	Face.LEFT: Face.TOP,
	Face.BOTTOM: Face.LEFT,
	Face.RIGHT: Face.BOTTOM,
}

## Tile-based state.
var current_tile := Vector2i.ZERO
var current_face: int = Face.TOP
var progress := 0.0
var is_alive := true
var is_clockwise := true

## Active direction tables (set by
## _apply_direction).
var _forward_map: Dictionary
var _next_face_map: Dictionary
var _concave_face_map: Dictionary

var _collision_tiles: TileMapLayer

## Network frame the snail's position was last
## computed at. -1 means not yet initialized.
var _last_processed_frame := -1

## Server-only: frame at which to respawn.
var _respawn_at_frame := -1
var _is_respawning := false

## Trail state.
var _last_trail_pos := Vector2.ZERO
var _trail_acc := 0.0
var _is_trail_initialized := false
var _pending_corner_positions: Array[Vector2] = []


@onready var _crush_area: Area2D = $CrushArea
@onready var _sprite: AnimatedSprite2D = (
	$AnimatedSprite2D)
@onready var _crunch_sfx: AudioStreamPlayer2D = (
	$CrunchSfx)


## Sets the collision tile layer. Call after
## instantiation but before add_child.
func setup(tiles: TileMapLayer) -> void:
	_collision_tiles = tiles


func _apply_direction(clockwise: bool) -> void:
	is_clockwise = clockwise
	if clockwise:
		_forward_map = _CW_FORWARD
		_next_face_map = _CW_NEXT_FACE
		_concave_face_map = _CW_CONCAVE_FACE
	else:
		_forward_map = _CCW_FORWARD
		_next_face_map = _CCW_NEXT_FACE
		_concave_face_map = _CCW_CONCAVE_FACE
	if is_instance_valid(_sprite):
		_sprite.flip_h = not clockwise


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Hidden until initialized by server (via
	# initialize() or _rpc_init).
	visible = false

	if Netcode.is_server:
		_crush_area.area_entered.connect(
			_on_crush_area_area_entered)
	# Clients don't need the crush area to
	# monitor.
	if Netcode.is_client:
		_crush_area.monitoring = false


## Called by NetworkedLevel on the server after
## adding the snail to the tree.
func initialize(
	tile: Vector2i,
	face: int,
	clockwise: bool,
) -> void:
	_apply_init(
		tile, face, clockwise,
		Netcode.server_frame_index)


## Shared initialization used by both server
## (initialize) and client (_rpc_init).
## Fast-forwards from event frame to the
## current server_frame_index.
func _apply_init(
	tile: Vector2i,
	face: int,
	clockwise: bool,
	frame: int,
) -> void:
	current_tile = tile
	current_face = face
	progress = Level.TILE_SIZE / 2.0
	is_alive = true
	visible = true
	_is_respawning = false
	_last_processed_frame = frame
	_is_trail_initialized = false
	_sprite.self_modulate.a = 1.0
	_apply_direction(clockwise)

	# Fast-forward from event frame to now.
	var frames_ahead := (
		Netcode.server_frame_index - frame)
	if frames_ahead > 0:
		_simulate_frames(frames_ahead)

	_update_visual()
	_sprite.play(&"crawl")


## Advances the snail by the given number of
## network frames.
func _simulate_frames(count: int) -> void:
	if not is_alive:
		return
	if not is_instance_valid(_collision_tiles):
		return
	var per_frame := (
		SPEED
		* Netcode.frame_driver
			.target_network_time_step_sec)
	var threshold := (
		Level.TILE_SIZE - _CONCAVE_CORNER_INSET)
	for i in count:
		progress += per_frame
		while progress >= threshold:
			if not _advance():
				break


func _spawn_goo_particles() -> void:
	if (not is_instance_valid(G.level)
			or not is_instance_valid(
				G.level.gore_manager)):
		return
	G.level.gore_manager \
		.spawn_snail_goo_particles(
			global_position)


## Spawns a standalone sprite showing the
## crunched frame at the snail's current
## position. The remnant manages its own
## display hold and fade-out, then frees
## itself.
func _spawn_crunch_remnant() -> void:
	var texture := (
		_sprite.sprite_frames
			.get_frame_texture(
				&"crunched", 0))
	if texture == null:
		return

	var remnant := Sprite2D.new()
	remnant.texture = texture
	remnant.flip_h = _sprite.flip_h
	remnant.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST)

	get_parent().add_child(remnant)

	remnant.global_rotation = (
		_sprite.global_rotation)
	# Shift along the sprite's local -Y (away
	# from the surface) so the centered remnant's
	# bottom aligns with the sprite's origin.
	var half_h := (
		remnant.texture.get_size().y * 0.5)
	var local_up := Vector2(0, -half_h).rotated(
		_sprite.global_rotation)
	remnant.global_position = (
		_sprite.global_position + local_up)

	var tween := remnant.create_tween()
	tween.tween_interval(
		_CRUNCH_DISPLAY_SEC)
	tween.tween_property(
		remnant, "self_modulate:a",
		0.0, _CRUNCH_FADE_SEC)
	tween.tween_callback(
		remnant.queue_free)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_collision_tiles):
		return
	# Not yet initialized.
	if _last_processed_frame < 0:
		return

	var current_frame := (
		Netcode.server_frame_index)

	# Server frame-based respawn timer.
	if Netcode.is_server and _is_respawning:
		if current_frame >= _respawn_at_frame:
			_respawn()
		return

	if not is_alive:
		return

	var frame_delta := (
		current_frame - _last_processed_frame)
	_last_processed_frame = current_frame

	# Clock correction backward or no change.
	if frame_delta <= 0:
		return

	_simulate_frames(frame_delta)
	_update_visual()
	_update_trail()


## Handles the transition when the snail
## reaches the end of the current tile face.
## Returns true if a transition occurred.
func _advance() -> bool:
	var forward: Vector2i = _forward_map[current_face]
	var normal: Vector2i = _FACE_NORMALS[current_face]

	# 1. Concave corner (triggers early).
	var concave_tile := (
		current_tile + forward + normal)
	if _has_tile(concave_tile):
		# Record corner vertex for trail.
		if _is_trail_initialized:
			var tc := (
				_collision_tiles.map_to_local(
					current_tile))
			var tg := (
				_collision_tiles.to_global(tc))
			var h := Level.TILE_SIZE / 2.0
			_pending_corner_positions.append(
				tg + Vector2(forward) * h
				+ Vector2(normal) * h)
		current_tile = concave_tile
		current_face = (
			_concave_face_map[current_face])
		progress = _CONCAVE_CORNER_INSET
		return true

	# Straight/convex need full tile size.
	if progress < Level.TILE_SIZE:
		return false

	# 2. Straight continuation.
	var straight_tile := current_tile + forward
	if _has_tile(straight_tile):
		current_tile = straight_tile
		progress -= Level.TILE_SIZE
		return true

	# 3. Convex corner.
	current_face = _next_face_map[current_face]
	progress = 0.0
	return true


## Updates position and rotation from the
## tile-based state.
func _update_visual() -> void:
	if not is_instance_valid(_collision_tiles):
		return

	var tile_center := (
		_collision_tiles.map_to_local(
			current_tile))
	var tile_global := (
		_collision_tiles.to_global(tile_center))
	var half := Level.TILE_SIZE / 2.0

	var normal := Vector2(_FACE_NORMALS[
		current_face])
	var forward := Vector2(_forward_map[
		current_face])

	# Place at the tile surface edge. The
	# sprite's bottom is at local (0, 0) via
	# its offset, so no extra normal shift
	# is needed.
	var face_offset := normal * half
	var progress_offset := (
		forward * (progress - half))

	global_position = (
		tile_global + face_offset
		+ progress_offset)

	# Always rotate using the CW forward so
	# the sprite's feet stay on the tile
	# surface. flip_h handles the visual
	# facing for CCW snails.
	var cw_forward := Vector2(
		_CW_FORWARD[current_face])
	rotation = cw_forward.angle()


## Spawns trail particles to fill each pixel of
## movement since the last update. Concave
## corner positions are used as waypoints so the
## trail follows the tile surface around bends.
func _update_trail() -> void:
	if not _is_trail_initialized:
		_last_trail_pos = global_position
		_trail_acc = 0.0
		_is_trail_initialized = true
		_pending_corner_positions.clear()
		return

	# Walk trail through any concave corners,
	# forcing a particle at each vertex.
	for corner_pos in _pending_corner_positions:
		_trail_walk_to(corner_pos)
		_spawn_trail_particle(corner_pos)
		_trail_acc = 0.0
	_pending_corner_positions.clear()

	_trail_walk_to(global_position)


## Spawns trail particles at 1px intervals
## along the line from _last_trail_pos to
## target, carrying _trail_acc across calls.
func _trail_walk_to(target: Vector2) -> void:
	var delta_vec := target - _last_trail_pos
	var distance := delta_vec.length()
	if distance < 0.001:
		_last_trail_pos = target
		return

	var dir := delta_vec / distance
	_trail_acc += distance

	while _trail_acc >= 1.0:
		_trail_acc -= 1.0
		var spawn_pos := (
			target - dir * _trail_acc)
		_spawn_trail_particle(spawn_pos)

	_last_trail_pos = target


func _spawn_trail_particle(
	pos: Vector2,
) -> void:
	var particle := Sprite2D.new()
	particle.texture = preload(
		"res://assets/images/white_pixel.png")
	var alpha := randf_range(
		_TRAIL_ALPHA_MIN,
		_TRAIL_ALPHA_MAX)
	particle.self_modulate = Color(
		1.0, 1.0, 1.0, alpha)
	particle.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST)

	get_parent().add_child(particle)

	particle.global_position = pos

	var tween := particle.create_tween()
	tween.tween_interval(
		_TRAIL_FADE_DELAY_SEC)
	tween.tween_property(
		particle, "self_modulate:a",
		0.0, _TRAIL_FADE_DURATION_SEC)
	tween.tween_callback(
		particle.queue_free)


func _has_tile(cell: Vector2i) -> bool:
	var tile_data := (
		_collision_tiles.get_cell_tile_data(cell))
	if tile_data == null:
		return false
	return (tile_data.get_terrain_set()
		!= Level.TERRAIN_SET_WATER)


func _on_crush_area_area_entered(
	area: Area2D,
) -> void:
	if not Netcode.is_server:
		return
	if not is_alive:
		return
	# Skip during resimulation to avoid
	# double-processing.
	if Netcode.frame_driver.is_resimulating:
		return

	var parent := area.get_parent()
	if not parent is Player:
		return
	var player: Player = parent

	# Must be moving downward.
	if player.pre_movement_velocity.y <= 0.0:
		return

	# Must be in the air (not walking on floor).
	if player.surfaces.is_attaching_to_floor:
		return

	_server_crush(player)


func _server_crush(player: Player) -> void:
	is_alive = false
	visible = false

	# Record stat for adjective tracking.
	G.match_state \
		.server_get_or_create_stats(
			player.player_id) \
		.record_snail_crush()

	player.server_trigger_snail_crush_bounce()

	_spawn_crunch_remnant()
	_spawn_goo_particles()
	_crunch_sfx.play()

	Netcode.print(
		"Snail crushed by player %d" %
		player.player_id,
		NetworkLogger.CATEGORY_GAME_STATE,
	)

	_is_respawning = true
	_respawn_at_frame = (
		Netcode.server_frame_index
		+ _RESPAWN_DELAY_FRAMES)

	_rpc_crush.rpc(
		Netcode.server_frame_index)


@rpc("authority", "call_remote", "reliable")
func _rpc_crush(_frame: int) -> void:
	is_alive = false
	visible = false
	_spawn_crunch_remnant()
	_spawn_goo_particles()
	_crunch_sfx.play()


func _respawn() -> void:
	_is_respawning = false

	if not is_instance_valid(_collision_tiles):
		return

	var surface := (
		SnailSpawner.find_random_interior_surface(
			_collision_tiles))
	if surface.is_empty():
		Netcode.warning(
			"No interior surfaces for snail "
			+"respawn",
			NetworkLogger.CATEGORY_GAME_STATE,
		)
		return

	var clockwise := randi() % 2 == 0
	_apply_respawn(
		surface.tile, surface.face,
		clockwise, Netcode.server_frame_index)

	_rpc_respawn.rpc(
		surface.tile.x,
		surface.tile.y,
		surface.face,
		1 if clockwise else 0,
		Netcode.server_frame_index,
	)


@rpc("authority", "call_remote", "reliable")
func _rpc_respawn(
	tile_x: int,
	tile_y: int,
	face: int,
	clockwise: int,
	frame: int,
) -> void:
	_apply_respawn(
		Vector2i(tile_x, tile_y),
		face,
		clockwise == 1,
		frame)


func _apply_respawn(
	tile: Vector2i,
	face: int,
	clockwise: bool,
	frame: int,
) -> void:
	_sprite.self_modulate.a = 1.0
	_apply_init(tile, face, clockwise, frame)


@rpc("authority", "call_remote", "reliable")
func _rpc_init(
	tile_x: int,
	tile_y: int,
	face: int,
	clockwise: int,
	frame: int,
) -> void:
	_apply_init(
		Vector2i(tile_x, tile_y),
		face,
		clockwise == 1,
		frame)
