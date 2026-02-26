class_name GoreManager
extends Node2D
## Manages gore/flower particle spawning, trail
## particles, and accumulation buffer.
##
## Client-side only. Not networked or rollback-aware.


# Margin in pixels around the tile map used rect for the
# accumulation buffer. Handles particles that fly slightly
# outside tile bounds.
const _BUFFER_MARGIN := 32
const MOREGORE_MULTIPLIER := 8

# Poop particle spawn count range.
const POOP_MIN_COUNT := 2
const POOP_MAX_COUNT := 5

# Poop particle fade delay range (seconds).
const POOP_FADE_DELAY_MIN_SEC := 10.0
const POOP_FADE_DELAY_MAX_SEC := 30.0

# Poop particle color (dark brown).
const POOP_COLOR := Color(0.30, 0.18, 0.08)

# Poop spawn scatter radius (pixels).
const POOP_SPAWN_SCATTER_RADIUS := 4.0

# Poop initial speed range (pixels/sec).
const POOP_SPEED_MIN := 13.0
const POOP_SPEED_MAX := 27.0

# Poop upward bias (pixels/sec).
const POOP_UPWARD_BIAS := -60.0

# Half-angle of the poop velocity spread cone
# (radians). PI/3 = 60°, giving a 120° cone.
const POOP_SPREAD_HALF_ANGLE := PI / 3.0

# Gore fade delay variance (seconds). Applied
# as +/- around the base gore_fade_delay_sec.
const GORE_FADE_DELAY_VARIANCE_SEC := 1.0

# Behind-player accumulation buffer (z_index = -1).
var _behind_image: Image
var _behind_texture: ImageTexture
var _behind_sprite: Sprite2D
var _is_behind_dirty := false

# In-front-of-player accumulation buffer (z_index = 0).
var _front_image: Image
var _front_texture: ImageTexture
var _front_sprite: Sprite2D
var _is_front_dirty := false

# Pixel offset from world origin to accumulation buffer
# origin.
var _buffer_origin := Vector2.ZERO

# Preloaded textures for the current mode
# (gore or flowers).
var _particle_textures: Array[Texture2D] = []
# Corresponding images for blitting into accumulation
# buffer.
var _particle_images: Array[Image] = []

# Preloaded trail textures for current mode.
# Index 0 = largest, index 5 = smallest.
var _trail_textures: Array[Texture2D] = []

# Active trail particles (updated each frame).
var _active_trails: Array[GoreTrailParticle] = []

# Tile size from the level's collision tile map.
var _tile_size := Vector2i(16, 16)


func _ready() -> void:
	_load_textures()
	_init_accumulation_buffer()


func _process(delta: float) -> void:
	if _is_behind_dirty:
		_is_behind_dirty = false
		_behind_texture.update(_behind_image)
	if _is_front_dirty:
		_is_front_dirty = false
		_front_texture.update(_front_image)

	# Shrink and remove trail particles.
	_update_trails(delta)


## Picks a random type index biased 2/3 toward small
## types (0..GORE_FAST_TYPE_END) and 1/3 toward large.
func _pick_type_index() -> int:
	var s := G.settings
	var type_count := s.gore_get_active_sprite_radii().size()
	if randi() % 3 != 0:
		return randi_range(0, s.GORE_FAST_TYPE_END)
	else:
		return randi_range(
			s.GORE_FAST_TYPE_END + 1,
			type_count - 1)


func spawn_particles(death_position: Vector2) -> void:
	var s := G.settings
	var center := death_position + s.gore_spawn_offset

	var particle_count := s.gore_particles_per_death
	if CheatManager.is_moregore_cheat_active():
		particle_count *= MOREGORE_MULTIPLIER
	for i in particle_count:
		var type_index := _pick_type_index()
		var is_behind := i % 2 == 0

		# Random position within scatter radius.
		var angle := randf_range(0.0, TAU)
		var dist := \
			randf() * s.gore_spawn_scatter_radius
		var spawn_pos := center + Vector2(
			cos(angle) * dist,
			sin(angle) * dist)

		# Initial velocity: outward direction with
		# speed based on type category.
		var speed_range := \
			s.gore_get_speed_range(type_index)
		var speed := randf_range(
			speed_range.x, speed_range.y)
		var vel_angle := randf_range(0.0, TAU)
		var vel := Vector2(
			cos(vel_angle) * speed,
			sin(vel_angle) * speed + s.gore_upward_bias)

		_spawn_particle(
			type_index, spawn_pos, vel, is_behind)

	# Also spawn kickable pieces.
	_spawn_kickables(death_position)


