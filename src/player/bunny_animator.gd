class_name BunnyAnimator
extends CharacterAnimator
## Game-specific animator that supports body type and
## costume appearance swapping, plus a toggleable crown
## overlay. All layers share the same sprite sheet
## template (same frame layout, size, and count).
##
## Manages up to 3 AnimatedSprite2D layers:
## 1. Base (body type texture) - the scene's
##    animated_sprite
## 2. Costume overlay (optional, from costume_index)
## 3. Crown overlay (optional, toggled independently)


var _costume_overlay: AnimatedSprite2D = null
var _crown_overlay: AnimatedSprite2D = null
var _crown_costume: CostumeConfig = null


## Applies body type and costume appearance. Swaps the
## base sprite's atlas textures and creates/removes the
## costume overlay as needed.
func apply_appearance(
	body_type_config: BodyTypeConfig,
	costume_config: CostumeConfig,
) -> void:
	# Apply body type texture to the base sprite.
	if (is_instance_valid(body_type_config) and
			is_instance_valid(body_type_config.sprite_sheet)):
		var new_frames := _create_swapped_sprite_frames(
			animated_sprite.sprite_frames,
			body_type_config.sprite_sheet,
		)
		animated_sprite.sprite_frames = new_frames

	# Remove previous costume overlay.
	_remove_overlay(_costume_overlay)
	_costume_overlay = null

	# Create costume overlay if the costume has a
	# texture.
	if (is_instance_valid(costume_config) and
			is_instance_valid(costume_config.sprite_sheet)):
		_costume_overlay = _create_overlay(
			costume_config.sprite_sheet)


## Stores the crown costume config for use when
## set_crown_visible(true) is called.
func set_crown_costume(
	costume_config: CostumeConfig,
) -> void:
	_crown_costume = costume_config


## Shows or hides the crown overlay.
func set_crown_visible(is_visible: bool) -> void:
	if is_visible:
		if not is_instance_valid(_crown_overlay):
			if (is_instance_valid(_crown_costume) and
					is_instance_valid(
						_crown_costume.sprite_sheet)):
				_crown_overlay = _create_overlay(
					_crown_costume.sprite_sheet)
		if is_instance_valid(_crown_overlay):
			_crown_overlay.visible = true
	else:
		if is_instance_valid(_crown_overlay):
			_crown_overlay.visible = false


## Returns the costume overlay sprite, or null.
func get_costume_overlay() -> AnimatedSprite2D:
	return _costume_overlay


## Returns the crown overlay sprite, or null.
func get_crown_overlay() -> AnimatedSprite2D:
	return _crown_overlay


func face_left() -> void:
	super.face_left()
	if is_instance_valid(_costume_overlay):
		_costume_overlay.flip_h = faces_right_by_default
	if is_instance_valid(_crown_overlay):
		_crown_overlay.flip_h = faces_right_by_default


func face_right() -> void:
	super.face_right()
	if is_instance_valid(_costume_overlay):
		_costume_overlay.flip_h = \
			not faces_right_by_default
	if is_instance_valid(_crown_overlay):
		_crown_overlay.flip_h = \
			not faces_right_by_default


func play(animation_name: StringName) -> void:
	super.play(animation_name)
	if is_instance_valid(_costume_overlay):
		_costume_overlay.play(animation_name)
	if is_instance_valid(_crown_overlay):
		_crown_overlay.play(animation_name)


## Creates a new AnimatedSprite2D overlay as a child of
## this animator, duplicated from the base sprite with
## atlas textures swapped to the given texture.
func _create_overlay(
	texture: Texture2D,
) -> AnimatedSprite2D:
	var overlay := AnimatedSprite2D.new()

	# Copy properties from the base sprite.
	overlay.position = animated_sprite.position
	overlay.flip_h = animated_sprite.flip_h

	# Duplicate and swap sprite frames.
	var new_frames := _create_swapped_sprite_frames(
		animated_sprite.sprite_frames, texture)
	overlay.sprite_frames = new_frames

	# Copy the material (will be duplicated later when
	# outline color is applied).
	if is_instance_valid(animated_sprite.material):
		overlay.material = \
			animated_sprite.material.duplicate()

	# Sync animation state.
	overlay.animation = animated_sprite.animation
	overlay.frame = animated_sprite.frame

	add_child(overlay)
	return overlay


## Removes an overlay sprite from the tree.
func _remove_overlay(
	overlay: AnimatedSprite2D,
) -> void:
	if is_instance_valid(overlay):
		overlay.queue_free()


## Duplicates a SpriteFrames resource and swaps all
## AtlasTexture atlases to the given texture.
static func _create_swapped_sprite_frames(
	source_frames: SpriteFrames,
	new_texture: Texture2D,
) -> SpriteFrames:
	var frames: SpriteFrames = source_frames.duplicate()

	for anim_name in frames.get_animation_names():
		var frame_count := \
			frames.get_frame_count(anim_name)
		for i in range(frame_count):
			var tex := frames.get_frame_texture(
				anim_name, i)
			if tex is AtlasTexture:
				var atlas_tex: AtlasTexture = \
					tex.duplicate()
				atlas_tex.atlas = new_texture
				frames.set_frame(
					anim_name,
					i,
					atlas_tex,
					frames.get_frame_duration(
						anim_name, i),
				)

	return frames
