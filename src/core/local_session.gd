class_name LocalSession
extends RefCounted


var is_game_active := false
var is_game_loading := false


func _init() -> void:
    reset()


func reset() -> void:
    is_game_active = false
    is_game_loading = false
