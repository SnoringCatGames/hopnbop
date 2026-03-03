class_name Butterfly
extends CharacterBody2D
## A butterfly that flies along smooth curved
## paths between in-air positions, landing on
## walls and floors to rest after a sustained
## flight phase. White sprite modulated to a
## random color. Client-side only.


enum State { FLYING, RESTING, BUMP_RESTING }

## HSV saturation for random color assignment.
const COLOR_SATURATION := 0.6

## HSV value (lightness) for random color
## assignment.
const COLOR_VALUE := 0.7

## Flight speed (pixels/sec).
const FLY_SPEED := 25.0

## Minimum rest duration (seconds).
const REST_DURATION_MIN := 1.5

## Maximum rest duration (seconds).
const REST_DURATION_MAX := 3.5

## Minimum bump rest duration (seconds).
const BUMP_REST_DURATION_MIN := 2.0

## Maximum bump rest duration (seconds).
const BUMP_REST_DURATION_MAX := 5.0

## Minimum total in-air duration before seeking
## a surface (seconds).
const AIR_DURATION_MIN := 5.0

## Maximum total in-air duration before seeking
## a surface (seconds).
const AIR_DURATION_MAX := 15.0

## Gravity applied when settling onto a floor
## during rest (pixels/sec^2).
const REST_GRAVITY := 120.0

## Constant push speed into wall during wall
## rest (pixels/sec). Just enough for
## move_and_slide to detect wall contact.
const WALL_REST_PUSH := 10.0

## Noise frequency for organic wander.
const WANDER_NOISE_FREQ := 0.5

## Wander force strength (pixels/sec).
const WANDER_STRENGTH := 15.0

## Player avoidance radius (pixels).
const PLAYER_FLEE_RADIUS := 35.0

## Minimum seconds since last disturbance
## before a new one can register.
const DISTURB_COOLDOWN_SEC := 0.8

## Player avoidance force (pixels/sec).
const PLAYER_FLEE_WEIGHT := 120.0

## Distance to target to consider arrived
## (pixels).
const ARRIVAL_DISTANCE := 8.0
const _ARRIVAL_DISTANCE_SQ := (
	ARRIVAL_DISTANCE * ARRIVAL_DISTANCE)

## Speed at which the butterfly drifts toward
## a surface when landing (pixels/sec).
const LANDING_SPEED := 30.0

## Distance to probe for nearby water
## (pixels).
const WATER_AVOID_DIST := 16.0

## Steering force away from water
## (pixels/sec).
const WATER_AVOID_WEIGHT := 60.0

## Probability of picking a wall surface
## over a floor when choosing a rest target.
const WALL_SURFACE_PROBABILITY := 0.75

## Maximum sampling attempts for air targets.
const AIR_TARGET_MAX_ATTEMPTS := 20

## Maximum sampling attempts for surface
## targets.
const SURFACE_TARGET_MAX_ATTEMPTS := 20

## Per-target safety timeout (seconds).
const SEGMENT_TIMEOUT_SEC := 8.0

## Frames to ignore surface contact after
## entering flight (prevents immediately
## re-entering bump rest on a surface).
const SURFACE_GRACE_FRAMES := 6

## Min perpendicular curve offset as fraction
## of start-to-end distance.
const CURVE_OFFSET_MIN := 0.2

## Max perpendicular curve offset as fraction
## of start-to-end distance.
const CURVE_OFFSET_MAX := 0.4

## How far ahead on curve to place the guide
## point (in t-parameter units).
const CURVE_LOOKAHEAD := 0.1

## Velocity lerp rate for smooth turning
## (per second).
const STEER_RESPONSE := 3.0

## Maximum sampling attempts for evasion
## targets.
const EVASION_TARGET_ATTEMPTS := 10

## Min dot product between flee direction and
## evasion target direction.
const EVASION_MIN_DOT := 0.3

## Minimum distance for evasion targets
## (pixels). Prevents ultra-short curves
## that cause jitter from rapid re-picking.
const EVASION_MIN_DISTANCE := 30.0

