class_name WrapGhost
extends Node2D
## Visual duplicate of a player rendered at a wrap
## offset. Shows the player partially on the
## opposite edge during wrap-around transitions.


const _ANIMATOR_SCENE := preload(
	"res://src/player/bunny_animator.tscn")

enum OffsetAxis {
	HORIZONTAL,
	VERTICAL,
	DIAGONAL,
}

var offset_axis: OffsetAxis
var _source: Bunny
var _animator: BunnyAnimator


## Initializes the ghost for the given source
## player and offset axis. Call after adding to
## tree.
func setup(
	source: Bunny,
	p_offset_axis: OffsetAxis,
) -> void:
	_source = source
	offset_axis = p_offset_axis
	# Disable physics interpolation. The ghost
	# sets its position every _process() frame,
	# so Godot must not lerp between physics
	# ticks. Otherwise the ghost visually slides
	# across the screen when the offset flips.
	physics_interpolation_mode = (
		PHYSICS_INTERPOLATION_MODE_OFF)

	_animator = _ANIMATOR_SCENE.instantiate()
	# Match the animator's local offset from the
	# player root node.
	_animator.position = source.animator.position
	add_child(_animator)

	_apply_appearance()
	_apply_outline()


## Applies the source player's appearance (body
## type, costume, crown) to the ghost's animator.
func _apply_appearance() -> void:
	var ms: GamePlayerState = _source.match_state
	if not is_instance_valid(ms):
		return

	var body_type_config: BodyTypeConfig = null
	if (
		ms.body_type_index >= 0
		and ms.body_type_index
			< G.settings.body_types.size()
	):
		body_type_config = G.settings.body_types[
			ms.body_type_index]

	var costume_config: CostumeConfig = null
	if (
		ms.costume_index >= 0
		and ms.costume_index
			< G.settings.costumes.size()
	):
		costume_config = G.settings.costumes[
			ms.costume_index]

	_animator.apply_appearance(
		body_type_config, costume_config)

	# Crown.
	if is_instance_valid(G.settings.crown_costume):
		_animator.set_crown_costume(
			G.settings.crown_costume)
	var src_anim := _source.animator as BunnyAnimator
	if is_instance_valid(src_anim):
		var src_crown := src_anim.get_crown_overlay()
		if (
			is_instance_valid(src_crown)
			and src_crown.visible
		):
			_animator.set_crown_visible(true)


## Copies the outline shader parameters from the
## source player's CanvasGroup material.
func _apply_outline() -> void:
	var src_anim := _source.animator as BunnyAnimator
	if not is_instance_valid(src_anim):
		return
	var src_group := src_anim.outline_group
	if not is_instance_valid(src_group):
		return
	var src_mat := (
		src_group.material as ShaderMaterial)
	if not is_instance_valid(src_mat):
		return

	var dst_group := _animator.outline_group
	if not is_instance_valid(dst_group):
		return
	dst_group.material = src_mat.duplicate()


func _process(_delta: float) -> void:
	if not is_instance_valid(_source):
		queue_free()
		return
	if not is_instance_valid(_source.animator):
		return

	_update_offset()
	_sync_visual()


func _update_offset() -> void:
	if not G.level is NetworkedLevel:
		return
	var bounds: Rect2 = G.level.wrap_bounds
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

	match offset_axis:
		OffsetAxis.HORIZONTAL:
			position = Vector2(h_offset, 0.0)
		OffsetAxis.VERTICAL:
			position = Vector2(0.0, v_offset)
		OffsetAxis.DIAGONAL:
			position = Vector2(
				h_offset, v_offset)


func _sync_visual() -> void:
	var src_anim := (
		_source.animator as BunnyAnimator)
	if not is_instance_valid(src_anim):
		return
	_animator.sync_visual_from(src_anim)
	_animator.visible = src_anim.visible


## Re-applies appearance from the source. Called
## when the source player's appearance changes.
func refresh_appearance() -> void:
	if is_instance_valid(_animator):
		_apply_appearance()
		_apply_outline()