## Spawns poop particles at the given position.
## Uses the same GoreParticle scene as gore but
## with brown color, no rasterization, no trails,
## and a long random fade delay. backward_sign
## controls horizontal direction: -1 = left,
## +1 = right (opposite the player's motion).
func spawn_poop_particles(
	spawn_position: Vector2,
	backward_sign: float,
) -> void:
	# Base angle: PI (left) or 0 (right).
	var base_angle: float
	if backward_sign < 0.0:
		base_angle = PI
	else:
		base_angle = 0.0

	var count := randi_range(
		POOP_MIN_COUNT, POOP_MAX_COUNT)
	for i in count:
		var is_behind := i % 2 == 0

		# Random position within scatter radius.
		var angle := randf_range(0.0, TAU)
		var dist := \
			randf() * POOP_SPAWN_SCATTER_RADIUS
		var spawn_pos := spawn_position + Vector2(
			cos(angle) * dist,
			sin(angle) * dist)

		# Initial velocity: directed away from
		# movement within a spread cone.
		var speed := randf_range(
			POOP_SPEED_MIN, POOP_SPEED_MAX)
		var vel_angle := base_angle + randf_range(
			- POOP_SPREAD_HALF_ANGLE,
			POOP_SPREAD_HALF_ANGLE)
		var vel := Vector2(
			cos(vel_angle) * speed,
			sin(vel_angle) * speed
				+ POOP_UPWARD_BIAS)

		_spawn_poop_particle(
			spawn_pos, vel, is_behind)


func _spawn_poop_particle(
	pos: Vector2,
	vel: Vector2,
	is_behind: bool,
) -> void:
	var particle: GoreParticle = \
		G.settings.gore_particle_scene.instantiate()
	particle.will_rasterize = false
	particle.is_behind = is_behind
	particle.position = pos
	particle.velocity = vel
	particle.emit_trails = false
	particle.fade_delay_sec = randf_range(
		POOP_FADE_DELAY_MIN_SEC,
		POOP_FADE_DELAY_MAX_SEC)

	if not is_behind:
		particle.z_index = 2

	# Set texture to white_pixel modulated to
	# dark brown.
	var sprite: Sprite2D = \
		particle.get_node("Sprite2D")
	sprite.texture = preload(
		"res://assets/images/white_pixel.png")
	sprite.modulate = POOP_COLOR

	# Set collision radius.
	var shape: CollisionShape2D = \
		particle.get_node("CollisionShape2D")
	var circle := CircleShape2D.new()
	circle.radius = \
		G.settings.gore_collision_radius
	shape.shape = circle

	add_child(particle)


func _spawn_kickables(
	death_position: Vector2,
) -> void:
	var s := G.settings
	if _particle_textures.is_empty():
		return
	var center := death_position + s.gore_spawn_offset

	var kickable_count := s.gore_kickables_per_death
	if CheatManager.is_moregore_cheat_active():
		kickable_count *= MOREGORE_MULTIPLIER
	for i in kickable_count:
		var type_index := _pick_type_index()

		# Random position within scatter radius.
		var angle := randf_range(0.0, TAU)
		var dist := \
			randf() * s.gore_spawn_scatter_radius
		var spawn_pos := center + Vector2(
			cos(angle) * dist,
			sin(angle) * dist)

		# Initial velocity (slower than particles).
		var speed := randf_range(
			s.gore_kickable_speed_min,
			s.gore_kickable_speed_max)
		var vel_angle := randf_range(0.0, TAU)
		var vel := Vector2(
			cos(vel_angle) * speed,
			sin(vel_angle) * speed
				+s.gore_upward_bias)

		_spawn_kickable(type_index, spawn_pos, vel)


func _spawn_kickable(
	type_index: int,
	pos: Vector2,
	vel: Vector2,
) -> void:
	var s := G.settings
	var kickable: GoreKickable = \
		s.gore_kickable_scene.instantiate()
	kickable.type_index = type_index
	kickable.position = pos
	kickable.velocity = vel
	kickable.z_index = 2

	# Set texture from shared pool.
	var sprite: Sprite2D = \
		kickable.get_node("Sprite2D")
	sprite.texture = _particle_textures[type_index]

	# Set collision radius based on type size.
	var is_small := s.gore_is_fast_type(type_index)
	var shape: CollisionShape2D = kickable.get_node(
		"CollisionShape2D")
	var circle := CircleShape2D.new()
	if is_small:
		circle.radius = \
			s.gore_kickable_small_collision_radius
	else:
		circle.radius = \
			s.gore_kickable_collision_radius
	shape.shape = circle

	# Set kick area detection radius.
	var kick_shape: CollisionShape2D = \
		kickable.get_node(
			"KickArea/CollisionShape2D")
	var kick_circle := CircleShape2D.new()
	kick_circle.radius = \
		s.gore_kickable_kick_area_radius
	kick_shape.shape = kick_circle

	add_child(kickable)


