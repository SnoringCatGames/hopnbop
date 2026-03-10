class_name Splash
extends AnimatedSprite2D
## A one-shot splash effect that frees itself when
## its animation finishes.


@export var _default_splash_texture: Texture2D
@export var _blood_splash_texture: Texture2D


func _ready() -> void:
	animation_finished.connect(queue_free)
	_apply_cheat_texture()


## Sets the atlas to the blood or default texture
## based on the current cheat state.
func _apply_cheat_texture() -> void:
	if (CheatManager
			.is_bloodisthickerthanwater_cheat_active()):
		_swap_atlas(_blood_splash_texture)
	else:
		_swap_atlas(_default_splash_texture)


## Replaces the atlas texture on every frame of every
## animation in the current SpriteFrames resource.
func _swap_atlas(new_atlas: Texture2D) -> void:
	var frames := sprite_frames
	for anim_name in frames.get_animation_names():
		var count := frames.get_frame_count(
			anim_name)
		for i in count:
			var tex: AtlasTexture = (
				frames.get_frame_texture(
					anim_name, i)
			)
			if tex != null:
				tex.atlas = new_atlas
