class_name FlySwarm
extends Node2D
## Controls a swarm of flies using simplified Boids
## flocking (separation + cohesion, no alignment).
## Flies avoid players (or are attracted when the
## lordoftheflies cheat is active) and are drawn to
## poop. Client-side only.


# --- Swarm configuration ---

## Number of flies in the swarm. Set before
## add_child() to override the default.
var fly_count := 10

## Spawn offset from chosen spawn point
## (primary attempt).
const SPAWN_OFFSET_PRIMARY := Vector2(0.0, -31.5)

## Fallback spawn offset if primary intersects
## collision.
const SPAWN_OFFSET_FALLBACK := Vector2(0.0, -15.5)

# --- Steering weights (px/s^2) ---
# All _calc_* functions return vectors with
# magnitude roughly in [0, 1]. Weights scale
# them to physical steering force.

const SEPARATION_WEIGHT := 80.0
const COHESION_WEIGHT := 30.0
const PLAYER_INTERACTION_WEIGHT := 200.0
const POOP_ATTRACTION_WEIGHT := 40.0
const HOME_WEIGHT := 20.0

# --- Steering radii (pixels) ---

const SEPARATION_RADIUS := 5.0
const COHESION_RADIUS := 60.0
const PLAYER_INTERACTION_RADIUS := 40.0
const POOP_ATTRACTION_RADIUS := 100.0

# --- Movement parameters ---

const MAX_SPEED := 70.0

## Per-physics-frame velocity damping.
## Higher = more momentum retained.
const DRAG := 0.94

## Maximum steering force per frame
## (pixels/sec^2).
const MAX_STEER_FORCE := 500.0

## Home point drift radius (pixels). The home
## point wanders within this radius of the
## spawn position.
const HOME_DRIFT_RADIUS := 35.0

# --- Dart impulse parameters ---
# Each fly periodically picks a random
# direction and darts toward it, simulating
# the erratic flight pattern of real flies.

## Speed of each random dart impulse (px/s).
const DART_IMPULSE_SPEED := 45.0

## Minimum seconds between darts.
const DART_INTERVAL_MIN := 0.15

## Maximum seconds between darts.
const DART_INTERVAL_MAX := 0.6

## When a player is within this radius, the fly
## gets a direct velocity impulse away (fast
## scatter). Outside this but within
## PLAYER_INTERACTION_RADIUS, normal steering
## applies.
const PLAYER_SCATTER_RADIUS := 35.0

## Speed of the scatter impulse (px/s).
const PLAYER_SCATTER_SPEED := 65.0

# --- Audio parameters ---

## Minimum distance for proximity score
## calculation. Prevents division by zero.
const _AUDIO_MIN_DIST := 8.0

## Positional buzz max hearing distance (pixels).
const _POSITIONAL_MAX_DISTANCE := 300.0

## Ambient buzz max distance (very high so it
## always plays).
const _AMBIENT_MAX_DISTANCE := 9999.0

## Ambient buzz attenuation (very low so
## distance doesn't affect volume).
const _AMBIENT_ATTENUATION := 0.1

## Ambient buzz panning oscillation range
## (pixels from camera center).
const _AMBIENT_PAN_RANGE := 40.0

## Ambient buzz panning noise frequency.
const _AMBIENT_PAN_NOISE_FREQUENCY := 0.3

## Audio file paths (placeholder).
const _POSITIONAL_BUZZ_PATH := \
	"res://assets/audio/sfx/fly_buzz_positional.ogg"
const _AMBIENT_BUZZ_PATH := \
	"res://assets/audio/sfx/fly_buzz_ambient.ogg"

# Collision mask bit for normal_surfaces.
const _NORMAL_SURFACES_MASK := 1 << 0

var _flies: Array[Fly] = []
var _dart_timers: Array[float] = []
var _noise_time: float = 0.0
var _fly_scene: PackedScene

# Home point: a slowly-drifting anchor that
# keeps the swarm spatially coherent.
var _home_point := Vector2.ZERO
var _home_origin := Vector2.ZERO
var _home_noise: FastNoiseLite

# Audio nodes (null if audio files not found).
var _positional_buzz: AudioStreamPlayer2D
var _ambient_buzz: AudioStreamPlayer2D
var _ambient_pan_noise: FastNoiseLite
var _ambient_pan_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fly_scene = preload(
		"res://src/objects/flies/fly.tscn")
	_spawn_flies()
	_init_audio()