## Flight speed multiplier during evasion.
const EVASION_SPEED_MULT := 2.0

## Steer response multiplier during evasion.
const EVASION_STEER_MULT := 2.0

## Flutter frequency multiplier when agitated.
const EVASION_FLUTTER_FREQ_MULT := 1.6

## Flutter amplitude multiplier when agitated.
const EVASION_FLUTTER_AMP_MULT := 1.4

## How quickly agitation ramps up (per second).
const AGITATION_RISE_RATE := 4.0

## How quickly agitation decays (per second).
const AGITATION_DECAY_RATE := 0.8

## Sprite flutter base frequency (Hz).
const FLUTTER_FREQ := 2.0

## Per-burst frequency variation (multiplier
## range around 1.0).
const FLUTTER_FREQ_VARIANCE := 0.3

## Sprite flutter displacement (pixels).
const FLUTTER_AMPLITUDE := 4.0

## Bounce sharpness: 0 = pure sine,
## 1 = fully bouncy.
const FLUTTER_BOUNCE := 0.35

## Min duration of a flapping burst (seconds).
const FLAP_DURATION_MIN := 0.6

## Max duration of a flapping burst (seconds).
const FLAP_DURATION_MAX := 1.4

## Min duration of a glide pause (seconds).
const GLIDE_DURATION_MIN := 0.3

## Max duration of a glide pause (seconds).
const GLIDE_DURATION_MAX := 0.8

## How quickly the envelope eases between
## flap and glide (per second).
const FLUTTER_ENVELOPE_RATE := 5.0

## Emitted when a player disturbs this
## butterfly.
signal disturbed(player_id: int)


var _state: int = State.FLYING
var _target := Vector2.ZERO
var _noise: FastNoiseLite
var _noise_time := 0.0
var _collision_tiles: TileMapLayer
var _interior_cells: Array = []
var _prev_position := Vector2.ZERO

## Seconds since this butterfly was last
## disturbed.
var _time_since_disturbed := INF

## Countdown for total in-air phase before
## seeking a surface.
var _air_duration_timer := 0.0

## Per-target safety timeout.
var _segment_timer := 0.0

## Rest duration countdown.
var _rest_timer := 0.0

## Bump rest duration countdown.
var _bump_rest_timer := 0.0

## True when current target is a surface.
var _seeking_surface := false

## True when drifting toward surface to land.
var _landing := false

## True when evading a nearby player.
var _evading := false

## Direction to drift when landing
## (toward the surface).
var _landing_direction := Vector2.ZERO

## Cached wall surface targets from
## SnailSpawner.
var _wall_surfaces: Array = []

## Cached floor surface targets from
## SnailSpawner.
var _floor_surfaces: Array = []

## Bezier curve start point.
var _curve_start := Vector2.ZERO

## Bezier curve control point.
var _curve_control := Vector2.ZERO

## Bezier curve end point.
var _curve_end := Vector2.ZERO

## Progress along curve [0, 1].
var _curve_t := 0.0

## Rate of t advance per second.
var _curve_speed := 0.0

## Current flutter envelope (0 = glide,
## 1 = full flap). Eases between states.
var _flutter_envelope := 1.0

## True when in a flapping burst, false
## during a glide pause.
var _flapping := true

## Countdown for current flap/glide phase.
var _flutter_phase_timer := 0.0

## Frequency multiplier for current flap
## burst (randomized each burst).
var _flutter_freq_mult := 1.0

## Phase accumulator for flutter sine wave.
## Avoids phase jumps when frequency changes.
var _flutter_phase := 0.0

## Frames remaining where surface contact
## is ignored after entering flight.
var _surface_grace := 0

## Current agitation level (0 = calm,
## 1 = fully agitated). Ramps up during
## evasion, decays when calm.
var _agitation := 0.0

@onready var _sprite: AnimatedSprite2D = (
	$AnimatedSprite2D)


