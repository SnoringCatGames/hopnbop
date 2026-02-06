class_name GameTime
extends NetworkTime
## Example NetworkTime implementation using Timer nodes.
##
## Provides timeout, interval, and throttling functionality for the netcode
## plugin.

var _scene_tree: SceneTree
var _next_id := 1
var _active_timers := {}  # Dictionary<int, Timer>
var _throttle_last_call_times := {}  # Dictionary<Callable, float>


func _init(scene_tree: SceneTree) -> void:
	_scene_tree = scene_tree


func set_timeout(callback: Callable, delay_sec: float) -> int:
	var timer := Timer.new()
	timer.wait_time = delay_sec
	timer.one_shot = true

	var id := _next_id
	_next_id += 1
	_active_timers[id] = timer

	timer.timeout.connect(func() -> void:
		callback.call()
		_active_timers.erase(id)
		timer.queue_free()
	)

	_scene_tree.root.add_child(timer)
	timer.start()

	return id


func set_interval(callback: Callable, interval_sec: float) -> int:
	var timer := Timer.new()
	timer.wait_time = interval_sec
	timer.one_shot = false

	var id := _next_id
	_next_id += 1
	_active_timers[id] = timer

	timer.timeout.connect(callback)

	_scene_tree.root.add_child(timer)
	timer.start()

	return id


func clear_timeout(id: int) -> void:
	if _active_timers.has(id):
		var timer: Timer = _active_timers[id]
		timer.stop()
		timer.queue_free()
		_active_timers.erase(id)


func throttle(callback: Callable, cooldown_sec: float) -> Callable:
	return func() -> void:
		var current_time := Time.get_ticks_msec() / 1000.0
		var last_call := _throttle_last_call_times.get(callback, -INF)

		if current_time - last_call >= cooldown_sec:
			_throttle_last_call_times[callback] = current_time
			callback.call()