func _physics_process(delta: float) -> void:
	_noise_time += delta
	_update_flocking(delta)
	_update_audio(delta)


func _spawn_flies() -> void:
	var spawn_pos := _choose_spawn_position()
	_home_origin = spawn_pos
	_home_point = spawn_pos

	# Home point noise for slow wandering.
	_home_noise = FastNoiseLite.new()
	_home_noise.seed = randi()
	_home_noise.noise_type = \
		FastNoiseLite.TYPE_SIMPLEX
	_home_noise.frequency = 0.15

	for i in fly_count:
		var fly: Fly = _fly_scene.instantiate()
		fly.position = spawn_pos + Vector2(
			randf_range(-3.0, 3.0),
			randf_range(-3.0, 3.0))
		add_child(fly)
		_flies.append(fly)

		# Stagger initial dart timers so flies
		# don't all dart at the same time.
		_dart_timers.append(
			randf_range(0.0, DART_INTERVAL_MAX))


func _choose_spawn_position() -> Vector2:
	var level: Level = G.level
	if not is_instance_valid(level):
		return Vector2.ZERO

	var spawn_points := level._get_spawn_points()
	if spawn_points.is_empty():
		return Vector2.ZERO

	var chosen: SpawnPoint = \
		spawn_points.pick_random()
	var base_pos := chosen.spawn_position

	# Try primary offset.
	var primary := base_pos + SPAWN_OFFSET_PRIMARY
	if not _intersects_normal_surfaces(primary):
		return primary

	# Fallback offset.
	return base_pos + SPAWN_OFFSET_FALLBACK


func _intersects_normal_surfaces(
	test_pos: Vector2,
) -> bool:
	var space_state := \
		get_world_2d().direct_space_state
	var query := \
		PhysicsPointQueryParameters2D.new()
	query.position = test_pos
	query.collision_mask = _NORMAL_SURFACES_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var results := \
		space_state.intersect_point(query, 1)
	return not results.is_empty()


func _update_flocking(delta: float) -> void:
	# Drift the home point slowly using noise.
	_update_home_point()

	# Gather player positions.
	var player_positions: Array[Vector2] = []
	var level: Level = G.level
	if is_instance_valid(level):
		for player in level.players:
			if is_instance_valid(player):
				player_positions.append(
					player.global_position)

	# Gather poop positions.
	var poop_positions: Array[Vector2] = []
	if (
		is_instance_valid(level) and
		is_instance_valid(level.gore_manager)
	):
		for poop in \
				level.gore_manager.poop_particles:
			if is_instance_valid(poop):
				poop_positions.append(
					poop.global_position)

	# Check cheat state once per frame.
	var attract_to_players := \
		CheatManager \
			.is_lordoftheflies_cheat_active()

	for i in _flies.size():
		var fly := _flies[i]
		if not is_instance_valid(fly):
			continue

		var pos := fly.global_position
		var steer := Vector2.ZERO

		# 1) Separation (only prevents overlap).
		steer += _calc_separation(
			i, pos) * SEPARATION_WEIGHT

		# 2) Cohesion.
		steer += _calc_cohesion(
			i, pos) * COHESION_WEIGHT

		# 3) Player interaction (avoid or
		# attract depending on cheat).
		steer += _calc_player_interaction(
			pos,
			player_positions,
			attract_to_players,
		) * PLAYER_INTERACTION_WEIGHT

		# 4) Poop attraction.
		steer += _calc_poop_attraction(
			pos,
			poop_positions,
		) * POOP_ATTRACTION_WEIGHT

		# 5) Home point attraction.
		steer += _calc_home_attraction(
			pos) * HOME_WEIGHT

		# Clamp steering force.
		if steer.length() > MAX_STEER_FORCE:
			steer = steer.normalized() \
				* MAX_STEER_FORCE

		# Apply drag.
		fly.velocity *= DRAG

		# Apply steering force.
		fly.velocity += steer * delta

		# 6) Scatter impulse: if a player is very
		# close, immediately dart away.
		if not attract_to_players:
			var scatter := _calc_scatter_impulse(
				pos, player_positions)
			if scatter != Vector2.ZERO:
				fly.velocity = scatter

		# 7) Random dart impulses. Each fly
		# periodically darts in a random
		# direction, creating erratic individual
		# movement within the swarm.
		_dart_timers[i] -= delta
		if _dart_timers[i] <= 0.0:
			var angle := randf() * TAU
			fly.velocity = Vector2(
				cos(angle), sin(angle),
			) * DART_IMPULSE_SPEED
			_dart_timers[i] = randf_range(
				DART_INTERVAL_MIN,
				DART_INTERVAL_MAX)

		# Clamp to max speed.
		if fly.velocity.length() > MAX_SPEED:
			fly.velocity = \
				fly.velocity.normalized() \
				* MAX_SPEED

		fly.move_and_slide()


