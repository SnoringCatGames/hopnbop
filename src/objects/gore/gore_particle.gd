class_name GoreParticle
extends CharacterBody2D
## A single gore/flower particle that bounces off level
## geometry and either rasterizes into the accumulation
## buffer or fades out when at rest.


signal came_to_rest(particle: GoreParticle)

var type_index := 0
var is_behind := false
## Set by GoreManager at spawn time. When true, the
## particle rasterizes into the accumulation buffer on
## rest. When false, it fades out instead.
var will_rasterize := true

## Per-particle fade delay override (seconds).
## When >= 0, used instead of the global
## gore_fade_delay_sec from settings.
var fade_delay_sec := -1.0

## Whether this particle emits trail particles
## while moving. Set to false for poop particles.
var emit_trails := true

## Per-particle bounce damping override. When
## >= 0, used instead of the global setting.
## Set to 0.0 to disable bouncing entirely.
var bounce_damping := -1.0

var _rest_frame_counter := 0
var _trail_elapsed := 0.0


func _physics_process(delta: float) -> void:
	# Apply gravity.
	velocity.y += (
		G.settings.default_gravity_acceleration
		* G.settings.gore_gravity_multiplier
		* delta)

	var collision := move_and_collide(velocity * delta)
	if collision:
		var damping: float
		if bounce_damping >= 0.0:
			damping = bounce_damping
		else:
			damping = G.settings.gore_bounce_damping
		velocity = velocity.bounce(
			collision.get_normal()
		) * damping
		velocity *= G.settings.gore_friction

	# Wrap position for toroidal level bounds.
	if G.level is NetworkedLevel:
		G.level.wrap_node(self)

	# Spawn trail particles while moving.
	if emit_trails:
		_trail_elapsed += delta
		var spawn_interval: float = (
			G.settings
				.gore_trail_spawn_interval_sec)
		if _trail_elapsed >= spawn_interval:
			_trail_elapsed -= spawn_interval
			if (
				is_instance_valid(G.level) and
				is_instance_valid(
					G.level.gore_manager)
			):
				G.level.gore_manager.spawn_trail_particle(
				position,
				type_index,
				is_behind,
				self,
				velocity,
			)

	# Rest detection with consecutive-frame
	# requirement. Only count frames where the chunk
	# is in contact with a surface. A chunk at the
	# apex of its arc is airborne, not at rest.
	if (
		collision
		and velocity.length()
			< G.settings.gore_rest_speed_threshold
	):
		_rest_frame_counter += 1
		var rest_frames := int(
			G.settings.gore_rest_duration_sec
			/ Netcode.time.get_time_step_sec()
		)
		if _rest_frame_counter >= rest_frames:
			# Clear velocity so trail clamping sees
			# the chunk as not moving upward. Without
			# this, the post-bounce velocity.y is
			# slightly negative and the clamp skips.
			velocity = Vector2.ZERO
			if will_rasterize:
				came_to_rest.emit(self)
				queue_free()
			else:
				_disable_collision()
				_start_fade()
				set_physics_process(false)
	else:
		_rest_frame_counter = 0


## Disables collision on this particle to reduce
## physics engine load once at rest.
func _disable_collision() -> void:
	collision_layer = 0
	collision_mask = 0
	var shape: CollisionShape2D = (
		get_node_or_null("CollisionShape2D"))
	if is_instance_valid(shape):
		shape.set_deferred("disabled", true)


func _start_fade() -> void:
	var delay: float
	if fade_delay_sec >= 0.0:
		delay = fade_delay_sec
	else:
		delay = G.settings.gore_fade_delay_sec
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(
		self, "modulate:a", 0.0,
		G.settings.gore_fade_duration_sec,
	).set_ease(
		Tween.EASE_IN
	).set_trans(
		Tween.TRANS_QUAD
	)
	tween.tween_callback(queue_free)
