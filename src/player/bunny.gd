@tool
class_name Bunny
extends Player


var match_state: PlayerMatchState:
	get:
		return G.get_player_match_state(player_id)

# Dictionary<int, bool>
var _intersecting_head_player_ids := {}


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

	# Set up outline color when match state becomes available.
	if is_instance_valid(match_state):
		_apply_outline_color()
	else:
		G.match_state.player_joined.connect(_on_any_player_joined)


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()


func play_sound(sound_name: StringName) -> void:
	if not G.network.is_primary_client:
		return

	var stream_player := _get_audio_stream_player(sound_name)
	if not stream_player.playing:
		stream_player.play()


# TODO: Make better sounds.
func _get_audio_stream_player(sound_name: StringName) -> AudioStreamPlayer2D:
	match sound_name:
		"jump":
			return %JumpAudioStreamPlayer
		"land":
			return %LandAudioStreamPlayer
		"walk":
			return %WalkAudioStreamPlayer
		"die":
			if G.settings.is_gore_enabled:
				return %DieGoreAudioStreamPlayer
			else:
				return %DieFlowersAudioStreamPlayer
		_:
			G.fatal()
			return null


func _on_local_authority_added(
		_input_from_client: PlayerInputFromClient,
) -> void:
	_set_up_camera()


func _set_up_camera() -> void:
	var is_local_player := peer_id == G.network.local_peer_id

	G.print(
		"Setting up camera for player %s (peer=%d, local=%d, is_local=%s)" % [
			player_id,
			peer_id,
			G.network.local_peer_id,
			is_local_player,
		],
		ScaffolderLog.CATEGORY_CORE_SYSTEMS,
		ScaffolderLog.Verbosity.VERBOSE,
	)

	%CharacterCamera.enabled = is_local_player


func get_string() -> String:
	if is_instance_valid(match_state):
		return match_state.get_string()
	return "{Player}"


func _on_any_player_joined(player: PlayerMatchState) -> void:
	if player.player_id == player_id:
		_apply_outline_color()
		G.match_state.player_joined.disconnect(_on_any_player_joined)


func _apply_outline_color() -> void:
	if not G.ensure(is_instance_valid(match_state)):
		return

	var sprite := animator.animated_sprite as AnimatedSprite2D
	var shader_material := sprite.material as ShaderMaterial

	if G.ensure(is_instance_valid(shader_material)):
		shader_material.set_shader_parameter(
			"outline_color",
			match_state.outline_color
		)

		# Toggle outline based on whether we're in a networked match.
		shader_material.set_shader_parameter(
			"outline_enabled",
			G.is_networked_level_active)


func _on_collided_with_player(other_player_id: int) -> void:
	if not G.is_server:
		return
	# FIXME: LEFT OFF HERE: Need to fix two big problems:
	# 1. We need to record on the other player that they got bumped this frame,
	#    and check for that flag here, so we don't double-count.
	# 2. We need to account for rollbacks.
	#    - To do so, I think we should record this frame as bumped/killed/died
	#      between these two players, and make this record indelible by rollbacks.
	#      We then need to prevent bumps/kills/deaths from ever being recorded
	#      for this player if there was aalready bump/kill/death recorded on this
	#      player with this other player within N past or future frames (N should
	#      be 4, but make it a const).
	#    - We should record this in MatchState.
	#    - But we don't need to replicate this state. We can just track it on the
	#      server.
	#    - Make sure we then send an RPC to all players whenever a bump or kill
	#      is recorded.
	#      - Include killer, killee, position, and time in the RPC args.
	if not _intersecting_head_player_ids.has(other_player_id):
		# Bump
		G.match_state.server_add_bump(player_id, other_player_id)
	else:
		# Kill
		G.match_state.server_add_kill(player_id, other_player_id)


func _on_foot_area_area_entered(area: Area2D) -> void:
	if not G.is_server:
		return

	var other_parent: Node = area.get_parent()
	if not G.ensure(other_parent is Player):
		return
	var other_player := other_parent as Player

	_intersecting_head_player_ids[other_player.player_id] = true


func _on_foot_area_area_exited(area: Area2D) -> void:
	if not G.is_server:
		return

	var other_parent: Node = area.get_parent()
	if not G.ensure(other_parent is Player):
		return
	var other_player := other_parent as Player

	_intersecting_head_player_ids.erase(other_player.player_id)
