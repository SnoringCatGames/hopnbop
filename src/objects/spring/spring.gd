class_name Spring
extends StaticBody2D
## A spring tile that bounces players upward.
## Uses Area2D detection instead of terrain
## sampling.


func _on_trigger_area_body_entered(
	body: Node2D,
) -> void:
	if not body is Player:
		return
	var player := body as Player
	if player.state_from_server.is_dead:
		return
	# Server triggers gameplay bounce.
	player.server_trigger_spring_bounce()
	# Animation plays on all peers (cosmetic).
	$AnimatedSprite2D.play("bounce")


func _on_animated_sprite_2d_animation_finished(
) -> void:
	$AnimatedSprite2D.play("idle")
