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
##
## Includes idle-eat behavior: while Rest loops, a
## random iteration is chosen to interrupt with the
## Eat animation. After Eat completes, Rest resumes
## without further eat chances until the next fresh
## external Rest trigger (i.e., the player moves and
## stops again).

## Upper bound (inclusive) for the random Rest loop
## iteration that triggers the Eat interrupt.
const EAT_CHANCE_RANGE: int = 5

## Fraction of the Rest animation's frame count at
## which the Eat interrupt check occurs.
const REST_INTERRUPT_RATIO: float = 0.4

## Emitted when the Rest/Eat cycle ends after an
## eat occurred (i.e., the bunny transitions to a
## non-Rest animation after having eaten).
signal eat_cycle_ended

@export var outline_group: CanvasGroup = null

var _costume_overlay: AnimatedSprite2D = null
var _crown_overlay: AnimatedSprite2D = null
var _crown_costume: CostumeConfig = null

## Whether the Rest/Eat cycle is active. True from
## the first external Rest trigger until a non-Rest
## animation plays.
var _rest_eat_active: bool = false

## Whether the Eat animation is currently playing.
var _is_eating: bool = false

## The randomly chosen Rest loop iteration on which
## to trigger Eat. Set to -1 after Eat completes to
## prevent further triggers.
var _eat_target_iteration: int = -1

## Current Rest loop iteration counter (0-based).
var _rest_loop_count: int = 0

## Whether an Eat animation played during the
## current Rest/Eat cycle. Reset on cycle start.
var _did_eat_this_cycle: bool = false


func _ready() -> void:
	animated_sprite.animation_looped.connect(
		_on_animation_looped)
	animated_sprite.frame_changed.connect(
		_on_frame_changed)


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
		var current_anim := animated_sprite.animation
		var new_frames := _create_swapped_sprite_frames(
			animated_sprite.sprite_frames,
			body_type_config.sprite_sheet,
		)
		animated_sprite.sprite_frames = new_frames
		# Re-play current animation to maintain playback
		# after sprite_frames swap.
		animated_sprite.play(current_anim)

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
func set_crown_visible(visible_flag: bool) -> void:
	if visible_flag:
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


## Copies animation, frame, and flip state from
## the source animator. Bypasses eat/rest cycle
## logic so the ghost stays in lockstep.
func sync_visual_from(
	source: BunnyAnimator,
) -> void:
	# Base sprite.
	animated_sprite.animation = (
		source.animated_sprite.animation)
	animated_sprite.frame = (
		source.animated_sprite.frame)
	animated_sprite.flip_h = (
		source.animated_sprite.flip_h)
	# Costume overlay.
	var src_costume := source.get_costume_overlay()
	if (
		is_instance_valid(_costume_overlay)
		and is_instance_valid(src_costume)
	):
		_costume_overlay.animation = (
			src_costume.animation)
		_costume_overlay.frame = (
			src_costume.frame)
		_costume_overlay.flip_h = (
			src_costume.flip_h)
	# Crown overlay.
	var src_crown := source.get_crown_overlay()
	if (
		is_instance_valid(_crown_overlay)
		and is_instance_valid(src_crown)
	):
		_crown_overlay.animation = (
			src_crown.animation)
		_crown_overlay.frame = (
			src_crown.frame)
		_crown_overlay.flip_h = (
			src_crown.flip_h)


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
		_costume_overlay.flip_h = (
			not faces_right_by_default)
	if is_instance_valid(_crown_overlay):
		_crown_overlay.flip_h = (
			not faces_right_by_default)


func play(animation_name: StringName) -> void:
	# Skip eat state changes during rollback
	# resimulation. Animation is cosmetic-only and
	# the correct state is restored on the final
	# non-resim frame.
	if Netcode.frame_driver.is_resimulating:
		return

	if animation_name == &"Rest":
		if _rest_eat_active:
			# Don't interrupt Eat, don't re-roll if
			# Rest or Eat is active.
			return
		# Fresh external Rest trigger. Start cycle.
		_rest_eat_active = true
		_is_eating = false
		_did_eat_this_cycle = false
		_rest_loop_count = 0
		_eat_target_iteration = randi_range(
			0, EAT_CHANCE_RANGE)
		_play_on_all_layers(animation_name)
	else:
		# Non-Rest animation clears eat state.
		if _rest_eat_active and _did_eat_this_cycle:
			eat_cycle_ended.emit()
		_rest_eat_active = false
		_is_eating = false
		_did_eat_this_cycle = false
		_play_on_all_layers(animation_name)


func _play_on_all_layers(
	animation_name: StringName,
) -> void:
	super.play(animation_name)
	if is_instance_valid(_costume_overlay):
		_costume_overlay.play(animation_name)
	if is_instance_valid(_crown_overlay):
		_crown_overlay.play(animation_name)


func stop() -> void:
	animated_sprite.stop()
	if is_instance_valid(_costume_overlay):
		_costume_overlay.stop()
	if is_instance_valid(_crown_overlay):
		_crown_overlay.stop()


func _on_frame_changed() -> void:
	if not _rest_eat_active or _is_eating:
		return
	if animated_sprite.animation != &"Rest":
		return
	var halfway_frame := int(
		animated_sprite.sprite_frames
			.get_frame_count(&"Rest")
		* REST_INTERRUPT_RATIO)
	if animated_sprite.frame != halfway_frame:
		return
	if _rest_loop_count == _eat_target_iteration:
		_trigger_eat()


func _on_animation_looped() -> void:
	if not _rest_eat_active:
		return
	if _is_eating:
		# Eat completed. Go back to Rest, no new
		# cycle. Set target to -1 so no future loop
		# iteration can trigger Eat again.
		_is_eating = false
		_eat_target_iteration = -1
		_play_on_all_layers(&"Rest")
	else:
		# Rest looped. Increment iteration counter.
		_rest_loop_count += 1


## Clears all Rest/Eat cycle state without
## emitting eat_cycle_ended. Call on death and
## respawn to prevent stale state.
func reset_eat_cycle() -> void:
	_rest_eat_active = false
	_is_eating = false
	_did_eat_this_cycle = false
	_eat_target_iteration = -1
	_rest_loop_count = 0


func _trigger_eat() -> void:
	_is_eating = true
	_did_eat_this_cycle = true
	_play_on_all_layers(&"Eat")


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

	# Sync animation state (play, then sync frame).
	overlay.play(animated_sprite.animation)
	overlay.frame = animated_sprite.frame

	# Add to outline_group so the CanvasGroup shader
	# sees the combined silhouette.
	if is_instance_valid(outline_group):
		outline_group.add_child(overlay)
	else:
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
		var frame_count := (
			frames.get_frame_count(anim_name))
		for i in range(frame_count):
			var tex := frames.get_frame_texture(
				anim_name, i)
			if tex is AtlasTexture:
				var atlas_tex: AtlasTexture = (
					tex.duplicate())
				atlas_tex.atlas = new_texture
				frames.set_frame(
					anim_name,
					i,
					atlas_tex,
					frames.get_frame_duration(
						anim_name, i),
				)

	return frames
