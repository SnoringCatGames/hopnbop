class_name Cricket
extends CharacterBody2D
## A small cricket that hops along floor surfaces,
## flees from nearby players, and periodically fades
## out and respawns at a new location. Client-side
## only, not networked.


# --- Movement ---

## Gravity acceleration (px/s^2).
const GRAVITY := 800.0

## Jump arc peak height (pixels).
const HOP_HEIGHT := 16.0

## Minimum horizontal hop distance (pixels).
const HOP_DISTANCE_MIN := 16.0

## Maximum horizontal hop distance (pixels).
const HOP_DISTANCE_MAX := 48.0

## Horizontal speed when fleeing (px/s).
const FLEE_HORIZONTAL_SPEED := 100.0

## Flee hop height multiplier.
const FLEE_HOP_HEIGHT_MULT := 1.5

# --- Timing ---

## Minimum rest delay before a hop (seconds).
const REST_DELAY_MIN := 0.5

## Maximum rest delay before a hop (seconds).
const REST_DELAY_MAX := 3.0

## Time undisturbed before auto-despawn
## (seconds).
const AUTO_DESPAWN_SEC := 10.0

## Duration of fade-in when spawning (seconds).
const FADE_IN_SEC := 1.0

## Duration of fade-out when despawning
## (seconds).
const FADE_OUT_SEC := 1.0

# --- Detection ---

## Distance at which a player scares the
## cricket (pixels).
const SCARE_RADIUS := 40.0

## Emitted when a player scares this cricket.
signal disturbed(player_id: int)

## Minimum distance from players for preferred
## spawn point selection (pixels).
const SPAWN_MIN_PLAYER_DIST := 80.0

# --- Raycasting ---

## Raycast distance to scan for floor at hop
## target (pixels).
const FLOOR_SCAN_DIST := 32.0

## Step size when scanning for floor edge
## (pixels).
const FLOOR_SCAN_STEP := 8.0

## Inset from detected floor edge so the
## cricket doesn't land right at the lip
## (pixels).
const FLOOR_EDGE_MARGIN := 4.0

# --- Collision ---

## Only collide with normal_surfaces (bit 0).
const COLLISION_MASK_VALUE := 1 << 0

## Animation name for the jump sequence.
const ANIM_JUMP := &"jump"

## Animation name for the resting pose.
const ANIM_REST := &"rest"

enum State {
	WAITING,
	SPAWNING,
	RESTING,
	HOPPING,
	FLEEING,
	DESPAWNING,
}

var _state: int = State.WAITING
var _rest_timer := 0.0
var _undisturbed_timer := 0.0
var _fade_tween: Tween
var _sprite: AnimatedSprite2D

## Cached duration of one jump animation frame
## (seconds).
var _jump_frame_sec := 0.0

## Countdown for the anticipation frame before
## hop motion begins.
var _hop_delay := 0.0

## Velocity to apply once the hop delay expires.
var _pending_hop_velocity := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision_layer = 0
	collision_mask = COLLISION_MASK_VALUE
	up_direction = Vector2.UP
	floor_snap_length = 2.0
	_sprite = $AnimatedSprite2D

	# Cache jump animation frame duration from
	# the SpriteFrames resource.
	var frames := _sprite.sprite_frames
	var fps := frames.get_animation_speed(
		ANIM_JUMP)
	var count := frames.get_frame_count(
		ANIM_JUMP)
	if fps > 0.0 and count > 0:
		_jump_frame_sec = 1.0 / fps

	# Start invisible; _respawn() begins the
	# lifecycle.
	_sprite.play(ANIM_REST)
	modulate.a = 0.0
	_respawn()

	CritterWrapGhost.create_ghosts(
		self, _sprite)


func _physics_process(delta: float) -> void:
	# If critters are disabled mid-game, despawn.
	if (
		not G.settings.are_critters_enabled
		and _state != State.WAITING
		and _state != State.DESPAWNING
	):
		_start_despawn()
		return

	match _state:
		State.RESTING:
			_process_resting(delta)
		State.HOPPING:
			_process_hopping(delta)
		State.FLEEING:
			_process_fleeing(delta)

	# Wrap position for toroidal level bounds.
	var level := G.level
	if level is NetworkedLevel:
		level.wrap_node(self)


# --- State processing ---


func _process_resting(delta: float) -> void:
	# Keep the cricket grounded via physics.
	velocity.y += GRAVITY * delta
	move_and_slide()

	_undisturbed_timer += delta
	_rest_timer -= delta

	# Check auto-despawn.
	if _undisturbed_timer >= AUTO_DESPAWN_SEC:
		_start_despawn()
		return

	# Check player proximity.
	if _is_player_nearby():
		_start_flee()
		return

	# Start hop when rest timer expires.
	if _rest_timer <= 0.0:
		_start_hop()