## Call after instantiation, before add_child.
func setup(
	tiles: TileMapLayer,
	interior_cells: Array,
) -> void:
	_collision_tiles = tiles
	_interior_cells = interior_cells
	_precompute_surfaces()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision_layer = 0
	# Collide with normal_surfaces only.
	collision_mask = 1 << 0
	up_direction = Vector2.UP
	floor_stop_on_slope = false

	# Assign random color.
	var hue := randf()
	var color := Color.from_hsv(
		hue, COLOR_SATURATION, COLOR_VALUE)
	_sprite.modulate = color

	# Wander noise.
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.noise_type = (
		FastNoiseLite.TYPE_SIMPLEX)
	_noise.frequency = WANDER_NOISE_FREQ

	_enter_flying()
	_pick_air_target()

	# Random start frame within the fly
	# animation.
	var frame_count := (
		_sprite.sprite_frames
			.get_frame_count(&"fly"))
	if frame_count > 1:
		_sprite.frame = randi() % frame_count

	CritterWrapGhost.create_ghosts(
		self, _sprite)


func _physics_process(delta: float) -> void:
	_noise_time += delta
	_time_since_disturbed += delta

	# Ease agitation toward target.
	var agitation_target := (
		1.0 if _evading else 0.0)
	if _agitation < agitation_target:
		_agitation = minf(
			_agitation
			+ AGITATION_RISE_RATE * delta,
			1.0)
	else:
		_agitation = maxf(
			_agitation
			- AGITATION_DECAY_RATE * delta,
			0.0)

	# Tick flap/glide phase timer during
	# flight.
	if _state == State.FLYING:
		_flutter_phase_timer -= delta
		if _flutter_phase_timer <= 0.0:
			if _flapping:
				_start_glide()
			else:
				_start_flap_burst()
		# Ease envelope toward target.
		var target_env := (
			1.0 if _flapping else 0.0)
		_flutter_envelope = move_toward(
			_flutter_envelope,
			target_env,
			FLUTTER_ENVELOPE_RATE * delta)

	match _state:
		State.FLYING:
			_air_duration_timer -= delta
			_segment_timer -= delta
			var speed_mult := lerpf(
				1.0,
				EVASION_SPEED_MULT,
				_agitation)
			_curve_t = minf(
				_curve_t
				+ _curve_speed
				* speed_mult * delta,
				1.0)
			_process_flying(delta)
		State.RESTING:
			_rest_timer -= delta
			_process_resting(delta)
		State.BUMP_RESTING:
			_bump_rest_timer -= delta
			_process_bump_rest(delta)

	# Wrap position for toroidal level bounds.
	if G.level is NetworkedLevel:
		G.level.wrap_node(self)


