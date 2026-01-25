@tool
class_name _Throttler
extends RefCounted

var time_type: int
var time_tracker
var elapsed_time_key: StringName
var callback: Callable
var interval: float
var invokes_at_end: bool
var parent

var last_timeout_id := -1

var last_call_time := -INF
var is_callback_scheduled := false
var pending_args: Array = []


func _init(
		p_parent,
		p_time_type: int,
		p_callback: Callable,
		p_interval: float,
		p_invokes_at_end: bool,
) -> void:
	self.parent = p_parent
	self.time_type = p_time_type
	self.time_tracker = G.time._get_time_tracker_for_time_type(p_time_type)
	self.elapsed_time_key = G.time._get_elapsed_time_key_for_time_type(p_time_type)
	self.callback = p_callback
	self.interval = p_interval
	self.invokes_at_end = p_invokes_at_end


func on_call(arg1 = null, arg2 = null, arg3 = null, arg4 = null) -> void:
	# Collect non-null arguments
	var args: Array = []
	if arg1 != null:
		args.append(arg1)
	if arg2 != null:
		args.append(arg2)
	if arg3 != null:
		args.append(arg3)
	if arg4 != null:
		args.append(arg4)

	if !is_callback_scheduled:
		var current_call_time: float = time_tracker.get(elapsed_time_key)
		var next_call_time := last_call_time + interval
		if current_call_time > next_call_time:
			_trigger_callback(args)
		elif invokes_at_end:
			pending_args = args
			last_timeout_id = G.time.set_timeout(
				_trigger_callback_from_timeout,
				next_call_time - current_call_time,
				[],
				time_type,
			)
			is_callback_scheduled = true


func cancel() -> void:
	G.time.clear_timeout(last_timeout_id)
	is_callback_scheduled = false
	pending_args = []


func _trigger_callback_from_timeout() -> void:
	_trigger_callback(pending_args)
	pending_args = []


func _trigger_callback(args: Array) -> void:
	last_call_time = time_tracker.get(elapsed_time_key)
	is_callback_scheduled = false
	if callback.is_valid():
		callback.callv(args)
