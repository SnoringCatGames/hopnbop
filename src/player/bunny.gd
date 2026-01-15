class_name Bunny
extends Player


var match_state: PlayerMatchState:
    get:
        if G.game_panel.match_state.players_by_id.has(multiplayer_id):
            return G.game_panel.match_state.players_by_id[multiplayer_id]
        else:
            return null


func _enter_tree() -> void:
    super._enter_tree()


func _exit_tree() -> void:
    super._exit_tree()


func _physics_process(delta: float) -> void:
    super._physics_process(delta)


func _network_process() -> void:
    super._network_process()


func play_sound(sound_name: String) -> void:
    # TODO: Implement sounds.
    match sound_name:
        "jump":
            pass
        "land":
            pass


func get_string() -> String:
    if is_instance_valid(match_state):
        return match_state.get_string()
    else:
        return "{Player}"
