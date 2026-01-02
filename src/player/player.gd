class_name Player
extends CharacterBody2D


func _enter_tree() -> void:
	G.player = self


func _ready() -> void:
	reset()


func reset() -> void:
	# TODO
	pass


func _physics_process(delta_sec: float):
	_handle_movement(delta_sec)


func _handle_movement(delta_sec: float):
	# TODO
	velocity.x = 0
	velocity.y = 10
	move_and_slide()


func is_movement_action_pressed() -> bool:
	return (
		Input.is_action_pressed("MoveLeft") or
		Input.is_action_pressed("MoveRight") or
		Input.is_action_pressed("MoveUp") or
		Input.is_action_pressed("MoveDown")
	)
