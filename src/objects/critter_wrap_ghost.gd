class_name CritterWrapGhost
extends Node2D
## Visual duplicate of a critter rendered at a wrap
## offset. Shows the critter partially on the
## opposite edge during wrap-around transitions.
## Uses top_level so the ghost's transform is
## independent of the parent critter's rotation.


enum OffsetAxis {
	HORIZONTAL,
	VERTICAL,
	DIAGONAL,
}

var _source: Node2D
var _source_sprite: AnimatedSprite2D
var _ghost_sprite: AnimatedSprite2D
var _offset_axis: OffsetAxis


## Initializes the ghost for the given source
## critter, sprite, and offset axis. Call before
## adding to the tree.
func setup(
	source: Node2D,
	source_sprite: AnimatedSprite2D,
	p_offset_axis: OffsetAxis,
) -> void:
	_source = source
	_source_sprite = source_sprite
	_offset_axis = p_offset_axis
	top_level = true

	_ghost_sprite = AnimatedSprite2D.new()
	_ghost_sprite.sprite_frames = (
		source_sprite.sprite_frames)
	_ghost_sprite.texture_filter = (
		source_sprite.texture_filter)
	_ghost_sprite.offset = source_sprite.offset
	# Copy initial color (e.g. butterfly tint).
	_ghost_sprite.modulate = (
		source_sprite.modulate)
	add_child(_ghost_sprite)


func _process(_delta: float) -> void:
	if not is_instance_valid(_source):
		queue_free()
		return
	if not is_instance_valid(_source_sprite):
		visible = false
		return

	_update_offset()
	_sync_visual()


func _update_offset() -> void:
	var level := G.level
	if not level is NetworkedLevel:
		return
	var bounds: Rect2 = level.wrap_bounds
	if bounds.size == Vector2.ZERO:
		return

	var center := bounds.get_center()
	var src_pos := _source.global_position
	var h_offset := (
		-bounds.size.x
		if src_pos.x >= center.x
		else bounds.size.x
	)
	var v_offset := (
		-bounds.size.y
		if src_pos.y >= center.y
		else bounds.size.y
	)

	match _offset_axis:
		OffsetAxis.HORIZONTAL:
			global_position = (
				src_pos
				+ Vector2(h_offset, 0.0))
		OffsetAxis.VERTICAL:
			global_position = (
				src_pos
				+ Vector2(0.0, v_offset))
		OffsetAxis.DIAGONAL:
			global_position = (
				src_pos
				+ Vector2(h_offset, v_offset))


func _sync_visual() -> void:
	# Sync root rotation (e.g. snail tile
	# crawl orientation).
	global_rotation = _source.global_rotation

	# Sync sprite animation state.
	_ghost_sprite.animation = (
		_source_sprite.animation)
	_ghost_sprite.frame = (
		_source_sprite.frame)
	_ghost_sprite.flip_h = (
		_source_sprite.flip_h)
	_ghost_sprite.flip_v = (
		_source_sprite.flip_v)

	# Sync sprite local transform (e.g.
	# butterfly flutter offset and wall-rest
	# rotation).
	_ghost_sprite.position = (
		_source_sprite.position)
	_ghost_sprite.rotation = (
		_source_sprite.rotation)

	# Sync per-sprite tint (e.g. snail death
	# fade via self_modulate.a).
	_ghost_sprite.self_modulate = (
		_source_sprite.self_modulate)

	# Inherit visibility from source. The
	# parent's modulate is already inherited
	# through the node tree.
	visible = _source.visible


## Creates three wrap ghosts (horizontal,
## vertical, diagonal) for a critter. Returns
## an empty array if wrapping is disabled.
static func create_ghosts(
	source: Node2D,
	source_sprite: AnimatedSprite2D,
) -> Array:
	var level := G.level
	if not level is NetworkedLevel:
		return []
	if level.wrap_bounds.size == Vector2.ZERO:
		return []

	var ghosts: Array = []
	for axis in [
		OffsetAxis.HORIZONTAL,
		OffsetAxis.VERTICAL,
		OffsetAxis.DIAGONAL,
	]:
		var ghost := CritterWrapGhost.new()
		ghost.setup(
			source, source_sprite, axis)
		source.add_child(ghost)
		ghosts.append(ghost)
	return ghosts
