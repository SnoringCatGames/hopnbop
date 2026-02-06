class_name ScaffolderTime
extends RefCounted
## Simple timer utilities using native Godot APIs.
##
## Provides set_timeout, set_interval, throttle, and basic time tracking.
## Replaces the complex ScaffolderTime system.


var _scene_tree: SceneTree
var _next_id := 1
var _active_callbacks := {} # <int, Callable>
var _start_time_usec := 0
var _is_cleaning_up := false


func _init(scene_tree: SceneTree) -> void:
	_scene_tree = scene_tree
	_start_time_usec = Time.get_ticks_usec()


## Clean up all active callbacks. Call this before freeing.
func cleanup() -> void:
	_is_cleaning_up = true
	_active_callbacks.clear()


## Get app time in seconds since G singleton initialized.
func get_app_time() -> float:
	return (Time.get_ticks_usec() - _start_time_usec) / 1_000_000.0


## Get play time (same as app time in this simple implementation).
func get_play_time() -> float:
	return get_app_time()


## Schedule a callback after a delay.
func set_timeout(callback: Callable, delay_sec: float) -> int:
	if _is_cleaning_up:
		return -1

	var id := _next_id
	_next_id += 1

	var timer := _scene_tree.create_timer(delay_sec)
	var cleanup_callback := func():
		if not _is_cleaning_up and id in _active_callbacks:
			callback.call()
			_active_callbacks.erase(id)

	timer.timeout.connect(cleanup_callback)
	_active_callbacks[id] = cleanup_callback

	return id


## Schedule a callback to repeat at an interval.
func set_interval(callback: Callable, interval_sec: float) -> int:
	if _is_cleaning_up:
		return -1

	var id := _next_id
	_next_id += 1

	# Create wrapper that can be called recursively.
	var wrapper := _IntervalWrapper.new(self , id, callback, interval_sec)
	_active_callbacks[id] = wrapper

	# Start first timer.
	var timer := _scene_tree.create_timer(interval_sec)
	timer.timeout.connect(wrapper.execute)

	return id


## Cancel a timeout or interval.
func clear_timeout(id: int) -> void:
	_active_callbacks.erase(id)


## Create a throttled version of a callback.
func throttle(callback: Callable, cooldown_sec: float) -> Callable:
	# Use array to allow mutation from lambda (arrays are passed by reference).
	var last_call_time := [-INF]

	return func() -> void:
		var current_time := Time.get_ticks_msec() / 1000.0
		if current_time - last_call_time[0] >= cooldown_sec:
			last_call_time[0] = current_time
			callback.call()


## Get next task ID for internal use.
func get_next_task_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


## Get combined time scale (always 1.0 in simplified version).
func get_combined_scale() -> float:
	return 1.0


## Get scaled network frame delta (1/60 sec for 60 FPS network tick).
func get_scaled_network_frame_delta() -> float:
	return 1.0 / 60.0


# --- Helper classes ---


## Wrapper for interval callbacks to avoid self-referencing lambda issues.
class _IntervalWrapper extends RefCounted:
	var _scaffolder_time: ScaffolderTime
	var _id: int
	var _callback: Callable
	var _interval_sec: float

	func _init(
		simple_time: ScaffolderTime,
		id: int,
		callback: Callable,
		interval_sec: float
	) -> void:
		_scaffolder_time = simple_time
		_id = id
		_callback = callback
		_interval_sec = interval_sec

	func execute() -> void:
		# Check if ScaffolderTime is being cleaned up or callback was cancelled.
		if not is_instance_valid(_scaffolder_time) or _scaffolder_time._is_cleaning_up:
			return
		if _id not in _scaffolder_time._active_callbacks:
			return

		# Execute callback.
		_callback.call()

		# Schedule next execution (only if still valid).
		if not _scaffolder_time._is_cleaning_up and is_instance_valid(_scaffolder_time._scene_tree):
			var timer := _scaffolder_time._scene_tree.create_timer(_interval_sec)
			timer.timeout.connect(execute)
