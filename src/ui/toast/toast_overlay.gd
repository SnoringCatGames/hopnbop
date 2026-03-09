class_name ToastOverlay
extends PanelContainer
## Displays temporary toast notifications at the bottom
## of the screen. Toasts fade out automatically after a
## short delay.


const _FADE_DELAY_SEC := 2.0
const _FADE_DURATION_SEC := 0.5
const _MAX_TOASTS := 5

enum Type {
	INFO,
	SUCCESS,
	ERROR,
}

const _COLORS := {
	Type.INFO: Color.WHITE,
	Type.SUCCESS: Color(0.6, 1.0, 0.6),
	Type.ERROR: Color(1.0, 0.4, 0.4),
}


func _enter_tree() -> void:
	G.toast_overlay = self


## Show a toast message with the given type.
func show_toast(
	message: String,
	type: Type = Type.INFO,
) -> void:
	var type_name: String = Type.keys()[type]
	G.log.print(
		"[Toast:%s] %s" % [type_name, message],
	)

	var label := Label.new()
	label.text = message
	label.modulate = _COLORS.get(type, Color.WHITE)
	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	%ToastContainer.add_child(label)

	# Cap the number of visible toasts.
	while %ToastContainer.get_child_count() > _MAX_TOASTS:
		var oldest: Node = %ToastContainer.get_child(0)
		oldest.queue_free()

	# Fade out and remove after delay.
	var tween := get_tree().create_tween()
	tween.tween_property(
		label, "modulate:a",
		0.0, _FADE_DURATION_SEC,
	).set_delay(_FADE_DELAY_SEC)
	tween.tween_callback(
		func() -> void:
			if is_instance_valid(label):
				label.queue_free()
	)
