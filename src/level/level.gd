class_name Level
extends Node2D


@export var players_node: Node2D

var players: Array[Character] = []


func _enter_tree() -> void:
    G.level = self


func _exit_tree() -> void:
    if G.level == self:
        G.level = null


func _ready() -> void:
    # FIXME: LEFT OFF HERE: ACTUAL: Network player spawing: Update this for the set of players that are matched to the game session.
    var player: Character = G.settings.player_scene.instantiate()
    players_node.add_child(player)
    players.append(player)
