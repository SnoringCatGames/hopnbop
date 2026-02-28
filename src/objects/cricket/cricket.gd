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

## Minimum distance from players for preferred
## spawn point selection (pixels).
const SPAWN_MIN_PLAYER_DIST := 80.0

# --- Raycasting ---

## Raycast distance to detect floor below a
## spawn point (pixels).
const FLOOR_DETECT_DIST := 64.0

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
var _sprite: Sprite2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision_layer = 0
	collision_mask = COLLISION_MASK_VALUE
	up_direction = Vector2.UP
	floor_snap_length = 2.0
	_sprite = $Sprite2D
	# Start invisible; _respawn() begins the
	# lifecycle.
	modulate.a = 0.0
	_respawn()


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
	velocity.y += GRAVITY * delta
	move_and_slide()

	# Check player proximity.
	if _is_player_nearby():
		_start_flee()
		return

	# Landed on floor.
	if is_on_floor():
		velocity = Vector2.ZERO
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

	velocity = Vector2(vx, vy)
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
	var away_dir := _get_away_direction()

	# Launch away with a higher hop.
	var vy := -sqrt(
		2.0 * GRAVITY * HOP_HEIGHT
		* FLEE_HOP_HEIGHT_MULT)
	var vx := away_dir * FLEE_HORIZONTAL_SPEED

	velocity = Vector2(vx, vy)
	_sprite.flip_h = vx < 0.0
	_state = State.FLEEING
	_start_despawn()


func _get_away_direction() -> float:
	var level: Level = G.level
	if not is_instance_valid(level):
		return 1.0 if randf() > 0.5 else -1.0

	var nearest_dist := INF
	var nearest_dir := 1.0
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
	return nearest_dir


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
	_state = State.RESTING


# --- Spawn point selection ---


func _choose_spawn_position() -> Vector2:
	var level: Level = G.level
	if not is_instance_valid(level):
		return Vector2.ZERO

	var points := level._get_spawn_points()
	if points.is_empty():
		return Vector2.ZERO

	# Filter out spawn points over water.
	var dry_points: Array[SpawnPoint] = []
	for sp in points:
		if not level.is_position_in_water(
			sp.spawn_position
		):
			dry_points.append(sp)
	if dry_points.is_empty():
		dry_points.assign(points)

	# Prefer points far from all players.
	var far_points: Array[SpawnPoint] = []
	var best_point: SpawnPoint = null
	var best_min_dist := -INF

	for sp in dry_points:
		var min_dist := INF
		for player in level.players:
			if not is_instance_valid(player):
				continue
			var d: float = sp.spawn_position \
				.distance_to(
					player.global_position)
			min_dist = minf(min_dist, d)
		if min_dist >= SPAWN_MIN_PLAYER_DIST:
			far_points.append(sp)
		if min_dist > best_min_dist:
			best_min_dist = min_dist
			best_point = sp

	var chosen: SpawnPoint
	if not far_points.is_empty():
		chosen = far_points.pick_random()
	else:
		chosen = best_point

	# Raycast down from spawn point to find
	# actual floor surface.
	return _find_floor_below(
		chosen.spawn_position)


func _find_floor_below(
	pos: Vector2,
) -> Vector2:
	var space := \
		get_world_2d().direct_space_state
	# Start well above the position so the ray
	# always approaches tiles from above, even
	# if pos is inside a tile.
	var ray_start := pos + Vector2(
		0.0, -FLOOR_DETECT_DIST)
	var ray_end := pos + Vector2(
		0.0, FLOOR_DETECT_DIST)
	var query := PhysicsRayQueryParameters2D \
		.create(
			ray_start,
			ray_end,
			COLLISION_MASK_VALUE,
		)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return pos
	# Nudge above the surface so the collision
	# shape doesn't start inside the tile.
	return result.position + Vector2(0.0, -1.0)


# --- Tween utility ---


func _kill_tween() -> void:
	if (
		_fade_tween != null
		and _fade_tween.is_valid()
	):
		_fade_tween.kill()
	_fade_tween = null