func _spawn_particle(
	type_index: int,
	pos: Vector2,
	vel: Vector2,
	is_behind: bool,
) -> void:
	var particle: GoreParticle = \
		G.settings.gore_particle_scene.instantiate()
	particle.type_index = type_index
	particle.is_behind = is_behind
	particle.position = pos
	particle.velocity = vel
	particle.will_rasterize = \
		randf() < G.settings.gore_rasterize_ratio

	# Randomize fade delay for non-rasterized
	# gore particles.
	if not particle.will_rasterize:
		particle.fade_delay_sec = \
			G.settings.gore_fade_delay_sec \
			+ randf_range(
				- GORE_FADE_DELAY_VARIANCE_SEC,
				GORE_FADE_DELAY_VARIANCE_SEC)

	if not is_behind:
		particle.z_index = 2

	# Set texture.
	var sprite: Sprite2D = \
		particle.get_node("Sprite2D")
	sprite.texture = _particle_textures[type_index]

	# Set collision radius per type.
	var shape: CollisionShape2D = particle.get_node(
		"CollisionShape2D")
	var circle := CircleShape2D.new()
	circle.radius = G.settings.gore_collision_radius
	shape.shape = circle

	if particle.will_rasterize:
		particle.came_to_rest.connect(
			_on_particle_rested)
	add_child(particle)


func _on_particle_rested(
	particle: GoreParticle,
) -> void:
	_rasterize_particle(particle)


func _rasterize_particle(
	particle: GoreParticle,
) -> void:
	var type_index := particle.type_index

	Netcode.check(type_index >= 0)
	Netcode.check(type_index < _particle_images.size())

	var src_image := _particle_images[type_index]
	var src_rect := Rect2i(
		Vector2i.ZERO,
		src_image.get_size())

	# Convert world position to buffer coordinates.
	# X: centered on particle. Y: bottom-aligned to the
	# nearest visual tile surface below the particle, to
	# compensate for the half-tile offset between physics
	# collision surfaces and visual tile boundaries.
	var world_pos := particle.global_position
	var sprite_radius: float = \
		G.settings.gore_get_active_sprite_radii()[type_index]
	var particle_bottom := world_pos.y + sprite_radius
	var tile_h := float(_tile_size.y)
	var visual_surface_y := ceilf(
		particle_bottom / tile_h) * tile_h
	@warning_ignore("integer_division")
	var buffer_pos := Vector2i(
		floori(world_pos.x - _buffer_origin.x) -
			src_image.get_width() / 2,
		floori(
			visual_surface_y - _buffer_origin.y
		) - src_image.get_height() +
			ceili(
				sprite_radius -
				G.settings.gore_collision_radius))

	# Select the correct accumulation buffer layer.
	var accum_image: Image
	if particle.is_behind:
		accum_image = _behind_image
	else:
		accum_image = _front_image

	# Clamp to buffer bounds.
	var buf_size := accum_image.get_size()
	if (
		buffer_pos.x + src_image.get_width() < 0 or
		buffer_pos.y + src_image.get_height() < 0 or
		buffer_pos.x >= buf_size.x or
		buffer_pos.y >= buf_size.y
	):
		return

	accum_image.blend_rect(
		src_image, src_rect, buffer_pos)
	if particle.is_behind:
		_is_behind_dirty = true
	else:
		_is_front_dirty = true


## Spawns a single trail particle at a position.
## type_index selects the starting trail size via
## ratio mapping from chunk type count to trail
## texture count. chunk is used for vertical
## clamping. chunk_vel sets initial trail velocity.
func spawn_trail_particle(
	pos: Vector2,
	type_index: int,
	is_behind: bool,
	chunk: CharacterBody2D,
	chunk_vel: Vector2,
) -> void:
	var trail_count := _trail_textures.size()
	if trail_count == 0:
		return
	var chunk_count := _particle_textures.size()
	if chunk_count <= 1:
		return
	# Map chunk type to trail start index. Type 0
	# (smallest) starts near the end (smallest
	# trail); highest type starts at 0 (largest).
	var ratio := float(type_index) / (chunk_count - 1)
	var max_trail := trail_count - 1
	var size_index := int(
		(1.0 - ratio) * max_trail)

	var trail := GoreTrailParticle.new()
	trail.texture = _trail_textures[size_index]
	trail.size_index = size_index
	trail.is_behind = is_behind
	trail.position = pos
	trail.vel = chunk_vel * \
		GoreTrailParticle.SPEED_MULTIPLIER
	trail.source_chunk = chunk
	trail.last_chunk_y = pos.y
	trail.texture_filter = \
		CanvasItem.TEXTURE_FILTER_NEAREST
	if is_behind:
		trail.z_index = -1
	else:
		trail.z_index = 1

	add_child(trail)
	_active_trails.append(trail)


