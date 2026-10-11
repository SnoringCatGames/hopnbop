extends GutTest
## Tests for PlayerDisplay's display-only (remote party member) mode
## and the leader crown. The live-match path isn't exercised here (it
## needs a full match state); these cover the party-member rendering
## added for the lobby nameplate row.

const _SCENE := "res://src/ui/hud/player_display.tscn"


func _make_display() -> PlayerDisplay:
	var d: PlayerDisplay = load(_SCENE).instantiate()
	add_child_autofree(d)
	return d


func test_display_only_shows_member_name() -> void:
	var d := _make_display()
	d.set_party_member({
		"user_id": "u1",
		"display_name": "Alice",
		"role": "member",
	})
	# _update_display_only runs in _process.
	await wait_frames(2)
	assert_eq(d.get_node("%Name").text, "Alice")
	assert_false(
		d.get_node("%Score").visible,
		"display-only entries have no score")


func test_display_only_crowns_leader() -> void:
	var d := _make_display()
	d.set_party_member({
		"user_id": "u1",
		"display_name": "Boss",
		"role": "leader",
	})
	await wait_frames(2)
	assert_true(
		d._crown_label.visible, "leader member should be crowned")


func test_display_only_no_crown_for_member() -> void:
	var d := _make_display()
	d.set_party_member({
		"user_id": "u2",
		"display_name": "Bob",
		"role": "member",
	})
	await wait_frames(2)
	assert_false(
		d._crown_label.visible, "non-leader must not be crowned")


func test_display_name_falls_back_to_username() -> void:
	var d := _make_display()
	d.set_party_member({
		"user_id": "u3",
		"username": "CODE3",
		"role": "member",
	})
	await wait_frames(2)
	assert_eq(
		d.get_node("%Name").text, "CODE3",
		"blank display_name falls back to username")


func test_display_only_hides_bunny() -> void:
	var d := _make_display()
	d.set_party_member({
		"user_id": "u4",
		"display_name": "Dana",
		"role": "member",
	})
	await wait_process_frames(2)
	assert_false(
		d.get_node("%BunnyFrame").visible,
		"party state carries no appearance, so no bunny")