func _process_flying(delta: float) -> void:
	# Blend speed and steer response based on
	# agitation.
	var speed := lerpf(
		FLY_SPEED,
		FLY_SPEED * EVASION_SPEED_MULT,
		_agitation)
	var steer_rate := lerpf(
		STEER_RESPONSE,
		STEER_RESPONSE * EVASION_STEER_MULT,
		_agitation)

	# Steer toward guide point on Bezier
	# curve.
	var guide := _sample_curve(
		minf(
			_curve_t + CURVE_LOOKAHEAD,
			1.0))
	var to_guide := guide - global_position
	var steer := Vector2.ZERO

	if to_guide.length() > 1.0:
		steer = (
			to_guide.normalized() * speed)

	# Noise wander.
	var nx := _noise.get_noise_2d(
		_noise_time * 60.0, 0.0)
	var ny := _noise.get_noise_2d(
		0.0, _noise_time * 60.0)
	steer += (
		Vector2(nx, ny) * WANDER_STRENGTH)

	# Landing behavior: dampen flight and
	# push toward the surface.
	if _landing:
		steer *= 0.4
		steer += (
			_landing_direction * LANDING_SPEED)

	# Water avoidance.
	var water_flee := _calc_water_avoidance()
	steer += water_flee
	if (
		_landing
		and water_flee.length() > 1.0
	):
		_pick_surface_target()

	# Player avoidance (reactive supplement
	# when not in evasion mode).
	var flee_result := _calc_player_flee()
	if not _evading:
		steer += flee_result[0] as Vector2

	# Smooth velocity transition.
	velocity = velocity.lerp(
		steer, steer_rate * delta)
	_prev_position = global_position
	move_and_slide()

	# If we entered water, revert and
	# re-pick target.
	if _is_in_water():
		global_position = _prev_position
		if _landing or _seeking_surface:
			_pick_surface_target()
		else:
			_pick_air_target()
		return

	# Tick surface grace countdown.
	if _surface_grace > 0:
		_surface_grace -= 1

	# If we bumped a surface while not
	# landing or evading, rest briefly before
	# resuming. Grace period prevents
	# immediately re-entering rest after
	# takeoff. Evading butterflies slide along
	# surfaces instead of stopping.
	if (
		not _landing
		and not _evading
		and _surface_grace <= 0
		and (is_on_floor() or is_on_wall())
	):
		_enter_bump_rest()
		return

	# Flip sprite based on horizontal
	# movement.
	if absf(velocity.x) > 0.5:
		_sprite.flip_h = velocity.x < 0.0

	# Sprite flutter (visual only). Frequency
	# and amplitude increase with agitation.
	var freq_mult := lerpf(
		1.0, EVASION_FLUTTER_FREQ_MULT,
		_agitation)
	var amp_mult := lerpf(
		1.0, EVASION_FLUTTER_AMP_MULT,
		_agitation)
	var freq := (
		FLUTTER_FREQ
		* _flutter_freq_mult
		* freq_mult)
	_flutter_phase += freq * delta * TAU
	var raw := sin(_flutter_phase)
	var bouncy := absf(raw)
	var blend := lerpf(
		raw, bouncy, FLUTTER_BOUNCE)
	_sprite.position.y = (
		-blend
		* FLUTTER_AMPLITUDE
		* amp_mult
		* _flutter_envelope)

	# Target arrival / state transitions.
	var dist_sq_to_end := (
		global_position.distance_squared_to(
			_curve_end))
	var arrived := (
		_curve_t >= 1.0
		and dist_sq_to_end < _ARRIVAL_DISTANCE_SQ)
	var timed_out := _segment_timer <= 0.0
	var flee: Vector2 = flee_result[0]
	var nearest_pos: Vector2 = flee_result[2]
	var player_close := flee.length() > 1.0

	if _evading:
		# Clear evasion when player leaves range.
		# Continue current curve naturally so
		# agitation decays smoothly.
		if not player_close:
			_evading = false
		if arrived or timed_out:
			if player_close:
				_pick_evasion_target(
					nearest_pos)
			elif _air_duration_timer <= 0.0:
				_pick_surface_target()
			else:
				_pick_air_target()
	elif _landing:
		if timed_out:
			_pick_surface_target()
		elif is_on_floor() or is_on_wall():
			_enter_resting()
	elif _seeking_surface:
		if arrived:
			_landing = true
		elif timed_out:
			_pick_surface_target()
		elif player_close:
			_pick_evasion_target(nearest_pos)
	else:
		# Normal air chaining.
		if arrived or timed_out:
			if _air_duration_timer <= 0.0:
				_pick_surface_target()
			else:
				_pick_air_target()
		elif player_close:
			_pick_evasion_target(nearest_pos)


