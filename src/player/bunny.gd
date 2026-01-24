@tool
class_name Bunny
extends Player

var match_state: PlayerMatchState:
	:
		 G.get_player_match_state(multiplayer_id)


func _enter_tree() -> void:
	er._enter_tree()


func _exit_tree() -> void:
	er._exit_tree()


func _ready() -> void:
	er._ready()

	Engine.is_editor_hint():


	G.network.is_client:
		ork.local_authority_added.connect(
			_authority_added,
			NE_SHOT,

	t_up_camera.call_deferred()


func _process_movement_and_actions() -> void:
	er._process_movement_and_actions()


func play_sound(sound_name: String) -> void:
	ODO: Implement sounds.
	ch sound_name:
		:

		:



func _on_local_authority_added(
		_from_client: PlayerInputFromClient,
) -> void:
	t_up_camera()


func _set_up_camera() -> void:
	 is_local_player := multiplayer_id == G.network.local_id

	rint(
		ng up camera for player %d (local=%d, is_local=%s)" % [
			er_id,
			.local_id,
			player,

		lderLog.CATEGORY_CORE_SYSTEMS,
		lderLog.Verbosity.VERBOSE,


	aracterCamera.enabled = is_local_player


func get_string() -> String:
	is_instance_valid(match_state):
		 match_state.get_string()
	e:
		 "{Player}"