func _update_home_point() -> void:
	# Slowly wander the home point around the
	# spawn origin using noise.
	var hx := _home_noise.get_noise_2d(
		_noise_time * 20.0, 0.0)
	var hy := _home_noise.get_noise_2d(
		0.0, _noise_time * 20.0)
	_home_point = _home_origin + Vector2(
		hx, hy) * HOME_DRIFT_RADIUS


func _calc_home_attraction(
	pos: Vector2,
) -> Vector2:
	var diff := _home_point - pos
	var dist := diff.length()
	if dist < 1.0:
		return Vector2.ZERO
	# Strength increases with distance from home,
	# capped at 1.0.
	return diff.normalized() * clampf(
		dist / COHESION_RADIUS, 0.0, 1.0)


func _calc_separation(
	fly_index: int,
	pos: Vector2,
) -> Vector2:
	var steer := Vector2.ZERO
	var count := 0
	for j in _flies.size():
		if j == fly_index:
			continue
		var other := _flies[j]
		if not is_instance_valid(other):
			continue
		var diff := pos - other.global_position
		var dist := diff.length()
		if dist > 0.0 and \
				dist < SEPARATION_RADIUS:
			# Stronger repulsion when closer.
			# Ratio is 1.0 at dist=0, 0.0 at
			# dist=SEPARATION_RADIUS.
			var ratio := 1.0 - \
				dist / SEPARATION_RADIUS
			steer += diff.normalized() * ratio
			count += 1
	if count > 0:
		steer /= count
	return steer


func _calc_cohesion(
	fly_index: int,
	pos: Vector2,
) -> Vector2:
	var center := Vector2.ZERO
	var count := 0
	for j in _flies.size():
		if j == fly_index:
			continue
		var other := _flies[j]
		if not is_instance_valid(other):
			continue
		var dist := pos.distance_to(
			other.global_position)
		if dist < COHESION_RADIUS:
			center += other.global_position
			count += 1
	if count == 0:
		return Vector2.ZERO
	center /= count
	return (center - pos).normalized()


func _calc_player_interaction(
	pos: Vector2,
	player_positions: Array[Vector2],
	attract: bool,
) -> Vector2:
	var steer := Vector2.ZERO
	for player_pos in player_positions:
		var diff := pos - player_pos
		var dist := diff.length()
		if (
			dist > 0.0 and
			dist < PLAYER_INTERACTION_RADIUS
		):
			# Stronger effect when closer.
			var ratio := 1.0 - dist / \
				PLAYER_INTERACTION_RADIUS
			if attract:
				# Steer toward player.
				steer -= diff.normalized() * ratio
			else:
				# Steer away from player.
				steer += diff.normalized() * ratio
	return steer


func _calc_scatter_impulse(
	pos: Vector2,
	player_positions: Array[Vector2],
) -> Vector2:
	# Find the nearest player within scatter
	# radius and return an immediate velocity
	# impulse away from them.
	var nearest_dist := INF
	var nearest_diff := Vector2.ZERO
	for player_pos in player_positions:
		var diff := pos - player_pos
		var dist := diff.length()
		if (
			dist > 0.0 and
			dist < PLAYER_SCATTER_RADIUS and
			dist < nearest_dist
		):
			nearest_dist = dist
			nearest_diff = diff
	if nearest_dist == INF:
		return Vector2.ZERO
	# Dart away from the player with some
	# random spread so flies don't all flee in
	# the exact same direction.
	var away := nearest_diff.normalized()
	var spread := randf_range(-0.5, 0.5)
	away = away.rotated(spread)
	return away * PLAYER_SCATTER_SPEED


