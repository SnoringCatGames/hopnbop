class_name GoreManager
extends Node2D
## Manages gore/flower particle spawning and accumulation buffer.
##
## Client-side only. Not networked or rollback-aware.


# Margin in pixels around the tile map used rect for the
# accumulation buffer. Handles particles that fly slightly
# outside tile bounds.
const _BUFFER_MARGIN := 32

var _accumulation_image: Image
var _accumulation_texture: ImageTexture
var _accumulation_sprite: Sprite2D

# Pixel offset from world origin to accumulation buffer origin.
var _buffer_origin := Vector2.ZERO

# Preloaded textures for the current mode (gore or flowers).
var _particle_textures: Array[Texture2D] = []
# Corresponding images for blitting into accumulation buffer.
var _particle_images: Array[Image] = []

var _is_dirty := false


func _ready() -> void:
	_load_textures()
	_init_accumulation_buffer()
	# FIXME: REMOVE - Gore diagnostic logging.
	print(
		("GORE: GoreManager ready, textures=%d, "
		+ "buffer=%s") % [
			_particle_textures.size(),
			(
				"valid"
				if _accumulation_image
				else "null"
			),
		]
	)


func _process(_delta: float) -> void:
	if _is_dirty:
		_is_dirty = false
		_accumulation_texture.update(_accumulation_image)


func spawn_particles(death_position: Vector2) -> void:
	# FIXME: REMOVE - Gore diagnostic logging.
	print(
		("GORE: GoreManager.spawn_particles "
		+ "at %s, children=%d") % [
			death_position,
			get_child_count(),
		]
	)
	var s := G.settings
	var center := death_position + s.gore_spawn_offset
	var type_count := s.gore_collision_radii.size()

	for i in s.gore_particles_per_death:
		var type_index := randi_range(0, type_count - 1)

		# Random position within scatter radius.
		var angle := randf_range(0.0, TAU)
		var dist := randf() * s.gore_spawn_scatter_radius
		var spawn_pos := center + Vector2(
			cos(angle) * dist, sin(angle) * dist)

		# Initial velocity: outward direction with speed based
		# on type category.
		var speed_range := s.gore_get_speed_range(type_index)
		var speed := randf_range(speed_range.x, speed_range.y)
		var vel_angle := randf_range(0.0, TAU)
		var vel := Vector2(
			cos(vel_angle) * speed,
			sin(vel_angle) * speed + s.gore_upward_bias)

		_spawn_particle(type_index, spawn_pos, vel)


func _spawn_particle(
	type_index: int,
	pos: Vector2,
	vel: Vector2,
) -> void:
	var particle: GoreParticle = \
		G.settings.gore_particle_scene.instantiate()
	particle.type_index = type_index
	particle.position = pos
	particle.velocity = vel

	# Set texture.
	var sprite: Sprite2D = particle.get_node("Sprite2D")
	sprite.texture = _particle_textures[type_index]

	# Set collision radius per type.
	var shape: CollisionShape2D = particle.get_node(
		"CollisionShape2D")
	var circle := CircleShape2D.new()
	circle.radius = G.settings.gore_collision_radii[type_index]
	shape.shape = circle

	particle.came_to_rest.connect(_on_particle_rested)
	add_child(particle)


func _on_particle_rested(particle: GoreParticle) -> void:
	_rasterize_particle(particle)


func _rasterize_particle(particle: GoreParticle) -> void:
	var type_index := particle.type_index

	Netcode.check(type_index >= 0)
	Netcode.check(type_index < _particle_images.size())

	var src_image := _particle_images[type_index]
	var src_rect := Rect2i(
		Vector2i.ZERO,
		src_image.get_size())

	# Convert world position to buffer coordinates, centered on
	# the particle sprite.
	var world_pos := particle.global_position
	@warning_ignore("integer_division")
	var buffer_pos := Vector2i(
		int(world_pos.x - _buffer_origin.x) -
			src_image.get_width() / 2,
		int(world_pos.y - _buffer_origin.y) -
			src_image.get_height() / 2)

	# Clamp to buffer bounds.
	var buf_size := _accumulation_image.get_size()
	if (buffer_pos.x + src_image.get_width() < 0 or
			buffer_pos.y + src_image.get_height() < 0 or
			buffer_pos.x >= buf_size.x or
			buffer_pos.y >= buf_size.y):
		return

	_accumulation_image.blend_rect(
		src_image, src_rect, buffer_pos)
	_is_dirty = true


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


func _init_accumulation_buffer() -> void:
	var level: Level = get_parent()
	if not is_instance_valid(level) or \
			not is_instance_valid(level.collision_tiles):
		push_warning(
			"GoreManager: No collision_tiles found on " +
			"parent level.")
		return

	var tile_map: TileMapLayer = level.collision_tiles
	var used_rect: Rect2i = tile_map.get_used_rect()
	var tile_size: Vector2i = tile_map.tile_set.tile_size

	# Convert tile rect to pixel rect with margin.
	var pixel_rect := Rect2i(
		used_rect.position * tile_size -
			Vector2i(_BUFFER_MARGIN, _BUFFER_MARGIN),
		used_rect.size * tile_size +
			Vector2i(_BUFFER_MARGIN * 2, _BUFFER_MARGIN * 2))

	_buffer_origin = Vector2(pixel_rect.position)

	_accumulation_image = Image.create(
		pixel_rect.size.x,
		pixel_rect.size.y,
		false,
		Image.FORMAT_RGBA8)

	_accumulation_texture = ImageTexture.create_from_image(
		_accumulation_image)

	_accumulation_sprite = Sprite2D.new()
	_accumulation_sprite.texture = _accumulation_texture
	_accumulation_sprite.centered = false
	_accumulation_sprite.position = _buffer_origin
	_accumulation_sprite.texture_filter = \
		CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_accumulation_sprite)