func _update_trails(delta: float) -> void:
	var trail_count := _trail_textures.size()
	if trail_count == 0:
		return
	var shrink_interval: float = \
		G.settings.gore_trail_duration_sec / trail_count
	var max_size_index: int = trail_count - 1
	var gravity: float = \
		G.settings.default_gravity_acceleration * \
		G.settings.gore_gravity_multiplier * \
		G.settings.gore_trail_gravity_multiplier
	var i := _active_trails.size() - 1

	while i >= 0:
		var trail := _active_trails[i]
		if not is_instance_valid(trail):
			_active_trails.remove_at(i)
			i -= 1
			continue

		# Apply gravity and move trail particle.
		trail.vel.y += gravity * delta
		trail.position += trail.vel * delta

		# Clamp trail to not sink below the chunk
		# when the chunk isn't moving upward or is
		# no longer alive.
		var chunk := trail.source_chunk
		if is_instance_valid(chunk):
			trail.last_chunk_y = chunk.position.y
			if (
				chunk.velocity.y >= 0.0 and
				trail.position.y > chunk.position.y
			):
				trail.position.y = chunk.position.y
		elif trail.position.y > trail.last_chunk_y:
			trail.position.y = trail.last_chunk_y

		trail.elapsed += delta
		if trail.elapsed >= shrink_interval:
			trail.elapsed -= shrink_interval
			trail.size_index += 1

			if trail.size_index > max_size_index:
				trail.queue_free()
				_active_trails.remove_at(i)
			else:
				trail.texture = \
					_trail_textures[
						trail.size_index]
		i -= 1


func _load_textures() -> void:
	_particle_textures.clear()
	_particle_images.clear()

	var paths: Array[String]
	if G.settings.is_gore_enabled:
		paths = G.settings.gore_texture_paths
	else:
		paths = G.settings.gore_flower_texture_paths

	for path in paths:
		var tex: Texture2D = load(path)
		_particle_textures.append(tex)
		_particle_images.append(tex.get_image())

	# Load trail textures.
	_trail_textures.clear()
	var trail_paths: Array[String]
	if G.settings.is_gore_enabled:
		trail_paths = \
			G.settings.gore_trail_texture_paths
	else:
		trail_paths = \
			G.settings \
				.gore_flower_trail_texture_paths

	for path in trail_paths:
		var tex: Texture2D = load(path)
		_trail_textures.append(tex)


func _init_accumulation_buffer() -> void:
	var level: Level = get_parent()
	if (
		not is_instance_valid(level) or
		not is_instance_valid(level.collision_tiles)
	):
		push_warning(
			"GoreManager: No collision_tiles " +
			"found on parent level.")
		return

	var tile_map: TileMapLayer = \
		level.collision_tiles
	var used_rect: Rect2i = \
		tile_map.get_used_rect()
	var tile_size: Vector2i = \
		tile_map.tile_set.tile_size
	_tile_size = tile_size

	# Convert tile rect to pixel rect with margin.
	var pixel_rect := Rect2i(
		used_rect.position * tile_size -
			Vector2i(
				_BUFFER_MARGIN, _BUFFER_MARGIN),
		used_rect.size * tile_size +
			Vector2i(
				_BUFFER_MARGIN * 2,
				_BUFFER_MARGIN * 2))

	_buffer_origin = Vector2(pixel_rect.position)

	# Create behind-player accumulation buffer
	# (z=-1).
	_behind_image = Image.create(
		pixel_rect.size.x,
		pixel_rect.size.y,
		false,
		Image.FORMAT_RGBA8)
	_behind_texture = \
		ImageTexture.create_from_image(
			_behind_image)
	_behind_sprite = Sprite2D.new()
	_behind_sprite.texture = _behind_texture
	_behind_sprite.centered = false
	_behind_sprite.position = _buffer_origin
	_behind_sprite.texture_filter = \
		CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_behind_sprite)

	# Create in-front-of-player accumulation buffer.
	_front_image = Image.create(
		pixel_rect.size.x,
		pixel_rect.size.y,
		false,
		Image.FORMAT_RGBA8)
	_front_texture = \
		ImageTexture.create_from_image(
			_front_image)
	_front_sprite = Sprite2D.new()
	_front_sprite.texture = _front_texture
	_front_sprite.centered = false
	_front_sprite.position = _buffer_origin
	_front_sprite.texture_filter = \
		CanvasItem.TEXTURE_FILTER_NEAREST
	_front_sprite.z_index = 2
	add_child(_front_sprite)