func _process_hopping(delta: float) -> void:
	# Anticipation frame: stay grounded while
	# the first animation frame plays.
	if _hop_delay > 0.0:
		_hop_delay -= delta
		velocity.y += GRAVITY * delta
		move_and_slide()
		if _hop_delay <= 0.0:
			velocity = _pending_hop_velocity
		return

	velocity.y += GRAVITY * delta
	move_and_slide()

	# Check player proximity.
	if _is_player_nearby():
		_start_flee()
		return

	# Landed on floor.
	if is_on_floor():
		velocity = Vector2.ZERO
		_sprite.play(ANIM_REST)
		_state = State.RESTING
		_rest_timer = randf_range(
			REST_DELAY_MIN, REST_DELAY_MAX)


func _process_fleeing(delta: float) -> void:
	velocity.y += GRAVITY * delta
	move_and_slide()


# --- Hop ---


func _start_hop() -> void:
	var target_x := _pick_hop_target_x()
	var dx := target_x - global_position.x

	# Face the hop direction.
	_sprite.flip_h = dx < 0.0

	# Vertical launch velocity:
	# v^2 = 2*g*h => v = sqrt(2*g*h).
	var vy := -sqrt(
		2.0 * GRAVITY * HOP_HEIGHT)

	# Total air time for symmetric parabola.
	var air_time := 2.0 * absf(vy) / GRAVITY

	# Horizontal velocity to cover dx in
	# air_time.
	var vx := dx / air_time if \
		air_time > 0.0 else 0.0

	# Play jump animation immediately, but
	# delay the actual motion by one animation
	# frame (anticipation).
	_sprite.play(ANIM_JUMP)
	_pending_hop_velocity = Vector2(vx, vy)
	_hop_delay = _jump_frame_sec
	_state = State.HOPPING


func _pick_hop_target_x() -> float:
	var direction := 1.0 if randf() > 0.5 \
		else -1.0

	# Scan outward to find where the floor
	# ends in the chosen direction.
	var edge_dist := _find_floor_edge(
		direction)

	# If barely any room, try the other way.
	if edge_dist < HOP_DISTANCE_MIN:
		direction = -direction
		edge_dist = _find_floor_edge(
			direction)

	# Clamp hop distance within the floor
	# extent, leaving a margin from the edge.
	var max_dist := maxf(
		edge_dist - FLOOR_EDGE_MARGIN, 0.0)
	if max_dist < 1.0:
		return global_position.x
	var dist := randf_range(
		minf(HOP_DISTANCE_MIN, max_dist),
		minf(HOP_DISTANCE_MAX, max_dist))
	return global_position.x \
		+ direction * dist


## Steps outward from the cricket's position
## in the given direction until no floor is
## found. Returns the distance to the floor
## edge.
func _find_floor_edge(
	direction: float,
) -> float:
	var space := \
		get_world_2d().direct_space_state
	var origin_y := global_position.y
	var step := FLOOR_SCAN_STEP * direction
	var dist := 0.0
	var max_scan := HOP_DISTANCE_MAX \
		+ FLOOR_EDGE_MARGIN

	while dist < max_scan:
		dist += FLOOR_SCAN_STEP
		var test_x := \
			global_position.x + step \
			* (dist / FLOOR_SCAN_STEP)
		var query := \
			PhysicsRayQueryParameters2D.create(
				Vector2(test_x,
					origin_y - 4.0),
				Vector2(test_x,
					origin_y
					+ FLOOR_SCAN_DIST),
				COLLISION_MASK_VALUE,
			)
		var result := space.intersect_ray(
			query)
		if result.is_empty():
			return dist - FLOOR_SCAN_STEP
	return dist


# --- Flee ---


func _start_flee() -> void:
	var result := _get_away_direction()

	# Launch away with a higher hop.
	var vy := -sqrt(
		2.0 * GRAVITY * HOP_HEIGHT
		* FLEE_HOP_HEIGHT_MULT)
	var vx: float = (
		result[0] * FLEE_HORIZONTAL_SPEED)

	velocity = Vector2(vx, vy)
	_sprite.flip_h = vx < 0.0
	_sprite.play(ANIM_JUMP)
	_state = State.FLEEING
	_start_despawn()

	# Notify tracker which player scared us.
	var pid: int = result[1]
	if pid >= 0:
		disturbed.emit(pid)


## Returns [away_direction, player_id]. Player
## ID is -1 when no player is found.
func _get_away_direction() -> Array:
	var level: Level = G.level
	if not is_instance_valid(level):
		var dir := 1.0 if randf() > 0.5 \
			else -1.0
		return [dir, -1]

	var nearest_dist := INF
	var nearest_dir := 1.0
	var nearest_pid := -1
	for player in level.players:
		if not is_instance_valid(player):
			continue
		var diff := global_position.x \
			- player.global_position.x
		var dist := absf(diff)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_dir = signf(diff) \
				if diff != 0.0 else 1.0
			nearest_pid = player.player_id
	return [nearest_dir, nearest_pid]


