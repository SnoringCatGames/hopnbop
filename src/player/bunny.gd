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

    if Engine.is_editor_hint():
        return

    if G.network.is_client:
        G.network.local_authority_added.connect(
            _on_local_authority_added,
            CONNECT_ONE_SHOT,
        )
    _set_up_camera.call_deferred()


func _process_movement_and_actions() -> void:
    super._process_movement_and_actions()


func play_sound(sound_name: String) -> void:
    # TODO: Implement sounds.
    match sound_name:
        "jump":
            pass
        "land":
            pass


func _on_local_authority_added(
        _input_from_client: PlayerInputFromClient,
) -> void:
    _set_up_camera()


func _set_up_camera() -> void:
    var is_local_player := multiplayer_id == G.network.local_id

    G.print(
        "Setting up camera for player %d (local=%d, is_local=%s)" % [
            multiplayer_id,
            G.network.local_id,
            is_local_player,
        ],
        ScaffolderLog.CATEGORY_CORE_SYSTEMS,
        ScaffolderLog.Verbosity.VERBOSE,
    )

    %CharacterCamera.enabled = is_local_player


func get_string() -> String:
    if is_instance_valid(match_state):
        return match_state.get_string()
    else:
        return "{Player}"