func _process_resting(delta: float) -> void:
	# Apply surface-appropriate rest forces.
	if is_on_wall():
		# Push into wall, zero vertical to
		# prevent sliding.
		velocity = (
			-get_wall_normal()
			* WALL_REST_PUSH)
	else:
		# Floor rest: gravity settles onto
		# surface.
		velocity.y += REST_GRAVITY * delta
		velocity.x = 0.0

	# Player proximity check: flee if close.
	var result := _calc_player_flee()
	var flee: Vector2 = result[0]
	if flee.length() > 1.0:
		# Emit disturbance if cooldown
		# expired.
		var pid: int = result[1]
		if (
			pid >= 0
			and _time_since_disturbed
				>= DISTURB_COOLDOWN_SEC
		):
			_time_since_disturbed = 0.0
			disturbed.emit(pid)
		var pos: Vector2 = result[2]
		_enter_flying()
		_pick_evasion_target(pos)
		return

	move_and_slide()

	# Detect surface for sprite rotation.
	if is_on_wall():
		var normal := get_wall_normal()
		_sprite.rotation = (
			normal.angle() + PI / 2.0)
	elif is_on_floor():
		_sprite.rotation = 0.0

	if _rest_timer <= 0.0:
		_enter_flying()
		_pick_air_target()


func _enter_flying() -> void:
	_state = State.FLYING
	_landing = false
	_seeking_surface = false
	_evading = false
	_landing_direction = Vector2.ZERO
	_surface_grace = SURFACE_GRACE_FRAMES
	_air_duration_timer = randf_range(
		AIR_DURATION_MIN, AIR_DURATION_MAX)
	_sprite.rotation = 0.0
	_sprite.position.y = 0.0
	_sprite.play(&"fly")
	_start_flap_burst()


func _enter_resting() -> void:
	_state = State.RESTING
	_rest_timer = randf_range(
		REST_DURATION_MIN, REST_DURATION_MAX)
	velocity = Vector2.ZERO
	_seeking_surface = false
	_landing = false
	_evading = false
	_sprite.position.y = 0.0
	_sprite.play(&"rest")


func _enter_bump_rest() -> void:
	_state = State.BUMP_RESTING
	_bump_rest_timer = randf_range(
		BUMP_REST_DURATION_MIN,
		BUMP_REST_DURATION_MAX)
	velocity = Vector2.ZERO
	_sprite.position.y = 0.0
	_sprite.play(&"rest")


func _process_bump_rest(delta: float) -> void:
	# Apply surface-appropriate rest forces.
	if is_on_wall():
		velocity = (
			-get_wall_normal()
			* WALL_REST_PUSH)
	else:
		velocity.y += REST_GRAVITY * delta
		velocity.x = 0.0

	# Player proximity: flee if close.
	var result := _calc_player_flee()
	var flee: Vector2 = result[0]
	if flee.length() > 1.0:
		var pid: int = result[1]
		if (
			pid >= 0
			and _time_since_disturbed
				>= DISTURB_COOLDOWN_SEC
		):
			_time_since_disturbed = 0.0
			disturbed.emit(pid)
		var pos: Vector2 = result[2]
		_enter_flying()
		_pick_evasion_target(pos)
		return

	move_and_slide()

	# Orient sprite to surface.
	if is_on_wall():
		var normal := get_wall_normal()
		_sprite.rotation = (
			normal.angle() + PI / 2.0)
	elif is_on_floor():
		_sprite.rotation = 0.0

	# Resume flight when timer expires.
	if _bump_rest_timer <= 0.0:
		_sprite.rotation = 0.0
		_enter_flying()
		if _air_duration_timer <= 0.0:
			_pick_surface_target()
		else:
			_pick_air_target()


func _start_flap_burst() -> void:
	_flapping = true
	_flutter_phase_timer = randf_range(
		FLAP_DURATION_MIN,
		FLAP_DURATION_MAX)
	_flutter_freq_mult = randf_range(
		1.0 - FLUTTER_FREQ_VARIANCE,
		1.0 + FLUTTER_FREQ_VARIANCE)


func _start_glide() -> void:
	_flapping = false
	_flutter_phase_timer = randf_range(
		GLIDE_DURATION_MIN,
		GLIDE_DURATION_MAX)


# ---- Target picking ----


