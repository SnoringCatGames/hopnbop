extends GutTest
## H6: networked splashes and landing skids fired twice.
## surfaces.previous_bitmask lags the current frame (it is
## restored from the rollback buffer), so the just_* getters
## read true on two consecutive frames, and a rollback replay
## presented the same transition again. Bunny's effects now
## consume each transition once.


class _CountingSplashManager:
	extends SplashManager

	var animations: Array = []

	func spawn_splash(
		_pos: Vector2,
		animation_name: StringName,
	) -> void:
		animations.append(animation_name)


class _CountingSkidManager:
	extends SkidManager

	var animations: Array = []

	func spawn_skid(
		_pos: Vector2,
		animation_name: StringName,
		_flip_h: bool,
	) -> void:
		animations.append(animation_name)


var _bunny: Bunny
var _level: Level
var _splashes: _CountingSplashManager
var _skids: _CountingSkidManager
var _saved_level: Level
var _saved_resimulating: bool


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_saved_level = G.level
	_saved_resimulating = Netcode.frame_driver.is_resimulating
	Netcode.frame_driver.is_resimulating = false

	_level = Level.new()
	_splashes = _CountingSplashManager.new()
	_skids = _CountingSkidManager.new()
	_level.splash_manager = _splashes
	_level.skid_manager = _skids
	G.level = _level

	_bunny = Bunny.new()
	var state := CharacterStateFromServer.new()
	state.character = _bunny
	_bunny.state_from_server = state


func after_each() -> void:
	G.level = _saved_level
	Netcode.frame_driver.is_resimulating = _saved_resimulating
	if is_instance_valid(_bunny.state_from_server):
		_bunny.state_from_server.free()
	if is_instance_valid(_bunny):
		_bunny.free()
	if is_instance_valid(_level):
		_level.free()
	ArrayPool.clear_all_pools()


## Sets the water bit with previous_bitmask one frame behind,
## as the networked restore leaves it.
func _set_water(is_in_water: bool) -> void:
	_bunny.surfaces.is_in_water = not is_in_water
	_bunny.surfaces.previous_bitmask = _bunny.surfaces.bitmask
	_bunny.surfaces.is_in_water = is_in_water


func test_water_entry_splashes_once_over_two_frames() -> void:
	_set_water(true)
	_bunny._update_splashes()
	_bunny._update_splashes()

	assert_eq(
		_splashes.animations, [&"enter_water"],
		"one splash per water entry",
	)


func test_water_exit_splashes_once() -> void:
	_set_water(true)
	_bunny._update_splashes()
	_set_water(false)
	_bunny._update_splashes()
	_bunny._update_splashes()

	assert_eq(
		_splashes.animations, [&"enter_water", &"exit_water"],
		"one splash per water exit",
	)


func test_resimulation_does_not_refire_splash() -> void:
	_set_water(true)
	_bunny._update_splashes()

	Netcode.frame_driver.is_resimulating = true
	_bunny._update_splashes()
	Netcode.frame_driver.is_resimulating = false
	_bunny._update_splashes()

	assert_eq(
		_splashes.animations, [&"enter_water"],
		"a replayed transition does not splash again",
	)


func test_landing_skid_fires_once_over_two_frames() -> void:
	_bunny.surfaces.is_attaching_to_floor = false
	_bunny.surfaces.previous_bitmask = _bunny.surfaces.bitmask
	_bunny.surfaces.is_attaching_to_floor = true

	_bunny._update_skids()
	_bunny._update_skids()

	assert_eq(
		_skids.animations, [&"skid_both"],
		"one landing skid per landing",
	)