# --- Player detection ---


func _is_player_nearby() -> bool:
	var level: Level = G.level
	if not is_instance_valid(level):
		return false
	for player in level.players:
		if not is_instance_valid(player):
			continue
		var dist := global_position \
			.distance_to(player.global_position)
		if dist < SCARE_RADIUS:
			return true
	return false


# --- Fade / despawn / respawn ---


func _start_despawn() -> void:
	if _state == State.DESPAWNING:
		return
	if _state != State.FLEEING:
		_state = State.DESPAWNING
	_kill_tween()
	_fade_tween = create_tween()
	_fade_tween.tween_property(
		self, "modulate:a",
		0.0, FADE_OUT_SEC)
	_fade_tween.tween_callback(
		_on_despawn_complete)


func _on_despawn_complete() -> void:
	velocity = Vector2.ZERO
	_state = State.WAITING
	# Short delay before respawning at a new
	# spawn point.
	_kill_tween()
	_fade_tween = create_tween()
	_fade_tween.tween_interval(
		randf_range(REST_DELAY_MIN,
			REST_DELAY_MAX))
	_fade_tween.tween_callback(_respawn)


func _respawn() -> void:
	if not G.settings.are_critters_enabled:
		_state = State.WAITING
		return

	var spawn_pos := _choose_spawn_position()
	global_position = spawn_pos
	velocity = Vector2.ZERO
	_undisturbed_timer = 0.0
	_rest_timer = randf_range(
		REST_DELAY_MIN, REST_DELAY_MAX)

	# Fade in.
	_kill_tween()
	_state = State.SPAWNING
	modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(
		self, "modulate:a",
		1.0, FADE_IN_SEC)
	_fade_tween.tween_callback(
		_on_spawn_complete)


func _on_spawn_complete() -> void:
	_sprite.play(ANIM_REST)
	_state = State.RESTING


# --- Spawn point selection ---


func _choose_spawn_position() -> Vector2:
	var level: Level = G.level
	if not is_instance_valid(level):
		return Vector2.ZERO

	# Use SnailSpawner's flood-fill to find
	# interior TOP-face surfaces (floors).
	var tiles: TileMapLayer = \
		level.collision_tiles
	if not is_instance_valid(tiles):
		return Vector2.ZERO

	var surfaces := \
		SnailSpawner.find_interior_surfaces(
			tiles)

	# Keep only TOP faces (floors), skipping
	# ice tiles and scene collection tiles
	# (e.g. springs).
	var floor_surfaces: Array = []
	for s in surfaces:
		if s.face != Snail.Face.TOP:
			continue
		var td := tiles.get_cell_tile_data(
			s.tile)
		# Scene collection tiles (springs)
		# return null tile data.
		if td == null:
			continue
		if (td.get_terrain_set()
				== Level.TERRAIN_SET_COLLISION
				and td.get_terrain()
				== Level.ICE_TERRAIN_ID):
			continue
		floor_surfaces.append(s)
	if floor_surfaces.is_empty():
		return Vector2.ZERO

	# Convert tile coords to world positions.
	# TOP face = top edge of tile center.
	var half_tile := Level.TILE_SIZE / 2.0

	# Prefer surfaces far from all players.
	var far: Array = []
	var best_surface: Dictionary = {}
	var best_min_dist := -INF

	for s in floor_surfaces:
		var local_pos := tiles.map_to_local(
			s.tile)
		var world_pos := tiles.to_global(
			local_pos)
		# Position on top of the tile.
		world_pos.y -= half_tile

		var min_dist := INF
		for player in level.players:
			if not is_instance_valid(player):
				continue
			var d: float = world_pos \
				.distance_to(
					player.global_position)
			min_dist = minf(min_dist, d)
		if min_dist >= SPAWN_MIN_PLAYER_DIST:
			far.append(s)
		if min_dist > best_min_dist:
			best_min_dist = min_dist
			best_surface = s

	var chosen: Dictionary
	if not far.is_empty():
		chosen = far.pick_random()
	else:
		chosen = best_surface

	var local_pos := tiles.map_to_local(
		chosen.tile)
	var world_pos := tiles.to_global(local_pos)
	# Place on top of the tile, nudged 1px up
	# so the collision shape sits above the
	# surface.
	world_pos.y -= half_tile + 1.0
	return world_pos


# --- Tween utility ---


func _kill_tween() -> void:
	if (
		_fade_tween != null
		and _fade_tween.is_valid()
	):
		_fade_tween.kill()
	_fade_tween = null
