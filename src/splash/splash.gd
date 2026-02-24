class_name Splash
extends AnimatedSprite2D
## A one-shot splash effect that frees itself when
## its animation finishes.


func _ready() -> void:
	animation_finished.connect(queue_free)
