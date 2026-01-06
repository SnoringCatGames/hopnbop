class_name CharacterAnimator
extends Node2D


@export var faces_right_by_default := true
@export var animated_sprite: AnimatedSprite2D = null


func face_left() -> void:
    animated_sprite.flip_h = faces_right_by_default


func face_right() -> void:
    animated_sprite.flip_h = not faces_right_by_default


func play(animation_name: String) -> void:
    animated_sprite.play(animation_name)
