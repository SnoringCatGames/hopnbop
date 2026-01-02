class_name GamePanel
extends Node2D


func _enter_tree() -> void:
	G.game_panel = self
	G.session = Session.new()


func start_game() -> void:
	G.session.reset()
	G.session.is_game_ended = false


func end_game() -> void:
	G.session.is_game_ended = true


func reset() -> void:
	# TODO
	pass


func on_return_from_screen() -> void:
	if G.session.is_game_ended:
		start_game()
