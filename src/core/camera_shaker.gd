class_name CameraShaker
extends Node
## Applies a decaying random offset to the active
## Camera2D to produce a screen-shake effect.
## Registered as a global service on G.
##
## Uses get_viewport().get_camera_2d() each frame
## to find the active camera, so it survives scene
## reloads without manual re-registration.


const _DEFAULT_INTENSITY := 6.0
const _DEFAULT_DURATION_SEC := 0.25
const _DECAY_EXPONENT := 2.0

var _shake_timer := 0.0
var _shake_intensity := 0.0
var _shake_duration := 0.0


## Starts a camera shake. Overlapping shakes
## take the max of current and new values.
func shake(
	intensity := _DEFAULT_INTENSITY,
	duration := _DEFAULT_DURATION_SEC,
) -> void:
	var camera := get_viewport().get_camera_2d()
	if not is_instance_valid(camera):
		return
	if _shake_timer > 0.0:
		_shake_intensity = max(
			_shake_intensity, intensity)
		_shake_timer = max(
			_shake_timer, duration)
		_shake_duration = _shake_timer
	else:
		_shake_intensity = intensity
		_shake_duration = duration
		_shake_timer = duration


func _process(delta: float) -> void:
	if _shake_timer <= 0.0:
		return

	var camera := get_viewport().get_camera_2d()
	if not is_instance_valid(camera):
		return

	_shake_timer -= delta

	if _shake_timer <= 0.0:
		_shake_timer = 0.0
		camera.offset = Vector2.ZERO
		return

	# Decay from full intensity to zero with
	# exponential falloff.
	var progress := _shake_timer / \
		_shake_duration
	var decay := pow(progress, _DECAY_EXPONENT)
	var current := _shake_intensity * decay

	camera.offset = Vector2(
		randf_range(-current, current),
		randf_range(-current, current),
	)
