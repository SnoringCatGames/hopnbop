class_name CreditsOverlay
extends CanvasLayer
## Full-screen credits overlay with centered text
## on a semi-transparent black background. Closes
## on any left/right/trigger input from any
## device.


const _ACTIVATION_DELAY_SEC := 0.2

var _poller: AnyDeviceInputPoller
var _time_open := 0.0
var _is_dismissed := false


func _ready() -> void:
	_poller = AnyDeviceInputPoller.new()
	_poller.prime()
	G.is_ui_interaction_mode_enabled = true


func _process(delta: float) -> void:
	_time_open += delta
	if _time_open < _ACTIVATION_DELAY_SEC:
		# Still in delay. Pump poller to keep
		# prev_* state fresh but ignore output.
		_poller.poll(delta)
		return

	_poller.poll(delta)
	if (_poller.left_just
			or _poller.right_just
			or _poller.trigger_just):
		close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_pause"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	if _is_dismissed:
		return
	_is_dismissed = true
	G.is_ui_interaction_mode_enabled = false
	queue_free()
