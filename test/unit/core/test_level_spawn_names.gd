extends GutTest
## H26: after a preview hot reload, levels got Godot's
## auto-generated names (@Node2D@39) wherever the new level
## met the old one's still-lingering node on a peer, and every
## replicated node under it errored. Spawned levels now get
## a unique name per spawn from the server.


var _panel: GamePanel


func before_each() -> void:
	_panel = GamePanel.new()


func after_each() -> void:
	if is_instance_valid(_panel):
		_panel.free()


func test_first_spawn_keeps_the_scene_name() -> void:
	assert_eq(
		_panel._next_level_node_name("Level1"),
		"Level1",
	)


func test_respawns_never_reuse_a_name() -> void:
	var names: Array = []
	for i in range(4):
		names.append(_panel._next_level_node_name("Level1"))

	assert_eq(
		names,
		["Level1", "Level1_2", "Level1_3", "Level1_4"],
		"each spawn gets a fresh, replicable name",
	)


func test_names_are_tracked_per_level() -> void:
	_panel._next_level_node_name("Level1")

	assert_eq(
		_panel._next_level_node_name("Level2"),
		"Level2",
		"another level still starts from its scene name",
	)
