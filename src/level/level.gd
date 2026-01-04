class_name Level
extends Node2D


var players: Array[Character] = []


func _ready() -> void:
    # FIXME: Update this for the set of players that are matched to the game session.
    var player: Character = G.settings.player_scene.instantiate()
    add_child(player)
    players.append(player)
