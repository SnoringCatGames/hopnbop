extends GutTest
## H5: podium bunnies never animate. The podium sits in the
## level under the game-over screen, and opening that screen
## pauses the tree (ScreensMain), so portrayals with the
## default process mode freeze on their first frame.


const _PORTRAYAL_SCENE := preload(
	"res://src/player/player_portrayal.tscn")


func after_each() -> void:
	get_tree().paused = false
	ArrayPool.clear_all_pools()


func test_portrayal_animates_while_the_tree_is_paused() -> void:
	var portrayal: PlayerPortrayal = (
		_PORTRAYAL_SCENE.instantiate())
	add_child_autofree(portrayal)

	var player_state := GamePlayerState.new()
	portrayal.apply_player_state(player_state)

	get_tree().paused = true
	portrayal.play_after_delay(0.05)

	# The SceneTreeTimer fires during the pause; give the
	# sprite time to advance past its first frame.
	await get_tree().create_timer(0.8).timeout

	var sprite: AnimatedSprite2D = (
		portrayal._animator.animated_sprite)
	assert_true(
		sprite.is_playing(),
		"portrayal is playing on the podium",
	)
	assert_gt(
		sprite.frame + sprite.frame_progress, 0.0,
		"portrayal advanced past frame 0 while paused",
	)
