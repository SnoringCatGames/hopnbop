extends GutTest
## H118: detached world sprites (the player squish, the
## snail crunch remnant) draw in the characters' band,
## immediately before the players node, so foreground
## art after the players still covers them.


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