func _pick_air_target() -> void:
	_seeking_surface = false
	_landing = false
	_evading = false
	_segment_timer = SEGMENT_TIMEOUT_SEC

	if (
		_interior_cells.is_empty()
		or not is_instance_valid(
			_collision_tiles)
	):
		_target = (
			global_position
			+ Vector2(
				randf_range(-40.0, 40.0),
				randf_range(-40.0, 40.0)))
		_compute_curve(_target)
		return

	for _attempt in AIR_TARGET_MAX_ATTEMPTS:
		var candidate: Vector2i = (
			_interior_cells.pick_random())
		if _is_cell_water(candidate):
			continue
		var cand_local := (
			_collision_tiles.map_to_local(
				candidate))
		var cand_global := (
			_collision_tiles.to_global(
				cand_local))
		if _has_clear_path(cand_global):
			_target = (
				cand_global
				+ Vector2(
					randf_range(-4.0, 4.0),
					randf_range(-4.0, 4.0)))
			_compute_curve(_target)
			return

	push_warning(
		"Butterfly: failed to find clear air "
		+ "target after %d attempts."
		% AIR_TARGET_MAX_ATTEMPTS)
	_target = (
		global_position
		+ Vector2(
			randf_range(-40.0, 40.0),
			randf_range(-40.0, 40.0)))
	_compute_curve(_target)


func _pick_surface_target() -> void:
	_seeking_surface = true
	_landing = false
	_evading = false
	_segment_timer = SEGMENT_TIMEOUT_SEC

	if not is_instance_valid(_collision_tiles):
		_pick_air_target()
		return

	# Decide wall vs floor.
	var use_wall := (
		randf() < WALL_SURFACE_PROBABILITY
		and not _wall_surfaces.is_empty())
	var pool: Array = (
		_wall_surfaces if use_wall
		else _floor_surfaces)

	# Fallback to the other pool if chosen
	# is empty.
	if pool.is_empty():
		pool = (
			_floor_surfaces if use_wall
			else _wall_surfaces)
	if pool.is_empty():
		push_warning(
			"Butterfly: no surfaces "
			+ "available.")
		_pick_air_target()
		return

	var half := Level.TILE_SIZE / 2.0
	for _attempt in SURFACE_TARGET_MAX_ATTEMPTS:
		var surface: Dictionary = (
			pool.pick_random())
		var tile: Vector2i = surface.tile
		var face: int = surface.face

		var normal := _face_to_normal(face)
		var tile_local := (
			_collision_tiles.map_to_local(
				tile))
		var tile_global := (
			_collision_tiles.to_global(
				tile_local))
		# Position at the surface edge,
		# offset into the empty space.
		var surface_pos := (
			tile_global
			+ Vector2(normal) * half)

		if not _has_clear_path(surface_pos):
			continue

		_target = surface_pos
		_landing_direction = -Vector2(normal)
		_compute_curve(_target)
		return

	# All attempts failed; use last sampled.
	push_warning(
		"Butterfly: failed to find clear "
		+ "surface target after %d attempts."
		% SURFACE_TARGET_MAX_ATTEMPTS)
	var fallback: Dictionary = (
		pool.pick_random())
	var normal := (
		_face_to_normal(fallback.face))
	var tile_local := (
		_collision_tiles.map_to_local(
			fallback.tile))
	var tile_global := (
		_collision_tiles.to_global(
			tile_local))
	_target = (
		tile_global
		+ Vector2(normal)
		* Level.TILE_SIZE / 2.0)
	_landing_direction = -Vector2(normal)
	_compute_curve(_target)


