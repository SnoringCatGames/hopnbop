class_name Splash
extends AnimatedSprite2D
## A one-shot splash effect that frees itself when
## its animation finishes.


const _DEFAULT_SPLASH_TEXTURE := preload(
	"res://assets/images/splash.png"
)
const _BLOOD_SPLASH_TEXTURE := preload(
	"res://assets/images/"
	+ "bloodisthickerthanwater_splash.png"
)


func _ready() -> void:
	animation_finished.connect(queue_free)
	_apply_cheat_texture()


## Sets the atlas to the blood or default texture
## based on the current cheat state.
func _apply_cheat_texture() -> void:
	if (CheatManager
			.is_bloodisthickerthanwater_cheat_active()):
		_swap_atlas(_BLOOD_SPLASH_TEXTURE)
	else:
		_swap_atlas(_DEFAULT_SPLASH_TEXTURE)


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
