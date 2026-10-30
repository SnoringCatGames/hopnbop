extends GutTest
## Alt+Enter toggles fullscreen (H96): the key flips the same
## setting the Settings panel toggle flips, and plain Enter,
## key releases, and echoes do not.


var _manager: WindowManager
var _was_full_screen: bool


func before_each() -> void:
	_was_full_screen = G.settings.full_screen
	_manager = WindowManager.new()
	add_child_autofree(_manager)


func after_each() -> void:
	G.settings.full_screen = _was_full_screen


func _alt_enter(echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.alt_pressed = true
	event.pressed = true
	event.echo = echo
	return event


func test_alt_enter_toggles_fullscreen() -> void:
	G.settings.full_screen = false

	_manager._unhandled_input(_alt_enter())

	assert_true(G.settings.full_screen)


func test_alt_enter_toggles_back() -> void:
	G.settings.full_screen = true

	_manager._unhandled_input(_alt_enter())

	assert_false(G.settings.full_screen)


func test_plain_enter_and_echo_do_not_toggle() -> void:
	G.settings.full_screen = false
	var plain := InputEventKey.new()
	plain.keycode = KEY_ENTER
	plain.pressed = true

	_manager._unhandled_input(plain)
	_manager._unhandled_input(_alt_enter(true))

	assert_false(G.settings.full_screen)
