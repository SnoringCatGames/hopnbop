class_name Bunny
extends Player


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
