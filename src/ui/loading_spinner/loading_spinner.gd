class_name LoadingSpinner
extends TextureRect
## Animated loading spinner driven by a horizontal
## spritesheet. Cycles through frames at a fixed
## rate. Toggle visibility to show or hide.


const _FRAME_COUNT := 16
const _FRAME_WIDTH := 12
const _FRAME_HEIGHT := 12
const _FRAMES_PER_SECOND := 12.0

var _frame := 0
var _elapsed := 0.0
var _atlas: AtlasTexture


func _ready() -> void:
	# Duplicate the atlas so each instance can
	# animate independently.
	_atlas = (texture as AtlasTexture).duplicate()
	texture = _atlas
	_update_frame()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	var frame_duration := 1.0 / _FRAMES_PER_SECOND
	if _elapsed >= frame_duration:
		_elapsed -= frame_duration
		_frame = (_frame + 1) % _FRAME_COUNT
		_update_frame()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible:
			_elapsed = 0.0


func _update_frame() -> void:
	if _atlas == null:
		return
	_atlas.region = Rect2(
		_frame * _FRAME_WIDTH, 0,
		_FRAME_WIDTH, _FRAME_HEIGHT,
	)
