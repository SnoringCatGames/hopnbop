extends GutTest
## H118: detached world sprites (the player squish, the
## snail crunch remnant) draw in the characters' band,
## immediately before the players node. The scenes put
## their foreground art at Level.FOREGROUND_Z_INDEX and
## the lobby landmarks one step above it, so no gameplay
## effect (gore is the highest, at z 2) can paint over
## the art. The scene tests below load the real scenes:
## a foreground node added or renamed without its
## z_index in the scene fails them.

const _LEVEL_SCENES: Array[String] = [
	"res://src/level/lobby_level.tscn",
	"res://src/level/level_0.tscn",
	"res://src/level/level_1.tscn",
	"res://src/level/level_2.tscn",
	"res://src/level/level_3.tscn",
	"res://src/level/level_4.tscn",
	"res://src/level/level_5.tscn",
]

## Root children after Players that never sort with the
## world: gameplay containers, the settings interactable
## (behind the tiles by design), and triggers/layers.
const _AFTER_PLAYERS_EXEMPT: Array[StringName] = [
	&"Objects", &"SpawnPoints", &"SettingsBook",
]

## GoreManager's highest z_index (particles front buffer).
const _GORE_MAX_Z := 2

var _level: Level
var _players: Node2D
var _foreground: Node2D


func before_each() -> void:
	_level = Level.new()
	# Behind-layer content first, then players, then a
	# foreground node, matching the level scenes.
	var background := Node2D.new()
	background.name = "Background"
	_level.add_child(background)
	_players = Node2D.new()
	_players.name = "Players"
	_level.add_child(_players)
	_foreground = Node2D.new()
	_foreground.name = "Foreground"
	_level.add_child(_foreground)
	_level.players_node = _players


func after_each() -> void:
	_level.free()


func test_sprite_lands_immediately_before_players() -> void:
	var sprite := Sprite2D.new()

	_level.add_sprite_at_character_depth(sprite)

	assert_same(sprite.get_parent(), _level)
	assert_eq(sprite.get_index(), _players.get_index() - 1,
		"sprite sits immediately before the players node")
	assert_true(sprite.get_index() < _foreground.get_index(),
		"foreground art still draws over the sprite")


func test_two_sprites_keep_spawn_order() -> void:
	var first := Sprite2D.new()
	var second := Sprite2D.new()

	_level.add_sprite_at_character_depth(first)
	_level.add_sprite_at_character_depth(second)

	assert_true(first.get_index() < second.get_index(),
		"later sprites draw over earlier ones in the band")
	assert_true(second.get_index() < _players.get_index(),
		"both stay behind the players")


## Every world-drawing root child after Players in the
## real scenes sorts above gore's z: foreground art at
## FOREGROUND_Z_INDEX, lobby landmarks above that.
func test_scenes_foreground_sorts_above_gameplay() -> void:
	for scene_path in _LEVEL_SCENES:
		var scene := _instantiate(scene_path)
		var checked := _check_after_players(scene)
		assert_gt(checked, -1,
			"%s: Players node present" % scene_path)
		scene.free()


## The two scenes with foreground art carry it at
## FOREGROUND_Z_INDEX; the lobby keeps its landmarks
## above the art at FOREGROUND_UI_Z_INDEX.
func test_scenes_carry_the_foreground_depths() -> void:
	var level_0 := _instantiate(_LEVEL_SCENES[1])
	_assert_has_depth(level_0, Level.FOREGROUND_Z_INDEX,
		"level_0 occlusion art")
	level_0.free()

	var lobby := _instantiate(_LEVEL_SCENES[0])
	_assert_has_depth(lobby, Level.FOREGROUND_Z_INDEX,
		"lobby occlusion tiles")
	_assert_has_depth(lobby, Level.FOREGROUND_UI_Z_INDEX,
		"lobby landmarks")
	lobby.free()

	assert_gt(Level.FOREGROUND_Z_INDEX, _GORE_MAX_Z,
		"foreground art sorts above gore's z")
	assert_gt(Level.FOREGROUND_UI_Z_INDEX,
		Level.FOREGROUND_Z_INDEX,
		"landmarks sort above the foreground art")
	assert_lt(Level.FOREGROUND_Z_INDEX, 100,
		"foreground art stays below the wrap overlay")


func _instantiate(scene_path: String) -> Node:
	var packed := ResourceLoader.load(scene_path)
	assert_not_null(packed, scene_path)
	var scene := (packed as PackedScene).instantiate()
	assert_not_null(scene, scene_path)
	return scene


## Asserts every non-exempt CanvasItem after Players in
## the scene has z_index above gore's, and returns how
## many were checked (-1 when Players is missing).
func _check_after_players(scene: Node) -> int:
	var players := scene.get_node_or_null("Players")
	if players == null:
		return -1
	var checked := 0
	for index in range(
			players.get_index() + 1, scene.get_child_count()):
		var child := scene.get_child(index)
		if child.name in _AFTER_PLAYERS_EXEMPT:
			continue
		if (child is Area2D or child is CanvasLayer
				or child is Camera2D
				or child is MultiplayerSpawner):
			continue
		if not (child is CanvasItem):
			continue
		checked += 1
		assert_gt((child as CanvasItem).z_index, _GORE_MAX_Z,
			"%s/%s sorts above gore's z" % [
				scene.name, child.name])
	return checked


func _assert_has_depth(
	scene: Node, z_index: int, what: String,
) -> void:
	var players := scene.get_node_or_null("Players")
	assert_not_null(players, what)
	var found := false
	for index in range(
			players.get_index() + 1, scene.get_child_count()):
		var child := scene.get_child(index)
		if (child is CanvasItem
				and (child as CanvasItem).z_index == z_index):
			found = true
	assert_true(found,
		"%s sits at z %d in %s" % [what, z_index, scene.name])
