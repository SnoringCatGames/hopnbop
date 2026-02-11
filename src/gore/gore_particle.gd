class_name GoreParticle
extends CharacterBody2D
## A single gore/flower particle that bounces off level geometry
## and rasterizes into the accumulation buffer when at rest.


signal came_to_rest(particle: GoreParticle)

var type_index := 0

var _rest_frame_counter := 0


func _physics_process(delta: float) -> void:
	# Apply gravity.
	velocity.y += G.settings.default_gravity_acceleration * delta

	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(
			collision.get_normal()) * G.settings.gore_bounce_damping
		velocity *= G.settings.gore_friction

	# Rest detection with consecutive-frame requirement.
	if velocity.length() < G.settings.gore_rest_speed_threshold:
		_rest_frame_counter += 1
		if _rest_frame_counter >= G.settings.gore_rest_frame_count:
			came_to_rest.emit(self)
			queue_free()
	else:
		_rest_frame_counter = 0
