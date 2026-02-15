class_name GoreKickable
extends CharacterBody2D
## A kickable gore/flower piece that persists, reacts to
## player collisions, and fades out after a time.
##
## Client-side only. Not networked or rollback-aware.


const _FADE_DURATION_SEC := 0.5
const _MAX_KICKS_PER_PLAYER := 3

var type_index := 0

var _lifetime := 0.0
var _kick_cooldown := 0.0
var _is_fading := false
var _kick_counts: Dictionary = {}  # Player → int


func _ready() -> void:
	$KickArea.body_entered.connect(
		_on_kick_area_body_entered)


func _physics_process(delta: float) -> void:
	# Apply gravity.
	velocity.y += \
		G.settings.default_gravity_acceleration * delta

	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(
			collision.get_normal()
		) * G.settings.gore_kickable_bounce_damping
		velocity *= G.settings.gore_kickable_friction

	# Update cooldowns.
	if _kick_cooldown > 0.0:
		_kick_cooldown -= delta

	# Update lifetime and start fade when expired.
	_lifetime += delta
	if (
		not _is_fading and
		_lifetime >= G.settings.gore_kickable_lifetime_sec
	):
		_start_fade()


func _on_kick_area_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	if _kick_cooldown > 0.0:
		return
	var count: int = _kick_counts.get(body, 0)
	if count >= _MAX_KICKS_PER_PLAYER:
		return
	var player := body as Player

	# Apply impulse from player velocity.
	var impulse := \
		player.velocity * \
		G.settings.gore_kickable_kick_multiplier

	# Push horizontally away from the player's center.
	var away_x := global_position.x - player.global_position.x
	if away_x != 0.0:
		impulse.x += \
			signf(away_x) * \
			G.settings.gore_kickable_repulsion_speed

	# Ensure a minimum upward pop so kicked pieces
	# launch visibly into the air.
	impulse.y = min(
		impulse.y,
		-G.settings.gore_kickable_min_kick_pop)

	# Clamp to max kick speed.
	var max_speed := G.settings.gore_kickable_max_kick_speed
	if impulse.length() > max_speed:
		impulse = impulse.normalized() * max_speed

	velocity = impulse
	_kick_cooldown = \
		G.settings.gore_kickable_kick_cooldown_sec
	_kick_counts[body] = count + 1

	# Reset lifetime so kicked pieces persist longer.
	_lifetime = 0.0


func _start_fade() -> void:
	_is_fading = true
	var tween := create_tween()
	tween.tween_property(
		self, "modulate:a", 0.0,
		_FADE_DURATION_SEC,
	).set_ease(
		Tween.EASE_IN
	).set_trans(
		Tween.TRANS_QUAD
	)
	tween.tween_callback(queue_free)