## The resting bunny shown next to the profile image for a live match
## player. Each test gets its own match state and client session.
class TestBunny:
	extends GutTest

	const _SCENE := "res://src/ui/hud/player_display.tscn"
	const _PLAYER_ID := 7
	const _RIVAL_ID := 8

	var _saved_match_state: GameMatchState
	var _saved_client_session: ClientSession
	var _saved_level: Level
	var _fake_level: Level
	var _player_state: GamePlayerState


	func before_each() -> void:
		_saved_match_state = G.match_state
		_saved_client_session = G.client_session
		_saved_level = G.level
		G.match_state = GameMatchState.new()
		G.client_session = ClientSession.new()
		G.level = null
		_player_state = _add_player(_PLAYER_ID, 3)


	func after_each() -> void:
		G.match_state = _saved_match_state
		G.client_session = _saved_client_session
		G.level = _saved_level
		if is_instance_valid(_fake_level):
			_fake_level.free()


	func test_hidden_until_player_state_exists() -> void:
		G.match_state.players_by_id.erase(_PLAYER_ID)
		var display := _make_display()
		await wait_process_frames(2)
		assert_false(
			display.get_node("%Bunny").visible,
			"no default bunny before the player's state arrives")
		G.match_state.players_by_id[_PLAYER_ID] = _player_state
		await wait_process_frames(2)
		assert_true(display.get_node("%Bunny").visible)


	func test_shows_player_body_type() -> void:
		var display := _make_display()
		await wait_process_frames(2)
		assert_true(display.get_node("%BunnyFrame").visible)
		assert_eq(
			_body_sheet(display),
			G.settings.body_types[3].sprite_sheet,
			"bunny wears the player's body type")


	func test_rebuilds_when_body_type_changes() -> void:
		var display := _make_display()
		await wait_process_frames(2)
		_player_state.body_type_index = 5
		await wait_process_frames(2)
		assert_eq(
			_body_sheet(display),
			G.settings.body_types[5].sprite_sheet,
			"appearance change re-renders the bunny")


	func test_plays_rest_animation() -> void:
		var display := _make_display()
		await wait_process_frames(2)
		var sprite := _animator(display).animated_sprite
		assert_eq(sprite.animation, &"Rest")
		assert_true(sprite.is_playing(), "the resting bunny animates")


	func test_crowns_kill_leader() -> void:
		_enter_level(NetworkedLevel.new())
		_add_player(_RIVAL_ID, 0)
		var display := _make_display()
		_give_crown_lead()
		await wait_process_frames(2)
		var crown := _animator(display).get_crown_overlay()
		assert_true(
			is_instance_valid(crown) and crown.visible,
			"the kill leader's bunny wears the crown")


	func test_first_lobby_player_is_not_crowned() -> void:
		# Lobby ids count down from -1, which is also what
		# get_crown_player_id() returns when nobody holds the crown.
		_enter_level(LobbyLevel.new())
		G.match_state.players_by_id.erase(_PLAYER_ID)
		_add_player(-1, 0)
		_add_player(-2, 0)
		var display := _make_display(-1)
		await wait_process_frames(2)
		var crown := _animator(display).get_crown_overlay()
		assert_false(
			is_instance_valid(crown) and crown.visible,
			"no crown in the lobby, even for player -1")


	func test_drops_crown_when_lead_is_lost() -> void:
		_enter_level(NetworkedLevel.new())
		_add_player(_RIVAL_ID, 0)
		var display := _make_display()
		_give_crown_lead()
		await wait_process_frames(2)
		var crown := _animator(display).get_crown_overlay()
		assert_true(
			is_instance_valid(crown) and crown.visible,
			"precondition: crowned while leading")
		G.match_state.kills = PackedInt32Array()
		await wait_process_frames(2)
		assert_false(
			is_instance_valid(crown) and crown.visible,
			"crown comes off once the lead is gone")


	func test_outline_only_in_networked_match() -> void:
		var display := _make_display()
		await wait_process_frames(2)
		assert_false(
			_is_outline_enabled(display),
			"no outline outside a networked match, as in-world")
		_enter_level(NetworkedLevel.new())
		await wait_process_frames(2)
		assert_eq(
			_is_outline_enabled(display),
			G.settings.show_player_outlines,
			"networked match outline follows the outline setting")


	func test_scaled_by_whole_pixels() -> void:
		var display := _make_display()
		await wait_process_frames(1)
		var bunny_scale: Vector2 = display.get_node("%Bunny").scale
		assert_eq(bunny_scale.x, roundf(bunny_scale.x))
		assert_eq(bunny_scale.x, bunny_scale.y)
		assert_gte(bunny_scale.x, 1.0)
		assert_eq(
			display.get_node("%BunnyFrame").custom_minimum_size,
			PlayerDisplay._BUNNY_REGION.size * bunny_scale.x,
			"the frame reserves the scaled bunny region")


	func _add_player(
		player_id: int,
		body_type_index: int,
	) -> GamePlayerState:
		var state := GamePlayerState.new()
		state.player_id = player_id
		state.body_type_index = body_type_index
		state.base_color = Color.RED
		G.match_state.players_by_id[player_id] = state
		return state


	func _give_crown_lead() -> void:
		# Kills are stored as killer, killee pairs.
		var kills := PackedInt32Array()
		for _kill_index in range(G.settings.crown_kill_lead):
			kills.append(_PLAYER_ID)
			kills.append(_RIVAL_ID)
		G.match_state.kills = kills


	## Stands in for the active level. Never enters the tree.
	func _enter_level(level: Level) -> void:
		if is_instance_valid(_fake_level):
			_fake_level.free()
		_fake_level = level
		G.level = level


	func _make_display(player_id: int = _PLAYER_ID) -> PlayerDisplay:
		var display: PlayerDisplay = load(_SCENE).instantiate()
		# PlayerList assigns the id before adding the display.
		display.set_player_id(player_id)
		add_child_autofree(display)
		return display


	func _animator(display: PlayerDisplay) -> BunnyAnimator:
		return display.get_node("%Bunny").get_node("%Animator")


	func _body_sheet(display: PlayerDisplay) -> Texture2D:
		var frames := _animator(display).animated_sprite.sprite_frames
		var frame: AtlasTexture = frames.get_frame_texture(&"Rest", 0)
		return frame.atlas


	func _is_outline_enabled(display: PlayerDisplay) -> bool:
		var outline_material: ShaderMaterial = (
			_animator(display).outline_group.material)
		return outline_material.get_shader_parameter(
			"outline_enabled")
