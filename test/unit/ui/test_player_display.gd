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
