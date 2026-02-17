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

var _rest_frame_counter := 0
var _trail_elapsed := 0.0


func _physics_process(delta: float) -> void:
	# Apply gravity.
	velocity.y += \
		G.settings.default_gravity_acceleration * delta

	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(
			collision.get_normal()
		) * G.settings.gore_bounce_damping
		velocity *= G.settings.gore_friction

	# Spawn trail particles while moving.
	_trail_elapsed += delta
	var spawn_interval: float = \
		G.settings.gore_trail_spawn_interval_sec
	if _trail_elapsed >= spawn_interval:
		_trail_elapsed -= spawn_interval
		var level: Level = G.level
		if (
			is_instance_valid(level) and
			is_instance_valid(level.gore_manager)
		):
			var start_index: int = G.settings \
				.gore_trail_start_size_index[
					type_index]
			level.gore_manager \
				.spawn_trail_particle(
					global_position,
					start_index,
					is_behind)

	# Rest detection with consecutive-frame
	# requirement.
	if (
		velocity.length() <
		G.settings.gore_rest_speed_threshold
	):
		_rest_frame_counter += 1
		if (
			_rest_frame_counter >=
			G.settings.gore_rest_frame_count
		):
			if will_rasterize:
				came_to_rest.emit(self)
				queue_free()
			else:
				_start_fade()
				set_physics_process(false)
	else:
		_rest_frame_counter = 0


func _start_fade() -> void:
	var tween := create_tween()
	tween.tween_property(
		self, "modulate:a", 0.0,
		G.settings.gore_fade_duration_sec,
	).set_ease(
		Tween.EASE_IN
	).set_trans(
		Tween.TRANS_QUAD
	)
	tween.tween_callback(queue_free)
