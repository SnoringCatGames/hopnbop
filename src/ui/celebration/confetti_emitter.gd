class_name ConfettiEmitter
extends Node2D
## Spawns colorful confetti particles at a world
## position with an upward burst. Each particle is
## a small colored rectangle affected by gravity.


const _GRAVITY := 400.0
const _UPWARD_MIN := -350.0
const _UPWARD_MAX := -150.0
const _HORIZONTAL_SPREAD := 200.0
const _PARTICLE_LIFETIME_SEC := 2.0
const _FADE_DURATION_SEC := 0.5
const _PARTICLE_SIZE := Vector2(4, 3)
const _SPIN_SPEED_MAX := 12.0

const _COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.2),  # Red.
	Color(1.0, 0.85, 0.1), # Yellow.
	Color(0.2, 0.9, 0.3),  # Green.
	Color(0.3, 0.5, 1.0),  # Blue.
	Color(1.0, 0.4, 0.7),  # Pink.
	Color(1.0, 0.55, 0.1), # Orange.
]


var _particles: Array[Dictionary] = []
var _cached_texture: ImageTexture


func burst(
	world_position: Vector2,
	count: int = 40,
) -> void:
	if _cached_texture == null:
		_cached_texture = _create_pixel_texture()

	for i in count:
		var sprite := Sprite2D.new()
		sprite.texture = _cached_texture
		sprite.modulate = _COLORS[
			randi() % _COLORS.size()
		]
		sprite.position = world_position
		add_child(sprite)

		_particles.append({
			"sprite": sprite,
			"velocity": Vector2(
				randf_range(
					-_HORIZONTAL_SPREAD,
					_HORIZONTAL_SPREAD,
				),
				randf_range(
					_UPWARD_MIN,
					_UPWARD_MAX,
				),
			),
			"spin": randf_range(
				-_SPIN_SPEED_MAX,
				_SPIN_SPEED_MAX,
			),
			"age": 0.0,
		})


func _process(delta: float) -> void:
	var i := _particles.size() - 1
	while i >= 0:
		var p: Dictionary = _particles[i]
		var sprite: Sprite2D = p["sprite"]

		if not is_instance_valid(sprite):
			_particles.remove_at(i)
			i -= 1
			continue

		p["age"] += delta
		var age: float = p["age"]

		if age >= _PARTICLE_LIFETIME_SEC:
			sprite.queue_free()
			_particles.remove_at(i)
			i -= 1
			continue

		# Apply gravity.
		var vel: Vector2 = p["velocity"]
		vel.y += _GRAVITY * delta
		p["velocity"] = vel

		sprite.position += vel * delta
		sprite.rotation += p["spin"] * delta

		# Fade out near end of life.
		var fade_start := (
			_PARTICLE_LIFETIME_SEC
			- _FADE_DURATION_SEC
		)
		if age > fade_start:
			var fade_t := (
				(age - fade_start)
				/ _FADE_DURATION_SEC
			)
			sprite.modulate.a = 1.0 - fade_t

		i -= 1

	# Self-cleanup when all particles are gone.
	if _particles.is_empty():
		queue_free()


static func _create_pixel_texture() -> ImageTexture:
	var image := Image.create(
		int(_PARTICLE_SIZE.x),
		int(_PARTICLE_SIZE.y),
		false,
		Image.FORMAT_RGBA8,
	)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
