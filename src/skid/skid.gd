class_name Skid
extends AnimatedSprite2D
## A one-shot skid effect that frees itself when
## its animation finishes.


func _ready() -> void:
	animation_finished.connect(queue_free)
