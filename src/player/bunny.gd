@tool
class_name Bunny
extends Player

var match_state: PlayerMatchState:
    get:
        return G.get_player_match_state(multiplayer_id)


func _enter_tree() -> void:
    super._enter_tree()


func _exit_tree() -> void:
    super._exit_tree()


func _ready() -> void:
    super._ready()


func _process_movement_and_actions() -> void:
    super._process_movement_and_actions()


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