func _calc_poop_attraction(
	pos: Vector2,
	poop_positions: Array[Vector2],
) -> Vector2:
	# Steer toward nearest poop within radius.
	var nearest_dist := INF
	var nearest_pos := Vector2.ZERO
	var found := false
	for poop_pos in poop_positions:
		var dist := pos.distance_to(poop_pos)
		if (
			dist < POOP_ATTRACTION_RADIUS and
			dist < nearest_dist
		):
			nearest_dist = dist
			nearest_pos = poop_pos
			found = true
	if not found:
		return Vector2.ZERO
	return (nearest_pos - pos).normalized()


# --- Audio ---


func _init_audio() -> void:
	# Positional buzz.
	if ResourceLoader.exists(
			_POSITIONAL_BUZZ_PATH):
		var stream: AudioStream = load(
			_POSITIONAL_BUZZ_PATH)
		_positional_buzz = \
			AudioStreamPlayer2D.new()
		_positional_buzz.stream = stream
		_positional_buzz.autoplay = true
		_positional_buzz.max_distance = \
			_POSITIONAL_MAX_DISTANCE
		_positional_buzz.volume_db = -80.0
		add_child(_positional_buzz)

	# Ambient buzz with panning motion.
	if ResourceLoader.exists(
			_AMBIENT_BUZZ_PATH):
		var stream: AudioStream = load(
			_AMBIENT_BUZZ_PATH)
		_ambient_buzz = \
			AudioStreamPlayer2D.new()
		_ambient_buzz.stream = stream
		_ambient_buzz.autoplay = true
		_ambient_buzz.max_distance = \
			_AMBIENT_MAX_DISTANCE
		_ambient_buzz.attenuation = \
			_AMBIENT_ATTENUATION
		_ambient_buzz.volume_db = -80.0
		add_child(_ambient_buzz)

		# Noise for ambient panning motion.
		_ambient_pan_noise = FastNoiseLite.new()
		_ambient_pan_noise.seed = randi()
		_ambient_pan_noise.noise_type = \
			FastNoiseLite.TYPE_SIMPLEX
		_ambient_pan_noise.frequency = \
			_AMBIENT_PAN_NOISE_FREQUENCY


func _update_audio(delta: float) -> void:
	if (
		_positional_buzz == null and
		_ambient_buzz == null
	):
		return

	_ambient_pan_time += delta

	var level: Level = G.level
	if not is_instance_valid(level):
		return
	if not is_instance_valid(level.level_camera):
		return

	var listener_pos: Vector2 = \
		level.level_camera.global_position

	# Calculate aggregate proximity score and
	# weighted centroid.
	var score := 0.0
	var centroid_num := Vector2.ZERO
	for fly in _flies:
		if not is_instance_valid(fly):
			continue
		var dist := fly.global_position \
			.distance_to(listener_pos)
		var weight := \
			1.0 / maxf(dist, _AUDIO_MIN_DIST)
		score += weight
		centroid_num += \
			fly.global_position * weight

	if score <= 0.0:
		if _positional_buzz != null:
			_positional_buzz.volume_db = -80.0
		if _ambient_buzz != null:
			_ambient_buzz.volume_db = -80.0
		return

	var weighted_centroid: Vector2 = \
		centroid_num / score

	# Normalize score to 0-1 range.
	var max_score: float = \
		fly_count / _AUDIO_MIN_DIST
	var normalized: float = \
		clampf(score / max_score, 0.0, 1.0)
	var volume_db: float = clampf(
		linear_to_db(normalized), -80.0, 0.0)

	# Update positional buzz.
	if _positional_buzz != null:
		_positional_buzz.global_position = \
			weighted_centroid
		_positional_buzz.volume_db = volume_db

	# Update ambient buzz with panning motion.
	if _ambient_buzz != null:
		var pan_offset: float = \
			_ambient_pan_noise.get_noise_1d(
				_ambient_pan_time * 60.0
			) * _AMBIENT_PAN_RANGE
		_ambient_buzz.global_position = \
			listener_pos + Vector2(pan_offset, 0.0)
		_ambient_buzz.volume_db = volume_db
