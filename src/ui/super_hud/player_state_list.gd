class_name PlayerStateList
extends PanelContainer


# FIXME: LEFT OFF HERE: List actual networked players:
# - Remove the hard-coded player-state from the scene tree
# - Update when players connect or disconnect
# - Update each frame with current player state


func _enter_tree() -> void:
    visible = G.settings.show_debug_player_state