func _pick_evasion_target(
	nearest_player_pos: Vector2,
) -> void:
	_evading = true
	_seeking_surface = false
	_landing = false
	_segment_timer = SEGMENT_TIMEOUT_SEC

	var flee_dir := (
		(global_position - nearest_player_pos)
		.normalized())

	if (
		_interior_cells.is_empty()
		or not is_instance_valid(
			_collision_tiles)
	):
		_target = (
			global_position
			+ flee_dir * 60.0)
		_compute_curve(_target)
		return

	for _attempt in EVASION_TARGET_ATTEMPTS:
		var candidate: Vector2i = (
			_interior_cells.pick_random())
		if _is_cell_water(candidate):
			continue
		var cand_local := (
			_collision_tiles.map_to_local(
				candidate))
		var cand_global := (
			_collision_tiles.to_global(
				cand_local))
		# Skip targets too close to avoid
		# ultra-short curves.
		if (
			cand_global
				.distance_squared_to(
					global_position)
			< EVASION_MIN_DISTANCE
				* EVASION_MIN_DISTANCE
		):
			continue
		var to_cand := (
			(cand_global - global_position)
			.normalized())
		if to_cand.dot(flee_dir) < (
				EVASION_MIN_DOT):
			continue
		if not _has_clear_path(cand_global):
			continue
		_target = cand_global
		_compute_curve(_target)
		return

	# Fallback: move in flee direction.
	_target = (
		global_position + flee_dir * 60.0)
	_compute_curve(_target)


# ---- Bezier curve helpers ----


func _compute_curve(target: Vector2) -> void:
	_curve_start = global_position
	_curve_end = target
	_curve_t = 0.0

	var mid := (
		(_curve_start + _curve_end) * 0.5)
	var diff := _curve_end - _curve_start
	var dist := diff.length()

	if dist < 1.0:
		_curve_control = mid
		_curve_speed = 1.0
		return

	var dir := diff / dist
	var perp := Vector2(-dir.y, dir.x)
	var offset := (
		randf_range(
			CURVE_OFFSET_MIN,
			CURVE_OFFSET_MAX)
		* dist)
	var sign_val := (
		1.0 if randf() < 0.5 else -1.0)

	# Try one side, then the other, then
	# fall back to straight.
	var candidate := (
		mid + perp * offset * sign_val)
	_curve_control = candidate
	if not _is_curve_clear():
		candidate = (
			mid
			+ perp * offset * -sign_val)
		_curve_control = candidate
		if not _is_curve_clear():
			_curve_control = mid

	# Approximate curve length via segments.
	var mid_a := _sample_curve(0.25)
	var mid_b := _sample_curve(0.5)
	var mid_c := _sample_curve(0.75)
	var approx_len := (
		_curve_start.distance_to(mid_a)
		+ mid_a.distance_to(mid_b)
		+ mid_b.distance_to(mid_c)
		+ mid_c.distance_to(_curve_end))
	_curve_speed = (
		FLY_SPEED / maxf(approx_len, 1.0))


func _sample_curve(t: float) -> Vector2:
	var t1 := 1.0 - t
	return (
		t1 * t1 * _curve_start
		+ 2.0 * t1 * t * _curve_control
		+ t * t * _curve_end)


## Samples the current Bezier curve at
## half-tile intervals and returns false if
## any sample point lies in a solid tile.
func _is_curve_clear() -> bool:
	if not is_instance_valid(_collision_tiles):
		return true
	var step := Level.TILE_SIZE * 0.5
	# Walk along the curve in world-space
	# increments.
	var prev := _curve_start
	var num_samples := 8
	for i in num_samples:
		var t := float(i + 1) / num_samples
		var pt := _sample_curve(t)
		# Also check intermediate point
		# between samples for tight gaps.
		var mid_pt := (prev + pt) * 0.5
		for check in [mid_pt, pt]:
			var local := (
				_collision_tiles.to_local(
					check))
			var cell := (
				_collision_tiles.local_to_map(
					local))
			var td := (
				_collision_tiles
					.get_cell_tile_data(cell))
			if td != null:
				return false
		prev = pt
	return true


# ---- Surface precomputation ----


func _precompute_surfaces() -> void:
	if not is_instance_valid(_collision_tiles):
		return
	var surfaces := (
		SnailSpawner.find_interior_surfaces(
			_collision_tiles))
	for s in surfaces:
		var face: int = s.face
		match face:
			Snail.Face.LEFT, \
			Snail.Face.RIGHT:
				_wall_surfaces.append(s)
			Snail.Face.TOP:
				_floor_surfaces.append(s)


static func _face_to_normal(
	face: int,
) -> Vector2i:
	match face:
		Snail.Face.TOP:
			return Vector2i(0, -1)
		Snail.Face.RIGHT:
			return Vector2i(1, 0)
		Snail.Face.BOTTOM:
			return Vector2i(0, 1)
		Snail.Face.LEFT:
			return Vector2i(-1, 0)
	return Vector2i(0, -1)


# ---- Utility ----


func _is_point_solid(pos: Vector2) -> bool:
	if not is_instance_valid(_collision_tiles):
		return false
	var local := _collision_tiles.to_local(pos)
	var cell := (
		_collision_tiles.local_to_map(local))
	var td := (
		_collision_tiles
			.get_cell_tile_data(cell))
	return td != null


func _is_in_water() -> bool:
	if not is_instance_valid(_collision_tiles):
		return false
	var local_pos := _collision_tiles.to_local(
		global_position)
	var cell := _collision_tiles.local_to_map(
		local_pos)
	return _is_cell_water(cell)


func _is_cell_water(cell: Vector2i) -> bool:
	var tile_data := (
		_collision_tiles
			.get_cell_tile_data(cell))
	if tile_data == null:
		return false
	return (tile_data.get_terrain_set()
		== Level.TERRAIN_SET_WATER)


## Probe one tile in each cardinal direction.
## Return a steering vector away from any
## nearby water cells.
func _calc_water_avoidance() -> Vector2:
	if not is_instance_valid(_collision_tiles):
		return Vector2.ZERO
	var avoid := Vector2.ZERO
	var dirs: Array[Vector2] = [
		Vector2.DOWN, Vector2.UP,
		Vector2.LEFT, Vector2.RIGHT,
	]
	for dir in dirs:
		var probe_pos := (
			global_position
			+ dir * WATER_AVOID_DIST)
		var local := (
			_collision_tiles.to_local(
				probe_pos))
		var cell := (
			_collision_tiles.local_to_map(
				local))
		if _is_cell_water(cell):
			avoid -= dir * WATER_AVOID_WEIGHT
	return avoid


## Steps from current position to to_pos in
## half-tile increments. Returns false if any
## intermediate cell contains tile data (solid
## wall or water).
func _has_clear_path(
	to_pos: Vector2,
) -> bool:
	if not is_instance_valid(_collision_tiles):
		return true
	var step := Level.TILE_SIZE * 0.5
	var from := global_position
	var diff := to_pos - from
	var dist := diff.length()
	if dist < step:
		return true
	var dir := diff / dist
	var steps := int(dist / step)
	for i in steps:
		var check := (
			from + dir * step * float(i + 1))
		var local := (
			_collision_tiles.to_local(check))
		var cell := (
			_collision_tiles.local_to_map(
				local))
		var td := (
			_collision_tiles
				.get_cell_tile_data(cell))
		if td != null:
			return false
	return true


## Returns [flee_vector, nearest_player_id,
## nearest_player_position]. Player ID is -1
## when no player is nearby.
func _calc_player_flee() -> Array:
	var flee := Vector2.ZERO
	var nearest_dist := INF
	var nearest_pid := -1
	var nearest_pos := Vector2.ZERO
	var level: Level = G.level
	if not is_instance_valid(level):
		return [flee, nearest_pid, nearest_pos]

	for player in level.players:
		if not is_instance_valid(player):
			continue
		var diff := (
			global_position
			- player.global_position)
		var dist := diff.length()
		if dist > 0.0 and (
				dist < PLAYER_FLEE_RADIUS):
			var ratio := (
				1.0
				- dist / PLAYER_FLEE_RADIUS)
			flee += (
				diff.normalized()
				* PLAYER_FLEE_WEIGHT * ratio)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_pid = player.player_id
				nearest_pos = (
					player.global_position)

	return [flee, nearest_pid, nearest_pos]
